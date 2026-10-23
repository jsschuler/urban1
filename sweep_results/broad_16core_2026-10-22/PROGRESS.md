# 16-core sweep progress

State: **Prepared — not running**

- Machine verified: 16 physical cores, 128 GiB RAM.
- Execution: 16 independent Julia workers, one compute thread each; nested numeric-library threading disabled.
- Budget: 12 hours from launch; stop new jobs 30 minutes before the deadline.
- Design: 360 parameter combinations × 5 seeds = 1,800 queued runs, 1,000 ticks each.
- Priority: 200 core comparisons first; then vary city size and inflow.
- Previous four-worker sweep stopped; partial trajectories preserved separately.

Run from the repository root:

```sh
caffeinate -i python3 -u scripts/broad_sweep.py --output sweep_results/broad_16core_2026-10-22 --workers 16 --hours 12
```

This file becomes the live progress dashboard when the command starts. `EVENTS.md` will hold timestamped run events. Ctrl+C stops the coordinator and its workers cleanly.

## Preparation checks

- Eight small-city factorial runs completed successfully with the 16-worker setting.
- Reports and Markdown dashboard generated without errors.
- SIGTERM test stopped both active test workers and recorded interrupted status.
- Python syntax and repository whitespace checks passed.
- Full replacement sweep has not been started.
