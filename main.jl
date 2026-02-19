using Printf
using Random
using Statistics: mean

# Include in dependency order — each file is loaded exactly once.
# Individual files contain no include() calls themselves.
include("structs.jl")
include("utility.jl")
include("generation.jl")
include("step.jl")
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
    n_x     ::Int = 10,
    n_y     ::Int = 10,
    k       ::Int = 8,
    n_agents::Int = 0,
    seed    ::Int = 42,
    ws_port ::Int = 8765,
    kwargs...
)
    rng = MersenneTwister(seed)

    @printf "=== NIMBY ABM ===\n"
    @printf "City   : %d×%d neighbourhoods, k=%d  →  %d buildings\n" n_x n_y k (n_x*n_y*k*k)
    @printf "Agents : %d   seed: %d\n\n" n_agents seed

    city     = generate_city(n_x, n_y; k=k)
    generate_agents!(city, n_agents; rng=rng, kwargs...)

    # city_ref lets listen! push a full_sync! to any client that (re)connects
    city_ref = Ref{Union{Nothing,City}}(city)
    vis      = Visualizer()
    listen!(vis, city_ref; port=ws_port)

    println("Blender → connect to  ws://127.0.0.1:$(ws_port)")
    println("Run 'Setup Scene' in the NIMBY panel, then press Enter to start.\n")
    readline()

    return city, vis, rng
end

# ============================================================
# Step loop
# ============================================================

"""
    run_steps!(city, vis, rng; n_steps, n_search, step_delay,
                                 agents_inflow, existing_move_share, blender_update_every)

Run `n_steps` steps of the model and print a one-line summary after each step.
If `require_authorization=true` (default), Julia prompts for approval before
running the step batch.
If `agents_inflow > 0`, that many new agents are appended before each step.
`existing_move_share` controls the random share of existing agents that
attempt relocation each step before new arrivals are added.
Blender updates are throttled by `blender_update_every`:
  - `0`  → send once at the end of the batch
  - `k>0` → send every `k` steps (and once at the end if needed)

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
    step_delay::Float64 = 0.1,
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
        t0 = time()
        n_existing = length(city.agents)
        n_movers = clamp(round(Int, existing_move_share * n_existing), 0, n_existing)
        mover_ids = n_movers > 0 ? randperm(rng, n_existing)[1:n_movers] : Int[]
        step!(city; n_search=n_search, rng=rng, agent_ids=mover_ids, build_if_unhoused=false)

        n_before_inflow = length(city.agents)
        agents_inflow > 0 && add_agents!(city, agents_inflow; rng=rng)
        n_after_inflow = length(city.agents)
        new_ids = if n_after_inflow > n_before_inflow
            collect((n_before_inflow + 1):n_after_inflow)
        else
            Int[]
        end
        step!(city; n_search=n_search, rng=rng, agent_ids=new_ids, build_if_unhoused=true)
        elapsed = time() - t0

        if blender_update_every > 0 && (t % blender_update_every == 0)
            send_step_diff!(vis, city)
            last_sent_step = t
        end
        _print_stats(t, city, elapsed)

        step_delay > 0.0 && sleep(step_delay)
    end

    if blender_update_every == 0 || last_sent_step != n_steps
        send_step_diff!(vis, city)
    end
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
    n_agents > 0 && add_agents!(city, n_agents; rng=rng, kwargs...)

    if sync_blender
        reset_vis!(vis)
        full_sync!(vis, city)
    end
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
    step_delay::Float64 = 0.1,
    require_authorization::Bool = true,
    seed      ::Int     = 42,
    ws_port   ::Int     = 8765,
    kwargs...
)
    city, vis, rng = init_model(; n_x, n_y, k, n_agents, seed, ws_port, kwargs...)
    run_steps!(city, vis, rng; n_steps, n_search, agents_inflow, existing_move_share, blender_update_every, step_delay, require_authorization)
    return city, vis, rng
end

# ============================================================
# Script entry point
# ============================================================

if abspath(PROGRAM_FILE) == @__FILE__
    run!()
end
