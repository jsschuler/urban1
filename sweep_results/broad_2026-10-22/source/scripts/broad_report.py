"""Endpoint tables and exploratory heatmaps; unequal replicate counts remain visible."""
import csv
import json
import math
import os
from pathlib import Path
import statistics

FACTORS=['n_neighborhoods_sqrt','agents_inflow','allow_displacement','enable_roads','land_use_eval_every','land_use_eval_horizon']
METRICS=['housed_share','sorting','pct_laws','n_roads','dwellings']+[f'{m}_q{q}' for m in ('exclusion','commute') for q in range(1,6)]

def report(out,rows,plots=False):
    out=Path(out);groups={}
    for row in rows:groups.setdefault(tuple(row[k] for k in FACTORS),[]).append(row)
    aggregate=[]
    for key,group in sorted(groups.items()):
        row=dict(zip(FACTORS,key));row['replicates']=len(group);row['seeds']=' '.join(str(r['seed']) for r in group)
        for m in METRICS:
            values=[r[m] for r in group if r[m] is not None and math.isfinite(r[m])]
            row[m+'_n']=len(values)
            row[m+'_mean']=statistics.mean(values) if values else None
            row[m+'_sd']=statistics.stdev(values) if len(values)>1 else None
            row[m+'_min']=min(values) if values else None
            row[m+'_max']=max(values) if values else None
        aggregate.append(row)
    if not aggregate:return
    tmp=out/'condition_summary.tmp'
    with tmp.open('w',newline='') as f:
        w=csv.DictWriter(f,fieldnames=list(aggregate[0]));w.writeheader();w.writerows(aggregate)
    tmp.replace(out/'condition_summary.csv')
    # Conditional contrasts compare only cells sharing exactly the same completed seed set.
    # This does not imply matched household arrivals or paired treatment effects.
    contrasts=[]
    pairs=[]
    for key,group in groups.items():
        for factor in ('allow_displacement','enable_roads'):
            index=FACTORS.index(factor)
            if not key[index]:
                other=list(key);other[index]=True
                pairs.append((key,tuple(other),factor+' on minus off'))
        # Keep displacement, roads, size and inflow fixed for zoning contrasts.
        if key[4]==0:
            for every in (5,10,20):
                for horizon in (5,10,20):
                    other=(*key[:4],every,horizon)
                    pairs.append((key,other,f'zoning T={every} H={horizon} minus off'))
        if key[4]>0 and key[5]==5:
            for horizon in (10,20):
                pairs.append((key,(*key[:5],horizon),f'horizon {horizon} minus 5'))
    for key,other,label in pairs:
        if other not in groups:continue
        group=groups[key]
        common={r['seed'] for r in group} & {r['seed'] for r in groups[other]}
        for metric in METRICS:
            # Both sides must have this metric for the same seed subset.
            valid=common & {r['seed'] for r in group if r[metric] is not None} & {r['seed'] for r in groups[other] if r[metric] is not None}
            a=[r[metric] for r in group if r['seed'] in valid]
            b=[r[metric] for r in groups[other] if r['seed'] in valid]
            if not a:continue
            contrasts.append({**dict(zip(FACTORS,key)),'contrast':label,'metric':metric,
                'common_seeds':' '.join(map(str,sorted(valid))),'baseline_n':len(a),'comparison_n':len(b),
                'difference_in_means':statistics.mean(b)-statistics.mean(a)})
    if contrasts:
        tmp=out/'contrasts.tmp'
        with tmp.open('w',newline='') as f:
            w=csv.DictWriter(f,fieldnames=list(contrasts[0]));w.writeheader();w.writerows(contrasts)
        tmp.replace(out/'contrasts.csv')
    if not plots:return
    os.environ.setdefault('MPLCONFIGDIR','/tmp/urban-presentation-matplotlib')
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
    import numpy as np
    charts=out/'charts';charts.mkdir(exist_ok=True)
    law_levels=[(0,5)]+[(t,h) for t in (5,10,20) for h in (5,10,20)]
    sides=sorted({r['n_neighborhoods_sqrt'] for r in rows});inflows=sorted({r['agents_inflow'] for r in rows})
    lookup={tuple(r[k] for k in FACTORS):r for r in aggregate}
    for metric in ('exclusion_q1','exclusion_q5','sorting','commute_q1','commute_q5'):
        fig,axes=plt.subplots(len(sides),len(inflows),figsize=(5*len(inflows),4.5*len(sides)),squeeze=False,constrained_layout=True)
        finite=[r[metric+'_mean'] for r in aggregate if r[metric+'_mean'] is not None]
        vmax=1 if metric.startswith('exclusion') or metric=='sorting' else max(finite or [1])
        for i,side in enumerate(sides):
            for j,inflow in enumerate(inflows):
                data=np.full((10,4),np.nan);counts=np.zeros((10,4),int)
                for y,(t,h) in enumerate(law_levels):
                    for x,(d,r) in enumerate(((False,False),(False,True),(True,False),(True,True))):
                        cell=lookup.get((side,inflow,d,r,t,h))
                        if cell and cell[metric+'_mean'] is not None:
                            data[y,x]=cell[metric+'_mean'];counts[y,x]=cell[metric+'_n']
                ax=axes[i,j];im=ax.imshow(np.ma.masked_invalid(data),vmin=0,vmax=vmax,aspect='auto',cmap='viridis')
                ax.set_title(f'{side}×{side} neighborhoods · {inflow} arrivals/tick')
                ax.set_xticks(range(4),['D− R−','D− R+','D+ R−','D+ R+'])
                ax.set_yticks(range(10),['Zoning off']+[f'T={t}, H={h}' for t,h in law_levels[1:]])
                for y,x in zip(*np.where(np.isfinite(data))):ax.text(x,y,f'{data[y,x]:.2f}\nn={counts[y,x]}',ha='center',va='center',fontsize=7,color='white' if data[y,x]<vmax*.5 else 'black')
        fig.colorbar(im,ax=axes.ravel().tolist(),shrink=.7)
        fig.suptitle(f'{metric} · {rows[0]["n_steps"]}-tick endpoints · means of completed runs\nD: displacement; R: roads; T: vote interval; H: forecast horizon. Blank: unavailable. Arrivals unmatched.',fontsize=12)
        tmp=charts/(metric+'.tmp.png');fig.savefig(tmp,dpi=140);plt.close(fig);tmp.replace(charts/(metric+'.png'))

if __name__=='__main__':
    import sys
    out=Path(sys.argv[1]);rows=[json.loads(p.read_text()) for p in out.glob('*.summary.json')];report(out,rows,plots=True)
