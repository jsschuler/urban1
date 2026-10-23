# One isolated presentation condition; shares the live simulation loop.
include(joinpath(@__DIR__, "..", "main.jl"))
using Dates
function _save_city_snapshot(city, cfg, run_id, out_dir)
    n_x = Int(city.n_x)
    n_y = Int(city.n_y)
    k   = Int(city.k)

    # Agent id → budget lookup
    agent_budget = Dict{Int32,Float32}(a.id => a.budget for a in city.agents)

    # Dwellings (same fields as "new_dwellings" WebSocket message)
    dw_list = Vector{Dict{String,Any}}(undef, length(city.dwellings))
    for (i, d) in enumerate(city.dwellings)
        b      = city.buildings[d.building_id]
        budget = d.occupant_id == 0 ? 0.0f0 : get(agent_budget, d.occupant_id, 0.0f0)
        dw_list[i] = Dict(
            "id"    => Int(d.id),
            "x"     => Int(b.pos.x),
            "y"     => Int(b.pos.y),
            "floor" => Int(d.floor),
            "budget"=> Float64(budget),
        )
    end

    # Roads with neighbourhood-centre coordinates (same as "new_roads" message)
    road_list = Vector{Dict{String,Any}}(undef, length(city.roads))
    for (i, (nid_a, nid_b)) in enumerate(city.roads)
        ca = nh_center(city, Int(nid_a))
        cb = nh_center(city, Int(nid_b))
        road_list[i] = Dict(
            "nid_a" => Int(nid_a), "nid_b" => Int(nid_b),
            "x_a"   => Float64(ca.x), "y_a" => Float64(ca.y),
            "x_b"   => Float64(cb.x), "y_b" => Float64(cb.y),
        )
    end

    snapshot = Dict(
        "run_id"      => run_id,
        "run_config"  => Dict(string(k2) => v for (k2, v) in pairs(cfg)),
        "city_config" => Dict("n_x" => n_x, "n_y" => n_y, "k" => k),
        "dwellings"   => dw_list,
        "roads"       => road_list,
    )

    open(joinpath(out_dir, "$(run_id)_city.json"), "w") do io
        JSON3.write(io, snapshot)
    end
end


condition, displacement_arg, seed_arg, output = ARGS[1:4]
seed = parse(Int, seed_arg)
displacement = parse(Bool, displacement_arg)
steps = length(ARGS) >= 5 ? parse(Int, ARGS[5]) : 250
side = length(ARGS) >= 6 ? parse(Int, ARGS[6]) : 10
inflow = length(ARGS) >= 7 ? parse(Int, ARGS[7]) : 40
condition in ("no_zoning", "zoning", "long", "roads_on") || error("Unknown condition")
config = Dict("condition"=>condition, "displacement"=>displacement, "seed"=>seed,
    "n_steps"=>steps, "n_neighborhoods_sqrt"=>side, "k"=>8,
    "agents_inflow"=>inflow, "n_search"=>5, "existing_move_share"=>0.1,
    "land_use_eval_every"=>condition == "no_zoning" ? 0 : 10,
    "land_use_eval_horizon"=>condition == "long" ? 20 : 5,
    "enable_roads"=>condition == "roads_on", "road_eval_every"=>20,
    "road_unit"=>1.01, "enable_employer"=>true, "employer_eval_every"=>1,
    "employer_n_candidates"=>5, "employer_horizon"=>3,
    "allow_displacement"=>displacement, "law_allow_displacement"=>displacement,
    "law_incumbent_mover_share"=>0.0, "law_incumbent_can_build"=>false,
    "initial_agents"=>0, "matched_arrivals"=>false)
mkpath(dirname(output))
city = generate_city(side, side; k=8)
rng = MersenneTwister(seed)
generate_agents!(city, 0; rng)
cx = side * 8 ÷ 2; cy = cx
center_bid = Int32(((cy ÷ 8) * side + cx ÷ 8) * 64 + (cy % 8) * 8 + cx % 8 + 1)
push!(city.employers, Employer(Int32(1), center_bid, Set{Int32}()))
vis = Visualizer()
vis.stop_flag[] = false
started = time()
open(output * ".partial", "w") do io
    println(io, JSON3.write(Dict("type"=>"config", "config"=>config, "started"=>string(now())))); flush(io)
    run_steps!(city, vis, rng; n_steps=steps, agents_inflow=inflow,
        n_search=5, existing_move_share=0.1, step_delay=0.0,
        land_use_eval_every=config["land_use_eval_every"],
        land_use_eval_horizon=config["land_use_eval_horizon"],
        allow_displacement=displacement, law_allow_displacement=displacement,
        enable_roads=config["enable_roads"], road_eval_every=20, road_unit=1.01f0,
        enable_employer=true, employer_eval_every=1, employer_n_candidates=5, employer_horizon=3,
        require_authorization=false,
        on_step=(t,c)->begin
            row = merge(presentation_stats(c), housing_access_stats(c; road_unit=1.01f0),
                Dict("type"=>"step", "step"=>t, "agents"=>length(c.agents),
                    "housed"=>count(a->a.dwelling_id != 0,c.agents),
                    "n_roads"=>length(c.roads), "dwellings"=>length(c.dwellings),
                    "pct_laws"=>100*count(x->!isempty(x),c.neighborhood_laws)/length(c.neighborhoods),
                    "wall_seconds"=>time()-started))
            println(io, JSON3.write(row)); flush(io)
        end)
    _save_city_snapshot(city, config, splitext(basename(output))[1], dirname(output))
    println(io, JSON3.write(Dict("type"=>"complete", "wall_seconds"=>time()-started))); flush(io)
end
mv(output * ".partial", output; force=true)
println("COMPLETE ", output)
