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
  n_agents        number of agents                        (default 10_000)
  seed            RNG seed                                (default 42)
  ws_port         WebSocket port Blender connects to      (default 8765)

Any extra keyword arguments are forwarded to generate_agents! (e.g.
pref_density_μ, budget_μ, budget_σ, etc.).
"""
function init_model(;
    n_x     ::Int = 10,
    n_y     ::Int = 10,
    k       ::Int = 8,
    n_agents::Int = 10_000,
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
    run_steps!(city, vis, rng; n_steps, n_search, step_delay)

Run `n_steps` steps of the model.  After each step the diff is pushed to Blender
and a one-line summary is printed.

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
    n_steps   ::Int     = 50,
    n_search  ::Int     = 5,
    step_delay::Float64 = 0.0,
)
    for t in 1:n_steps
        t0 = time()
        step!(city; n_search=n_search, rng=rng)
        elapsed = time() - t0

        send_step_diff!(vis, city)
        _print_stats(t, city, elapsed)

        step_delay > 0.0 && sleep(step_delay)
    end
end

function _print_stats(t::Int, city::City, elapsed::Float64)
    n_dw     = length(city.dwellings)
    n_housed = count(a -> a.dwelling_id != 0, city.agents)
    occupied = filter(b -> height(b) > 0, city.buildings)
    h_mean   = isempty(occupied) ? 0.0 : mean(height.(occupied))
    h_max    = isempty(occupied) ? 0   : maximum(height.(occupied))
    n_empty  = length(city.buildings) - length(occupied)

    @printf "step %4d | housed %6d | dwellings %6d | mean h %5.2f | max h %3d | empty %5d | %5.2fs\n" t n_housed n_dw h_mean h_max n_empty elapsed
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
    city, vis, rng = run!(n_agents=5_000, n_steps=20, step_delay=0.5)
"""
function run!(;
    n_x       ::Int     = 10,
    n_y       ::Int     = 10,
    k         ::Int     = 8,
    n_agents  ::Int     = 10_000,
    n_steps   ::Int     = 50,
    n_search  ::Int     = 5,
    step_delay::Float64 = 0.0,
    seed      ::Int     = 42,
    ws_port   ::Int     = 8765,
    kwargs...
)
    city, vis, rng = init_model(; n_x, n_y, k, n_agents, seed, ws_port, kwargs...)
    run_steps!(city, vis, rng; n_steps, n_search, step_delay)
    return city, vis, rng
end

# ============================================================
# Script entry point
# ============================================================

if abspath(PROGRAM_FILE) == @__FILE__
    run!()
end
