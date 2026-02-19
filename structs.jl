# ============================================================
# Spatial primitives
# ============================================================

struct Position
    x::Int32
    y::Int32
end

distance(a::Position, b::Position) =
    sqrt(Float32((a.x - b.x)^2 + (a.y - b.y)^2))

# ============================================================
# Dwelling  (defined before Building so Building can hold Vector{Dwelling})
# ============================================================

mutable struct Dwelling
    id::Int32
    building_id::Int32
    floor::Int32
    building_name::String
    occupant_id::Int32      # 0 = vacant
end

# ============================================================
# Urban fabric
# ============================================================

struct Neighborhood
    id::Int32
    pos::Position   # position in neighborhood grid (neighborhood units)
end

struct Building
    id::Int32
    pos::Position           # position in city grid (building units)
    neighborhood_id::Int32
    name::String
    dwellings::Vector{Dwelling}
end

# Height is the number of stacked dwellings; +1 gives the job-probability weight
# (every parcel has baseline weight 1 even when empty).
height(b::Building)      = length(b.dwellings)
job_weight(b::Building)  = length(b.dwellings) + 1

# ============================================================
# Agent
# ============================================================

mutable struct Agent
    id::Int32
    dwelling_id::Int32      # 0 = unhoused
    job_building_id::Int32

    budget::Float32

    # Residential preference parameters (used in marginal transforms)
    pref_neighborhood_density::Float32  # preferred avg dwellings/building in neighbourhood
    pref_neighborhood_max_height::Float32  # preferred max building height in neighbourhood
    pref_neighborhood_min_height::Float32  # preferred min building height in neighbourhood
    pref_building_height::Float32       # preferred home building height (floors)
    σ_neighborhood::Float32            # sensitivity to % deviation from preferred neighbourhood density
    σ_building::Float32                # sensitivity to % deviation from preferred building height
    proximity_scale::Float32           # exponential decay length for job distance (building units)

    # Copula dependence parameter (Frank copula θ; > 0 = positive dependence)
    copula_θ::Float32
end

# ============================================================
# City
# ============================================================

struct City
    neighborhoods::Vector{Neighborhood}
    buildings::Vector{Building}
    dwellings::Vector{Dwelling}         # flat list for fast global iteration
    agents::Vector{Agent}

    k::Int32        # neighborhood side length  (k×k buildings per neighborhood)
    n_x::Int32      # neighborhoods in x direction
    n_y::Int32      # neighborhoods in y direction

    neighborhood_to_buildings::Vector{Vector{Int32}}  # neighborhood id → [building ids]
end
