# NIMBY ABM — AI Guide

## Overview

This is a **NIMBY (Not In My Back Yard) Agent-Based Model** simulating urban housing dynamics. Written in Julia, with a real-time 3D visualization in Blender via WebSocket. The model captures how heterogeneous residents search for housing, bid up construction, and vote on zoning laws that restrict new supply.

---

## File Map

| File | Role |
|------|------|
| `main.jl` | Entry point, simulation loop, reset |
| `structs.jl` | Core data types |
| `generation.jl` | City grid and agent creation |
| `utility.jl` | Agent utility function (Frank copula) |
| `step.jl` | Per-step logic (movement, construction) |
| `laws.jl` | Land-use law proposals and voting |
| `transport.jl` | Road network, hop-count cache, effective commute distance |
| `employer.jl` | Employer struct, worker assignment, branch-simulated location search |
| `visualizer.jl` | Julia-side WebSocket server |
| `blender_vis.py` | Blender add-on (receiver + renderer) |
| `sweep.jl` | Overnight parallel parameter sweep (162 configs, no visualizer) |
| `blender_sweep_loader.py` | Standalone Blender script for loading sweep JSON snapshots |
| `talk.tex` | Beamer presentation "Urbanization from the Bottom Up" (GMU CSS) |

---

## Data Model (`structs.jl`)

- **`Position`** — 2D integer grid coordinate (building units)
- **`Dwelling`** — one housing unit; tracks building, floor, and occupant ID (0 = vacant)
- **`Building`** — land parcel; grows vertically as dwellings are added; `height(b) = length(b.dwellings)`
- **`Neighborhood`** — a k×k block of buildings; the unit of zoning law governance
- **`Agent`** — a person with a job location, budget, and residential preference parameters
- **`LandUseLaw` / `LawNode`** — a depth-2 binary decision tree that can prohibit construction based on neighborhood observables
- **`City`** — top-level container: neighborhoods, buildings, dwellings (flat list), agents, lookup tables, per-neighborhood laws, road list (`roads`), pairwise neighborhood hop-count cache (`nh_hop_cache`), and employers

---

## Agent Preferences

Each agent is created with preferences drawn from log-normal / truncated normal distributions:

| Parameter | Meaning |
|-----------|---------|
| `budget` | log-normal; scales housing affordability |
| `pref_neighborhood_density` | preferred median building height in neighborhood |
| `pref_neighborhood_max_height` | preferred max height in neighborhood |
| `pref_neighborhood_min_height` | preferred min height in neighborhood |
| `pref_building_height` | preferred height of home building |
| `σ_neighborhood` | sensitivity to % deviation from preferred neighborhood density |
| `σ_building` | sensitivity to % deviation from preferred building height |
| `proximity_scale` | exponential decay length for job distance |
| `copula_θ` | Frank copula dependence parameter (positive = dimensions reinforce each other) |

Job buildings are assigned at creation, weighted by `job_weight(b) = height(b) + 1`.

---

## Utility Function (`utility.jl`)

Agent utility is a **Frank copula** over marginal utilities in [0, 1]:

1. **Proximity**: `exp(-dist / proximity_scale)` — exponential decay with distance to job
2. **Neighborhood density**: half-normal on % deviation from preferred median height
3. **Neighborhood max height**: half-normal on % deviation from preferred max
4. **Neighborhood min height**: half-normal on % deviation from preferred min
5. **Building height**: half-normal on % deviation from preferred building height

Active dimensions are configurable via `set_utility_dimensions!(...)`. The Frank copula with θ > 0 models positive dependence (all dimensions must be satisfied jointly).

---

## Simulation Step (`step.jl`)

Each call to `step!`:
1. Snapshot neighborhood statistics into a cache (median/max/min height, vacancy rate)
2. Shuffle selected agents; for each:
   - Sample up to `2n_search` existing dwellings at random
   - If a sampled vacancy has higher utility than current home → move in
   - If unhoused and no vacancy found → search `3n_search` candidate buildings (`2n` weighted by utility + `n` uniform random), pick best that passes zoning law, **build a new dwelling**; if Phase 1 finds nothing, fall back to exhaustive search across all law-free neighborhoods

`run_steps!` in `main.jl` separates movers (existing agents attempting relocation) from inflow (new agents, always allowed to build if needed). Every unhoused agent is stepped on every tick regardless of `existing_move_share`; that parameter applies only to the housed pool.

---

## Land-Use Laws / NIMBY Mechanism (`laws.jl`)

Every `land_use_eval_every` steps:

1. **Propose**: for every neighborhood (regardless of whether it already has an active law), generate a random depth-2 decision tree over observables (`median_height`, `max_height`, `min_height`, `vacancy_rate`)
2. **Branch simulation**: deep-copy the city twice (with / without proposed laws); run `land_use_eval_horizon` steps of new-agent inflow on each branch using identical RNG seeds
3. **Vote**: incumbent residents compare their utility in the two branches; majority rules
4. **Adopt**: if >50% vote yes, the law becomes permanent — `can_build_in_neighborhood` will block new construction when the tree returns `prohibit_new_build = true`

---

## Visualization

### Julia side (`visualizer.jl`)
- WebSocket server on `ws://127.0.0.1:8765` (configurable)
- On connect: sends `city_config`, `color_scheme`, then all existing dwellings (`new_dwellings`)
- Each step diff: `new_dwellings` (geometry) + `budget_updates` (color changes)
- Messages chunked in batches of 200

### Blender side (`blender_vis.py`)
- Blender add-on; UI panel under View3D → N → NIMBY
- Dwellings rendered as 0.9-unit cubes using **vertex instancing** (one instancer mesh per neighborhood for performance)
- Color modes: **budget** (occupant wealth), **building height**, **neighborhood density**
- Operators: Setup Scene, Start, Stop, Clear Dwellings, Recolor All

### Workflow
1. Run Julia backend (headless): `julia main.jl`
   - Starts WebSocket servers on ports 8765 (Blender) and 8766 (browser)
2. Open `index.html` in a browser to control the model (Start / Stop / Reset, live stats)
3. In Blender: load `blender_vis.py` as a script or add-on, press **Setup Scene**, then **Start**
4. In the browser, set parameters and press **Start** — the model runs; Blender updates live

Or interactively from Julia REPL:
```julia
include("main.jl")
city, vis, rng = init_model(n_agents=5_000)
run_steps!(city, vis, rng; n_steps=10)
```

### Blender update frequency
Controlled by `blender_update_every` in `run_steps!` / browser UI:
- `0` → send one diff at the very end of the batch
- `k > 0` → send a diff every `k` steps (and once at the end if needed)

---

## Key Entry Points

```julia
# Headless mode (browser-driven)
# shell: julia main.jl
# then open index.html

# Interactive REPL use
include("main.jl")
city, vis, rng = init_model(n_agents=5_000)
run_steps!(city, vis, rng; n_steps=10)
set_color_scheme!(vis; attribute="height", max_value=20.0)
run_steps!(city, vis, rng; n_steps=10)

# Reset without restarting Julia
reset_model!(city, vis, rng; n_agents=5_000)
```

---

---

## Overnight Parameter Sweep (`sweep.jl`)

### What it sweeps

| Axis | Values | Meaning |
|------|--------|---------|
| `enable_roads` | `false`, `true` | transport network on/off |
| `law_every` (T) | 5, 10, 20 | how often zoning votes fire (steps) |
| `law_horizon` (H) | 3, 7, 15 | branch-simulation look-ahead depth |
| `n_sqrt` | 6, 8, 10 | city side length (city = n×n neighbourhoods, k=8) |
| `seed` | 42, 137, 999 | replication |

Total: 2 × 3 × 3 × 3 × 3 = **162 runs**. Population is **fixed** across city sizes (`N_AGENTS_INIT = 500`, `AGENTS_INFLOW = 50`) so density varies — small cities are crowded, large cities sparse.

### How to run

```bash
# On any machine with Julia installed and the project dependencies
cd /path/to/urban1
julia --project sweep.jl
```

The script automatically detects available cores and spawns `min(CPU_THREADS − 1, 15)` workers via `Distributed.addprocs`.

### Julia package dependencies

These must be installed in the project environment (`julia --project` then `]instantiate`, or `]add` manually):

```
Distributed   (stdlib)
Random        (stdlib)
Statistics    (stdlib)
StatsBase
CSV
DataFrames
JSON3
```

### Outputs

All written to `sweep_results/` (created automatically):

| File | Content |
|------|---------|
| `seed<S>_roads<R>_T<T>_H<H>_n<N>.csv` | Per-step metrics for one run |
| `seed<S>_roads<R>_T<T>_H<H>_n<N>_city.json` | Final city snapshot for Blender |
| `all_runs.csv` | All per-run CSVs merged (written at end) |

Per-step metrics columns: `seed`, `enable_roads`, `law_every`, `law_horizon`, `n_sqrt`, `step`, `n_agents`, `housed_frac`, `mean_height`, `max_height`, `pct_laws`, `n_roads`, `height_p10`, `height_p50`, `height_p90`, `elapsed_s`.

### City snapshot format (`*_city.json`)

Mirrors the live WebSocket messages so `blender_sweep_loader.py` can load them directly:

```json
{
  "run_id":      "seed42_roadstrue_T10_H7_n8",
  "run_config":  { ...all cfg fields... },
  "city_config": { "n_x": 8, "n_y": 8, "k": 8 },
  "dwellings":   [{"id":1, "x":3, "y":4, "floor":2, "budget":1234.5}, ...],
  "roads":       [{"nid_a":1, "nid_b":2, "x_a":0.5, "y_a":0.5, "x_b":4.5, "y_b":0.5}, ...]
}
```

### Blender loader (`blender_sweep_loader.py`)

Load a snapshot interactively or render headless:

```bash
# Interactive: open Blender, run the script, use the "NIMBY Sweep" N-panel
#   → Load Snapshot (browse to a *_city.json file)
#   → Recolor (switch between budget / height / density color modes)

# Headless batch render of all runs in a sweep directory:
blender --background --python blender_sweep_loader.py -- \
  --sweep_dir sweep_results \
  --output_dir renders \
  --color_attr height
```

Color modes: `budget`, `height`, `density` (same logic as `blender_vis.py`).

---

## Changelog

### 2026-03-19 (session 10)

#### `sweep.jl` (new file)
- Overnight parallel parameter sweep: 162 configs across `enable_roads` × `law_every` × `law_horizon` × `n_sqrt` × `seed`
- Uses `Distributed.addprocs` + `pmap`; spawns `min(CPU_THREADS − 1, 15)` workers
- Population **fixed** (`N_AGENTS_INIT = 500`, `AGENTS_INFLOW = 50`) across all city sizes — density varies with `n_sqrt` to show law-formation and inequality differences
- Each run writes `sweep_results/<run_id>.csv` (per-step metrics) immediately on completion for crash resilience
- Constants used in `@everywhere` functions (`N_SEARCH`, `ROAD_UNIT`, `ROAD_EVERY`, `MOVE_SHARE`) defined inside the `@everywhere begin...end` block so workers can access them

#### `sweep.jl` — city snapshot for Blender
- Each run also writes `sweep_results/<run_id>_city.json` via `_save_city_snapshot`
- Format mirrors live WebSocket messages: `city_config`, `dwellings` (id, x, y, floor, budget), `roads` (nid_a/b + centre coordinates)
- Uses `JSON3` for serialization

#### `blender_sweep_loader.py` (new file)
- Standalone Blender script (no live WebSocket dependency) for loading sweep snapshots
- Replicates all mesh/color logic from `blender_vis.py`: direct mesh geometry per neighbourhood, `FLOAT_COLOR CORNER` attribute, Principled BSDF with `display_color` geometry attribute
- Three operators: `SWEEP_OT_Load` (browse + load a `*_city.json`), `SWEEP_OT_Recolor` (switch color mode), `SWEEP_OT_BatchRender`
- N-panel tab: "NIMBY Sweep" in View3D
- Headless batch render: `blender --background --python blender_sweep_loader.py -- --sweep_dir sweep_results --output_dir renders --color_attr height`

#### `talk.tex` (new file) — Beamer presentation
- Title: "Urbanization from the Bottom Up"; audience: GMU CSS & Data Science group
- Black background, white/yellow/green/red/blue text; all diagrams in TikZ + pgfplots
- **pgfplots compat**: installed version is 2014-era; use `\pgfplotsset{compat=1.10}` and `\pgfmathtruncatemacro` (not `\pgfmathsetmacro`) for any integer comparisons in `\ifnum`
- `matrix plot*` is unsupported — heatmap slide uses pure TikZ `\fill` + `\foreach` instead
- Slide structure: Outline → Fairfax prices (PNG) → Why ABM → City Structure (TikZ grid) → Agent Preferences → Utility Function → Simulation Step (flowchart) → NIMBY Mechanism (decision tree) → Transport & Employer → What Emerges → AI section (4 slides) → Sweep Design + 3 placeholder result frames → Connection to Real Market → Zoning Laws Are Already Trees → Future Work → Summary → Thank You

#### `talk.tex` — "Zoning Laws Are Already Trees" slide
- Fed the full Fairfax County zoning ordinance to ChatGPT and asked to what extent the rules can be represented as decision trees
- Answer: most can (permit thresholds, setbacks, height limits, use-by-right tables); main exception is special-purpose / planned-development districts requiring case-by-case negotiation
- Connects to naturalness of Julia structs for zone types + multiple dispatch for a single `can_build_in_neighborhood` interface
- Opens path to a synthetic Fairfax County: parameterise model directly from ordinance

### 2026-02-27 (session 1)
- Created `AIguide.md` with initial codebase description.

### 2026-02-27 (session 2)

#### `visualizer.jl`
- Added three fields to `Visualizer` struct:
  - `incoming::Channel{Any}` — commands from Blender and browser clients
  - `ctrl_clients::Vector{Any}` — browser WebSocket connections
  - `stop_flag::Ref{Bool}` — set `true` to interrupt a running step batch
- Updated constructor accordingly (channel capacity 32, stop_flag starts `true`)
- Rewrote `listen!` to fix concurrent read/write WebSocket conflict that was causing Blender updates to silently drop:
  - Incoming Blender messages are read in a dedicated `@async` task that puts to `vis.incoming`
  - The handler task itself runs a passive `while !isclosed; sleep(0.1); end` loop to keep the connection alive without blocking sends
- Added `_broadcast_ctrl!(vis, payload)` — sends JSON to all connected browser clients, pruning dead connections
- Added `listen_control!(vis; port=8766)` — second WebSocket server for the browser UI; all incoming messages forwarded to `vis.incoming`

#### `main.jl`
- Removed blocking `readline()` from `init_model`; runs fully headlessly when invoked as a script
- Added `ctrl_port::Int = 8766` parameter to `init_model` and `run!`
- `init_model` now creates `rng_ref`, calls `listen_control!` and `_ctrl_loop!` automatically
- Added `send_ctrl_stats!(vis, t, city, elapsed)` — broadcasts per-step stats to browser clients
- Added `_ctrl_loop!(vis, city_ref, rng_ref)` — background task draining `vis.incoming`:
  - `"start"` → launches `run_steps!` as `@async` with browser-supplied params; broadcasts `running=true/false`
  - `"stop"` → sets `vis.stop_flag[] = true`
  - `"reset"` / `"reset_request"` → stops, waits 0.3 s, calls `reset_model!`, broadcasts `running=false`
- `run_steps!` now checks `vis.stop_flag[]` at the start of each step (early-exit from browser Stop button) and calls `send_ctrl_stats!` each step
- Entry point uses `isinteractive()` to choose between REPL and headless modes:
  - Non-interactive: `while true; sleep(60); end` keeps async servers alive
  - Interactive: prints REPL prompt, yields to async tasks while idle

#### `blender_vis.py`
- **Websocket auto-install**: `import websocket` falls back to prepending `site.getusersitepackages()` to `sys.path`, then runs `pip install websocket-client` via `ensurepip` if still missing — handles the case where pip installs to user site-packages outside Blender's default path
- **Reset operator** (`NIMBY_OT_Reset`): clears all Blender dwelling geometry and sends `{"type": "reset_request"}` to Julia over the WebSocket; appears as **Reset** button in the N-panel
- **Rendering approach** — reverted from GeoNodes to **VERTS instancing** (GeoNodes discarded due to fragility across Blender versions):
  - One instancer mesh object per neighbourhood (`NIMBY_DwellingPoints_<id>`)
  - One prototype cube object per neighbourhood (`NIMBY_DwellingProto_<id>`) parented to the instancer
  - `instance_type = "VERTS"` — one cube spawned per vertex at the vertex's position
  - Cubes are 0.9 × 0.9 × 1 unit (±0.45 XY, ±0.5 Z); stacked floor-by-floor via Z coordinate
- **Per-dwelling coloring** via `FLOAT_COLOR` vertex attribute:
  - Each instancer mesh carries a `display_color` `FLOAT_COLOR` `POINT` attribute (one RGBA entry per vertex/dwelling)
  - One shared material `NIMBY_DwellingMat` uses `ShaderNodeAttribute(attribute_name="display_color", attribute_type="INSTANCER")` → `Principled BSDF Base Color`, so each dwelling cube reads its own color independently
  - `_dwellings` dict now stores `vert_idx` for O(1) color updates
  - `update_budget()` writes directly to `obj.data.attributes["display_color"].data[vert_idx].color`
  - `recolor_all()` rewrites every vertex's color in one pass (called on color scheme changes)
- Positions centered on city grid: `co = (x - center_x, y - center_y, floor - 0.5)`

### 2026-02-27 (session 3)

#### `blender_vis.py` — fix per-dwelling coloring

Root cause: `ShaderNodeAttribute` with `attribute_type = "INSTANCER"` reads **object-level** attributes from the instancer, not individual vertex attributes from its mesh. Blender's VERTS instancing cannot pass per-vertex FLOAT_COLOR data to the instanced object's shader. The coloring therefore never worked — all dwellings rendered as uniform grey.

Fix: dropped VERTS instancing entirely and switched to **direct mesh geometry** per neighbourhood:
- `bl_info` minimum version bumped to (3, 2, 0) — required for `mesh.color_attributes` / `FLOAT_COLOR`
- Removed `_POINTS_OBJ_PREFIX`, `_PROTO_OBJ_PREFIX`, `_create_cube_mesh`, `_ensure_instancer`
- Added `_NH_OBJ_PREFIX = "NIMBY_NH_"`, `_CUBE_VERTS`, `_CUBE_FACES`, `_LOOPS_PER_DWELLING = 24`
- Added `_nh_dwelling_ids: dict` — tracks insertion-order list of `d_id` per neighbourhood (index = `mesh_idx`)
- `_dwellings` entries now store `mesh_idx` instead of `vert_idx`
- `_get_dwelling_material`: removed `attr.attribute_type = "INSTANCER"` — now uses default `"GEOMETRY"`, which reads from the mesh's own per-face-corner attributes
- Added `_ensure_nh_obj(nh_id)` — creates/returns a plain mesh object per neighbourhood with the shared material applied
- Added `_rebuild_nh_mesh(nh_id)` — rebuilds the neighbourhood mesh from scratch via `mesh.clear_geometry()` + `mesh.from_pydata(all_verts, [], all_faces)`, then recreates the `FLOAT_COLOR CORNER` attribute `display_color` and sets all 24 loops per dwelling to `_resolve_color(d_id)`
- `create_dwellings_batch` — populates `_dwellings` + `_nh_dwelling_ids`, then calls `_rebuild_nh_mesh` for each affected neighbourhood
- `update_budget` — writes `color_attr.data[mesh_idx*24 : mesh_idx*24+24].color` directly, O(24) per dwelling
- `recolor_all` — iterates all dwellings and rewrites loop colors, calls `mesh.update()` once per dirty mesh
- `reset_dwellings` — clears both dicts and calls `mesh.clear_geometry()` + removes `display_color` attribute on all NH objects
- Fixed `_handle("color_scheme")` to use dot notation (`props.cs_attribute = ...`) instead of dict-style subscript access

#### `index.html` (new file)
- Dark-themed browser control panel connecting to `ws://127.0.0.1:8766`
- Editable parameters: n_steps, n_search, agents_inflow, existing_move_share, blender_update_every, land_use_eval_every, land_use_eval_horizon, step_delay
- Start / Stop / Reset buttons (state-aware: disabled when not applicable)
- Live stats grid: step, agents, housed, dwellings, vacant, mean height, max height, step time
- Auto-reconnects to Julia every 3 seconds if disconnected

### 2026-02-27 (session 4)

No code changes. Key model behaviour clarified:

#### Why agents > dwellings (unhoused agents)

- An unhoused agent is one with `dwelling_id == 0`.
- New inflow agents (`build_if_unhoused=true`) can only fail to build if **all** `2*n_search` sampled candidate buildings fall in neighbourhoods where the active law's decision tree currently returns `prohibit_new_build = true`. This does **not** require every neighbourhood to have a law — a minority of blocked neighbourhoods combined with small sample size (default `n_search=5`, so 10 candidates) is sufficient.
- Laws are **conditional**: an active `LandUseLaw` evaluates a depth-2 tree against live observables (`median_height`, `max_height`, `min_height`, `vacancy_rate`). A neighbourhood with an active law may still permit building at current conditions.
- Once unhoused, an agent is processed as a mover with `build_if_unhoused=false` and cannot build their way out through the normal vacancy search.
- **Fixed in session 8**: a Phase 2 fallback in `step.jl` now allows unhoused inflow agents to build in the best-utility building across all law-free neighbourhoods if the weighted candidate search fails. Agents can only remain permanently unhoused if every neighbourhood's active laws currently prohibit construction.

### 2026-03-19 (session 9)

#### `main.jl` — unhoused agents always re-housed
- Bug: `existing_move_share` sampled a flat fraction of **all** agents (housed + unhoused), so displaced agents might wait many steps before getting a chance to rebuild — causing a growing unhoused backlog.
- Fix: mover sampling now always steps every unhoused agent each tick, while `existing_move_share` is applied only to the housed pool. All unhoused movers are called with `build_if_unhoused=true`.

#### `main.jl` — employer starts at city centre
- Bug: employer was initialised at building ID 1 (position (0,0) — a corner). All workers had `job_building_id = 1`, so agents clustered at the corner and stacked into a massive tower there.
- Fix: on creation, the employer is placed at the building nearest the geometric centre of the grid, computed from `city.n_x`, `city.n_y`, `city.k`.

#### `blender_vis.py` — transparency for dwellings and landscape
- Added `_DWELLING_ALPHA = 0.7` and `_LANDSCAPE_ALPHA = 0.3` constants.
- `_get_dwelling_material`: sets `mat.blend_method = "BLEND"` and `bsdf.inputs["Alpha"].default_value = _DWELLING_ALPHA`.
- `create_landscape`: sets `mat.blend_method = "BLEND"`, `mat.diffuse_color` alpha, and `bsdf.inputs["Alpha"].default_value = _LANDSCAPE_ALPHA` — makes ground plane semi-transparent so underground road tubes are visible.

#### `blender_vis.py` — narrow black roads
- `_ROAD_BEVEL` reduced from `1.5` → `0.3` (thin tube).
- `_get_road_material` replaced bright yellow Emission shader with a black Principled BSDF (`Base Color = (0,0,0,1)`, `Roughness = 0.9`) — roads appear as narrow black lines visible against the transparent ground.

#### `main.jl` + `index.html` — City Maps panel
- `send_ctrl_stats!` now computes and broadcasts `nh_density` (per-neighbourhood median height array), `nh_employment` (worker count per neighbourhood), and `roads` (list of `[nid_a, nid_b]` pairs).
- New **City Maps** panel in `index.html` with three `<canvas>` elements: neighbourhood density heatmap (green), employment heatmap (purple), road network (yellow edges + red connected nodes). Rendered by `drawNhMap()`.

#### `main.jl` + `index.html` — complete parameter GUI with tooltips
- `run_steps!` now accepts all 18 agent-distribution parameters (`budget_μ/σ`, `pref_density_μ/σ`, `pref_height_μ/σ`, `pref_nh_max/min_μ/σ`, `σ_neighborhood_μ/σ`, `σ_building_μ/σ`, `proximity_scale_μ/σ`, `copula_θ_μ/σ`) and forwards them to `add_agents!` each inflow step.
- `_ctrl_loop!` city-rebuild logic extended to also handle a `k` parameter (neighbourhood side length).
- `index.html` redesigned left column: parameters reorganised into sections (Simulation, City Grid, Land-Use Laws, Roads, Employer, Blender); new **Agent Distribution** panel with all 18 parameters in μ/σ pairs. Every field has a `ⓘ` icon with a hover tooltip (`data-tip` + CSS `::after`) explaining the parameter.

#### `transport.jl` — road planner corner bias fixed
- Bug: `evaluate_roads!` iterated pairs as `for a in 1:n, b in (a+1):n` with a strict `> best_score` update, so neighbourhood 1 (corner) always won ties (e.g. when all medians are 0 early in the run).
- Fix: candidate pairs are now collected into a vector and shuffled via `shuffle!(rng, candidates)` before scoring, so ties resolve uniformly at random. `rng::AbstractRNG` added as a parameter; call site in `main.jl` passes the simulation RNG.

### 2026-03-12 (session 8)

#### `structs.jl` — employer worker deduplication
- `Employer.worker_ids` changed from `Vector{Int32}` to `Set{Int32}` — prevents duplicate worker registration under async race conditions; `push!` on a Set is idempotent

#### `step.jl` — unhoused agent fallback build
- Bug: unhoused agents could only build in buildings returned by `search_candidates` (a small weighted sample of `2*n_search` buildings). If all sampled buildings fell in law-blocked neighbourhoods the agent stayed unhoused permanently, even when the majority of the city permitted building.
- Fix: added a **Phase 2 fallback** — if the weighted candidate search finds no buildable location, the agent exhaustively searches all law-free neighbourhoods and builds in the best-utility building among them. The fallback only fires when Phase 1 fails, so it adds no cost in the common case.

#### `employer.jl` + `structs.jl` + `generation.jl` + `main.jl` + `index.html` — employer relocation feature
- New `Employer` struct: `id`, `job_building_id`, `worker_ids` (Set)
- `City` gains `employers::Vector{Employer}` field; initialised empty in `generate_city`
- New file `employer.jl`:
  - `assign_to_employer!(city, eid, agent_ids)` — registers agents as workers and sets their `job_building_id` to the employer's current building
  - `evaluate_employer_location!(city, rng, eid; n_candidates, horizon, n_search, road_unit)` — branch-simulates `n_candidates` candidate buildings (weighted by `job_weight`), runs `horizon` steps on each deepcopy, measures mean effective commute of housed workers, moves employer to the best candidate if strictly better than current location
  - `_mean_employer_commute` — helper computing mean `effective_distance` over housed workers
- `run_steps!` gains `enable_employer`, `employer_eval_every`, `employer_n_candidates`, `employer_horizon` params; assigns new inflow agents to employer each step; evaluates location every `employer_eval_every` steps
- `reset_model!` clears `city.employers`; `_ctrl_loop!` creates a fresh employer (building 1, empty workers) when `enable_employer=true` and no employer exists
- `send_ctrl_stats!` broadcasts `employer_workers` (worker count) and `employer_pos` ([x, y] of current building)
- `index.html`: employer checkbox + 3 parameter fields; `[EMPLOYER]` log entries in purple; "Emp workers" and "Emp location" stat tiles

### 2026-03-12 (session 7)

#### `transport.jl` — road path fix
- `evaluate_roads!` now walks a **4-connected Bresenham path** from the chosen endpoint pair to the other, adding every adjacent edge along the diagonal so all intermediate neighbourhoods are fully connected in the hop cache
- Blender shows each adjacent segment; collectively they form a diagonal-looking corridor
- `_ROAD_Z` changed from `-0.5` to `-4.0` and `_ROAD_BEVEL` from `0.2` to `1.5` in `blender_vis.py` for visibility at city scale

#### `blender_vis.py` — road visibility
- `_ROAD_Z = -4.0` — tubes sit well below the landscape plane
- `_ROAD_BEVEL = 1.5` — 3-unit diameter tubes clearly visible across the 80-unit city grid

### 2026-03-12 (session 6)

#### `transport.jl` (new file)
- `nh_center(city, nid)` — neighbourhood centre in building-grid units
- `rebuild_hop_cache!(city)` — BFS over `city.roads` to fill `city.nh_hop_cache` (pairwise hop counts; `typemax(Int32)` = unconnected)
- `effective_distance(city, home_b, job_b, road_unit)` — `min(euclidean, subway)` where subway = walk to home nh-centre + hops × road_unit + walk from job nh-centre; falls back to Euclidean if neighbourhoods unconnected
- `evaluate_roads!(city; road_unit)` — greedy planner: scores all unbuilt neighbourhood pairs by `|median_height_a − median_height_b|`, adds the best edge, rebuilds hop cache; returns a `Dict` with `nid_a`, `nid_b`, `score`, `msg`, `n_roads`

#### `structs.jl`
- Added `roads::Vector{Tuple{Int32,Int32}}` and `nh_hop_cache::Matrix{Int32}` to `City`

#### `generation.jl`
- `generate_city` initialises `roads = Tuple{Int32,Int32}[]` and `hop_cache` (identity diagonal, `typemax(Int32)` elsewhere)

#### `step.jl`
- `search_candidates` type-B weights now use `effective_distance` instead of raw Euclidean
- `step!` passes `road_unit` through to both `effective_distance` calls and `search_candidates`

#### `laws.jl`
- `_simulate_hypothetical!` and `evaluate_land_use_laws!` accept and forward `road_unit`

#### `main.jl`
- `run_steps!` gains `enable_roads`, `road_eval_every`, `road_unit` parameters; calls `evaluate_roads!` and `send_new_roads!` on schedule; broadcasts `"road"` message to browser clients
- `reset_model!` clears `city.roads` and calls `rebuild_hop_cache!`
- `send_ctrl_stats!` broadcasts `"n_roads"` count
- `_ctrl_loop!` forwards `enable_roads`, `road_eval_every`, `road_unit` from browser start command

#### `visualizer.jl`
- `Visualizer` gains `sent_roads::Set{Tuple{Int32,Int32}}`
- `_road_entry(city, nid_a, nid_b)` — builds road dict with centre positions
- `send_new_roads!(vis, city)` — sends unsent roads as `"new_roads"` message
- `full_sync!` and `send_step_diff!` both call `send_new_roads!`
- `reset_vis!` clears `sent_roads`

#### `blender_vis.py` — road visualization
- `_ROADS_OBJ_NAME = "NIMBY_Roads"`, `_ROAD_Z = -0.5`, `_ROAD_BEVEL = 0.2`
- `_get_road_material()` — yellow Emission shader (RGB 1.0, 0.85, 0.1; strength 3.0)
- `_ensure_roads_obj()` — single CURVE object in "Roads" collection, `bevel_depth=0.2`, 8-sided tube
- `create_roads_batch(roads)` — adds POLY splines at `z = -0.5` (underground subway aesthetic)
- `reset_roads()` — removes all splines, clears `_roads_built` tracking set
- `_handle` wired: `"new_roads"` → `create_roads_batch`; `"reset"` calls both `reset_dwellings` and `reset_roads`

#### `index.html` — road UI
- CSS `.log .entry.road` — cyan (`#00bcd4`) log style
- `msg.type === "road"` handler logs `[ROAD] <msg>` in cyan
- "Roads" stat tile (`s-n-roads`) updated from `msg.n_roads` in stats handler
- "Enable road planning", "Road eval every N steps", "Road unit distance" parameter fields sent in `sendStart()`

### 2026-02-27 (session 5)

#### `generation.jl` — tighten σ defaults
- `σ_neighborhood_μ`: `0.5` → `-0.5` (log-scale; median σ drops from ≈1.65 to ≈0.61 in %-deviation units) in both `generate_agents!` and `add_agents!`
- `σ_building_μ`: same change
- Effect: agents are now meaningfully sensitive to deviations from their preferred density/height; a 100% deviation gives utility ≈0.26 instead of ≈0.83
- Proximity (`proximity_scale`) left unchanged — monotone decay peaking at dist=0 is intentional

#### `structs.jl` — proximity field unchanged
- An earlier edit that replaced `proximity_scale` with `pref_proximity + σ_proximity` was reverted; proximity stays as exponential decay

#### Utility histogram design clarified

- **Realized utility histograms**: computed at each housed agent's current dwelling — show the distribution of achieved utility per dimension
- **Why proximity spreads**: heterogeneous `proximity_scale` (log-normal) + agents can't always live at their job → natural spread across [0,1]
- **Why density/height peaked at 1**: agents freely sort into matching neighbourhoods and build to match preferences → sorting drives housed agents near their bliss point
- **Modal utility**: the mode of each marginal utility function (in dimension/condition space) back-transforms to the agent's preferred value — i.e., `pref_neighborhood_density`, `pref_building_height`, etc. Modal utility in utility space is trivially 1 for all agents. The useful representation is histograms of preferred values in floor units.

#### `main.jl`
- Added `_MODAL_MAX_HEIGHT = 20.0f0` constant
- Added `_hist_bin_dim!(h, val, n)` — bins a floor value into [0, 20] range
- Added `_modal_histograms(city)` — histograms of `pref_neighborhood_density`, `pref_neighborhood_max_height`, `pref_neighborhood_min_height`, `pref_building_height` over **all** agents (not just housed), in floor units
- Fixed early-return bug in `_utility_histograms`: was missing `nh_max` and `nh_min` fields in the zero-agent fast path
- `send_ctrl_stats!`: now also broadcasts `pct_laws` (% of neighbourhoods with an active law) and four modal histogram arrays (`modal_density`, `modal_nh_max`, `modal_nh_min`, `modal_bldg`)
- `_ctrl_loop!` start handler: if `n_neighborhoods_sqrt` in the start command differs from the current city's neighbourhood count, rebuilds the city from scratch (`generate_city(n_sqrt, n_sqrt; k=cur.k)`) and syncs Blender before starting the run

#### `index.html`
- Added **Laws %** stat tile (`s-pct-laws`)
- Added **City side √neighborhoods** parameter field (`p-n_neighborhoods_sqrt`, default 10 = 10×10 city); sent in `sendStart()`
- Renamed histogram panel to **"Realized Utility"** (utility ∈ [0,1]); updated all 6 canvas labels to end in "utility" for clarity
- Added separate **"Preferred Values"** panel (4-column grid, purple/orange colour scheme) showing `modal-density`, `modal-nh-max`, `modal-nh-min`, `modal-bldg` with x-axis labelled 0 / 10 / 20 floors
- `drawHist(id, bins, xLabels)` now accepts an optional `xLabels` array (default `["0","0.5","1"]`) so modal histograms can display floor labels
