"""Time-bounded exploratory factorial sweep; never writes presentation charts."""
import argparse
from concurrent.futures import ThreadPoolExecutor, wait, FIRST_COMPLETED
import csv
from datetime import datetime, timedelta
import itertools
import json
import math
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
SEEDS = [42, 137, 999, 2026, 8675309]
FACTORS = ['n_neighborhoods_sqrt','agents_inflow','allow_displacement','enable_roads','land_use_eval_every','land_use_eval_horizon']

def atomic_json(path, data):
    tmp=path.with_suffix(path.suffix+'.tmp')
    tmp.write_text(json.dumps(data,indent=2,allow_nan=False)); tmp.replace(path)

def grid(steps=1000, smoke=False):
    # Horizon has no meaning with zoning off; don't duplicate that condition.
    laws=[(0,5)]+list(itertools.product([5,10,20],[5,10,20]))
    contexts=[(10,40)]+[(n,a) for n in (6,10,14) for a in (20,40,80) if (n,a)!=(10,40)]
    seeds=SEEDS
    if smoke: laws=[(0,5),(5,5)]; contexts=[(2,2)]; seeds=[42]
    jobs=[]
    # Complete five replicated core blocks first, then cover each wider context once
    # before adding more seeds. Four displacement/transport cells stay adjacent.
    blocks=[(contexts[0],s) for s in seeds]+[(context,s) for s in seeds for context in contexts[1:]]
    for (side,inflow),seed in blocks:
        for every,horizon in laws:
            for displacement,roads in itertools.product((False,True),repeat=2):
                name=f'n{side}_a{inflow}_T{every}_H{horizon}_d{int(displacement)}_r{int(roads)}_s{seed}'
                cfg=dict(condition=name,displacement=displacement,seed=seed,n_steps=steps,
                    n_neighborhoods_sqrt=side,k=8,agents_inflow=inflow,n_search=5,existing_move_share=0.1,
                    land_use_eval_every=every,land_use_eval_horizon=horizon,enable_roads=roads,
                    road_eval_every=20,road_unit=1.01,enable_employer=True,employer_eval_every=1,
                    employer_n_candidates=5,employer_horizon=3,allow_displacement=displacement,
                    law_allow_displacement=displacement,law_incumbent_mover_share=0.0,
                    law_incumbent_can_build=False,initial_agents=0,matched_arrivals=False)
                jobs.append(cfg)
    return jobs

def summary(path):
    cfg=last=None; ticks=0; complete=False
    with path.open() as stream:
        for line in stream:
            r=json.loads(line)
            if r['type']=='config': cfg=r['config']
            elif r['type']=='step': last=r; ticks+=1
            elif r['type']=='complete': complete=True
    if not complete or ticks != cfg['n_steps'] or last['step'] != cfg['n_steps']:
        raise ValueError(f'Incomplete data: {path}')
    from plot_presentation import sorting
    result={**cfg,'wall_seconds':last['wall_seconds'],'agents':last['agents'],
        'housed_share':last['housed']/last['agents'] if last['agents'] else None,
        'sorting':sorting(last),'pct_laws':last['pct_laws'],'n_roads':last['n_roads'],
        'dwellings':last['dwellings']}
    for q in range(5):
        for metric,field in [('exclusion','budget_quintile_unhoused_share'),('commute','budget_quintile_mean_commute'),('population','budget_quintile_population'),('housed','budget_quintile_housed')]:
            result[f'{metric}_q{q+1}']=last[field][q]
    return {k:None if isinstance(v,float) and not math.isfinite(v) else v for k,v in result.items()}

def write_csv(path,rows):
    if not rows: return
    tmp=path.with_suffix('.tmp')
    with tmp.open('w',newline='') as f:
        w=csv.DictWriter(f,fieldnames=list(rows[0]));w.writeheader();w.writerows(rows)
    tmp.replace(path)

def main():
    p=argparse.ArgumentParser()
    p.add_argument('--output',type=Path,required=True)
    p.add_argument('--hours',type=float,default=12)
    p.add_argument('--workers',type=int,default=4)
    p.add_argument('--steps',type=int,default=1000)
    p.add_argument('--smoke',action='store_true')
    args=p.parse_args()
    if args.hours<=0 or args.workers<1 or args.steps<1:p.error('hours, workers and steps must be positive')
    out=args.output.resolve();out.mkdir(parents=True,exist_ok=True)
    # Held until interpreter exit. Prevent two processes from sharing outputs.
    import fcntl
    lock=(out/'runner.lock').open('w')
    fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
    jobs=grid(args.steps,args.smoke)
    snapshot=out/'source';manifest_path=out/'manifest.json'
    if manifest_path.exists():
        manifest=json.loads(manifest_path.read_text())
        if manifest['jobs']!=jobs: raise ValueError('Resume grid differs; choose a new output directory')
    else:
        (snapshot/'scripts').mkdir(parents=True)
        for file in ROOT.glob('*.jl'):shutil.copy2(file,snapshot/file.name)
        for name in ('presentation_run.jl','broad_sweep.py','broad_report.py','plot_presentation.py'):
            shutil.copy2(ROOT/'scripts'/name,snapshot/'scripts'/name)
        manifest={'created':datetime.now().isoformat(),'jobs':jobs,'matched_arrivals':False,
            'priority':'Five seeds at n=10/inflow=40, then wider contexts by seed',
            'settings':'1000-tick endpoints; raw trajectories also available at 250/500 ticks'}
        atomic_json(manifest_path,manifest)
    configs=out/'configs'; configs.mkdir(exist_ok=True)
    for cfg in jobs:atomic_json(configs/(cfg['condition']+'.json'),cfg)
    start=time.monotonic(); deadline=start+args.hours*3600
    # Reserve up to 30 minutes for in-flight runs; all are killed at the hard deadline.
    launch_deadline=deadline-min(1800,args.hours*3600*.05)
    julia=shutil.which('julia')
    if not julia:raise RuntimeError('Julia not found')
    rows=[];results={};active={};pending=[];report_errors=[]
    for cfg in jobs:
        name=cfg['condition']; path=out/(name+'.jsonl')
        if path.exists():
            rows.append(summary(path));results[name]='complete'
        else:pending.append(cfg)
    def status(state='running'):
        atomic_json(out/'status.json',dict(state=state,updated=datetime.now().isoformat(),
            deadline=(datetime.now()+timedelta(seconds=max(0,deadline-time.monotonic()))).isoformat(),
            total=len(jobs),complete=sum(v=='complete' for v in results.values()),
            failed=[k for k,v in results.items() if v=='failed'],
            timed_out=[k for k,v in results.items() if v=='timed_out'],
            report_errors=report_errors,active=list(active.values()),unstarted=len(pending),elapsed_seconds=time.monotonic()-start))
    def run(cfg):
        name=cfg['condition']; target=out/(name+'.jsonl')
        print('START',name,flush=True)
        cmd=[julia,'--threads=1',str(snapshot/'scripts/presentation_run.jl'),'--config',str(configs/(name+'.json')),str(target)]
        try:
            with (out/(name+'.log')).open('w') as log:
                proc=subprocess.run(cmd,cwd=snapshot,stdout=log,stderr=subprocess.STDOUT,
                    timeout=max(.01,deadline-time.monotonic()),env={**os.environ,'OPENBLAS_NUM_THREADS':'1'})
            if proc.returncode:return name,'failed',None
            return name,'complete',summary(target)
        except subprocess.TimeoutExpired:return name,'timed_out',None
        except Exception as error:
            print('ERROR',name,str(error),flush=True);return name,'failed',None
    print(f'Queued {len(jobs)} runs; {args.workers} workers; budget {args.hours} hours',flush=True)
    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        while pending or active:
            while pending and len(active)<args.workers and time.monotonic()<launch_deadline:
                cfg=pending.pop(0);active[pool.submit(run,cfg)]=cfg['condition']
            status()
            if not active:break
            done,_=wait(active,timeout=15,return_when=FIRST_COMPLETED)
            for f in done:
                active.pop(f); name,state,row=f.result(); results[name]=state
                print(state.upper(),name,flush=True)
                if row is not None:
                    rows.append(row);atomic_json(out/(name+'.summary.json'),row)
                    write_csv(out/'endpoints.csv',rows)
            if done:
                # Reports only touch completed runs; a report error must not cancel simulations.
                try:
                    from broad_report import report
                    report(out,rows,plots=len(rows)%40==0)
                except Exception as error:
                    report_errors.append(str(error));print('REPORT ERROR',str(error),flush=True)
    write_csv(out/'endpoints.csv',rows)
    try:
        from broad_report import report
        report(out,rows,plots=True)
    except Exception as error:
        report_errors.append(str(error));print('REPORT ERROR',str(error),flush=True)
    status('complete' if not pending and all(v=='complete' for v in results.values()) else 'stopped')
    print(f'FINISHED: {len(rows)}/{len(jobs)} complete',flush=True)
    return 1 if any(v=='failed' for v in results.values()) else 0

if __name__=='__main__':sys.exit(main())
