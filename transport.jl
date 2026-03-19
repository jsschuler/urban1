using Statistics: median
using Random: shuffle!, AbstractRNG, default_rng

# ============================================================
# Network geometry helpers
# ============================================================

"""Neighbourhood centre position in building-grid units."""
@inline function nh_center(city::City, nid::Int)::Position
    nh = city.neighborhoods[nid]
    Position(
        Int32(nh.pos.x * city.k + city.k ÷ 2),
        Int32(nh.pos.y * city.k + city.k ÷ 2),
    )
end

# ============================================================
# Hop-count cache (BFS over neighbourhood graph)
# ============================================================

"""
Recompute the full pairwise BFS hop-count matrix from the current road set.
Call after any modification to city.roads.
"""
function rebuild_hop_cache!(city::City)
    n = length(city.neighborhoods)
    fill!(city.nh_hop_cache, typemax(Int32))
    for i in 1:n; city.nh_hop_cache[i, i] = Int32(0); end

    adj = [Int32[] for _ in 1:n]
    for (a, b) in city.roads
        push!(adj[a], b)
        push!(adj[b], a)
    end

    for src in 1:n
        queue = [Int32(src)]
        head  = 1
        while head <= length(queue)
            cur = queue[head]; head += 1
            d   = city.nh_hop_cache[src, cur]
            for nb in adj[cur]
                if city.nh_hop_cache[src, nb] == typemax(Int32)
                    city.nh_hop_cache[src, nb] = d + Int32(1)
                    push!(queue, nb)
                end
            end
        end
    end
end

# ============================================================
# Effective commute distance
# ============================================================

"""
    effective_distance(city, home_b, job_b, road_unit) → Float32

Effective commute distance, taking the subway network into account:

    subway = euclidean(home, home_nh_centre)
           + hops × road_unit
           + euclidean(job_nh_centre, job)

Returns min(euclidean, subway). Falls back to pure Euclidean if the two
neighbourhoods are not connected in the current road graph.
"""
function effective_distance(
    city     ::City,
    home_b   ::Building,
    job_b    ::Building,
    road_unit::Float32,
)::Float32
    eucl = distance(home_b.pos, job_b.pos)
    isempty(city.roads) && return eucl

    home_nid = Int(home_b.neighborhood_id)
    job_nid  = Int(job_b.neighborhood_id)
    hops = city.nh_hop_cache[home_nid, job_nid]
    hops == typemax(Int32) && return eucl

    home_ctr = nh_center(city, home_nid)
    job_ctr  = nh_center(city, job_nid)
    subway = distance(home_b.pos, home_ctr) +
             Float32(hops) * road_unit      +
             distance(job_ctr, job_b.pos)
    return min(eucl, subway)
end

# ============================================================
# Road planning
# ============================================================

"""
    evaluate_roads!(city; road_unit)

Build one road per call using a greedy planning heuristic:
  1. Compute the current median building height per neighbourhood.
  2. Score every unconnected neighbourhood pair by |median_height_a − median_height_b|.
  3. Add the highest-scoring direct edge to city.roads.
  4. Rebuild the hop-count cache.

No voting or branch simulation — a pure planner optimising connectivity
between low-density and high-density areas.
"""
function evaluate_roads!(city::City; road_unit::Float32 = 1f0, rng::AbstractRNG = default_rng())
    n = length(city.neighborhoods)

    existing = Set{Tuple{Int32,Int32}}(
        (min(a, b), max(a, b)) for (a, b) in city.roads
    )

    medians = Vector{Float32}(undef, n)
    for nid in 1:n
        hs = Float32[Float32(height(city.buildings[bid]))
                     for bid in city.neighborhood_to_buildings[nid]]
        medians[nid] = isempty(hs) ? 0f0 : Float32(median(hs))
    end

    n_x = Int(city.n_x)

    # Collect candidates in random order so ties break randomly (not always corner-first)
    candidates = [(Int32(a), Int32(b)) for a in 1:n for b in (a + 1):n
                  if (min(Int32(a), Int32(b)), max(Int32(a), Int32(b))) ∉ existing
                  && city.nh_hop_cache[a, b] == typemax(Int32)]
    shuffle!(rng, candidates)

    best_score = -1f0
    best_a = Int32(0)
    best_b = Int32(0)
    for (a, b) in candidates
        score = abs(medians[a] - medians[b])
        if score > best_score
            best_score = score
            best_a = a
            best_b = b
        end
    end

    best_a == 0 && return nothing   # all pairs already directly connected

    # Walk a 4-connected Bresenham path from best_a to best_b, adding every
    # adjacent edge so the diagonal corridor is fully connected.
    ax, ay = (Int(best_a) - 1) % n_x, (Int(best_a) - 1) ÷ n_x
    bx, by = (Int(best_b) - 1) % n_x, (Int(best_b) - 1) ÷ n_x
    sx, sy = sign(bx - ax), sign(by - ay)
    adx, ady = abs(bx - ax), abs(by - ay)
    cx, cy = ax, ay
    err = adx - ady
    while cx != bx || cy != by
        nid_cur = Int32(cy * n_x + cx + 1)
        if err >= 0
            cx += sx; err -= ady
        else
            cy += sy; err += adx
        end
        nid_next = Int32(cy * n_x + cx + 1)
        key = (min(nid_cur, nid_next), max(nid_cur, nid_next))
        key ∉ existing && push!(city.roads, (nid_cur, nid_next))
        push!(existing, key)
    end

    rebuild_hop_cache!(city)
    msg = "Nbhd $(best_a) ↔ $(best_b) — density diff $(round(best_score; digits=2)), " *
          "road_unit=$(road_unit), roads built: $(length(city.roads))"
    println("[ROAD] " * msg)
    return Dict{String,Any}(
        "nid_a"   => Int(best_a),
        "nid_b"   => Int(best_b),
        "score"   => Float64(best_score),
        "msg"     => msg,
        "n_roads" => length(city.roads),
    )
end
