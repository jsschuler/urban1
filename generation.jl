using Random
using StatsBase: sample, Weights

include("structs.jl")

# ============================================================
# City generation
# ============================================================

"""
    generate_city(n_x, n_y; k=8) -> City

Create an empty city grid of n_x × n_y neighborhoods, each k×k buildings.
All buildings start with no dwellings (height 0, job_weight 1).

Building names encode city-grid position: "({city_x},{city_y})".
"""
function generate_city(n_x::Int, n_y::Int; k::Int = 8)::City
    n_neighborhoods = n_x * n_y
    n_buildings     = n_neighborhoods * k * k

    # --- neighborhoods ---
    neighborhoods = Vector{Neighborhood}(undef, n_neighborhoods)
    for ny in 0:(n_y - 1), nx in 0:(n_x - 1)
        id = ny * n_x + nx + 1
        neighborhoods[id] = Neighborhood(Int32(id), Position(Int32(nx), Int32(ny)))
    end

    # --- buildings + neighborhood lookup ---
    buildings                 = Vector{Building}(undef, n_buildings)
    neighborhood_to_buildings = [Int32[] for _ in 1:n_neighborhoods]

    for ny in 0:(n_y - 1), nx in 0:(n_x - 1)
        nid = ny * n_x + nx + 1
        for by in 0:(k - 1), bx in 0:(k - 1)
            bid    = (ny * n_x + nx) * k * k + by * k + bx + 1
            city_x = Int32(nx * k + bx)
            city_y = Int32(ny * k + by)
            name   = "($(city_x),$(city_y))"
            buildings[bid] = Building(
                Int32(bid),
                Position(city_x, city_y),
                Int32(nid),
                name,
                Dwelling[],
            )
            push!(neighborhood_to_buildings[nid], Int32(bid))
        end
    end

    return City(
        neighborhoods,
        buildings,
        Dwelling[],
        Agent[],
        Int32(k), Int32(n_x), Int32(n_y),
        neighborhood_to_buildings,
    )
end

# ============================================================
# Agent generation
# ============================================================

"""
    generate_agents!(city, n_agents; rng, kwargs...)

Create n_agents agents with heterogeneous preferences and budgets.
Agents start unhoused (dwelling_id = 0).

Job buildings are assigned with probability proportional to job_weight(b) = height(b) + 1.
At initialisation all buildings are empty so every parcel has equal weight 1,
giving a uniform job distribution across the grid.

Preference parameters are drawn from truncated normals (floor at 0.5).
Budgets are drawn from a log-normal distribution.
"""
function generate_agents!(
    city::City,
    n_agents::Int;
    rng::AbstractRNG        = Random.default_rng(),
    pref_density_μ::Float32 = 3.0f0,
    pref_density_σ::Float32 = 2.0f0,
    pref_height_μ::Float32  = 3.0f0,
    pref_height_σ::Float32  = 2.0f0,
    σ_neighborhood::Float32 = 2.0f0,
    σ_building::Float32     = 2.0f0,
    w_proximity::Float32    = 1.0f0,
    w_neighborhood::Float32 = 1.0f0,
    w_building::Float32     = 1.0f0,
    budget_μ::Float32       = 1.0f0,   # log-normal parameters (log scale)
    budget_σ::Float32       = 0.5f0,
)
    n_buildings = length(city.buildings)

    # Job weights: height(b) + 1. At init all buildings are empty → uniform.
    weights  = Float64[job_weight(b) for b in city.buildings]
    job_bids = sample(rng, Int32(1):Int32(n_buildings), Weights(weights), n_agents)

    resize!(city.agents, n_agents)
    for i in 1:n_agents
        city.agents[i] = Agent(
            Int32(i),
            Int32(0),       # unhoused
            job_bids[i],
            exp(budget_μ + budget_σ * randn(rng, Float32)),   # log-normal budget
            max(0.5f0, pref_density_μ + pref_density_σ * randn(rng, Float32)),
            max(0.5f0, pref_height_μ  + pref_height_σ  * randn(rng, Float32)),
            σ_neighborhood,
            σ_building,
            w_proximity,
            w_neighborhood,
            w_building,
        )
    end
end
