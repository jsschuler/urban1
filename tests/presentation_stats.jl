using Test
include(joinpath(@__DIR__, "..", "main.jl"))
@testset "Presentation diagnostics" begin
    @test budget_gini(Float64[]) === nothing
    @test budget_gini([0, 0]) == 0
    @test budget_gini([2]) == 0
    @test budget_gini([1, 3]) ≈ 0.25
    @test budget_gini([0, 0, 6]) ≈ 2/3
    city = generate_city(2, 1; k=1)
    empty_stats = presentation_stats(city)
    @test empty_stats["nh_mean_budget"] == [nothing, nothing]
    @test empty_stats["nh_mean_density"] == [0, 0]
    @test sum(empty_stats["height_histogram"]["counts"]) == 2
    generate_agents!(city, 4)
    for (i, bid, budget) in [(1,1,1), (2,1,3), (3,2,10)]
        city.agents[i].budget = budget
        build_and_move_in!(city.agents[i], city.buildings[bid], city)
    end
    city.agents[4].budget = 1000 # Unhoused: must not enter neighborhood wealth.
    result = presentation_stats(city)
    @test result["nh_mean_density"] == [2,1]
    @test result["nh_mean_budget"] == [2,10]
    @test result["nh_budget_gini"] == [0.25,0]
    @test result["nh_residents"] == [2,1]
    @test result["between_neighborhood_gini"] ≈ 1/3
    @test result["height_histogram"]["counts"] == [0,2,0,0,0,0,0,0]
    @test result["nh_grid_width"] == 2
    @test result["nh_grid_height"] == 1
    # Vacancies count toward stock density and height, but not residents or wealth.
    city.dwellings[3].occupant_id = 0
    city.agents[3].dwelling_id = 0
    vacant_stats = presentation_stats(city)
    @test vacant_stats["nh_mean_density"] == [2,1]
    @test vacant_stats["nh_mean_budget"] == [2,nothing]
    @test vacant_stats["nh_budget_gini"] == [0.25,nothing]
    # All missing-value conventions must serialize cleanly over the WebSocket.
    @test_nowarn JSON3.write(result)
end

@testset "Housing exclusion and access" begin
    city = generate_city(2, 1; k=1)
    empty = housing_access_stats(city)
    @test empty["budget_quintile_population"] == zeros(Int,5)
    @test all(isnothing, empty["budget_quintile_unhoused_share"])
    @test all(isnothing, empty["budget_quintile_mean_commute"])
    generate_agents!(city, 5)
    for (i,budget) in enumerate([1.0, 1.2, 2.0, 3.5, 5.0])
        city.agents[i].budget=budget
        city.agents[i].job_building_id=2
    end
    # One of two low-budget agents is housed; Q3 has no agents; Q4 is entirely unhoused.
    for i in [1,3,5]
        build_and_move_in!(city.agents[i],city.buildings[1],city)
    end
    plain=housing_access_stats(city)
    @test plain["budget_quintile_population"] == [2,1,0,1,1]
    @test plain["budget_quintile_housed"] == [1,1,0,0,1]
    @test plain["budget_quintile_unhoused_share"] == [0.5,0,nothing,1,0]
    @test plain["budget_quintile_mean_commute"] == [1,1,nothing,nothing,1]
    push!(city.roads,(Int32(1),Int32(2)))
    rebuild_hop_cache!(city)
    fast=housing_access_stats(city;road_unit=0.2f0)
    @test fast["budget_quintile_mean_commute"][1] ≈ 0.2 atol=1e-7
    @test fast["budget_quintile_mean_commute"][4] === nothing
    @test housing_access_stats(city;road_unit=2f0)["budget_quintile_mean_commute"][1] == 1
    @test fast["budget_quintile_cutoffs"] == plain["budget_quintile_cutoffs"]
    @test_nowarn JSON3.write(fast)
end

@testset "Zoning votes use housing-choice transport distance" begin
    city = generate_city(2, 1; k=1)
    generate_agents!(city, 1; rng=MersenneTwister(42))
    a = city.agents[1]
    a.job_building_id = 2
    build_and_move_in!(a, city.buildings[1], city)
    cache = compute_nd_cache(city)
    direct = _agent_current_utility(city, Int32(1), cache; road_unit=0.2f0)
    @test direct == agent_utility(a,city.buildings[1],cache,city.buildings[2].pos)
    push!(city.roads, (Int32(1),Int32(2)))
    rebuild_hop_cache!(city)
    network = _agent_current_utility(city, Int32(1), cache; road_unit=0.2f0)
    @test network == agent_utility(a,city.buildings[1],cache,city.buildings[2].pos; eff_dist=0.2f0)
    @test network > direct
    @test _agent_current_utility(city, Int32(1), cache; road_unit=2f0) == direct
    a.dwelling_id = 0
    @test _agent_current_utility(city, Int32(1), cache; road_unit=0.2f0) == 0f0
end
