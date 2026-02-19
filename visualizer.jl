using HTTP
using JSON3

# ============================================================
# Color scheme
# ============================================================

"""
Mutable color scheme sent to Blender.
Change any field and call set_color_scheme! to push the update live.

attribute: "budget" | "height" | "density"
  budget  — occupant budget (or 0 for vacant)
  height  — building height, computed by Blender from dwelling positions
  density — neighbourhood density; Blender approximates from local heights
"""
Base.@kwdef mutable struct ColorScheme
    attribute ::String            = "budget"
    min_value ::Float64           = 0.0
    max_value ::Float64           = 10.0
    color_low ::NTuple{3,Float64} = (0.15, 0.30, 0.85)   # cool blue
    color_high::NTuple{3,Float64} = (0.85, 0.15, 0.15)   # warm red
    log_scale ::Bool              = false
end

_scheme_dict(s::ColorScheme) = Dict(
    "attribute"  => s.attribute,
    "min_value"  => s.min_value,
    "max_value"  => s.max_value,
    "color_low"  => collect(s.color_low),
    "color_high" => collect(s.color_high),
    "log_scale"  => s.log_scale,
)

# ============================================================
# Visualizer
# ============================================================

mutable struct Visualizer
    ws          ::Ref{Any}               # current WebSocket connection, or nothing
    sent_ids    ::Set{Int32}             # dwelling IDs already in Blender
    last_budgets::Dict{Int32,Float32}    # dwelling_id → last-sent budget (0 = vacant)
    scheme      ::ColorScheme
end

Visualizer(; scheme = ColorScheme()) =
    Visualizer(Ref{Any}(nothing), Set{Int32}(), Dict{Int32,Float32}(), scheme)

# ============================================================
# Server
# ============================================================

"""
    listen!(vis; host, port)

Start a WebSocket server in the background. Blender connects to ws://host:port.
On every (re)connection full_sync! is called automatically so Blender always
receives the complete current state before any incremental diffs.
city_ref holds a reference to the live City so it can be synced on reconnect.
"""
function listen!(vis::Visualizer, city_ref::Ref{Union{Nothing,City}};
                 host::String = "127.0.0.1", port::Int = 8765)
    @async HTTP.WebSockets.listen(host, UInt16(port)) do ws
        vis.ws[] = ws
        @info "Blender connected"
        # Push full state so a fresh or reconnecting Blender is never incomplete
        city = city_ref[]
        isnothing(city) || full_sync!(vis, city)
        try
            while isopen(ws)
                HTTP.WebSockets.receive(ws)   # drain pings / any client messages
            end
        catch
            # connection closed normally or abruptly
        finally
            vis.ws[] = nothing
            @info "Blender disconnected"
        end
    end
    @info "Visualizer listening on ws://$(host):$(port)"
end

function _send!(vis::Visualizer, payload::AbstractDict)
    ws = vis.ws[]
    isnothing(ws) && return
    try
        HTTP.WebSockets.send(ws, JSON3.write(payload))
    catch e
        @warn "Visualizer send error: $e"
    end
end

# ============================================================
# Sync helpers
# ============================================================

_dwelling_budget(d::Dwelling, city::City)::Float32 =
    d.occupant_id == 0 ? 0.0f0 : city.agents[d.occupant_id].budget

function _dwelling_entry(d::Dwelling, city::City)
    b = city.buildings[d.building_id]
    Dict("id" => d.id, "x" => b.pos.x, "y" => b.pos.y,
         "floor" => d.floor, "budget" => _dwelling_budget(d, city))
end

# ============================================================
# Public API
# ============================================================

"""
    full_sync!(vis, city)

Push the complete current state to Blender (e.g. after a reconnect).
Resets all tracking so the diff machinery starts fresh.
"""
function full_sync!(vis::Visualizer, city::City)
    empty!(vis.sent_ids)
    empty!(vis.last_budgets)

    _send!(vis, Dict("type" => "color_scheme", "scheme" => _scheme_dict(vis.scheme)))

    isempty(city.dwellings) && return

    payload = [_dwelling_entry(d, city) for d in city.dwellings]
    _send!(vis, Dict("type" => "new_dwellings", "dwellings" => payload))

    for d in city.dwellings
        push!(vis.sent_ids, d.id)
        vis.last_budgets[d.id] = _dwelling_budget(d, city)
    end
end

"""
    send_step_diff!(vis, city)

Send only what changed since the last call:
  • new dwellings  — geometry to add in Blender
  • budget changes — occupant moved in, moved out, or was displaced

Call once after each model step.
"""
function send_step_diff!(vis::Visualizer, city::City)
    isnothing(vis.ws[]) && return

    new_payload    = Vector{Dict{String,Any}}()
    update_payload = Vector{Dict{String,Any}}()

    for d in city.dwellings
        budget = _dwelling_budget(d, city)

        if d.id ∉ vis.sent_ids
            push!(new_payload, _dwelling_entry(d, city))
            push!(vis.sent_ids, d.id)
            vis.last_budgets[d.id] = budget

        elseif get(vis.last_budgets, d.id, -1.0f0) != budget
            push!(update_payload, Dict("id" => d.id, "budget" => budget))
            vis.last_budgets[d.id] = budget
        end
    end

    isempty(new_payload)    || _send!(vis, Dict("type" => "new_dwellings",  "dwellings" => new_payload))
    isempty(update_payload) || _send!(vis, Dict("type" => "budget_updates", "updates"   => update_payload))
end

"""
    set_color_scheme!(vis; attribute, min_value, max_value,
                           color_low, color_high, log_scale)

Update any subset of color scheme parameters and immediately push to Blender.
All keyword arguments are optional; unspecified fields keep their current value.

Example — switch to log-scale height colouring:
    set_color_scheme!(vis; attribute="height", log_scale=true, max_value=20.0)
"""
function set_color_scheme!(vis::Visualizer; kwargs...)
    for (k, v) in kwargs
        setfield!(vis.scheme, k, v)
    end
    _send!(vis, Dict("type" => "color_scheme", "scheme" => _scheme_dict(vis.scheme)))
end
