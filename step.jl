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

"""Reassign every agent a job; probability proportional to job_weight (height + 1)."""
function assign_jobs!(city::City, rng::AbstractRNG)
    n_b = Int32(length(city.buildings))
    w   = Weights(Float64[job_weight(b) for b in city.buildings])
    for agent in city.agents
        agent.job_building_id = sample(rng, Int32(1):n_b, w)
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
    agent.dwelling_id = did
end

function move_into_vacant!(agent::Agent, d::Dwelling)
    d.occupant_id = agent.id
    agent.dwelling_id = d.id
end

"""Move agent into `d`, evict current occupant, return the evicted agent."""
function displace_and_move_in!(agent::Agent, d::Dwelling, city::City)::Agent
    evicted           = city.agents[d.occupant_id]
    evicted.dwelling_id = Int32(0)
    d.occupant_id     = agent.id
    agent.dwelling_id = d.id
    return evicted
end

# ============================================================
# Main step
# ============================================================

"""
    step!(city; n_search, rng)

One model step:

1. Reassign all jobs (probability ∝ job_weight = height + 1).
2. Vacate all dwellings — every agent re-enters the housing market.
3. Snapshot neighbourhood densities (used for search weights and utility ranking).
4. Shuffle agents into a housing queue and process until all are housed:
     a. Search 2*n_search candidate buildings (alternating density / height+proximity).
     b. Rank unique candidates by full utility (descending).
     c. Walk the ranked list:
          - Vacant dwelling found        → move in, done.
          - Weakest occupant has lower budget → displace, add evicted to queue, done.
          - Otherwise                    → skip to next candidate.
     d. If list exhausted with no housing → build a new dwelling in the
        top-utility candidate building.
"""
function step!(
    city     ::City;
    n_search ::Int          = 5,
    rng      ::AbstractRNG  = Random.default_rng(),
)
    # 1. Reassign jobs
    assign_jobs!(city, rng)

    # 2. Vacate all existing dwellings
    for a in city.agents; a.dwelling_id  = Int32(0); end
    for d in city.dwellings; d.occupant_id = Int32(0); end

    # 3. Snapshot neighbourhood densities at step start
    nd_cache = compute_nd_cache(city)

    # 4. Build housing queue
    queue    = shuffle(rng, copy(city.agents))
    in_queue = Set{Int32}(a.id for a in queue)

    while !isempty(queue)
        agent = popfirst!(queue)
        delete!(in_queue, agent.id)

        jpos = city.buildings[agent.job_building_id].pos

        # --- search ---
        cand_bids   = search_candidates(agent, city, nd_cache, n_search, rng)
        unique_bids = unique(cand_bids)
        sort!(unique_bids;
              by  = bid -> agent_utility(agent, city.buildings[bid], nd_cache, jpos),
              rev = true)

        # --- try to claim housing ---
        housed = false
        for bid in unique_bids
            b = city.buildings[bid]

            # Vacant dwelling?
            vi = findfirst(d -> d.occupant_id == 0, b.dwellings)
            if vi !== nothing
                move_into_vacant!(agent, b.dwellings[vi])
                housed = true
                break
            end

            # Displace the weakest occupant?
            if !isempty(b.dwellings)
                wi      = argmin(i -> city.agents[b.dwellings[i].occupant_id].budget,
                                 eachindex(b.dwellings))
                weakest = city.agents[b.dwellings[wi].occupant_id]
                if agent.budget > weakest.budget
                    evicted = displace_and_move_in!(agent, b.dwellings[wi], city)
                    if evicted.id ∉ in_queue
                        push!(queue, evicted)
                        push!(in_queue, evicted.id)
                    end
                    housed = true
                    break
                end
            end
        end

        # --- last resort: build in top-utility candidate ---
        if !housed
            build_and_move_in!(agent, city.buildings[first(unique_bids)], city)
        end
    end
end
