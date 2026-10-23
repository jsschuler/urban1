# Presentation sweep

The presentation sweep runs 24 simulations: four unique conditions × displacement off/on × seeds 42, 137, 999. Zoning-on/H=5/roads-off is reused as the baseline for zoning, horizon, and transport comparisons. This covers all 12 named live presets without rerunning identical configurations.

Each starts with an empty 10×10-neighborhood city, k=8, 40 arrivals/tick, and runs 250 ticks. Employer behavior is enabled with the same evaluation settings as the slides. Road evaluation is every 20 ticks with hop cost 1.01. Housing allocation and zoning forecasts use the same displacement setting and effective-distance calculation. Arrival randomness remains shared with model decisions; matching seeds does not match households.

From the repository root:

```sh
python3 scripts/presentation_sweep.py --output sweep_results/presentation_2026-10-22 --workers 4
```

The sweep calls `run_steps!`, the live model's simulation loop, without starting WebSocket listeners. It disables display delays. Four isolated Julia processes run concurrently, each using one Julia thread. This script is separate from the older broad exploration in `sweep.jl`.

Each output directory includes:

- `manifest.json` and `source/`: settings and a frozen copy of the model and runner.
- One `.log` per simulation, and `.jsonl.partial` diagnostics flushed after every tick.
- Completed `.jsonl` files, renamed only after successful completion, and final Blender-compatible `_city.json` snapshots.
- `status.json` after all jobs finish, recording run or chart failures.

Repeating the command with the same output directory skips completed runs, uses the original source snapshot, and restarts unfinished runs from tick zero. Do not launch two orchestrators against the same output directory. To use revised source, choose a new output directory.

Charts regenerate after each completed run, using only seeds with all four relevant comparison cells complete. Thus early charts may have one or two seeds; the actual count is printed. Refresh or revisit the result slide to load the newest chart. Shading is the minimum–maximum range across seeds, not a confidence interval. Each chart shows exclusion and effective commute for the lowest/highest fixed baseline budget quintiles, and population-weighted residential sorting. All five quintiles and their denominators are retained in raw output. Missing observations remain missing. Results are descriptive simulation comparisons, with unmatched arrivals.

Regenerate charts manually:

```sh
python3 scripts/plot_presentation.py sweep_results/presentation_2026-10-22 slides/MarketsAndSociety2026/charts
```

For a quick integration check, use a separate output and chart directory:

```sh
python3 scripts/presentation_sweep.py --output /tmp/presentation-check --steps 22 --side 2 --inflow 2 --seeds 42 --workers 2 --charts /tmp/presentation-check/charts
```

This exercises all eight conditions, including zoning and road evaluation. Test charts must not be copied into the presentation.

## Active overnight job

The October 22 sweep was launched through macOS `launchctl` with label `urban.presentation-sweep.20261022`. Its output is in `sweep_results/presentation_2026-10-22/sweep.log`. The job runs under `caffeinate -i` to prevent idle system sleep while work remains, independently of this terminal session. Keep the computer powered and its lid open overnight.

Inspect the job with `launchctl list urban.presentation-sweep.20261022`. Run logs and `.partial` files show ongoing progress; `status.json` reports completion. Before restarting a stopped/failed sweep, confirm the previous workers have exited, then use the resume command above. No completion time is assumed from the small-city smoke test.
