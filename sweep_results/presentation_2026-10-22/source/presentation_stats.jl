# Live presentation diagnostics. Wealth is agent budget, not property value.
function budget_gini(values)
    isempty(values) && return nothing
    x = sort!(Float64.(values))
    total = sum(x)
    total == 0 && return 0.0
    n = length(x)
    clamp(2 * sum(i * v for (i, v) in enumerate(x)) / (n * total) - (n + 1) / n, 0.0, 1.0)
end

function presentation_stats(city::City)
    n = length(city.neighborhoods)
    budgets = [Float64[] for _ in 1:n]
    dwellings = zeros(Int, n)
    sites = zeros(Int, n)
    # Fixed, inclusive height categories keep comparisons stable across runs.
    upper = [0, 2, 4, 8, 16, 32, 64, typemax(Int)]
    counts = zeros(Int, length(upper))
    for b in city.buildings
        h = height(b)
        counts[searchsortedfirst(upper, h)] += 1
        dwellings[b.neighborhood_id] += h
        sites[b.neighborhood_id] += 1
    end
    for a in city.agents
        a.dwelling_id == 0 && continue
        b = city.buildings[city.dwellings[a.dwelling_id].building_id]
        push!(budgets[b.neighborhood_id], Float64(a.budget))
    end
    wealth = [isempty(v) ? nothing : sum(v) / length(v) for v in budgets]
    Dict(
        "height_histogram" => Dict("labels" => ["0", "1–2", "3–4", "5–8", "9–16", "17–32", "33–64", "65+"], "counts" => counts),
        "nh_grid_width" => Int(city.n_x),
        "nh_grid_height" => Int(city.n_y),
        "nh_mean_density" => [sites[i] == 0 ? 0.0 : dwellings[i] / sites[i] for i in 1:n],
        "nh_mean_budget" => wealth,
        "nh_budget_gini" => budget_gini.(budgets),
        "nh_residents" => length.(budgets),
        "between_neighborhood_gini" => budget_gini(Float64[x for x in wealth if x !== nothing]),
    )
end

# Fixed quintiles of the baseline budget distribution, log(budget) ~ N(1, 0.5²).
# Fixed thresholds preserve membership as the city grows and across treatments.
const _BUDGET_QUINTILE_CUTOFFS = exp.(1.0 .+ 0.5 .* [-0.8416212335729143, -0.2533471031357997, 0.2533471031357997, 0.8416212335729143])

function housing_access_stats(city::City; road_unit::Float32=1f0)
    population = zeros(Int, 5)
    housed = zeros(Int, 5)
    commute = zeros(Float64, 5)
    for agent in city.agents
        q = searchsortedfirst(_BUDGET_QUINTILE_CUTOFFS, Float64(agent.budget))
        population[q] += 1
        agent.dwelling_id == 0 && continue
        housed[q] += 1
        home = city.buildings[city.dwellings[agent.dwelling_id].building_id]
        job = city.buildings[agent.job_building_id]
        commute[q] += Float64(effective_distance(city, home, job, road_unit))
    end
    Dict(
        "budget_quintile_cutoffs" => _BUDGET_QUINTILE_CUTOFFS,
        "budget_quintile_population" => population,
        "budget_quintile_housed" => housed,
        "budget_quintile_unhoused_share" => [population[q] == 0 ? nothing : (population[q]-housed[q])/population[q] for q in 1:5],
        "budget_quintile_mean_commute" => [housed[q] == 0 ? nothing : commute[q]/housed[q] for q in 1:5],
        "diagnostic_road_unit" => Float64(road_unit),
    )
end
