"""Reproduce slide exports and descriptive analysis from the October 22 sweeps.

Run from the repository root: python3 scripts/analyze_completed_sweeps.py
Only complete trajectories enter the analysis; no simulations are launched.
"""
import csv
import json
from pathlib import Path
import statistics as st

from plot_presentation import render, sorting, plt, np, PercentFormatter
from broad_report import report, FACTORS

ROOT = Path(__file__).resolve().parents[1]
PRESENTATION = ROOT / 'sweep_results/presentation_2026-10-22'
BROAD = ROOT / 'sweep_results/broad_16core_2026-10-22'
OUT = ROOT / 'slides/MarketsAndSociety2026/charts'
METRICS = ['exclusion_q1', 'exclusion_q5', 'sorting', 'commute_q1', 'commute_q5']
CONDITIONS = [(0, 5, False), (10, 5, False), (10, 20, False), (10, 5, True)]
LABELS = ['Zoning off', 'H=5', 'H=20', 'H=5 + roads']


def endpoint(cfg, row):
    result = {**cfg, 'sorting': float(sorting(row))}
    for q in range(1, 6):
        for name, field in [('exclusion', 'budget_quintile_unhoused_share'), ('commute', 'budget_quintile_mean_commute'), ('population', 'budget_quintile_population'), ('housed', 'budget_quintile_housed')]:
            result[f'{name}_q{q}'] = row[field][q-1]
    return result


def write_csv(path, rows):
    with path.open('w', newline='') as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0])); w.writeheader(); w.writerows(rows)


def cell(rows, d, condition):
    return [r for r in rows if (r['land_use_eval_every'], r['land_use_eval_horizon'], r['enable_roads']) == condition and r['allow_displacement'] == d]


def main():
    OUT.mkdir(exist_ok=True)
    presentation = []
    for path in sorted(PRESENTATION.glob('*.jsonl')):
        records = [json.loads(line) for line in path.read_text().splitlines()]
        cfg = records[0]['config']; steps = [r for r in records if r['type'] == 'step']
        assert records[-1]['type'] == 'complete'
        assert [r['step'] for r in steps] == list(range(1, cfg['n_steps']+1))
        presentation.append(endpoint(cfg, steps[-1]))
    assert len(presentation) == 24
    broad = []
    for path in sorted(BROAD.glob('*.summary.json')):
        summary = json.loads(path.read_text())
        raw = path.with_name(path.name.replace('.summary.json', '.jsonl'))
        with raw.open('rb') as f:
            cfg = json.loads(f.readline())['config']
            f.seek(max(0, raw.stat().st_size-131072))
            tail = f.read().splitlines()
        assert json.loads(tail[-1])['type'] == 'complete', raw
        last = json.loads(tail[-2])
        assert last['type'] == 'step' and last['step'] == cfg['n_steps'] == 1000, raw
        calculated = endpoint(cfg, last)
        for k, v in calculated.items():
            assert summary[k] == v, (raw, k)
        assert last['agents'] == cfg['agents_inflow'] * cfg['n_steps']
        assert sum(last['budget_quintile_population']) == last['agents']
        assert sum(last['budget_quintile_housed']) == last['housed']
        broad.append(summary)
    status = json.loads((BROAD/'status.json').read_text())
    assert len(broad) == status['complete']
    keys = [tuple(r[k] for k in FACTORS) + (r['seed'],) for r in broad]
    assert len(set(keys)) == len(keys)
    core = [r for r in broad if r['n_neighborhoods_sqrt'] == 10 and r['agents_inflow'] == 40]
    assert len(core) == 200
    for d in (False, True):
        for condition in CONDITIONS:
            assert {r['seed'] for r in cell(core, d, condition)} == {42,137,999,2026,8675309}
    render(PRESENTATION, OUT)
    report(BROAD, broad, plots=True)
    write_csv(OUT/'presentation_endpoints.csv', presentation)
    tables = []
    for dataset, rows in [('presentation_250', presentation), ('core_1000', core)]:
        for d in (False, True):
            for condition, label in zip(CONDITIONS, LABELS):
                group = cell(rows, d, condition)
                for m in METRICS:
                    values = [r[m] for r in group if r[m] is not None]
                    tables.append(dict(dataset=dataset, displacement=d, condition=label, metric=m,
                                       n=len(values), mean=st.mean(values), minimum=min(values), maximum=max(values)))
    write_csv(OUT/'endpoint_summary.csv', tables)
    contrasts = []
    for dataset, rows in [('presentation_250', presentation), ('core_1000', core)]:
        for d in (False, True):
            for name, a, b in [('Zoning on minus off',0,1), ('H20 minus H5',1,2), ('Roads on minus off',1,3)]:
                left, right = cell(rows,d,CONDITIONS[a]), cell(rows,d,CONDITIONS[b])
                for m in METRICS:
                    x={r['seed']:r[m] for r in left if r[m] is not None}; y={r['seed']:r[m] for r in right if r[m] is not None}
                    seeds=sorted(x.keys() & y.keys())
                    contrasts.append(dict(dataset=dataset, displacement=d, contrast=name, metric=m, n=len(seeds),
                        difference_in_means=st.mean(y[s]-x[s] for s in seeds), common_seeds=' '.join(map(str,seeds))))
    write_csv(OUT/'slide_contrasts.csv', contrasts)
    fig, axes = plt.subplots(2,3,figsize=(16,8),constrained_layout=True,sharey='col')
    for i,d in enumerate((False,True)):
        for j,metrics in enumerate([['exclusion_q1','exclusion_q5'],['sorting'],['commute_q1','commute_q5']]):
            ax=axes[i,j]
            for k,m in enumerate(metrics):
                groups=[[r[m] for r in cell(core,d,c) if r[m] is not None] for c in CONDITIONS]
                means=np.array([st.mean(g) for g in groups]); x=np.arange(4)+(k-.5)*.16 if len(metrics)>1 else np.arange(4)
                ax.errorbar(x,means,yerr=[means-np.array([min(g) for g in groups]),np.array([max(g) for g in groups])-means],
                    fmt='o',capsize=5,color=['#2369b2','#c14e26'][k],label=m[-2:].upper() if m!='sorting' else 'Housed residents')
            ax.set_xticks(range(4),LABELS,rotation=15);ax.grid(axis='y',alpha=.2)
            ax.set_title(['Housing exclusion','Residential sorting · housed','Job access · housed'][j]); ax.legend(fontsize=10)
            ax.set_ylabel(['Unhoused share','Population-weighted Gini','Mean effective distance'][j])
            if j==0: ax.yaxis.set_major_formatter(PercentFormatter(1));ax.set_ylabel(f'Displacement {"on" if d else "off"}\nUnhoused share')
    for j in range(3):
        axes[0,j].set_ylim(0, max(.01, max(ax.dataLim.ymax for ax in axes[:,j])*1.08))
    fig.suptitle('Longer runs: 1,000-tick endpoints · five seeds per condition\n'
                 'Dots: means; whiskers: full seed range, not confidence intervals · 10×10 neighborhoods; 40 arrivals/tick\n'
                 'Zoning T=10 when enabled · Q1 lowest / Q5 highest baseline budgets · unmatched arrivals',fontsize=13)
    for ext in ('png','pdf','svg'): fig.savefig(OUT/f'long_run.{ext}',dpi=180)
    plt.close(fig)
    lines=['# Completed sweep analysis — October 23, 2026','',
        f'Presentation: 24/24 complete, three seeds per condition, 250 ticks. Broad: {len(broad)}/1800 complete, 1,000 ticks; {len(status["timed_out"])} timed out and {status["unstarted"]} unstarted. Partial runs are excluded. The central 10×10 / 40-arrivals design is complete: 40 cells × five seeds = 200 runs.', '',
        '## Main-slide endpoints', '',
        'Means [minimum, maximum] across seeds. Exclusion is percent; commute is effective distance in building-grid units; sorting is the population-weighted Gini of neighborhood mean budgets.', '',
        '| Ticks | Displacement | Condition | Q1 exclusion % | Q5 exclusion % | Sorting | Q1 commute | Q5 commute |',
        '|---|---|---|---|---|---|---|---|']
    for dataset in ['presentation_250','core_1000']:
        for d in (False,True):
            for label in LABELS:
                group=[r for r in tables if r['dataset']==dataset and r['displacement']==d and r['condition']==label]
                vals=[]
                for r in group:
                    scale=100 if r['metric'].startswith('exclusion') else 1
                    vals.append(f'{r["mean"]*scale:.3f} [{r["minimum"]*scale:.3f}, {r["maximum"]*scale:.3f}]')
                lines.append('| '+ ' | '.join([dataset.split('_')[-1], 'on' if d else 'off',label]+vals)+' |')
    lines += ['', '## Conditional contrasts', '',
        'Differences in means using common completed seed labels. These are descriptive simulation comparisons, not matched-arrival estimates. Exclusion differences are percentage points.', '',
        '| Ticks | Displacement | Contrast | Q1 exclusion pp | Q5 exclusion pp | Sorting | Q1 commute | Q5 commute |', '|---|---|---|---|---|---|---|---|']
    for dataset in ['presentation_250','core_1000']:
        for d in (False,True):
            for name in ['Zoning on minus off','H20 minus H5','Roads on minus off']:
                group=[r for r in contrasts if r['dataset']==dataset and r['displacement']==d and r['contrast']==name]
                lines.append('| '+' | '.join([dataset.split('_')[-1], 'on' if d else 'off',name]+[f'{r["difference_in_means"]*(100 if r["metric"].startswith("exclusion") else 1):+.3f}' for r in group])+' |')
    lines += ['', '## Broad sweep coverage', '', '| Neighborhood grid | Arrivals/tick | Complete / 200 | Replicates per cell (min–max) |', '|---|---|---|---|']
    for side in (6,10,14):
        for inflow in (20,40,80):
            group=[r for r in broad if r['n_neighborhoods_sqrt']==side and r['agents_inflow']==inflow]
            counts={}
            for r in group:
                key=tuple(r[k] for k in FACTORS);counts[key]=counts.get(key,0)+1
            lines.append(f'| {side}×{side} | {inflow} | {len(group)}/200 | {min(counts.values())}–{max(counts.values())} |')
    lines += ['', '## Patterns across the broader grid', '',
        'Counts below describe conditional mean differences, not independent significance tests or a pooled effect. Each contrast holds other factors fixed and uses common completed seeds (3–5). A zero is within 1e-12 of zero.', '',
        '| Comparison | Metric | Lower | Zero | Higher | Total |', '|---|---|---|---|---|---|']
    with (BROAD/'contrasts.csv').open() as f:
        broad_contrasts = list(csv.DictReader(f))
    for label in ['enable_roads on minus off', 'allow_displacement on minus off', 'zoning T=10 H=5 minus off', 'horizon 20 minus 5']:
        for metric in ['exclusion_q1', 'sorting', 'commute_q1']:
            values = [float(r['difference_in_means']) for r in broad_contrasts if r['contrast']==label and r['metric']==metric]
            lower = sum(v < -1e-12 for v in values); higher = sum(v > 1e-12 for v in values)
            lines.append(f'| {label} | {metric} | {lower} | {len(values)-lower-higher} | {higher} | {len(values)} |')
    lines += ['', 'Roads lower Q1 mean commute in 179/180 conditional comparisons; displacement increases sorting in 180/180. Exclusion effects vary in sign across settings. These counts overlap in their underlying runs and do not establish statistical significance.', '', '## Interpretation and limits', '',
        '- **Displacement greatly narrows across-seed exclusion variation in the central H=20 comparison.** At 1,000 ticks (10×10 neighborhoods, 40 arrivals/tick, zoning every 10 ticks, roads off; five seeds), Q1 exclusion without displacement averages 33.34%, spanning 0–84.11%; with displacement it averages 3.95%, spanning 3.77–4.14%. These are seed ranges, not confidence intervals. A possible mechanism is that outbidding incumbents provides an allocation route when construction is restricted, reducing dependence on the particular zoning trajectory while making exclusion more systematically budget-based. This mechanism remains a hypothesis; the result does not establish lower variance for every outcome or setting, and greater residential sorting accompanies it.',
        '- Transport reduces mean effective commute for Q1 and Q5 in both displacement regimes at 250 and 1,000 ticks in the central setting. This is access among housed residents, not a welfare measure.',
        '- Displacement produces a pronounced budget gradient in exclusion. Short-horizon zoning does not uniformly increase exclusion; its effect depends on the displacement regime and endpoint.',
        '- The long horizon produces a highly variable longer-run exclusion outcome without displacement. Show the individual seed range rather than describing the mean as universal.',
        '- Sorting is not geographic contiguity or total household wealth inequality. Low sorting or short commutes can coexist with exclusion because these metrics condition on being housed.',
        '- Q1–Q5 are fixed baseline log-normal budget groups, not re-ranked sample quintiles. Missing metrics stay missing. Bands and whiskers are seed ranges, not confidence intervals.',
        '- The broader sweep is incomplete by runtime, not a random sample of the design. Use conditional contrasts and visible replicate counts; do not pool its unbalanced cells into an overall treatment effect. Size and inflow jointly change development pressure.',
        '- The 250- and 1,000-tick sweeps are separate runs, with different seed counts. They are not treated as a single continuous trajectory.',
        '- Validation: every presentation tick is consecutive; all broad summaries match their raw final configuration and endpoint metrics, have a completion marker and tick 1,000, and pass population/housing denominator checks. Broad intermediate ticks were not reread for this endpoint audit.', '',
        '## Files and reproduction', '',
        '`python3 scripts/analyze_completed_sweeps.py` regenerates this analysis, three main-slide time-series charts, the long-run endpoint chart, CSV tables, and all broad-sweep heatmaps. Requires NumPy and Matplotlib; the verified interpreter on this machine is `/opt/anaconda3/bin/python3` (the default Homebrew Python lacks Matplotlib). Figures are exported as PNG, PDF, and SVG in `charts/`. Broad condition summaries, common-seed contrasts, and heatmaps remain in `sweep_results/broad_16core_2026-10-22/`.', '']
    (OUT.parent/'ANALYSIS.md').write_text('\n'.join(lines))
    print(f'Validated {len(presentation)} presentation runs and {len(broad)} broad endpoints; wrote slide analysis and plots.')


if __name__ == '__main__':
    main()
