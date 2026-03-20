# sweep.jl — Overnight parameter sweep (no visualizer)
#
# Run:   julia --project sweep.jl
#
# Sweeps:
#   enable_roads    ∈ {false, true}         — transport on/off
#   law_every  (T) ∈ {5, 10, 20}           — how often zoning votes happen
#   law_horizon (H) ∈ {3, 7, 15}           — look-ahead horizon for branch simulation
#   n_sqrt          ∈ {6, 8, 10}           — city side length (city = n×n neighbourhoods, k=8)
#   seed            ∈ {42, 137, 999}        — replication
#
# Total configs: 2 × 3 × 3 × 3 × 3 = 162 runs
# Results:       sweep_results/<run_id>.csv  (one per run, written as each completes)
#                sweep_results/all_runs.csv  (merged at end)

using Distributed

const N_WORKERS = min(Sys.CPU_THREADS - 1, 15)
@info "Starting $(N_WORKERS) workers on $(Sys.CPU_THREADS)-core machine"
addprocs(N_WORKERS)

# ── Load model on every worker ────────────────────────────────────────────────
@everywhere begin
    using Random, Statistics, StatsBase, CSV, DataFrames, JSON3

    include("structs.jl")
    include("transport.jl")
    include("utility.jl")
    include("generation.jl")
    include("step.jl")
    include("laws.jl")
    include("employer.jl")

    # Sweep-wide constants (must be defined on workers, not just main process)
    const N_SEARCH  = 5
    const ROAD_UNIT = 10f0   # effective subway unit distance
    const ROAD_EVERY = 10    # road planner fires every N steps when enabled
    const MOVE_SHARE = 0.1   # fraction of housed agents attempting relocation per step
end

using CSV, DataFrames, Dates

# ── Sweep grid ─────────────────────────────────────────────────────────────────
const SEEDS        = [42, 137, 999]
const ENABLE_ROADS = [false, true]
const LAW_EVERY    = [5, 10, 20]         # T  — law evaluation frequency (steps)
const LAW_HORIZON  = [3, 7, 15]          # H  — branch simulation look-ahead
const CITY_SIZES   = [6, 8, 10]          # n_sqrt (k=8 fixed → 6²×64 … 10²×64 buildings)
const N_STEPS      = 100
const K            = 8

# Population is FIXED across city sizes so density varies with n_sqrt.
# Small city (6×6) → crowded → more law formation pressure.
# Large city (10×10) → sparse → different law dynamics and height inequality.
const N_AGENTS_INIT = 500
const AGENTS_INFLOW =  50

configs = NamedTuple[]
for seed in SEEDS, roads in ENABLE_ROADS, T in LAW_EVERY, H in LAW_HORIZON, ns in CITY_SIZES
    push!(configs, (
        seed          = seed,
        enable_roads  = roads,
        law_every     = T,
        law_horizon   = H,
        n_sqrt        = ns,
        k             = K,
        n_agents_init = N_AGENTS_INIT,
        agents_inflow = AGENTS_INFLOW,
        n_steps       = N_STEPS,
    ))
end

@info "Sweep: $(length(configs)) configs on $(N_WORKERS) workers"
@info "Estimated completion: $(Dates.now() + Dates.Minute(length(configs) ÷ N_WORKERS * 10))"

mkpath("sweep_results")

# ── Per-run function (runs entirely on a worker process) ──────────────────────
@everywhere function run_and_save(cfg, out_dir)::String
    rng  = MersenneTwister(cfg.seed)
    city = generate_city(cfg.n_sqrt, cfg.n_sqrt; k=cfg.k)
    generate_agents!(city, cfg.n_agents_init; rng=rng)

    cfg.enable_roads && rebuild_hop_cache!(city)

    rows = Vector{NamedTuple}()
    sizehint!(rows, cfg.n_steps)

    for t in 1:cfg.n_steps
        t0 = time()

        # ── Road planner (before step, matching main.jl ordering) ───────────
        if cfg.enable_roads && t > 1 && (t - 1) % ROAD_EVERY == 0
            evaluate_roads!(city; road_unit=ROAD_UNIT, rng=rng)
        end

        # ── Zoning law evaluation ────────────────────────────────────────────
        if t > 1 && (t - 1) % cfg.law_every == 0
            evaluate_land_use_laws!(city, rng;
                horizon               = cfg.law_horizon,
                n_search              = N_SEARCH,
                agents_inflow         = cfg.agents_inflow,
                road_unit             = ROAD_UNIT,
                allow_displacement    = false,
                incumbent_mover_share = 0.0,
                incumbent_can_build   = false,
            )
        end

        # ── Agent movers: all unhoused + MOVE_SHARE of housed ───────────────
        n_existing    = length(city.agents)
        unhoused_ids  = [i for i in 1:n_existing if city.agents[i].dwelling_id == 0]
        housed_ids    = [i for i in 1:n_existing if city.agents[i].dwelling_id != 0]
        n_movers_h    = clamp(round(Int, MOVE_SHARE * length(housed_ids)), 0, length(housed_ids))
        housed_movers = n_movers_h > 0 ?
            housed_ids[randperm(rng, length(housed_ids))[1:n_movers_h]] : Int[]

        step!(city;
            n_search          = N_SEARCH,
            rng               = rng,
            agent_ids         = vcat(unhoused_ids, housed_movers),
            build_if_unhoused = true,
            road_unit         = ROAD_UNIT,
        )

        # ── Inflow ───────────────────────────────────────────────────────────
        n_before = length(city.agents)
        add_agents!(city, cfg.agents_inflow; rng=rng)
        n_after  = length(city.agents)
        new_ids  = n_after > n_before ? collect((n_before + 1):n_after) : Int[]

        step!(city;
            n_search          = N_SEARCH,
            rng               = rng,
            agent_ids         = new_ids,
            build_if_unhoused = true,
            road_unit         = ROAD_UNIT,
        )

        elapsed = time() - t0

        # ── Metrics ──────────────────────────────────────────────────────────
        n_total  = length(city.agents)
        n_housed = count(a -> a.dwelling_id != 0, city.agents)
        occupied = [b for b in city.buildings if height(b) > 0]
        mean_h   = isempty(occupied) ? 0.0 : mean(height.(occupied))
        max_h    = isempty(occupied) ? 0   : maximum(height.(occupied))
        n_nh     = length(city.neighborhoods)
        n_laws   = count(v -> !isempty(v), city.neighborhood_laws)
        n_roads  = length(city.roads)

        # Height distribution (deciles) of occupied buildings
        heights  = isempty(occupied) ? zeros(Float64, 10) :
                   [quantile(Float64.(height.(occupied)), q) for q in 0.1:0.1:1.0]

        push!(rows, (
            seed          = cfg.seed,
            enable_roads  = cfg.enable_roads,
            law_every     = cfg.law_every,
            law_horizon   = cfg.law_horizon,
            n_sqrt        = cfg.n_sqrt,
            step          = t,
            n_agents      = n_total,
            housed_frac   = n_housed / max(1, n_total),
            mean_height   = mean_h,
            max_height    = max_h,
            pct_laws      = 100.0 * n_laws / n_nh,
            n_roads       = n_roads,
            height_p10    = heights[1],
            height_p50    = heights[5],
            height_p90    = heights[9],
            elapsed_s     = elapsed,
        ))
    end

    run_id = "seed$(cfg.seed)_roads$(cfg.enable_roads)_T$(cfg.law_every)_H$(cfg.law_horizon)_n$(cfg.n_sqrt)"
    fname  = joinpath(out_dir, "$(run_id).csv")
    CSV.write(fname, DataFrame(rows))

    # ── City snapshot for Blender ─────────────────────────────────────────
    _save_city_snapshot(city, cfg, run_id, out_dir)

    return fname
end

# ── JSON city snapshot ────────────────────────────────────────────────────────
# Produces a file that blender_sweep_loader.py can read directly.
# Format mirrors the messages blender_vis.py already understands:
#   city_config  →  {n_x, n_y, k}
#   dwellings    →  [{id, x, y, floor, budget}]   (budget=0 for vacant)
#   roads        →  [{nid_a, nid_b, x_a, y_a, x_b, y_b}]
@everywhere function _save_city_snapshot(city, cfg, run_id, out_dir)
    n_x = Int(city.n_x)
    n_y = Int(city.n_y)
    k   = Int(city.k)

    # Agent id → budget lookup
    agent_budget = Dict{Int32,Float32}(a.id => a.budget for a in city.agents)

    # Dwellings (same fields as "new_dwellings" WebSocket message)
    dw_list = Vector{Dict{String,Any}}(undef, length(city.dwellings))
    for (i, d) in enumerate(city.dwellings)
        b      = city.buildings[d.building_id]
        budget = d.occupant_id == 0 ? 0.0f0 : get(agent_budget, d.occupant_id, 0.0f0)
        dw_list[i] = Dict(
            "id"    => Int(d.id),
            "x"     => Int(b.pos.x),
            "y"     => Int(b.pos.y),
            "floor" => Int(d.floor),
            "budget"=> Float64(budget),
        )
    end

    # Roads with neighbourhood-centre coordinates (same as "new_roads" message)
    road_list = Vector{Dict{String,Any}}(undef, length(city.roads))
    for (i, (nid_a, nid_b)) in enumerate(city.roads)
        ca = nh_center(city, Int(nid_a))
        cb = nh_center(city, Int(nid_b))
        road_list[i] = Dict(
            "nid_a" => Int(nid_a), "nid_b" => Int(nid_b),
            "x_a"   => Float64(ca.x), "y_a" => Float64(ca.y),
            "x_b"   => Float64(cb.x), "y_b" => Float64(cb.y),
        )
    end

    snapshot = Dict(
        "run_id"      => run_id,
        "run_config"  => Dict(string(k2) => v for (k2, v) in pairs(cfg)),
        "city_config" => Dict("n_x" => n_x, "n_y" => n_y, "k" => k),
        "dwellings"   => dw_list,
        "roads"       => road_list,
    )

    open(joinpath(out_dir, "$(run_id)_city.json"), "w") do io
        JSON3.write(io, snapshot)
    end
end

# ── Parallel execution ────────────────────────────────────────────────────────
t_start = time()
fnames  = pmap(cfg -> run_and_save(cfg, "sweep_results"), configs)

elapsed_total = round((time() - t_start) / 60; digits=1)
@info "All $(length(fnames)) runs complete in $(elapsed_total) min"

# ── Merge all per-run CSVs into a single master file ─────────────────────────
df = reduce(vcat, [CSV.read(f, DataFrame) for f in fnames])
CSV.write("sweep_results/all_runs.csv", df)
@info "Merged $(nrow(df)) rows → sweep_results/all_runs.csv"
