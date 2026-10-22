'use strict';
// All figures use actual backend statistics; no synthetic fallback data.
// Population-weighted Gini: sum_{i<j} w_i w_j |x_i-x_j| / (sum(w) sum(w*x)).
// Sorting and cumulative sums avoid quadratic work or expanding populations.
window.gini = function(values, weights=values.map(()=>1)) {
  if(values.length!==weights.length)return null;
  const pairs=[];
  for(let i=0;i<values.length;i++){
    const w=weights[i],x=values[i];
    if(!Number.isFinite(w)||w<0)return null;
    if(w===0)continue;
    if(!Number.isFinite(x)||x<0)return null;
    pairs.push({x,w});
  }
  if(!pairs.length)return null;
  pairs.sort((a,b)=>a.x-b.x);
  let population=0,weightedWealth=0,difference=0;
  for(const {x,w} of pairs){
    difference+=w*(x*population-weightedWealth);
    population+=w;weightedWealth+=w*x;
  }
  if(weightedWealth===0)return 0;
  return Math.max(0,Math.min(1,difference/(population*weightedWealth)));
};
window.wealthGinis = function(stats) {
  const means=stats.nh_mean_budget,counts=stats.nh_residents;
  if(!Array.isArray(means)||!Array.isArray(counts)||means.length!==counts.length)return null;
  const totals=[],populated=[],weights=[];
  for(let i=0;i<means.length;i++){
    if(!Number.isFinite(counts[i])||counts[i]<0)return null;
    if(counts[i]===0)continue;
    if(!Number.isFinite(means[i])||means[i]<0)return null;
    totals.push(means[i]*counts[i]);populated.push(means[i]);weights.push(counts[i]);
  }
  return {total:window.gini(totals,weights),average:window.gini(populated,weights)};
};
window.recordWealthPoint = function(history,stats,tick) {
  const values=window.wealthGinis(stats);if(!values)return history;
  // A tick reversal from another controller starts a new observed trajectory.
  const next=history.length&&tick<history.at(-1).tick?[]:[...history];
  const point={tick,...values,exclusion:stats.budget_quintile_unhoused_share?.slice(),commute:stats.budget_quintile_mean_commute?.slice()};if(next.at(-1)?.tick===tick)next[next.length-1]=point;else next.push(point);
  return next;
};
window.drawTelemetry = function(container, stats, connected, history=[]) {
  if(!container)return;
  container.replaceChildren();
  const make=(tag,text,cls)=>{const n=document.createElement(tag);if(text!==undefined)n.textContent=text;if(cls)n.className=cls;return n;};
  const number=v=>Number.isFinite(v)?v.toLocaleString(undefined,{maximumFractionDigits:2}):'—';
  const note=make('div',!stats?'Waiting for model statistics.':!connected?'Disconnected · last received snapshot':`Live model snapshot · batch step ${stats.step}`,'telemetry-status');container.append(note);
  if(!stats?.height_histogram){container.append(make('div',stats?'New diagnostics require the updated Julia backend.':'Start or continue a model run to populate the charts.','telemetry-empty'));return;}
  const primaryPanels=make('div',undefined,'telemetry-panels inequality-primary');container.append(primaryPanels);
  const secondary=make('details',undefined,'secondary-diagnostics');secondary.append(make('summary','City Structure and Secondary Measures'));
  let panels=make('div',undefined,'telemetry-panels inequality-secondary');const secondaryPanels=panels;secondary.append(panels);container.append(secondary);
  function card(title,caption){const c=make('section',undefined,'telemetry-card');c.append(make('h3',title),make('div',caption,'telemetry-caption'));panels.append(c);return c;}
  function svgNode(tag,attrs={}){const n=document.createElementNS('http://www.w3.org/2000/svg',tag);for(const [k,v] of Object.entries(attrs))n.setAttribute(k,String(v));return n;}
  const hist=card('Building Heights','All building sites, including height zero');
  const svg=svgNode('svg',{viewBox:'0 0 320 215',role:'img','aria-label':'Building height histogram: number of sites in each height category'});
  const counts=stats.height_histogram.counts,labels=stats.height_histogram.labels,max=Math.max(1,...counts);
  for(let i=0;i<counts.length;i++){
    const h=145*counts[i]/max,x=8+i*39;
    const bar=svgNode('rect',{x,y:168-h,width:30,height:h,fill:'#82ccbd'});
    const title=svgNode('title');title.textContent=`Height ${labels[i]}: ${counts[i]} sites`;bar.append(title);svg.append(bar);
    for(const [text,y,color] of [[String(counts[i]),Math.max(13,160-h),'#dce6e8'],[labels[i],190,'#b9c8d0']]){const t=svgNode('text',{x:x+15,y,'text-anchor':'middle',fill:color,'font-size':11});t.textContent=text;svg.append(t);}
  }
  const axis=svgNode('text',{x:160,y:211,'text-anchor':'middle',fill:'#b9c8d0','font-size':12});axis.textContent='Height (dwellings / building)';svg.append(axis);hist.append(svg);
  function grid(title,caption,values,kind,maxFixed){
    const c=card(title,caption),width=stats.nh_grid_width,height=stats.nh_grid_height;
    if(!Array.isArray(values)||values.length!==width*height){c.append(make('div','No neighborhood data'));return;}
    const max=maxFixed??Math.max(0,...values.filter(Number.isFinite));
    const g=make('div',undefined,'neighborhood-grid');g.style.gridTemplateColumns=`repeat(${width},1fr)`;g.style.aspectRatio=`${width} / ${height}`;g.setAttribute('role','img');g.setAttribute('aria-label',title+'; neighborhood x increases right, y increases upward');
    // IDs are x-fastest; reverse the rows so positive y points upward.
    for(let y=height-1;y>=0;y--)for(let x=0;x<width;x++){
      const i=y*width+x,v=values[i],cell=make('div',undefined,'neighborhood-cell');
      if(Number.isFinite(v)){
        const t=max>0?Math.min(1,v/max):0;
        const low=[27,49,63],high=kind==='wealth'?[235,189,115]:kind==='gini'?[211,155,222]:[130,204,189];
        cell.style.background=`rgb(${low.map((l,j)=>Math.round(l+(high[j]-l)*t)).join(',')})`;
      }else cell.className+=' missing';
      cell.title=`Neighborhood ${i+1} · (${x}, ${y}) · ${Number.isFinite(v)?number(v):'no residents'} · ${stats.nh_residents?.[i]??'—'} residents`;
      g.append(cell);
    }
    c.append(g,make('div',`0 → ${number(max)}${maxFixed?' · fixed scale':' · scale per snapshot'} · y ↑, x →`,'telemetry-legend'));
    if(kind!=='density')c.append(make('div','Hatched = no residents; hover for values','telemetry-legend'));
  }
  function series(title,key,caption,color){
    const c=card(title,caption),plot=svgNode('svg',{viewBox:'0 0 320 215',role:'img','aria-label':title+' over simulation ticks, Gini axis from zero to one'});
    const xmax=Math.max(250,...history.map(p=>p.tick)),xmin=0;
    const X=t=>34+270*(t-xmin)/(xmax-xmin),Y=v=>175-150*v;
    for(const v of [0,0.5,1]){plot.append(svgNode('line',{x1:34,x2:304,y1:Y(v),y2:Y(v),stroke:'#506472','stroke-width':0.6}));const label=svgNode('text',{x:28,y:Y(v)+4,'text-anchor':'end',fill:'#b9c8d0','font-size':12});label.textContent=String(v);plot.append(label);}
    for(const t of [0,Math.round(xmax/2),xmax]){const label=svgNode('text',{x:X(t),y:194,'text-anchor':'middle',fill:'#b9c8d0','font-size':12});label.textContent=String(t);plot.append(label);}
    let segment=[];
    const flush=()=>{if(segment.length){plot.append(svgNode('polyline',{points:segment.join(' '),fill:'none',stroke:color,'stroke-width':2.5}));segment=[];}};
    for(const p of history){if(Number.isFinite(p[key]))segment.push(`${X(p.tick)},${Y(p[key])}`);else flush();}flush();
    const last=history.at(-1);
    if(last&&Number.isFinite(last[key]))plot.append(svgNode('circle',{cx:X(last.tick),cy:Y(last[key]),r:3,fill:color}));
    const axis=svgNode('text',{x:165,y:211,'text-anchor':'middle',fill:'#b9c8d0','font-size':12});axis.textContent='Simulation Tick';plot.append(axis);c.append(plot);
    c.append(make('div',`Current Gini: ${number(last?.[key])}`,'telemetry-legend'));
  }
  function quintileSeries(title,key,caption,percent){
    const c=card(title,caption);
    if(!Array.isArray(stats.budget_quintile_population)){
      c.append(make('div','Requires the updated Julia diagnostics.','telemetry-empty'));return;
    }
    const colors=['#f08a81','#ebbd73','#e6e3c8','#82ccbd','#b4a3f0'];
    const xmax=Math.max(250,...history.map(p=>p.tick));
    const observed=history.flatMap(p=>(p[key]||[]).filter(Number.isFinite));
    const ymax=percent?1:Math.max(1,Math.ceil(Math.max(0,...observed)));
    const plot=svgNode('svg',{viewBox:'0 0 320 215',role:'img','aria-label':title+' over ticks by baseline budget quintile'});
    const X=t=>38+265*t/xmax,Y=v=>175-150*v/ymax;
    for(const v of [0,ymax/2,ymax]){
      plot.append(svgNode('line',{x1:38,x2:303,y1:Y(v),y2:Y(v),stroke:'#506472','stroke-width':0.6}));
      const label=svgNode('text',{x:33,y:Y(v)+4,'text-anchor':'end',fill:'#b9c8d0','font-size':11});label.textContent=percent?Math.round(v*100)+'%':number(v);plot.append(label);
    }
    for(const t of [0,Math.round(xmax/2),xmax]){const label=svgNode('text',{x:X(t),y:194,'text-anchor':'middle',fill:'#b9c8d0','font-size':11});label.textContent=t;plot.append(label);}
    for(let q=0;q<5;q++){
      let segment=[];const flush=()=>{if(segment.length)plot.append(svgNode('polyline',{points:segment.join(' '),fill:'none',stroke:colors[q],'stroke-width':2}));segment=[];};
      for(const p of history){const v=p[key]?.[q];if(Number.isFinite(v))segment.push(`${X(p.tick)},${Y(v)}`);else flush();}flush();
      const last=history.at(-1)?.[key]?.[q];if(Number.isFinite(last))plot.append(svgNode('circle',{cx:X(history.at(-1).tick),cy:Y(last),r:2.5,fill:colors[q]}));
    }
    const axis=svgNode('text',{x:165,y:211,'text-anchor':'middle',fill:'#b9c8d0','font-size':12});axis.textContent='Simulation Tick';plot.append(axis);c.append(plot);
    const legend=make('div',undefined,'quintile-legend');
    for(let q=0;q<5;q++){
      const v=history.at(-1)?.[key]?.[q],n=stats.budget_quintile_population[q],h=stats.budget_quintile_housed[q];
      const item=make('div',`Q${q+1}: ${Number.isFinite(v)?(percent?number(v*100)+'%':number(v)):'—'} · ${percent?n+' agents':h+' housed'}`);item.style.color=colors[q];legend.append(item);
    }c.append(legend);
  }
  panels=primaryPanels;
  quintileSeries('Housing Exclusion','exclusion','Unhoused share by baseline budget quintile · all agents',true);
  series('Residential Sorting','average','Population-weighted Gini of neighborhood mean budgets · housed agents','#ebbd73');
  quintileSeries('Access to Jobs','commute','Mean effective commute by baseline budget quintile · housed agents only',false);
  panels=secondaryPanels;
  series('Total Wealth Inequality','total','Secondary: population-weighted Gini of neighborhood total budgets','#d39bde');
  grid('Neighborhood Density','Dwellings per building site (including vacant stock)',stats.nh_mean_density,'density');
  grid('Neighborhood Wealth','Mean budget of housed residents · model units',stats.nh_mean_budget,'wealth');
  const definitions=make('details',undefined,'diagnostic-definitions');definitions.append(make('summary','Definitions and Budget Group Boundaries'));container.append(definitions);
  definitions.append(make('div','Q1 = lowest budgets; Q5 = highest. Groups use fixed quintile thresholds of the baseline budget distribution, so changing arrival budgets can change group sizes. Commutes use actual network distance and hop cost; unhoused agents have no commute observation. Read sorting together with exclusion. Ginis weight neighborhoods by population and exclude empty neighborhoods.','telemetry-definition'));
  if(stats.budget_quintile_cutoffs)definitions.append(make('div',`Budget group boundaries: ${stats.budget_quintile_cutoffs.map(number).join(' · ')}. Commute units: building-distance units; hop cost ${number(stats.diagnostic_road_unit)}. Lines contain only observations received since connection/reset.`,'telemetry-definition'));
};
