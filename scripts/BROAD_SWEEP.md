# Exploratory sweep for the 16-core machine

Run from the repository root:

```sh
caffeinate -i python3 -u scripts/broad_sweep.py --output sweep_results/broad_16core_2026-10-22 --hours 12 --workers 16
```

The queued design is 360 distinct cells, five seeds each (1,800 runs maximum):

| Factor | Values |
|---|---|
| Displacement (actual allocation and voting forecasts) | off, on |
| Transport | off, on |
| Zoning | off; or vote interval T = 5, 10, 20 × horizon H = 5, 10, 20 |
| Neighborhood grid | 6×6, 10×10, 14×14 |
| Arrivals per tick | 20, 40, 80 |
| Seeds | 42, 137, 999, 2026, 8675309 |

Horizon is irrelevant with zoning disabled, so that baseline is run only once per other factor combination. Each run starts empty and lasts 1,000 ticks; k=8, n_search=5, mover share=0.1, employer enabled with 5 candidates and horizon 3 every tick, road evaluation every 20 ticks, hop cost=1.01. Other distributions and utility dimensions retain the live model's defaults. This design does not vary employer behavior or household preference distributions.

Priority: all 40 mechanism cells at 10×10/40 arrivals, across all five seeds (200 runs), followed by the eight other size/inflow contexts across one seed at a time. Within each block, the four displacement/roads combinations are adjacent. This provides useful complete comparisons if the time window expires before the whole queue finishes. Completion of all 1,800 runs is not promised.

Sixteen independent Julia processes, one compute thread and one GC thread each, share the same `run_steps!` implementation as the live model. No WebSocket servers are started. Changing size at fixed inflow changes development pressure; changing inflow at fixed duration also changes total population. Interpret these jointly, not as pure geometry effects at fixed density. Voting and housing choice use the same effective network distance. Arrivals remain unmatched across treatments despite common seed labels, and hypothetical branches do not guarantee matching arrivals either.

The runner stops launching jobs before the deadline (a 30-minute reserve at the default budget). In-flight Julia processes have a timeout at the 12-hour deadline. Completed runs are retained; unfinished runs retain flushed tick diagnostics as `.partial` files and are explicitly labeled as timed out. Final reporting can add a short period after simulation work ends. Resume in the same directory with a new `--hours` budget: completed runs are skipped, unfinished runs restart from zero using the original frozen model. A file lock prevents overlapping orchestrators.

The machine reports 16 physical cores and 128 GiB RAM. The simulation loop is sequential, so parallelism is across independent runs. BLAS, OpenMP, MKL and Accelerate thread counts are capped at one to avoid nested compute pools. The lightweight Python coordinator records progress and generates reports; full 16-worker throughput has not been benchmarked.

Outputs, separate from presentation charts:

- `manifest.json`: full planned grid, ordering and provenance context.
- `source/`: frozen model and scripts; `configs/`: each submitted configuration.
- `PROGRESS.md`: current counts, active runs and last saved ticks, refreshed at least every 15 seconds while waiting for runs.
- `EVENTS.md`: timestamped start/completion/error history in Markdown.
- `status.json`: counts, active runs, failures, timeouts, interruptions, report errors and deadline.
- `sweep.log`, per-run `.log`: progress and model messages.
- `.jsonl`: per-tick diagnostics for complete runs; `.jsonl.partial`: unfinished trajectories.
- `_city.json`: final Blender-compatible city snapshots.
- `.summary.json`, `endpoints.csv`: endpoints and run settings, including all five budget groups and their denominators.
- `condition_summary.csv`: means, sample SD, min/max and available counts per condition/metric.
- `contrasts.csv`: conditional differences in means for displacement, roads, zoning, and horizon. Each comparison uses common completed seed labels with valid metrics on both sides; this is not a matched-arrival estimate or a confidence interval.
- `charts/`: heatmaps of lowest/highest-budget exclusion and commute, plus residential sorting. Every cell reports the actual available replicate count; blanks are unavailable results. Heatmaps refresh every 40 completed runs and at the end.

Read exclusion alongside sorting/access: the latter describe housed residents and can improve when low-budget households become excluded. Q1–Q5 use fixed baseline budget thresholds, not re-ranked population quintiles. Missing values are retained as missing. Longer-run trajectories allow separate inspection of ticks 250 and 500; the automatically generated tables and heatmaps use 1,000-tick endpoints only.

Regenerate reports:

```sh
python3 scripts/broad_report.py sweep_results/broad_16core_2026-10-22
```

The replacement is prepared but **not launched**. Run the command above in your terminal and leave it open. `caffeinate -i` prevents idle sleep until the Python process exits; keep the machine plugged in with its lid open. Press Ctrl+C to request a stop: the coordinator terminates all active Julia workers, preserves their partial files, and writes a final stopped status. SIGTERM behaves the same way. Rerun the same command to resume completed work with a fresh 12-hour budget.

The previous four-worker launch was explicitly stopped and unloaded from macOS. Its four partial trajectories remain in `sweep_results/broad_2026-10-22`; the replacement uses a new directory so its configuration and logs are unambiguous.
