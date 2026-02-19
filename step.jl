using Random
using StatsBase: sample, Weights

# ============================================================
# Neighbourhood density cache
# ============================================================

"""Mean building height across all buildings in neighbourhood nid."""
function neighborhood_density(city::City, nid::Int32)::Float32
    bids = city.neighborhood_to_buildings[nid]
    Float32(sum(height(city.buildings[bid]) for bid in bids)) / Float32(length(bids))
end

"""Snapshot neighbourhood densities once per step to avoid repeated O(k²) sums."""
function compute_nd_cache(city::City)::Vector{Float32}
    [neighborhood_density(city, Int32(nid)) for nid in 1:length(city.neighborhoods)]
end

# ============================================================
# Job assignment
# ============================================================

"""Assign jobs to selected agents; probability proportional to job_weight (height + 1)."""
function assign_jobs!(city::City, rng::AbstractRNG, agent_ids = eachindex(city.agents))
    n_b = Int32(length(city.buildings))
    w   = Weights(Float64[job_weight(b) for b in city.buildings])
    for i in agent_ids
        city.agents[i].job_building_id = sample(rng, Int32(1):n_b, w)
    end
end

# ============================================================
# Candidate search
# ============================================================

"""
Sample 2n candidate building IDs using alternating search criteria.

  Odd  draws (1, 3, …): weight by neighbourhood-density utility
                         → agent scouts areas that match density preference.
  Even draws (2, 4, …): weight by building-height utility × job proximity
                         → agent scouts buildings that match height preference
                            and are near work.
"""
function search_candidates(
    agent   ::Agent,
    city    ::City,
    nd_cache::Vector{Float32},
    n       ::Int,
    rng     ::AbstractRNG,
)::Vector{Int32}
    n_b  = length(city.buildings)
    jpos = city.buildings[agent.job_building_id].pos

    # Type-A weights: neighbourhood density marginal (consistent with copula)
    wA = Weights([begin
            nd = nd_cache[b.neighborhood_id]
            Float64(_u_pct_diff(nd, agent.pref_neighborhood_density, agent.σ_neighborhood)) + 1e-8
        end
        for b in city.buildings])

    # Type-B weights: building height marginal × proximity marginal
    wB = Weights([begin
            bh   = Float32(height(b))
            dist = distance(b.pos, jpos)
            uh   = Float64(_u_pct_diff(bh,  agent.pref_building_height, agent.σ_building))
            up   = Float64(_u_proximity(dist, agent.proximity_scale))
            uh * up + 1e-8
        end
        for b in city.buildings])

    out = Vector{Int32}(undef, 2n)
    for i in 1:2n
        out[i] = sample(rng, Int32(1):Int32(n_b), isodd(i) ? wA : wB)
    end
    return out
end

# ============================================================
# Housing actions
# ============================================================

function build_and_move_in!(agent::Agent, b::Building, city::City)
    did   = Int32(length(city.dwellings) + 1)
    floor = Int32(length(b.dwellings) + 1)
    d     = Dwelling(did, b.id, floor, b.name, agent.id)
    push!(b.dwellings, d)
    push!(city.dwellings, d)

    if agent.dwelling_id != 0
        old = city.dwellings[agent.dwelling_id]
        old.occupant_id = 0
    end
    agent.dwelling_id = did
end

function move_into_vacant!(agent::Agent, d::Dwelling, city::City)
    if agent.dwelling_id != 0 && agent.dwelling_id != d.id
        old = city.dwellings[agent.dwelling_id]
        old.occupant_id = 0
    end
    d.occupant_id = agent.id
    agent.dwelling_id = d.id
end

"""Sample existing dwellings (vacant and occupied) uniformly at random."""
function search_dwellings(city::City, n::Int, rng::AbstractRNG)::Vector{Dwelling}
    n_dw = length(city.dwellings)
    n_dw == 0 && return Dwelling[]
    m = min(max(1, 2n), n_dw)
    idx = sample(rng, 1:n_dw, m; replace=false)
    return city.dwellings[idx]
end

# ============================================================
# Main step
# ============================================================

"""
    step!(city; n_search, rng)

One model step:

1. Assign jobs for the selected agent subset (typically newly added agents).
2. Snapshot neighbourhood densities (used for search weights and utility ranking).
3. Shuffle selected agents and process each one:
     a. Sample existing dwellings (vacant and occupied) at random.
     b. Among sampled dwellings, pick the highest-utility vacant one (if any).
     c. Otherwise build a new dwelling in the top-utility sampled building.
"""
function step!(
    city     ::City;
    n_search ::Int          = 5,
    rng      ::AbstractRNG  = Random.default_rng(),
    agent_ids              = eachindex(city.agents),
)
    isempty(agent_ids) && return

    # 1. Assign jobs for selected agents only
    assign_jobs!(city, rng, agent_ids)

    # 2. Snapshot neighbourhood densities at step start
    nd_cache = compute_nd_cache(city)

    # 3. Process selected agents once in random order
    selected = [city.agents[i] for i in agent_ids]
    for agent in shuffle(rng, selected)
        jpos = city.buildings[agent.job_building_id].pos

        # --- sampled building fallback for potential new construction ---
        cand_bids   = search_candidates(agent, city, nd_cache, n_search, rng)
        unique_bids = unique(cand_bids)
        sort!(unique_bids;
              by  = bid -> agent_utility(agent, city.buildings[bid], nd_cache, jpos),
              rev = true)

        # --- sample existing dwellings and take best sampled vacancy ---
        sampled = search_dwellings(city, n_search, rng)
        best_d = nothing
        best_u = -Inf32

        for d in sampled
            if d.occupant_id == 0 || d.occupant_id == agent.id
                b = city.buildings[d.building_id]
                u = agent_utility(agent, b, nd_cache, jpos)
                if u > best_u
                    best_u = u
                    best_d = d
                end
            end
        end

        if best_d === nothing
            build_and_move_in!(agent, city.buildings[first(unique_bids)], city)
        else
            move_into_vacant!(agent, best_d, city)
        end
    end
end
