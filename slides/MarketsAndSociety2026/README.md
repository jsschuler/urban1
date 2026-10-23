# Markets and Society 2026

31-slide main talk with five optional parameter-reference slides, with a 25-minute speaker-note budget excluding questions. Housing markets are the central story; the spring 2026 AI workflow occupies two brief slides. Results remain explicitly pending.

## Present

Open `index.html` in a browser. All deck assets are local; no build step or CDN is required. Arrow keys, Page Up/Down, or space advance slides. N toggles notes, including cumulative timing. The URL hash links to individual slides. Hide notes before projecting. Switch to Blender manually during demos.

From the repository root, start the existing model using your Julia environment:

```sh
julia main.jl
```

In Blender, load `blender_vis.py`, choose Setup Scene, then Start (port 8765). In the slides, click Connect model (port 8766). The Full controls link opens the existing research dashboard.

On a demo slide: wait for the model to be idle, click Reset city, wait for acknowledgement, select the condition, and click Start condition. Stop run requests a stop after the current step. Wait until idle before resetting. Navigating slides never starts or stops a run. A disconnect does not stop Julia. Use only one browser controller during the presentation.

## Demo design

Presets in `app.js` use 250 ticks, 40 arrivals per step, 100 neighborhoods with 8×8 buildings, and Blender updates every 10 ticks. Employer behavior is enabled throughout. These are provisional demonstration settings, not a runtime guarantee or the overnight experiment specification. Rehearse and tune them on the presentation machine, especially H = 20.

- Slides 15–16: zoning disabled (`land_use_eval_every = 0`) versus proposals every 10 steps, H = 5.
- Slide 19: H = 5 versus H = 20, proposals every 10 steps.
- Slide 24: transport disabled versus enabled, holding zoning and H = 5 fixed.

Every condition starts from an empty city after an explicit reset. The existing reset command does **not** reseed the random generator. These are illustrative independent trajectories, not matched-seed experimental estimates. The deck does not alter the model backend. Stop and reset must remain separate because the existing server uses a short fixed wait when processing resets.

## Fill results tomorrow

Add exported PNG charts at these paths; the slides automatically display them on reload:

- `charts/zoning.png` — slide 17
- `charts/horizons.png` — slide 20
- `charts/transport.png` — slide 25

Missing images display labeled placeholders. No synthetic results are included. Put definitions, run settings, seed count, simulation duration, and uncertainty in the chart or slide text. Edit `slides.js` for captions, speaker notes, and substantive conclusions. Update slide 30 after reviewing the evidence. Revise the conclusion if the findings require it.

For a fallback, use the completed result slides or prepare recordings/snapshots from tonight’s runs; none are bundled yet. The presentation still loads without a model connection, with live controls disabled.

## Validation

JavaScript syntax and simulated WebSocket checks cover reset acknowledgement, custom run lengths, continuation, invalid settings, presets, stop/idle, and disconnect behavior. A background Blender test verifies that reset preserves the landscape and material while removing model geometry and state. Full live integration and timing rehearsal remain to be done. No overnight model runs were launched by this work.

## Audience experiments and longer runs

Refresh the browser to load the revised deck. All demos default to 250 ticks. Use **Experiments** in the footer on any slide, or **Audience experiment / edit settings** on demo slides. Load a named preset, then edit batch length, inflow, search, incumbent mobility, voting frequency/horizon, transport, employer behavior, displacement, or household distribution parameters. Loading a preset restores its default settings; advancing slides preserves your edited settings. Select the intended preset explicitly for each comparison.

**Start condition** requires a fresh reset. **Continue city** adds the selected number of steps to the current city after a batch finishes or is stopped. Continuation retains laws, roads, and households; Julia's existing per-batch scheduling clocks restart. Turning a mechanism off does not remove existing laws, roads, or job assignments. Use a reset for a clean comparison. Distribution edits affect new arrivals; preferred heights use floored normal draws, while budgets and tolerances use log-normal draws. Invalid parameter values cannot be sent. The step metric totals batches started in this browser session.

The Blender reset fix is in the repository's `blender_vis.py`. Reload the updated add-on/script in Blender to apply it to the current session. If an earlier reset already deleted the ground, use **Setup Scene** once to restore it. Subsequent resets preserve the land and its material. No Julia restart is needed for these changes.

## Live Diagnostics

Demo slides and the **Live charts** view show building heights, two wealth-inequality time series, and neighborhood density and mean-wealth grids. The total-wealth Gini compares neighborhood sums of resident budgets; the average-wealth Gini compares neighborhood mean resident budgets. Both use resident population as the neighborhood weight and exclude zero-population neighborhoods. Total wealth is still a neighborhood sum before applying population weights; it is not converted into a mean. Wealth means household budget in model units, not housing prices or net worth.

The time-series axes are simulation ticks and Gini (fixed 0–1). Histories contain only observations received since connection or reset, persist across slide navigation, and extend across Continue batches. Reconnecting starts a fresh observed history; unavailable historical ticks are not invented. Missing mean-wealth values are not joined by a line. An entirely unpopulated city has no Gini for either series. If populated neighborhoods all have zero wealth, their Gini is zero by convention.

The grids retain model coordinates (x right, y up). Density is dwellings per site, including vacant stock, rather than the median-height utility proxy. Hatched wealth cells have no residents. Hover for values. Histogram bins and grid conventions remain unchanged.

## Mathematics and Parameter Reference

Equations and inline symbols use native MathML, so no external math-rendering service is needed. The main talk defines the Frank copula and explains its use as a utility aggregator. **Parameter Reference** opens five appendix slides covering every experiment setting, household distribution, geometry/initialization setting, utility switch, numerical safeguard, and display control; clicking it again returns to the previous slide. The main talk remains budgeted for 25 minutes; reference slides are optional.

Each preset actually sends `n_steps: 250` to Julia. Audience experiments may explicitly change the batch length. Refresh the browser to load this version; the current Julia backend already sends the resident counts and mean budgets needed for both Gini series, so no restart is necessary.

Checks: `node tests/telemetry.cjs` verifies the wealth statistics and history handling; `julia --project=. -e 'include("tests/presentation_stats.jl")'` checks the underlying neighborhood aggregates.

For neighborhood values `x` and population weights `w`, the weighted Gini is `sum(i<j, w[i]*w[j]*abs(x[i]-x[j])) / (sum(w)*sum(w*x))`. This is equivalent to repeating each neighborhood value once for each resident. The implementation uses sorted cumulative sums. Refreshing the slides starts a new history so previously unweighted points are not mixed with weighted points. No backend restart is needed.

## Exclusion, Sorting, and Access

The primary dashboard shows three time series together:

1. **Housing Exclusion:** unhoused share in each baseline budget quintile; the denominator includes all agents in the group.
2. **Residential Sorting:** population-weighted Gini of mean neighborhood budgets among housed agents. Empty neighborhoods are excluded.
3. **Access to Jobs:** mean effective commute distance in each budget group, computed only over housed agents using the actual current `road_unit` setting and network.

Read all three together: a lower sorting index or commute average can reflect poorer households being left unhoused. Q1 has the lowest budgets and Q5 the highest. Thresholds are fixed at the quintiles of the baseline budget distribution, `log(budget) ~ Normal(1, 0.5²)`, approximately 1.784, 2.395, 3.085, and 4.141. These are fixed reference groups, not re-ranked quintiles of each tick's population. Altering budget-distribution parameters can change group sizes. Empty groups have missing exclusion rates; groups with no housed agents have missing commute averages. Missing observations break plotted lines rather than appear as zeros. Current denominators and group boundaries are shown under the plots.

**City Structure and Secondary Measures** expands to show the height histogram, total-neighborhood-wealth Gini, density grid, and mean-wealth grid. Empty Units remains the vacant-dwelling counter on each demo slide. The existing `budget_quintile_*` history is observed live; refreshed clients do not reconstruct earlier ticks.

The backend additions are in `housing_access_stats` in `presentation_stats.jl`, called by `send_ctrl_stats!`. A Julia restart is required to load these additions. The display reports missing backend support explicitly until the updated backend sends its first statistics. Paired-seed comparison results are not fabricated; these panels report the actual running city.

## Displacement Comparisons and Updated Defaults

Each of the six named presets has displacement-off and displacement-on variants (12 menu entries; some comparisons intentionally share an identical baseline). The variants set both `allow_displacement` and `law_allow_displacement` together. In each experiment family, run its two levels under each displacement regime: four conditions for zoning, four for horizon, and four for transport. Shared baselines can be reused in saved experimental results. This is not a full factorial of every parameter interaction.

All presets request 250 ticks, Blender updates every 10 ticks, and `road_unit = 1.01`. The full research dashboard uses the same display and hop defaults. One distance unit is horizontal spacing between adjacent building sites; dwellings stacked at one site do not create additional horizontal distance. A hop costs 1.01 such units, plus access travel. At the default eight-site neighborhood width, adjacent neighborhood centers are eight units apart.

Use a fresh city for each condition. Common seeds alone do not guarantee identical incoming household draws because treatments can consume random numbers differently; a rigorous paired experiment should pre-generate arrivals or separate random streams. Live presets demonstrate mechanisms and do not implement that matched-arrival experiment harness.

Presentation review: the current law-vote utility comparison uses direct Euclidean distance, while housing choice uses effective network distance. This is a model-consistency issue to resolve before treating transport comparisons as internally consistent welfare evaluations. Budget-based displacement is a priority rule, not a clearing-price mechanism. Both limitations should be made explicit when interpreting the model.

## Overnight presentation results (October 22 update)

Saved comparison slides now precede optional live demonstrations. Use **Run this comparison live** on a result slide to open the controls; all 12 named presets remain available. Earlier slide-number references above describe the previous ordering. Refresh Firefox to load the revised deck.

The presentation sweep is documented in `../../scripts/README.md`. It covers all three comparisons under both displacement regimes, with three seeds and shared baselines. Charts update as balanced runs finish; the displayed seed count and range describe completed runs only. Arrivals remain unmatched, including in hypothetical voting branches despite their identical starting seeds.

Zoning-vote utility now uses network-adjusted distance with the actual `road_unit`, consistent with housing choices. This supersedes the transport-consistency warning above and requires a Julia restart. The model remains a budget-priority allocation and construction model, without market-clearing prices or rents.
