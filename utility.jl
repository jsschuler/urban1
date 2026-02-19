# ============================================================
# Marginal transforms  →  each maps its raw argument to [0, 1]
# ============================================================

# Floor for denominators so we never divide by zero.
const _EPS_DENOM = 0.5f0   # minimum meaningful density / height value
const _EPS_SCALE = 0.1f0   # minimum proximity scale
const _EPS_SIGMA = 0.01f0  # minimum σ

"""
    _u_proximity(dist, scale) → Float32

Exponential survival: u = exp(−dist / scale).
  dist  ≥ 0   (building units; 0 when job and home share a building → u = 1)
  scale > 0   (tunable per-agent length scale; clamped away from 0)
"""
@inline function _u_proximity(dist::Float32, scale::Float32)::Float32
    exp(-dist / max(scale, _EPS_SCALE))
end

"""
    _u_pct_diff(actual, preferred, σ) → Float32

Half-normal transform of the % deviation from a preferred value:
  δ   = |actual − preferred| / max(preferred, _EPS_DENOM)
  u   = exp(−δ² / (2σ²))

Singularities handled:
  • preferred ≈ 0  →  denominator clamped to _EPS_DENOM
  • actual    = 0  →  empty building; δ = 1 giving u < 1 as expected
  • σ         ≈ 0  →  clamped to _EPS_SIGMA
"""
@inline function _u_pct_diff(actual::Float32, preferred::Float32, σ::Float32)::Float32
    δ = abs(actual - preferred) / max(preferred, _EPS_DENOM)
    exp(-δ^2 / (2f0 * max(σ, _EPS_SIGMA)^2))
end

# ============================================================
# Frank copula (3-dimensional)
# ============================================================

#=
C(u₁, u₂, u₃ ; θ) = −(1/θ) · ln[ 1 + ∏ᵢ(e^{−θuᵢ}−1) / (e^{−θ}−1)² ]

Properties relevant to utility:
  • C(1,1,1) = 1  (all dimensions at maximum → maximum utility)
  • C(u₁,…,0,…) = 0  (any dimension at 0 → utility collapses)
  • θ → 0 : independence,  C → u₁·u₂·u₃
  • θ → +∞: comonotonicity, C → min(u₁,u₂,u₃)
  • θ > 0 models positive dependence (natural for residential utility)

Singularities / numerical limits handled:
  |θ| < ε   → independence limit (avoid 0/0)
  θ  > 50   → Fréchet upper bound, min(u)  (exp underflow)
  θ  < −50  → Fréchet lower bound          (exp overflow)
  arg ≤ 0   → fallback to the appropriate Fréchet bound
  u clamped to (ε, 1−ε) to avoid log(0) and log of negative
=#

const _FRANK_EPS   = 1f-6   # u clamp margin
const _FRANK_THETA_INDEP = 1f-6   # |θ| below this → independence
const _FRANK_THETA_MAX   = 50f0   # |θ| above this → Fréchet limits

function frank_copula(u1::Float32, u2::Float32, u3::Float32, θ::Float32)::Float32
    # --- boundary cases ---
    abs(θ) < _FRANK_THETA_INDEP && return u1 * u2 * u3

    if θ > _FRANK_THETA_MAX
        return min(u1, u2, u3)                         # perfect positive dependence
    elseif θ < -_FRANK_THETA_MAX
        return max(u1 + u2 + u3 - 2f0, 0f0)           # Fréchet lower bound
    end

    # --- clamp u away from singularities ---
    u1 = clamp(u1, _FRANK_EPS, 1f0 - _FRANK_EPS)
    u2 = clamp(u2, _FRANK_EPS, 1f0 - _FRANK_EPS)
    u3 = clamp(u3, _FRANK_EPS, 1f0 - _FRANK_EPS)

    a1 = exp(-θ * u1) - 1f0
    a2 = exp(-θ * u2) - 1f0
    a3 = exp(-θ * u3) - 1f0
    D  = (exp(-θ) - 1f0)^2

    arg = 1f0 + (a1 * a2 * a3) / D

    # guard against floating-point noise pushing arg out of domain
    if arg ≤ 0f0
        return θ > 0f0 ? min(u1, u2, u3) : max(u1 + u2 + u3 - 2f0, 0f0)
    end

    return clamp(-log(arg) / θ, 0f0, 1f0)
end

# ============================================================
# Full agent utility
# ============================================================

"""
    agent_utility(agent, b, nd_cache, job_pos) → Float32

Frank-copula utility in [0, 1].  Arguments and their marginal transforms:

  1. Distance from work      →  _u_proximity(dist, agent.proximity_scale)
  2. % diff from preferred neighbourhood density  →  _u_pct_diff(nd,  pref_nd,  σ_nd)
  3. % diff from preferred building height         →  _u_pct_diff(bh,  pref_bh,  σ_bh)

The copula parameter θ controls cross-dimension dependence; θ > 0 (positive
dependence) is the economically natural setting.
"""
function agent_utility(
    agent   ::Agent,
    b       ::Building,
    nd_cache::Vector{Float32},
    job_pos ::Position,
)::Float32
    nd   = nd_cache[b.neighborhood_id]
    bh   = Float32(height(b))
    dist = distance(b.pos, job_pos)

    u_prox    = _u_proximity(dist, agent.proximity_scale)
    u_density = _u_pct_diff(nd,  agent.pref_neighborhood_density, agent.σ_neighborhood)
    u_height  = _u_pct_diff(bh,  agent.pref_building_height,      agent.σ_building)

    return frank_copula(u_prox, u_density, u_height, agent.copula_θ)
end
