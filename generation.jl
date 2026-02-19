using Random
using StatsBase: sample, Weights

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
    rng::AbstractRNG           = Random.default_rng(),
    # Preference means and spreads (truncated normal, floor at 0.5)
    pref_density_μ::Float32    = 3.0f0,
    pref_density_σ::Float32    = 2.0f0,
    pref_nh_max_height_μ::Float32 = 6.0f0,
    pref_nh_max_height_σ::Float32 = 2.0f0,
    pref_nh_min_height_μ::Float32 = 1.0f0,
    pref_nh_min_height_σ::Float32 = 1.0f0,
    pref_height_μ::Float32     = 3.0f0,
    pref_height_σ::Float32     = 2.0f0,
    # Marginal sensitivity parameters (% deviation scale; log-normal so always > 0)
    σ_neighborhood_μ::Float32  = 0.5f0,   # log-scale mean  (median ≈ exp(0.5) ≈ 1.65)
    σ_neighborhood_σ::Float32  = 0.3f0,
    σ_building_μ::Float32      = 0.5f0,
    σ_building_σ::Float32      = 0.3f0,
    # Proximity decay scale in building units (log-normal; median ≈ exp(2.5) ≈ 12)
    proximity_scale_μ::Float32 = 2.5f0,
    proximity_scale_σ::Float32 = 0.5f0,
    # Frank copula θ > 0 (log-normal; median ≈ exp(0.7) ≈ 2)
    copula_θ_μ::Float32        = 0.7f0,
    copula_θ_σ::Float32        = 0.4f0,
    # Budget (log-normal)
    budget_μ::Float32          = 1.0f0,
    budget_σ::Float32          = 0.5f0,
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
            exp(budget_μ          + budget_σ          * randn(rng, Float32)),
            max(0.5f0, pref_density_μ + pref_density_σ * randn(rng, Float32)),
            max(1.0f0, pref_nh_max_height_μ + pref_nh_max_height_σ * randn(rng, Float32)),
            max(0.0f0, pref_nh_min_height_μ + pref_nh_min_height_σ * randn(rng, Float32)),
            max(0.5f0, pref_height_μ  + pref_height_σ  * randn(rng, Float32)),
            exp(σ_neighborhood_μ  + σ_neighborhood_σ  * randn(rng, Float32)),
            exp(σ_building_μ      + σ_building_σ      * randn(rng, Float32)),
            exp(proximity_scale_μ + proximity_scale_σ * randn(rng, Float32)),
            exp(copula_θ_μ        + copula_θ_σ        * randn(rng, Float32)),
        )
    end
end

"""
    add_agents!(city, n_new; rng, kwargs...)

Append `n_new` additional agents to the existing city population.
Agent IDs continue from the current maximum ID.
"""
function add_agents!(
    city::City,
    n_new::Int;
    rng::AbstractRNG           = Random.default_rng(),
    # Preference means and spreads (truncated normal, floor at 0.5)
    pref_density_μ::Float32    = 3.0f0,
    pref_density_σ::Float32    = 2.0f0,
    pref_nh_max_height_μ::Float32 = 6.0f0,
    pref_nh_max_height_σ::Float32 = 2.0f0,
    pref_nh_min_height_μ::Float32 = 1.0f0,
    pref_nh_min_height_σ::Float32 = 1.0f0,
    pref_height_μ::Float32     = 3.0f0,
    pref_height_σ::Float32     = 2.0f0,
    # Marginal sensitivity parameters (% deviation scale; log-normal so always > 0)
    σ_neighborhood_μ::Float32  = 0.5f0,
    σ_neighborhood_σ::Float32  = 0.3f0,
    σ_building_μ::Float32      = 0.5f0,
    σ_building_σ::Float32      = 0.3f0,
    # Proximity decay scale in building units (log-normal; median ≈ exp(2.5) ≈ 12)
    proximity_scale_μ::Float32 = 2.5f0,
    proximity_scale_σ::Float32 = 0.5f0,
    # Frank copula θ > 0 (log-normal; median ≈ exp(0.7) ≈ 2)
    copula_θ_μ::Float32        = 0.7f0,
    copula_θ_σ::Float32        = 0.4f0,
    # Budget (log-normal)
    budget_μ::Float32          = 1.0f0,
    budget_σ::Float32          = 0.5f0,
)
    n_new <= 0 && return

    n_buildings = length(city.buildings)
    weights     = Float64[job_weight(b) for b in city.buildings]
    job_bids    = sample(rng, Int32(1):Int32(n_buildings), Weights(weights), n_new)

    id0 = length(city.agents)
    for i in 1:n_new
        push!(city.agents, Agent(
            Int32(id0 + i),
            Int32(0),  # unhoused
            job_bids[i],
            exp(budget_μ          + budget_σ          * randn(rng, Float32)),
            max(0.5f0, pref_density_μ + pref_density_σ * randn(rng, Float32)),
            max(1.0f0, pref_nh_max_height_μ + pref_nh_max_height_σ * randn(rng, Float32)),
            max(0.0f0, pref_nh_min_height_μ + pref_nh_min_height_σ * randn(rng, Float32)),
            max(0.5f0, pref_height_μ  + pref_height_σ  * randn(rng, Float32)),
            exp(σ_neighborhood_μ  + σ_neighborhood_σ  * randn(rng, Float32)),
            exp(σ_building_μ      + σ_building_σ      * randn(rng, Float32)),
            exp(proximity_scale_μ + proximity_scale_σ * randn(rng, Float32)),
            exp(copula_θ_μ        + copula_θ_σ        * randn(rng, Float32)),
        ))
    end
end
