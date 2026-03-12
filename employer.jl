using Random
using StatsBase: sample, Weights

# ============================================================
# Employer helpers
# ============================================================

"""
    assign_to_employer!(city, eid, agent_ids)

Register agents as workers of employer `eid` and redirect their
job_building_id to the employer's current building.
"""
function assign_to_employer!(city::City, eid::Int, agent_ids)
    emp = city.employers[eid]
    for aid in agent_ids
        push!(emp.worker_ids, Int32(aid))
        city.agents[aid].job_building_id = emp.job_building_id
    end
end

# ============================================================
# Mean commute metric
# ============================================================

function _mean_employer_commute(city::City, eid::Int, road_unit::Float32)::Float64
    emp   = city.employers[eid]
    job_b = city.buildings[emp.job_building_id]
    total = 0.0
    n     = 0
    for aid in emp.worker_ids
        a = city.agents[aid]
        a.dwelling_id == 0 && continue
        home_b = city.buildings[city.dwellings[a.dwelling_id].building_id]
        total += Float64(effective_distance(city, home_b, job_b, road_unit))
        n     += 1
    end
    return n == 0 ? Inf64 : total / n
end

# ============================================================
# Location evaluation (branch simulation)
# ============================================================

"""
    evaluate_employer_location!(city, rng, eid; kwargs...) → Dict or nothing

Branch-simulate `n_candidates` candidate buildings for employer `eid`
and move to the one that minimises mean effective commute of housed workers.
The current location is always included as a candidate (move only if a
strictly better option is found).

Returns a Dict with event data if the employer moves, `nothing` otherwise.
"""
function evaluate_employer_location!(
    city        ::City,
    rng         ::AbstractRNG,
    eid         ::Int;
    n_candidates::Int     = 5,
    horizon     ::Int     = 3,
    n_search    ::Int     = 5,
    road_unit   ::Float32 = 1f0,
)
    emp            = city.employers[eid]
    housed_workers = [aid for aid in emp.worker_ids
                      if city.agents[aid].dwelling_id != 0]
    isempty(housed_workers) && return nothing

    # Sample candidate buildings weighted by job_weight; always include current.
    n_b  = length(city.buildings)
    wts  = Weights(Float64[job_weight(city.buildings[i]) for i in 1:n_b])
    cands = unique(vcat(
        sample(rng, collect(1:n_b), wts, n_candidates),
        [Int(emp.job_building_id)],
    ))

    seed = rand(rng, UInt)

    best_bid     = Int(emp.job_building_id)
    best_commute = _mean_employer_commute(city, eid, road_unit)

    for bid in cands
        bid == Int(emp.job_building_id) && continue   # already measured above

        city_b = deepcopy(city)
        city_b.employers[eid].job_building_id = Int32(bid)
        for aid in emp.worker_ids
            city_b.agents[aid].job_building_id = Int32(bid)
        end

        _simulate_hypothetical!(city_b, MersenneTwister(seed);
            horizon=horizon, n_search=n_search,
            agents_inflow=0, road_unit=road_unit)

        mc = _mean_employer_commute(city_b, eid, road_unit)
        if mc < best_commute
            best_commute = mc
            best_bid     = bid
        end
    end

    Int(emp.job_building_id) == best_bid && return nothing   # already optimal

    # Commit move
    emp.job_building_id = Int32(best_bid)
    for aid in emp.worker_ids
        city.agents[aid].job_building_id = Int32(best_bid)
    end

    b   = city.buildings[best_bid]
    msg = "Employer $(eid) → bldg $(best_bid) ($(b.pos.x),$(b.pos.y)) — " *
          "mean commute $(round(best_commute; digits=2)), " *
          "workers: $(length(emp.worker_ids))"
    println("[EMPLOYER] " * msg)

    return Dict{String,Any}(
        "eid"          => eid,
        "building_id"  => best_bid,
        "x"            => Int(b.pos.x),
        "y"            => Int(b.pos.y),
        "mean_commute" => round(best_commute; digits=2),
        "n_workers"    => length(emp.worker_ids),
        "msg"          => msg,
    )
end
