"""Run the 24 presentation experiments with durable per-run output and source provenance."""
import argparse
import concurrent.futures
import datetime
import json
import shutil
import subprocess
import sys
from pathlib import Path
from plot_presentation import render

ROOT=Path(__file__).resolve().parents[1]

def main():
    p=argparse.ArgumentParser()
    p.add_argument('--output',type=Path,required=True)
    p.add_argument('--workers',type=int,default=4)
    p.add_argument('--steps',type=int,default=250)
    p.add_argument('--side',type=int,default=10)
    p.add_argument('--inflow',type=int,default=40)
    p.add_argument('--seeds',type=int,nargs='+',default=[42,137,999])
    p.add_argument('--charts',type=Path,default=ROOT/'slides/MarketsAndSociety2026/charts')
    args=p.parse_args()
    if args.workers < 1 or args.steps < 1: p.error('workers and steps must be positive')
    out=args.output.resolve(); out.mkdir(parents=True,exist_ok=True)
    snapshot=out/'source'
    manifest={'created':datetime.datetime.now().isoformat(),'steps':args.steps,'side':args.side,'inflow':args.inflow,'seeds':args.seeds,'matched_arrivals':False,'workers':args.workers}
    if (out/'manifest.json').exists():
        old=json.loads((out/'manifest.json').read_text())
        for key in ('steps','side','inflow','seeds'):
            if old[key]!=manifest[key]: raise ValueError(f'Resume settings differ: {key}')
    else:
        (snapshot/'scripts').mkdir(parents=True)
        for path in ROOT.glob('*.jl'): shutil.copy2(path,snapshot/path.name)
        for name in ('presentation_run.jl','presentation_sweep.py','plot_presentation.py'):
            shutil.copy2(ROOT/'scripts'/name,snapshot/'scripts'/name)
        shutil.copy2(ROOT/'slides/MarketsAndSociety2026/app.js',snapshot/'live_presets.js')
        (out/'manifest.json').write_text(json.dumps(manifest,indent=2))
    jobs=[(c,d,s) for s in args.seeds for d in (False,True) for c in ('no_zoning','zoning','long','roads_on')]
    julia=shutil.which('julia')
    if not julia: raise RuntimeError('Julia not found')
    def run(job):
        c,d,s=job; name=f'{c}_displacement_{str(d).lower()}_seed{s}'
        target=out/f'{name}.jsonl'
        if target.exists(): return name,0
        print(f'START {name}',flush=True)
        with (out/f'{name}.log').open('w') as log:
            cmd=[julia,'--threads=1',str(snapshot/'scripts/presentation_run.jl'),c,str(d).lower(),str(s),str(target),str(args.steps),str(args.side),str(args.inflow)]
            result=subprocess.run(cmd,cwd=snapshot,stdout=log,stderr=subprocess.STDOUT)
        print(f'{"DONE" if result.returncode == 0 else "FAILED"} {name}',flush=True)
        return name,result.returncode
    failures=[]
    chart_errors=[]
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.workers) as pool:
        for future in concurrent.futures.as_completed([pool.submit(run,j) for j in jobs]):
            name,code=future.result()
            if code: failures.append(name)
            try:
                render(out,args.charts)
            except Exception as error:
                chart_errors.append(str(error))
                print(f'CHART ERROR (runs continue): {error}',flush=True)
    (out/'status.json').write_text(json.dumps({'finished':datetime.datetime.now().isoformat(),'failures':failures,'chart_errors':chart_errors,'runs':len(jobs)},indent=2))
    print(f'Finished {len(jobs)} runs; failures: {failures}',flush=True)
    return bool(failures or chart_errors)

if __name__=='__main__': sys.exit(main())
