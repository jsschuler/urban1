# Completed sweep analysis — October 23, 2026

Presentation: 24/24 complete, three seeds per condition, 250 ticks. Broad: 1423/1800 complete, 1,000 ticks; 8 timed out and 369 unstarted. Partial runs are excluded. The central 10×10 / 40-arrivals design is complete: 40 cells × five seeds = 200 runs.

## Main-slide endpoints

Means [minimum, maximum] across seeds. Exclusion is percent; commute is effective distance in building-grid units; sorting is the population-weighted Gini of neighborhood mean budgets.

| Ticks | Displacement | Condition | Q1 exclusion % | Q5 exclusion % | Sorting | Q1 commute | Q5 commute |
|---|---|---|---|---|---|---|---|
| 250 | off | Zoning off | 0.000 [0.000, 0.000] | 0.000 [0.000, 0.000] | 0.030 [0.028, 0.033] | 30.025 [29.769, 30.268] | 29.614 [28.783, 30.146] |
| 250 | off | H=5 | 0.000 [0.000, 0.000] | 0.000 [0.000, 0.000] | 0.028 [0.025, 0.029] | 30.301 [29.766, 31.063] | 30.055 [29.441, 30.622] |
| 250 | off | H=20 | 10.122 [0.000, 30.366] | 10.029 [0.000, 30.087] | 0.027 [0.025, 0.031] | 31.085 [30.080, 32.166] | 30.814 [30.048, 31.265] |
| 250 | off | H=5 + roads | 0.000 [0.000, 0.000] | 0.000 [0.000, 0.000] | 0.027 [0.027, 0.027] | 19.959 [19.189, 21.457] | 19.926 [18.215, 22.259] |
| 250 | on | Zoning off | 14.097 [13.065, 14.934] | 0.972 [0.717, 1.290] | 0.130 [0.126, 0.135] | 12.153 [11.911, 12.329] | 20.494 [20.383, 20.569] |
| 250 | on | H=5 | 14.738 [13.630, 15.560] | 0.949 [0.918, 1.003] | 0.139 [0.133, 0.144] | 12.474 [12.102, 12.713] | 20.248 [20.088, 20.365] |
| 250 | on | H=20 | 13.905 [13.075, 14.673] | 1.144 [0.923, 1.355] | 0.158 [0.152, 0.168] | 13.011 [12.130, 13.515] | 19.940 [19.535, 20.372] |
| 250 | on | H=5 + roads | 14.938 [14.607, 15.156] | 0.966 [0.845, 1.058] | 0.151 [0.142, 0.156] | 6.016 [5.687, 6.317] | 8.423 [8.095, 8.681] |
| 1000 | off | Zoning off | 0.000 [0.000, 0.000] | 0.000 [0.000, 0.000] | 0.015 [0.014, 0.015] | 30.414 [30.253, 30.711] | 30.474 [30.249, 30.591] |
| 1000 | off | H=5 | 0.000 [0.000, 0.000] | 0.000 [0.000, 0.000] | 0.011 [0.010, 0.011] | 32.719 [27.477, 38.305] | 32.703 [27.451, 38.500] |
| 1000 | off | H=20 | 33.341 [0.000, 84.107] | 33.458 [0.000, 84.236] | 0.018 [0.007, 0.034] | 25.544 [11.942, 31.483] | 25.471 [12.041, 31.028] |
| 1000 | off | H=5 + roads | 0.000 [0.000, 0.000] | 0.000 [0.000, 0.000] | 0.011 [0.010, 0.012] | 7.764 [4.809, 8.684] | 7.757 [4.860, 8.690] |
| 1000 | on | Zoning off | 4.650 [4.252, 4.946] | 0.248 [0.174, 0.339] | 0.068 [0.064, 0.071] | 29.063 [28.780, 29.336] | 32.636 [32.362, 32.872] |
| 1000 | on | H=5 | 4.444 [3.911, 4.853] | 0.502 [0.278, 0.728] | 0.114 [0.100, 0.126] | 28.994 [28.490, 29.352] | 30.614 [30.241, 31.901] |
| 1000 | on | H=20 | 3.950 [3.767, 4.136] | 0.860 [0.655, 1.037] | 0.161 [0.153, 0.177] | 28.460 [27.196, 29.928] | 29.606 [27.811, 31.207] |
| 1000 | on | H=5 + roads | 4.421 [4.130, 4.784] | 0.526 [0.375, 0.713] | 0.103 [0.091, 0.122] | 7.944 [7.884, 8.025] | 8.274 [8.160, 8.438] |

## Conditional contrasts

Differences in means using common completed seed labels. These are descriptive simulation comparisons, not matched-arrival estimates. Exclusion differences are percentage points.

| Ticks | Displacement | Contrast | Q1 exclusion pp | Q5 exclusion pp | Sorting | Q1 commute | Q5 commute |
|---|---|---|---|---|---|---|---|
| 250 | off | Zoning on minus off | +0.000 | +0.000 | -0.002 | +0.276 | +0.441 |
| 250 | off | H20 minus H5 | +10.122 | +10.029 | -0.000 | +0.783 | +0.759 |
| 250 | off | Roads on minus off | +0.000 | +0.000 | -0.001 | -10.342 | -10.129 |
| 250 | on | Zoning on minus off | +0.640 | -0.023 | +0.009 | +0.321 | -0.246 |
| 250 | on | H20 minus H5 | -0.833 | +0.196 | +0.019 | +0.537 | -0.308 |
| 250 | on | Roads on minus off | +0.201 | +0.018 | +0.012 | -6.458 | -11.825 |
| 1000 | off | Zoning on minus off | +0.000 | +0.000 | -0.004 | +2.304 | +2.228 |
| 1000 | off | H20 minus H5 | +33.341 | +33.458 | +0.007 | -7.175 | -7.231 |
| 1000 | off | Roads on minus off | +0.000 | +0.000 | +0.000 | -24.954 | -24.945 |
| 1000 | on | Zoning on minus off | -0.207 | +0.254 | +0.046 | -0.070 | -2.022 |
| 1000 | on | H20 minus H5 | -0.494 | +0.357 | +0.047 | -0.533 | -1.008 |
| 1000 | on | Roads on minus off | -0.023 | +0.024 | -0.010 | -21.049 | -22.340 |

## Broad sweep coverage

| Neighborhood grid | Arrivals/tick | Complete / 200 | Replicates per cell (min–max) |
|---|---|---|---|
| 6×6 | 20 | 160/200 | 4–4 |
| 6×6 | 40 | 160/200 | 4–4 |
| 6×6 | 80 | 160/200 | 4–4 |
| 10×10 | 20 | 160/200 | 4–4 |
| 10×10 | 40 | 200/200 | 5–5 |
| 10×10 | 80 | 156/200 | 3–4 |
| 14×14 | 20 | 160/200 | 4–4 |
| 14×14 | 40 | 147/200 | 3–4 |
| 14×14 | 80 | 120/200 | 3–3 |

## Patterns across the broader grid

Counts below describe conditional mean differences, not independent significance tests or a pooled effect. Each contrast holds other factors fixed and uses common completed seeds (3–5). A zero is within 1e-12 of zero.

| Comparison | Metric | Lower | Zero | Higher | Total |
|---|---|---|---|---|---|
| enable_roads on minus off | exclusion_q1 | 36 | 45 | 99 | 180 |
| enable_roads on minus off | sorting | 103 | 0 | 77 | 180 |
| enable_roads on minus off | commute_q1 | 179 | 0 | 1 | 180 |
| allow_displacement on minus off | exclusion_q1 | 72 | 0 | 108 | 180 |
| allow_displacement on minus off | sorting | 0 | 0 | 180 | 180 |
| allow_displacement on minus off | commute_q1 | 97 | 0 | 83 | 180 |
| zoning T=10 H=5 minus off | exclusion_q1 | 10 | 14 | 12 | 36 |
| zoning T=10 H=5 minus off | sorting | 15 | 0 | 21 | 36 |
| zoning T=10 H=5 minus off | commute_q1 | 14 | 0 | 22 | 36 |
| horizon 20 minus 5 | exclusion_q1 | 18 | 19 | 71 | 108 |
| horizon 20 minus 5 | sorting | 24 | 0 | 84 | 108 |
| horizon 20 minus 5 | commute_q1 | 67 | 0 | 41 | 108 |

Roads lower Q1 mean commute in 179/180 conditional comparisons; displacement increases sorting in 180/180. Exclusion effects vary in sign across settings. These counts overlap in their underlying runs and do not establish statistical significance.

## Interpretation and limits

- **Displacement greatly narrows across-seed exclusion variation in the central H=20 comparison.** At 1,000 ticks (10×10 neighborhoods, 40 arrivals/tick, zoning every 10 ticks, roads off; five seeds), Q1 exclusion without displacement averages 33.34%, spanning 0–84.11%; with displacement it averages 3.95%, spanning 3.77–4.14%. These are seed ranges, not confidence intervals. A possible mechanism is that outbidding incumbents provides an allocation route when construction is restricted, reducing dependence on the particular zoning trajectory while making exclusion more systematically budget-based. This mechanism remains a hypothesis; the result does not establish lower variance for every outcome or setting, and greater residential sorting accompanies it.

- Transport reduces mean effective commute for Q1 and Q5 in both displacement regimes at 250 and 1,000 ticks in the central setting. This is access among housed residents, not a welfare measure.
- Displacement produces a pronounced budget gradient in exclusion. Short-horizon zoning does not uniformly increase exclusion; its effect depends on the displacement regime and endpoint.
- The long horizon produces a highly variable longer-run exclusion outcome without displacement. Show the individual seed range rather than describing the mean as universal.
- Sorting is not geographic contiguity or total household wealth inequality. Low sorting or short commutes can coexist with exclusion because these metrics condition on being housed.
- Q1–Q5 are fixed baseline log-normal budget groups, not re-ranked sample quintiles. Missing metrics stay missing. Bands and whiskers are seed ranges, not confidence intervals.
- The broader sweep is incomplete by runtime, not a random sample of the design. Use conditional contrasts and visible replicate counts; do not pool its unbalanced cells into an overall treatment effect. Size and inflow jointly change development pressure.
- The 250- and 1,000-tick sweeps are separate runs, with different seed counts. They are not treated as a single continuous trajectory.
- Validation: every presentation tick is consecutive; all broad summaries match their raw final configuration and endpoint metrics, have a completion marker and tick 1,000, and pass population/housing denominator checks. Broad intermediate ticks were not reread for this endpoint audit.

## Files and reproduction

`python3 scripts/analyze_completed_sweeps.py` regenerates this analysis, three main-slide time-series charts, the long-run endpoint chart, CSV tables, and all broad-sweep heatmaps. Requires NumPy and Matplotlib; the verified interpreter on this machine is `/opt/anaconda3/bin/python3` (the default Homebrew Python lacks Matplotlib). Figures are exported as PNG, PDF, and SVG in `charts/`. Broad condition summaries, common-seed contrasts, and heatmaps remain in `sweep_results/broad_16core_2026-10-22/`.
