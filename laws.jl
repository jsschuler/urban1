using Random
using Statistics: median

const _LAW_FEATURES = (:median_height, :max_height, :min_height, :vacancy_rate)

@inline function _law_feature(obs, feature::Symbol)::Float32
    if feature === :median_height
        return obs.median
    elseif feature === :max_height
        return obs.max
    elseif feature === :min_height
        return obs.min
    elseif feature === :vacancy_rate
        return obs.vacancy_rate
    end
    return 0f0
end

function _eval_law_tree(node::LawNode, obs)::Bool
    node.is_leaf && return node.prohibit_new_build
    val = _law_feature(obs, node.feature)
    child = val <= node.threshold ? node.left : node.right
    child === nothing && return false
    return _eval_law_tree(child, obs)
end

function _random_leaf(rng::AbstractRNG)::LawNode
    LawNode(true, :median_height, 0f0, rand(rng, Bool), nothing, nothing)
end

function _random_split_node(rng::AbstractRNG, obs)::LawNode
    feature = rand(rng, _LAW_FEATURES)
    center = _law_feature(obs, feature)
    spread = max(0.25f0, abs(center) * 0.25f0)
    threshold = max(0f0, center + spread * randn(rng, Float32))
    LawNode(false, feature, threshold, false, nothing, nothing)
end

"""
Create a depth-2 random decision tree over neighbourhood observables.
Leaf values indicate whether new construction is prohibited.
"""
function random_law_tree(rng::AbstractRNG, obs)::LawNode
    root  = _random_split_node(rng, obs)
    left  = _random_split_node(rng, obs)
    right = _random_split_node(rng, obs)
    left.left   = _random_leaf(rng)
    left.right  = _random_leaf(rng)
    right.left  = _random_leaf(rng)
    right.right = _random_leaf(rng)
    root.left = left
    root.right = right
    return root
end

"""
Neighbourhood observables used for utility and policy evaluation.
"""
function neighborhood_observables(city::City, nid::Int)
    bids = city.neighborhood_to_buildings[nid]
    hs = Float32[]
    n_dw = 0
    n_vac = 0
    for bid in bids
        b = city.buildings[bid]
        h = Float32(height(b))
        push!(hs, h)
        for d in b.dwellings
            n_dw += 1
            n_vac += d.occupant_id == 0 ? 1 : 0
        end
    end
    med = isempty(hs) ? 0f0 : Float32(median(hs))
    mx  = isempty(hs) ? 0f0 : maximum(hs)
    mn  = isempty(hs) ? 0f0 : minimum(hs)
    vac_rate = n_dw == 0 ? 1f0 : Float32(n_vac / n_dw)
    return (median=med, max=mx, min=mn, vacancy_rate=vac_rate)
end

function can_build_in_neighborhood(city::City, nid::Int, nd_cache)::Bool
    laws = city.neighborhood_laws[nid]
    isempty(laws) && return true
    obs = (
        median = nd_cache.median[nid],
        max = nd_cache.max[nid],
        min = nd_cache.min[nid],
        vacancy_rate = nd_cache.vacancy_rate[nid],
    )
    # Any active law that prohibits construction blocks the build.
    for law in laws
        if law.active && law.tree !== nothing && _eval_law_tree(law.tree, obs)
            return false
        end
    end
    return true
end

function _law_node_to_dict(node::LawNode)::Dict{String,Any}
    if node.is_leaf
        return Dict{String,Any}("leaf" => true, "block" => node.prohibit_new_build)
    else
        d = Dict{String,Any}(
            "leaf"      => false,
            "feature"   => String(node.feature),
            "threshold" => round(Float64(node.threshold); digits=2),
        )
        node.left  !== nothing && (d["left"]  = _law_node_to_dict(node.left))
        node.right !== nothing && (d["right"] = _law_node_to_dict(node.right))
        return d
    end
end

function _residents_by_neighborhood(city::City)
    out = [Int32[] for _ in 1:length(city.neighborhoods)]
    for b in city.buildings
        nid = Int(b.neighborhood_id)
        for d in b.dwellings
            d.occupant_id != 0 && push!(out[nid], d.occupant_id)
        end
    end
    return out
end

function _agent_current_utility(city::City, agent_id::Int32, nd_cache)::Float32
    a = city.agents[agent_id]
    a.dwelling_id == 0 && return 0f0
    d = city.dwellings[a.dwelling_id]
    b = city.buildings[d.building_id]
    jpos = city.buildings[a.job_building_id].pos
    return agent_utility(a, b, nd_cache, jpos)
end

function _simulate_hypothetical!(
    city::City,
    rng::AbstractRNG;
    horizon::Int,
    n_search::Int,
    agents_inflow::Int,
    road_unit::Float32 = 1f0,
)
    for _ in 1:horizon
        n_before = length(city.agents)
        agents_inflow > 0 && add_agents!(city, agents_inflow; rng=rng)
        n_after = length(city.agents)
        new_ids = n_after > n_before ? collect((n_before + 1):n_after) : Int[]
        step!(city; n_search=n_search, rng=rng, agent_ids=new_ids, build_if_unhoused=true, road_unit=road_unit)
    end
    return city
end

"""
Run neighbourhood-level policy referenda:
  1) propose a random tree law per neighbourhood
  2) branch simulation for `horizon` steps with and without proposed laws
  3) majority vote by incumbent residents on utility comparison
  4) if passed, law becomes permanent (new builds can be prohibited by law)
"""
function evaluate_land_use_laws!(
    city::City,
    rng::AbstractRNG;
    horizon::Int = 10,
    n_search::Int = 5,
    agents_inflow::Int = 100,
    road_unit::Float32 = 1f0,
)
    n_nh = length(city.neighborhoods)
    incumbent = _residents_by_neighborhood(city)
    nd_cache_now = compute_nd_cache(city)

    # Propose one new law per neighbourhood — regardless of existing laws.
    new_proposals = Vector{LandUseLaw}(undef, n_nh)
    for nid in 1:n_nh
        obs = (
            median = nd_cache_now.median[nid],
            max = nd_cache_now.max[nid],
            min = nd_cache_now.min[nid],
            vacancy_rate = nd_cache_now.vacancy_rate[nid],
        )
        new_proposals[nid] = LandUseLaw(
            active = true,
            tree = random_law_tree(rng, obs),
            vote_share = 0f0,
        )
        println("[LAW] considering neighbourhood $(nid)")
    end

    seed = rand(rng, UInt)
    city_without = deepcopy(city)
    city_with    = deepcopy(city)
    # Add each proposal to the with-law branch alongside any existing laws.
    for nid in 1:n_nh
        push!(city_with.neighborhood_laws[nid], new_proposals[nid])
    end

    rng_without = MersenneTwister(seed)
    rng_with    = MersenneTwister(seed)
    _simulate_hypothetical!(city_without, rng_without; horizon, n_search, agents_inflow, road_unit)
    _simulate_hypothetical!(city_with,    rng_with;    horizon, n_search, agents_inflow, road_unit)
    nd_without = compute_nd_cache(city_without)
    nd_with    = compute_nd_cache(city_with)

    passed = Dict{String,Any}[]
    for nid in 1:n_nh
        voters = incumbent[nid]
        if isempty(voters)
            println("[LAW] neighbourhood $(nid) result: FAIL (no voters)")
            continue
        end
        yes = 0
        for aid in voters
            u0 = _agent_current_utility(city_without, aid, nd_without)
            u1 = _agent_current_utility(city_with,    aid, nd_with)
            yes += u1 > u0 ? 1 : 0
        end
        share = Float32(yes / length(voters))
        if share > 0.5f0
            proposal = new_proposals[nid]
            proposal.vote_share = share
            push!(city.neighborhood_laws[nid], proposal)
            n_laws = length(city.neighborhood_laws[nid])
            println("[LAW] neighbourhood $(nid) result: PASS (law #$(n_laws), vote_share=$(round(share, digits=3)))")
            msg = "Nbhd $(nid) law #$(n_laws) passed — $(round(Int, share*100))% yes"
            push!(passed, Dict{String,Any}(
                "msg"        => msg,
                "nid"        => nid,
                "law_num"    => n_laws,
                "tree"       => proposal.tree !== nothing ? _law_node_to_dict(proposal.tree) : nothing,
                "vote_share" => Float64(share),
            ))
        else
            println("[LAW] neighbourhood $(nid) result: FAIL (vote_share=$(round(share, digits=3)))")
        end
    end
    return passed
end
