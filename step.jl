using Random
using StatsBase: sample, Weights
using Statistics: median

# ============================================================
# Neighbourhood density cache
# ============================================================

"""Mean building height across all buildings in neighbourhood nid."""
function neighborhood_density(city::City, nid::Int32)::Float32
    bids = city.neighborhood_to_buildings[nid]
    Float32(sum(height(city.buildings[bid]) for bid in bids)) / Float32(length(bids))
end

"""Snapshot neighbourhood stats once per step to avoid repeated O(k²) scans."""
function compute_nd_cache(city::City)
    n = length(city.neighborhoods)
    nd_median = Vector{Float32}(undef, n)
    nd_max  = Vector{Float32}(undef, n)
    nd_min  = Vector{Float32}(undef, n)
    nd_vacancy = Vector{Float32}(undef, n)

    for nid in 1:n
        bids = city.neighborhood_to_buildings[nid]
        hs = [Float32(height(city.buildings[bid])) for bid in bids]
        nd_median[nid] = isempty(hs) ? 0f0 : Float32(median(hs))
        nd_max[nid]  = isempty(hs) ? 0f0 : maximum(hs)
        nd_min[nid]  = isempty(hs) ? 0f0 : minimum(hs)
        n_dw = 0
        n_vac = 0
        for bid in bids
            for d in city.buildings[bid].dwellings
                n_dw += 1
                n_vac += d.occupant_id == 0 ? 1 : 0
            end
        end
        nd_vacancy[nid] = n_dw == 0 ? 1f0 : Float32(n_vac / n_dw)
    end
    return (median=nd_median, max=nd_max, min=nd_min, vacancy_rate=nd_vacancy)
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
    agent    ::Agent,
    city     ::City,
    nd_cache,
    n        ::Int,
    rng      ::AbstractRNG,
    road_unit::Float32 = 1f0,
)::Vector{Int32}
    n_b   = length(city.buildings)
    jpos  = city.buildings[agent.job_building_id].pos
    job_b = city.buildings[agent.job_building_id]

    # Type-A weights: neighbourhood density marginal (consistent with copula)
    wA = Weights([begin
            nd = nd_cache.median[b.neighborhood_id]
            Float64(_u_pct_diff(nd, agent.pref_neighborhood_density, agent.σ_neighborhood)) + 1e-8
        end
        for b in city.buildings])

    # Type-B weights: building height marginal × proximity marginal (using effective distance)
    wB = Weights([begin
            bh = Float32(height(b))
            ed = effective_distance(city, b, job_b, road_unit)
            uh = Float64(_u_pct_diff(bh, agent.pref_building_height, agent.σ_building))
            up = Float64(_u_proximity(ed, agent.proximity_scale))
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

1. Keep job locations fixed (assigned at agent creation time).
2. Snapshot neighbourhood densities (used for utility ranking).
3. Shuffle selected agents and process each one:
     a. Sample existing dwellings (vacant and occupied) at random.
     b. Among sampled dwellings, find the best vacant option.
     c. Move only if that sampled vacant option improves utility over current home.
     d. If the agent is unhoused and no sampled vacancy is available, build.
"""
function step!(
    city     ::City;
    n_search ::Int          = 5,
    rng      ::AbstractRNG  = Random.default_rng(),
    agent_ids              = eachindex(city.agents),
    build_if_unhoused::Bool = true,
    allow_displacement::Bool = false,
    road_unit::Float32 = 1f0,
)
    isempty(agent_ids) && return

    # 1. Snapshot neighbourhood densities at step start
    nd_cache = compute_nd_cache(city)

    # 2. Process selected agents once in random order
    selected = [city.agents[i] for i in agent_ids]
    for agent in shuffle(rng, selected)
        jpos  = city.buildings[agent.job_building_id].pos
        job_b = city.buildings[agent.job_building_id]

        # --- sample existing dwellings, choose best vacant or displaceable candidate ---
        sampled = search_dwellings(city, n_search, rng)
        best_cand = nothing
        best_cand_u = -Inf32

        for d in sampled
            b  = city.buildings[d.building_id]
            ed = effective_distance(city, b, job_b, road_unit)
            if d.occupant_id == 0
                u = agent_utility(agent, b, nd_cache, jpos; eff_dist=ed)
                if u > best_cand_u
                    best_cand_u = u
                    best_cand = d
                end
            elseif allow_displacement && d.occupant_id != agent.id
                occupant = city.agents[d.occupant_id]
                if agent.budget > occupant.budget
                    u = agent_utility(agent, b, nd_cache, jpos; eff_dist=ed)
                    if u > best_cand_u
                        best_cand_u = u
                        best_cand = d
                    end
                end
            end
        end

        current_u = if agent.dwelling_id == 0
            -Inf32
        else
            cur_d  = city.dwellings[agent.dwelling_id]
            cur_b  = city.buildings[cur_d.building_id]
            cur_ed = effective_distance(city, cur_b, job_b, road_unit)
            agent_utility(agent, cur_b, nd_cache, jpos; eff_dist=cur_ed)
        end

        if best_cand !== nothing && best_cand_u > current_u
            if best_cand.occupant_id != 0
                city.agents[best_cand.occupant_id].dwelling_id = Int32(0)
            end
            move_into_vacant!(agent, best_cand, city)
            continue
        end

        if agent.dwelling_id == 0 && build_if_unhoused
            # No sampled vacancy available for an unhoused entrant: build.
            cand_bids   = search_candidates(agent, city, nd_cache, n_search, rng, road_unit)
            unique_bids = unique(cand_bids)
            sort!(unique_bids;
                  by  = bid -> begin
                      b_ = city.buildings[bid]
                      ed = effective_distance(city, b_, job_b, road_unit)
                      agent_utility(agent, b_, nd_cache, jpos; eff_dist=ed)
                  end,
                  rev = true)
            build_bid = findfirst(bid -> can_build_in_neighborhood(city, Int(city.buildings[bid].neighborhood_id), nd_cache), unique_bids)
            if build_bid !== nothing
                build_and_move_in!(agent, city.buildings[unique_bids[build_bid]], city)
            end
        end
    end
end
