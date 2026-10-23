"""Render completed, balanced comparisons; bands show seed ranges, not confidence intervals."""
import argparse
import json
import os
from pathlib import Path
os.environ.setdefault('MPLCONFIGDIR', '/tmp/urban-presentation-matplotlib')
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import numpy as np

PAIRS = {'zoning': ('no_zoning', 'zoning'), 'horizons': ('zoning', 'long'), 'transport': ('zoning', 'roads_on')}
LABELS = {'no_zoning': 'Zoning off', 'zoning': 'Zoning on, H=5, roads off', 'long': 'H=20', 'roads_on': 'Roads on'}

def sorting(row):
    pairs = sorted((v, w) for v, w in zip(row['nh_mean_budget'], row['nh_residents']) if v is not None and w > 0)
    total_w = sum(w for v, w in pairs)
    total_x = sum(v*w for v, w in pairs)
    if not total_w: return np.nan
    if not total_x: return 0.0
    cw = cx = numerator = 0.0
    for v,w in pairs:
        numerator += w*(v*cw-cx)
        cw += w; cx += w*v
    return numerator/(total_w*total_x)

def render(source, destination):
    source, destination = Path(source), Path(destination)
    destination.mkdir(parents=True, exist_ok=True)
    runs = {}
    for path in source.glob('*.jsonl'):
        records = [json.loads(line) for line in path.read_text().splitlines()]
        if records[-1].get('type') != 'complete': continue
        c = records[0]['config']
        rows = [r for r in records if r['type'] == 'step']
        if len(rows) != c['n_steps']: raise ValueError(f'Incomplete run: {path}')
        runs[c['condition'], c['displacement'], c['seed']] = (c, rows)
    for family, conditions in PAIRS.items():
        seeds = sorted(set.intersection(*(set(k[2] for k in runs if k[:2] == (c,d)) for c in conditions for d in (False,True))))
        if not seeds: continue
        example = runs[conditions[0],False,seeds[0]][0]
        n = example['n_steps']
        for c in conditions:
            for d in (False,True):
                for seed in seeds:
                    cfg = runs[c,d,seed][0]
                    for key in ('n_steps','agents_inflow','n_neighborhoods_sqrt','k','road_unit'):
                        if cfg[key] != example[key]: raise ValueError(f'Mixed settings: {key}')
        fig, axes = plt.subplots(2,3,figsize=(16,8),sharex=True, sharey="col", constrained_layout=True)
        for row,d in enumerate((False,True)):
            for ci,c in enumerate(conditions):
                color = ('#2369b2','#c14e26')[ci]
                series = [runs[c,d,seed][1] for seed in seeds]
                metrics = [(0,'budget_quintile_unhoused_share'),(2,'budget_quintile_mean_commute')]
                for col,key in metrics:
                    for q,style in ((0,'-'),(4,'--')):
                        values = np.array([[np.nan if r[key][q] is None else r[key][q] for r in rows] for rows in series])
                        draw(axes[row,col],values,color,style,f'{LABELS[c]} · Q{q+1}')
                values = np.array([[sorting(r) for r in rows] for rows in series])
                draw(axes[row,1],values,color,'-',LABELS[c])
            for col,title in enumerate(('Housing exclusion · Q1 & Q5','Residential sorting · housed','Job access · Q1 & Q5 housed')):
                ax=axes[row,col]; ax.set_title(title); ax.grid(alpha=.18)
                ax.set_xlabel('Simulation tick'); ax.legend(fontsize=7)
                if col < 2: ax.set_ylim(0,1)
            axes[row,0].set_ylabel(f'Displacement {"on" if d else "off"}\nUnhoused share')
            axes[row,1].set_ylabel('Population-weighted Gini')
            axes[row,2].set_ylabel('Mean effective distance')
        fig.suptitle(f'{family.title()} comparison · {len(seeds)} seeds · mean and min–max range\n'
                     f'{n} ticks; {example["agents_inflow"]} arrivals/tick; {example["n_neighborhoods_sqrt"]}×{example["n_neighborhoods_sqrt"]} neighborhoods, k=8; employer on; hop cost 1.01\n'
                     'Q1 lowest / Q5 highest baseline budgets · unmatched arrivals · shared baseline reused',fontsize=12)
        tmp=destination/f'{family}.tmp.png'
        fig.savefig(tmp,dpi=150); plt.close(fig)
        tmp.replace(destination/f'{family}.png')
        (destination/f'{family}.json').write_text(json.dumps({'source':str(source.resolve()),'seeds':seeds,'conditions':conditions,'config':example,'band':'min–max across seeds','matched_arrivals':False},indent=2))
        print(f'Updated {family}: {len(seeds)} balanced seeds',flush=True)

def draw(ax,values,color,style,label):
    # Preserve unavailable observations rather than substituting zeros.
    valid=np.any(np.isfinite(values),axis=0)
    mean=np.full(values.shape[1],np.nan); low=mean.copy(); high=mean.copy()
    if valid.any():
        mean[valid]=np.nanmean(values[:,valid],axis=0)
        low[valid]=np.nanmin(values[:,valid],axis=0); high[valid]=np.nanmax(values[:,valid],axis=0)
    x=np.arange(1,values.shape[1]+1)
    ax.plot(x,mean,color=color,linestyle=style,label=label,linewidth=1.6)
    if len(values)>1: ax.fill_between(x,low,high,color=color,alpha=.10)

if __name__ == '__main__':
    p=argparse.ArgumentParser(); p.add_argument('source'); p.add_argument('destination')
    args=p.parse_args(); render(args.source,args.destination)
