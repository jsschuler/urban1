using Printf
using Random
using Statistics: mean

# Include in dependency order — each file is loaded exactly once.
# Individual files contain no include() calls themselves.
include("structs.jl")
include("transport.jl")
include("utility.jl")
include("generation.jl")
include("step.jl")
include("laws.jl")
include("employer.jl")
include("visualizer.jl")

# ============================================================
# Initialisation
# ============================================================

"""
    init_model(; kwargs...) → (city, vis, rng)

Build the city grid, populate agents, and start the WebSocket visualizer server.
Blocks until the user presses Enter, giving time to connect Blender and run
Setup Scene before the first step fires.

Keyword arguments
─────────────────
  n_x, n_y        city grid size in neighbourhoods       (default 10 × 10)
  k               neighbourhood side length in buildings  (default 8)
  n_agents        initial number of agents                (default 0)
  seed            RNG seed                                (default 42)
  ws_port         WebSocket port Blender connects to      (default 8765)

Any extra keyword arguments are forwarded to generate_agents! (e.g.
pref_density_μ, budget_μ, budget_σ, etc.).
"""
function init_model(;
    n_x      ::Int = 10,
    n_y      ::Int = 10,
    k        ::Int = 8,
    n_agents ::Int = 0,
    seed     ::Int = 42,
    ws_port  ::Int = 8765,
    ctrl_port::Int = 8766,
    kwargs...
)
    rng = MersenneTwister(seed)

    @printf "=== NIMBY ABM ===\n"
    @printf "City   : %d×%d neighbourhoods, k=%d  →  %d buildings\n" n_x n_y k (n_x*n_y*k*k)
    @printf "Agents : %d   seed: %d\n\n" n_agents seed

    city     = generate_city(n_x, n_y; k=k)
    generate_agents!(city, n_agents; rng=rng, kwargs...)

    city_ref = Ref{Union{Nothing,City}}(city)
    rng_ref  = Ref{AbstractRNG}(rng)
    vis      = Visualizer()
    listen!(vis, city_ref; port=ws_port)
    listen_control!(vis; port=ctrl_port)
    _ctrl_loop!(vis, city_ref, rng_ref)

    println("Blender → connect to  ws://127.0.0.1:$(ws_port)")
    println("Browser → open index.html  (control server: ws://127.0.0.1:$(ctrl_port))")
    println("Ready.\n")

    return city, vis, rng
end

# ============================================================
# Step loop
# ============================================================

"""
    run_steps!(city, vis, rng; n_steps, n_search, step_delay,
                                 agents_inflow, existing_move_share, blender_update_every,
                                 land_use_eval_every, land_use_eval_horizon)

Run `n_steps` steps of the model and print a one-line summary after each step.
If `require_authorization=true` (default), Julia prompts for approval before
running the step batch.
If `agents_inflow > 0`, that many new agents are appended before each step.
`existing_move_share` controls the random share of existing agents that
attempt relocation each step before new arrivals are added.
Blender updates are throttled by `blender_update_every`:
  - `0`  → send once at the end of the batch
  - `k>0` → send every `k` steps (and once at the end if needed)
Land-use policy evaluation:
  - every `land_use_eval_every` steps, each neighbourhood runs a
    hypothetical branch pair (`with_rule` / `without_rule`) for
    `land_use_eval_horizon` steps with hypothetical entrants only.
  - majority utility vote by incumbent residents decides adoption.

Can be called repeatedly from the REPL for interactive exploration:

    city, vis, rng = init_model(n_agents = 5_000)
    run_steps!(city, vis, rng; n_steps = 10)
    set_color_scheme!(vis; attribute = "height", max_value = 20.0)
    run_steps!(city, vis, rng; n_steps = 10)
"""
function run_steps!(
    city      ::City,
    vis       ::Visualizer,
    rng       ::AbstractRNG;
    n_steps   ::Int     = 1000,
    n_search  ::Int     = 5,
    agents_inflow::Int  = 100,
    existing_move_share::Float64 = 0.1,
    blender_update_every::Int = 0,
    land_use_eval_every::Int = 10,
    land_use_eval_horizon::Int = 10,
    step_delay::Float64 = 0.1,
    allow_displacement::Bool = false,
    law_allow_displacement::Bool = false,
    law_incumbent_mover_share::Float64 = 0.0,
    law_incumbent_can_build::Bool = false,
    enable_roads::Bool = false,
    road_eval_every::Int = 20,
    road_unit::Float32 = 1f0,
    enable_employer::Bool = false,
    employer_eval_every::Int = 1,
    employer_n_candidates::Int = 5,
    employer_horizon::Int = 3,
    # Agent generation parameters (forwarded to add_agents! for each inflow batch)
    pref_density_μ       ::Float32 = 3.0f0,
    pref_density_σ       ::Float32 = 2.0f0,
    pref_nh_max_height_μ ::Float32 = 6.0f0,
    pref_nh_max_height_σ ::Float32 = 2.0f0,
    pref_nh_min_height_μ ::Float32 = 1.0f0,
    pref_nh_min_height_σ ::Float32 = 1.0f0,
    pref_height_μ        ::Float32 = 3.0f0,
    pref_height_σ        ::Float32 = 2.0f0,
    σ_neighborhood_μ     ::Float32 = -0.5f0,
    σ_neighborhood_σ     ::Float32 = 0.3f0,
    σ_building_μ         ::Float32 = -0.5f0,
    σ_building_σ         ::Float32 = 0.3f0,
    proximity_scale_μ    ::Float32 = 2.5f0,
    proximity_scale_σ    ::Float32 = 0.5f0,
    copula_θ_μ           ::Float32 = 0.7f0,
    copula_θ_σ           ::Float32 = 0.4f0,
    budget_μ             ::Float32 = 1.0f0,
    budget_σ             ::Float32 = 0.5f0,
    require_authorization::Bool = true,
)
    if require_authorization
        print("Authorize run of $(n_steps) step(s)? [y/N]: ")
        ans = lowercase(strip(readline()))
        if !(ans in ("y", "yes"))
            println("Run cancelled.")
            return
        end
    end

    last_sent_step = 0
    for t in 1:n_steps
        vis.stop_flag[] && break

        if enable_roads && road_eval_every > 0 && t > 1 && (t - 1) % road_eval_every == 0
            road_data = evaluate_roads!(city; road_unit=road_unit, rng=rng)
            if road_data !== nothing
                send_new_roads!(vis, city)
                _broadcast_ctrl!(vis, Dict(
                    "type"    => "road",
                    "msg"     => road_data["msg"],
                    "nid_a"   => road_data["nid_a"],
                    "nid_b"   => road_data["nid_b"],
                    "score"   => road_data["score"],
                    "n_roads" => road_data["n_roads"],
                ))
            end
        end

        if land_use_eval_every > 0 && t > 1 && (t - 1) % land_use_eval_every == 0
            passed = evaluate_land_use_laws!(
                city, rng;
                horizon=land_use_eval_horizon,
                n_search=n_search,
                agents_inflow=agents_inflow,
                road_unit=road_unit,
                allow_displacement=law_allow_displacement,
                incumbent_mover_share=law_incumbent_mover_share,
                incumbent_can_build=law_incumbent_can_build,
            )
            for law_data in passed
                _broadcast_ctrl!(vis, Dict(
                    "type"       => "law",
                    "msg"        => law_data["msg"],
                    "nid"        => law_data["nid"],
                    "law_num"    => law_data["law_num"],
                    "tree"       => law_data["tree"],
                    "vote_share" => law_data["vote_share"],
                ))
            end
        end

        t0 = time()
        n_existing    = length(city.agents)
        unhoused_ids  = [i for i in 1:n_existing if city.agents[i].dwelling_id == 0]
        housed_ids    = [i for i in 1:n_existing if city.agents[i].dwelling_id != 0]
        n_movers_h    = clamp(round(Int, existing_move_share * length(housed_ids)), 0, length(housed_ids))
        housed_movers = n_movers_h > 0 ? housed_ids[randperm(rng, length(housed_ids))[1:n_movers_h]] : Int[]
        mover_ids     = vcat(unhoused_ids, housed_movers)
        step!(city; n_search=n_search, rng=rng, agent_ids=mover_ids, build_if_unhoused=true, allow_displacement=allow_displacement, road_unit=road_unit)

        n_before_inflow = length(city.agents)
        agents_inflow > 0 && add_agents!(city, agents_inflow; rng=rng,
            pref_density_μ=pref_density_μ, pref_density_σ=pref_density_σ,
            pref_nh_max_height_μ=pref_nh_max_height_μ, pref_nh_max_height_σ=pref_nh_max_height_σ,
            pref_nh_min_height_μ=pref_nh_min_height_μ, pref_nh_min_height_σ=pref_nh_min_height_σ,
            pref_height_μ=pref_height_μ, pref_height_σ=pref_height_σ,
            σ_neighborhood_μ=σ_neighborhood_μ, σ_neighborhood_σ=σ_neighborhood_σ,
            σ_building_μ=σ_building_μ, σ_building_σ=σ_building_σ,
            proximity_scale_μ=proximity_scale_μ, proximity_scale_σ=proximity_scale_σ,
            copula_θ_μ=copula_θ_μ, copula_θ_σ=copula_θ_σ,
            budget_μ=budget_μ, budget_σ=budget_σ)
        n_after_inflow = length(city.agents)
        new_ids = if n_after_inflow > n_before_inflow
            collect((n_before_inflow + 1):n_after_inflow)
        else
            Int[]
        end
        step!(city; n_search=n_search, rng=rng, agent_ids=new_ids, build_if_unhoused=true, allow_displacement=allow_displacement, road_unit=road_unit)

        # Assign new inflow agents to the employer, then evaluate location.
        if enable_employer && !isempty(city.employers)
            !isempty(new_ids) && assign_to_employer!(city, 1, new_ids)
            if employer_eval_every > 0 && t % employer_eval_every == 0
                emp_data = evaluate_employer_location!(city, rng, 1;
                    n_candidates=employer_n_candidates,
                    horizon=employer_horizon,
                    n_search=n_search,
                    road_unit=road_unit,
                )
                if emp_data !== nothing
                    _broadcast_ctrl!(vis, merge(emp_data, Dict("type" => "employer")))
                end
            end
        end

        elapsed = time() - t0

        if blender_update_every > 0 && (t % blender_update_every == 0)
            send_step_diff!(vis, city)
            last_sent_step = t
        end
        _print_stats(t, city, elapsed)
        send_ctrl_stats!(vis, t, city, elapsed)

        step_delay > 0.0 && sleep(step_delay)
    end

    if blender_update_every == 0 || last_sent_step != n_steps
        send_step_diff!(vis, city)
    end
end

@inline function _hist_bin!(h::Vector{Int}, u::Float32, n::Int)
    h[clamp(floor(Int, u * n) + 1, 1, n)] += 1
end

const _MODAL_MAX_HEIGHT = 20.0f0

@inline function _hist_bin_dim!(h::Vector{Int}, val::Float32, n::Int)
    h[clamp(floor(Int, val / _MODAL_MAX_HEIGHT * n) + 1, 1, n)] += 1
end

"""Histogram of agent preferred values in floor units (all agents, not just housed)."""
function _modal_histograms(city::City; n_bins::Int = 20)
    h_density = zeros(Int, n_bins)
    h_nh_max  = zeros(Int, n_bins)
    h_nh_min  = zeros(Int, n_bins)
    h_bldg    = zeros(Int, n_bins)
    for agent in city.agents
        _hist_bin_dim!(h_density, agent.pref_neighborhood_density,    n_bins)
        _hist_bin_dim!(h_nh_max,  agent.pref_neighborhood_max_height,  n_bins)
        _hist_bin_dim!(h_nh_min,  agent.pref_neighborhood_min_height,  n_bins)
        _hist_bin_dim!(h_bldg,    agent.pref_building_height,          n_bins)
    end
    return (density=h_density, nh_max=h_nh_max, nh_min=h_nh_min, bldg=h_bldg)
end

"""
Compute per-step utility histograms over all housed agents.
Returns four n_bins-length Int vectors:
  overall   — Frank-copula utility (all active dimensions)
  proximity — commute-distance marginal only
  nh        — neighbourhood median-height marginal only
  bldg      — building-height marginal only
"""
function _utility_histograms(city::City; n_bins::Int = 20)
    z = zeros(Int, n_bins)
    any(a -> a.dwelling_id != 0, city.agents) || return (overall=copy(z), proximity=copy(z), nh=copy(z), nh_max=copy(z), nh_min=copy(z), bldg=copy(z))

    nd_cache    = compute_nd_cache(city)
    h_overall   = zeros(Int, n_bins)
    h_proximity = zeros(Int, n_bins)
    h_nh        = zeros(Int, n_bins)
    h_bldg      = zeros(Int, n_bins)

    h_nh_max  = zeros(Int, n_bins)
    h_nh_min  = zeros(Int, n_bins)

    for agent in city.agents
        agent.dwelling_id == 0 && continue
        d    = city.dwellings[agent.dwelling_id]
        b    = city.buildings[d.building_id]
        jpos = city.buildings[agent.job_building_id].pos
        nid  = b.neighborhood_id

        dist = distance(b.pos, jpos)
        bh   = Float32(height(b))

        _hist_bin!(h_overall,   agent_utility(agent, b, nd_cache, jpos),                                         n_bins)
        _hist_bin!(h_proximity, _u_proximity(dist, agent.proximity_scale),                                        n_bins)
        _hist_bin!(h_nh,        _u_pct_diff(nd_cache.median[nid], agent.pref_neighborhood_density,   agent.σ_neighborhood), n_bins)
        _hist_bin!(h_nh_max,    _u_pct_diff(nd_cache.max[nid],    agent.pref_neighborhood_max_height, agent.σ_neighborhood), n_bins)
        _hist_bin!(h_nh_min,    _u_pct_diff(nd_cache.min[nid],    agent.pref_neighborhood_min_height, agent.σ_neighborhood), n_bins)
        _hist_bin!(h_bldg,      _u_pct_diff(bh, agent.pref_building_height, agent.σ_building),                   n_bins)
    end
    return (overall=h_overall, proximity=h_proximity, nh=h_nh, nh_max=h_nh_max, nh_min=h_nh_min, bldg=h_bldg)
end

function _print_stats(t::Int, city::City, elapsed::Float64)
    n_dw     = length(city.dwellings)
    n_agents = length(city.agents)
    n_housed = count(a -> a.dwelling_id != 0, city.agents)
    n_vacant = count(d -> d.occupant_id == 0, city.dwellings)
    occupied = filter(b -> height(b) > 0, city.buildings)
    h_mean   = isempty(occupied) ? 0.0 : mean(height.(occupied))
    h_max    = isempty(occupied) ? 0   : maximum(height.(occupied))
    n_empty_buildings = length(city.buildings) - length(occupied)

    @printf "step %4d | agents %6d | housed %6d | dwellings %6d | vacant %5d | mean h %5.2f | max h %3d | empty_bld %5d | %5.2fs\n" t n_agents n_housed n_dw n_vacant h_mean h_max n_empty_buildings elapsed
end

function send_ctrl_stats!(vis::Visualizer, t::Int, city::City, elapsed::Float64)
    isempty(vis.ctrl_clients) && return
    n_housed = count(a -> a.dwelling_id != 0, city.agents)
    n_vacant = count(d -> d.occupant_id == 0, city.dwellings)
    occupied = filter(b -> height(b) > 0, city.buildings)
    h_mean   = isempty(occupied) ? 0.0 : mean(height.(occupied))
    h_max    = isempty(occupied) ? 0   : maximum(height.(occupied))
    n_nh     = length(city.neighborhoods)
    n_laws   = count(laws -> !isempty(laws), city.neighborhood_laws)
    hists    = _utility_histograms(city)
    modal    = _modal_histograms(city)
    nd_map   = compute_nd_cache(city)
    emp_by_nh = zeros(Int, n_nh)
    for agent in city.agents
        emp_by_nh[Int(city.buildings[agent.job_building_id].neighborhood_id)] += 1
    end
    _broadcast_ctrl!(vis, Dict(
        "type"           => "stats",
        "step"           => t,
        "agents"         => length(city.agents),
        "housed"         => n_housed,
        "dwellings"      => length(city.dwellings),
        "vacant"         => n_vacant,
        "h_mean"         => round(h_mean; digits=2),
        "h_max"          => h_max,
        "elapsed"        => round(elapsed; digits=3),
        "n_neighborhoods" => n_nh,
        "pct_laws"       => round(100.0 * n_laws / n_nh; digits=1),
        "n_roads"        => length(city.roads),
        "employer_workers" => isempty(city.employers) ? 0 : length(city.employers[1].worker_ids),
        "employer_pos"   => if isempty(city.employers)
                                nothing
                            else
                                b = city.buildings[city.employers[1].job_building_id]
                                [Int(b.pos.x), Int(b.pos.y)]
                            end,
        "hist_overall"   => hists.overall,
        "hist_proximity" => hists.proximity,
        "hist_nh"        => hists.nh,
        "hist_nh_max"    => hists.nh_max,
        "hist_nh_min"    => hists.nh_min,
        "hist_bldg"      => hists.bldg,
        "modal_density"  => modal.density,
        "modal_nh_max"   => modal.nh_max,
        "modal_nh_min"   => modal.nh_min,
        "modal_bldg"     => modal.bldg,
        "nh_density"     => Float64.(nd_map.median),
        "nh_employment"  => emp_by_nh,
        "roads"          => [[Int(a), Int(b)] for (a, b) in city.roads],
    ))
end

"""
    _ctrl_loop!(vis, city_ref, rng_ref)

Background task that processes commands from `vis.incoming` (sent by both the
Blender add-on and the browser control UI).

Commands handled:
  start        — launch run_steps! as an async task using parameters from the message
  stop         — set stop_flag to interrupt a running batch
  reset / reset_request — stop + reset model + sync Blender
"""
function _ctrl_loop!(vis::Visualizer, city_ref, rng_ref)
    run_task = Ref{Union{Nothing,Task}}(nothing)
    _is_running() = (t = run_task[]; t !== nothing && !istaskdone(t))

    @async while true
        cmd = take!(vis.incoming)
        t   = get(cmd, "type", "")

        if t == "start"
            _is_running() && continue
            begin
                cur   = city_ref[]
                n_sq  = let v = get(cmd, "n_neighborhoods_sqrt", nothing)
                            v !== nothing ? Int(v) : Int(round(sqrt(length(cur.neighborhoods))))
                        end
                k_val = let v = get(cmd, "k", nothing)
                            v !== nothing ? Int(v) : Int(cur.k)
                        end
                if n_sq^2 != length(cur.neighborhoods) || k_val != Int(cur.k)
                    new_city = generate_city(n_sq, n_sq; k=k_val)
                    city_ref[] = new_city
                    reset_vis!(vis)
                    full_sync!(vis, new_city)
                end
            end
            # Create employer if enabled and not yet present.
            if get(cmd, "enable_employer", false) && isempty(city_ref[].employers)
                city_c = city_ref[]
                cx  = Int(city_c.n_x) * Int(city_c.k) ÷ 2
                cy  = Int(city_c.n_y) * Int(city_c.k) ÷ 2
                nx  = cx ÷ Int(city_c.k);  bx = cx % Int(city_c.k)
                ny  = cy ÷ Int(city_c.k);  by = cy % Int(city_c.k)
                center_bid = Int32((ny * Int(city_c.n_x) + nx) * Int(city_c.k)^2 + by * Int(city_c.k) + bx + 1)
                push!(city_ref[].employers, Employer(Int32(1), center_bid, Set{Int32}()))
            end

            vis.stop_flag[] = false
            _broadcast_ctrl!(vis, Dict("type" => "running", "value" => true))
            city = city_ref[]
            rng  = rng_ref[]
            run_task[] = @async begin
                try
                    run_steps!(city, vis, rng;
                        require_authorization  = false,
                        n_steps                = get(cmd, "n_steps",               1000)  |> Int,
                        n_search               = get(cmd, "n_search",              5)     |> Int,
                        agents_inflow          = get(cmd, "agents_inflow",         100)   |> Int,
                        existing_move_share    = get(cmd, "existing_move_share",   0.1)   |> Float64,
                        blender_update_every   = get(cmd, "blender_update_every",  0)     |> Int,
                        land_use_eval_every    = get(cmd, "land_use_eval_every",   10)    |> Int,
                        land_use_eval_horizon  = get(cmd, "land_use_eval_horizon", 10)    |> Int,
                        step_delay             = get(cmd, "step_delay",            0.1)   |> Float64,
                        allow_displacement          = get(cmd, "allow_displacement",           false) |> Bool,
                        law_allow_displacement      = get(cmd, "law_allow_displacement",       false) |> Bool,
                        law_incumbent_mover_share   = get(cmd, "law_incumbent_mover_share",    0.0)   |> Float64,
                        law_incumbent_can_build     = get(cmd, "law_incumbent_can_build",      false) |> Bool,
                        enable_roads                = get(cmd, "enable_roads",                 false) |> Bool,
                        road_eval_every        = get(cmd, "road_eval_every",       20)    |> Int,
                        road_unit              = get(cmd, "road_unit",             1.0)   |> Float32,
                        enable_employer        = get(cmd, "enable_employer",       false) |> Bool,
                        employer_eval_every    = get(cmd, "employer_eval_every",   1)     |> Int,
                        employer_n_candidates  = get(cmd, "employer_n_candidates", 5)     |> Int,
                        employer_horizon       = get(cmd, "employer_horizon",      3)     |> Int,
                        pref_density_μ         = Float32(get(cmd, "pref_density_μ",       3.0)),
                        pref_density_σ         = Float32(get(cmd, "pref_density_σ",       2.0)),
                        pref_nh_max_height_μ   = Float32(get(cmd, "pref_nh_max_height_μ", 6.0)),
                        pref_nh_max_height_σ   = Float32(get(cmd, "pref_nh_max_height_σ", 2.0)),
                        pref_nh_min_height_μ   = Float32(get(cmd, "pref_nh_min_height_μ", 1.0)),
                        pref_nh_min_height_σ   = Float32(get(cmd, "pref_nh_min_height_σ", 1.0)),
                        pref_height_μ          = Float32(get(cmd, "pref_height_μ",        3.0)),
                        pref_height_σ          = Float32(get(cmd, "pref_height_σ",        2.0)),
                        σ_neighborhood_μ       = Float32(get(cmd, "σ_neighborhood_μ",    -0.5)),
                        σ_neighborhood_σ       = Float32(get(cmd, "σ_neighborhood_σ",     0.3)),
                        σ_building_μ           = Float32(get(cmd, "σ_building_μ",        -0.5)),
                        σ_building_σ           = Float32(get(cmd, "σ_building_σ",         0.3)),
                        proximity_scale_μ      = Float32(get(cmd, "proximity_scale_μ",    2.5)),
                        proximity_scale_σ      = Float32(get(cmd, "proximity_scale_σ",    0.5)),
                        copula_θ_μ             = Float32(get(cmd, "copula_θ_μ",           0.7)),
                        copula_θ_σ             = Float32(get(cmd, "copula_θ_σ",           0.4)),
                        budget_μ               = Float32(get(cmd, "budget_μ",             1.0)),
                        budget_σ               = Float32(get(cmd, "budget_σ",             0.5)),
                    )
                finally
                    vis.stop_flag[] = true
                    _broadcast_ctrl!(vis, Dict("type" => "running", "value" => false))
                end
            end

        elseif t == "stop"
            vis.stop_flag[] = true

        elseif t in ("reset", "reset_request")
            vis.stop_flag[] = true
            sleep(0.3)   # let the current step finish before clearing state
            reset_model!(city_ref[], vis, rng_ref[])
            _broadcast_ctrl!(vis, Dict("type" => "running", "value" => false))
        end
    end
end

"""
    reset_model!(city, vis, rng; n_agents=0, sync_blender=true, kwargs...) -> city

Reset model state in-place:
  • clears all dwellings from every building
  • clears the flat dwellings list
  • clears all agents
  • optionally seeds a new initial agent population via add_agents!

If `sync_blender=true`, also sends a reset message and a fresh full_sync!.
"""
function reset_model!(
    city::City,
    vis::Visualizer,
    rng::AbstractRNG;
    n_agents::Int = 0,
    sync_blender::Bool = true,
    kwargs...
)
    for b in city.buildings
        empty!(b.dwellings)
    end
    empty!(city.dwellings)
    empty!(city.agents)
    for i in eachindex(city.neighborhood_laws)
        empty!(city.neighborhood_laws[i])
    end
    empty!(city.roads)
    empty!(city.employers)
    rebuild_hop_cache!(city)
    n_agents > 0 && add_agents!(city, n_agents; rng=rng, kwargs...)

    if sync_blender
        reset_vis!(vis)
        full_sync!(vis, city)
    end
    _broadcast_ctrl!(vis, Dict("type" => "reset_state"))
    return city
end

# ============================================================
# Convenience wrapper
# ============================================================

"""
    run!(; kwargs...)

Initialise and run the model in one call.  All keyword arguments are forwarded
to init_model and run_steps! as appropriate.  Returns `(city, vis, rng)` for
further interactive use.

Quick start:
    include("main.jl")
    city, vis, rng = run!(n_agents=100, n_steps=10, step_delay=0.5)
"""
function run!(;
    n_x       ::Int     = 10,
    n_y       ::Int     = 10,
    k         ::Int     = 8,
    n_agents  ::Int     = 0,
    n_steps   ::Int     = 1000,
    n_search  ::Int     = 5,
    agents_inflow::Int  = 100,
    existing_move_share::Float64 = 0.1,
    blender_update_every::Int = 0,
    land_use_eval_every::Int = 10,
    land_use_eval_horizon::Int = 10,
    step_delay::Float64 = 0.1,
    allow_displacement::Bool = false,
    law_allow_displacement::Bool = false,
    law_incumbent_mover_share::Float64 = 0.0,
    law_incumbent_can_build::Bool = false,
    enable_roads::Bool = false,
    road_eval_every::Int = 20,
    road_unit::Float32 = 1f0,
    enable_employer::Bool = false,
    employer_eval_every::Int = 1,
    employer_n_candidates::Int = 5,
    employer_horizon::Int = 3,
    require_authorization::Bool = true,
    seed      ::Int     = 42,
    ws_port   ::Int     = 8765,
    ctrl_port ::Int     = 8766,
    kwargs...
)
    city, vis, rng = init_model(; n_x, n_y, k, n_agents, seed, ws_port, ctrl_port, kwargs...)
    run_steps!(
        city, vis, rng;
        n_steps, n_search, agents_inflow, existing_move_share, blender_update_every,
        land_use_eval_every, land_use_eval_horizon, step_delay, allow_displacement, law_allow_displacement,
        law_incumbent_mover_share, law_incumbent_can_build,
        enable_roads, road_eval_every, road_unit,
        enable_employer, employer_eval_every, employer_n_candidates, employer_horizon,
        require_authorization,
    )
    return city, vis, rng
end

# ============================================================
# Script entry point
# ============================================================

if abspath(PROGRAM_FILE) == @__FILE__
    city, vis, rng = init_model()
    if isinteractive()
        # REPL keeps the process alive and yields to async tasks while idle.
        println("REPL ready. Call run_steps!(city, vis, rng; ...) to step manually.")
    else
        # Non-interactive: block the main task so async servers stay alive.
        # All control comes from the browser (index.html).
        println("Running in headless mode. Control via browser at index.html.")
        println("Press Ctrl+C to exit.")
        while true
            sleep(60)
        end
    end
end
