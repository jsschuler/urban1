const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');
class Node {
  constructor(tag){this.tag=tag;this.children=[];this.style={};this.attrs={};}
  append(...nodes){this.children.push(...nodes);}
  replaceChildren(){this.children=[];}
  setAttribute(k,v){this.attrs[k]=v;}
}
const context={window:{},document:{createElement:t=>new Node(t),createElementNS:(_,t)=>new Node(t)}};
vm.createContext(context);
vm.runInContext(fs.readFileSync('slides/MarketsAndSociety2026/telemetry.js','utf8'),context);
const root=new Node('div');
const render=(stats,connected=true)=>context.window.drawTelemetry(root,stats,connected,stats?context.window.recordWealthPoint([],stats,stats.step):[]);
const all=n=>[n,...n.children.flatMap(all)];
render(null);assert.match(root.children[0].textContent,/Waiting/);
render({step:1});assert.match(root.children[1].textContent,/updated Julia/);
const stats={step:7,height_histogram:{labels:['0','1–2'],counts:[2,2]},nh_grid_width:2,nh_grid_height:2,
 nh_mean_density:[0,1,2,3],nh_mean_budget:[null,2,3,4],nh_budget_gini:[null,0,.25,.5],nh_residents:[0,1,2,3],between_neighborhood_gini:.1};
render(stats);
assert.equal(all(root).filter(n=>n.tag==='rect').length,2);
const grids=all(root).filter(n=>n.className==='neighborhood-grid');assert.equal(grids.length,2);
assert.match(grids[0].children[0].title,/Neighborhood 3/); // y increases upward.
assert.match(grids[1].children[2].className,/missing/);
assert.doesNotMatch(grids[1].children[3].className,/missing/); // Genuine zero Gini is populated.
assert.equal(grids[1].children.length,4);
render(stats,false);assert.match(root.children[0].textContent,/last received snapshot/);
render(null);assert.equal(all(root).filter(n=>n.className==='neighborhood-grid').length,0);
console.log('PASS: chart rendering, grid orientation, empty/zero distinction, old-backend messaging, reset clearing, stale snapshot labeling.');

const approx=(actual,expected)=>assert(Math.abs(actual-expected)<1e-12);
const values=context.window.wealthGinis(stats);approx(values.total,37/150);approx(values.average,7/60);
assert.equal(context.window.wealthGinis({nh_mean_budget:[null,null],nh_residents:[0,0]}).total,null);
assert.equal(context.window.wealthGinis({nh_mean_budget:[null,null],nh_residents:[0,0]}).average,null);
let history=context.window.recordWealthPoint([],stats,7);
history=context.window.recordWealthPoint(history,stats,8);assert.equal(history.length,2);
history=context.window.recordWealthPoint(history,stats,8);assert.equal(history.length,2);
history=context.window.recordWealthPoint(history,stats,1);assert.equal(history.length,1);
assert.equal(history[0].tick,1);
console.log('PASS: total versus mean neighborhood wealth, empty neighborhoods, duplicate ticks and new trajectories.');

// Independent population-expansion oracle for the weighted statistic.
function expandedGini(values,weights){
  const x=values.flatMap((value,i)=>Array(weights[i]).fill(value));
  if(!x.length)return null;
  const sum=x.reduce((a,b)=>a+b,0);if(sum===0)return 0;
  return x.reduce((a,v)=>a+x.reduce((b,u)=>b+Math.abs(v-u),0),0)/(2*x.length*sum);
}
for(const [x,w] of [[[2,6,12],[1,2,3]],[[2,3,4],[1,2,3]],[[0,0],[2,5]],[[7],[20]],[[1,9,3],[2,2,2]]]){
  approx(context.window.gini(x,w),expandedGini(x,w));
}
const withoutEmpty=context.window.wealthGinis({nh_mean_budget:[2,3,4],nh_residents:[1,2,3]});
approx(withoutEmpty.total,values.total);approx(withoutEmpty.average,values.average);
approx(context.window.gini([2,3,4],[10,20,30]),values.average);
assert.equal(context.window.gini([null,3],[0,5]),0);
assert.equal(context.window.gini([1,2],[1,-1]),null);
assert.equal(context.window.wealthGinis({nh_mean_budget:[0,0],nh_residents:[2,3]}).total,0);
assert.equal(context.window.wealthGinis({nh_mean_budget:[0,0],nh_residents:[2,3]}).average,0);
console.log('PASS: population weighting matches pairwise expansion; empty neighborhoods excluded; weight-scale invariance and zero-wealth edge cases.');

const access={...stats,budget_quintile_population:[2,1,0,1,1],budget_quintile_housed:[1,1,0,0,1],budget_quintile_unhoused_share:[.5,0,null,1,0],budget_quintile_mean_commute:[1,2,null,null,3],budget_quintile_cutoffs:[1.7,2.4,3.1,4.1],diagnostic_road_unit:.5};
const accessHistory=context.window.recordWealthPoint([],access,1);
assert.equal(accessHistory[0].exclusion[0],.5);
assert.equal(accessHistory[0].commute[3],null);
access.budget_quintile_mean_commute[0]=99;assert.equal(accessHistory[0].commute[0],1);
context.window.drawTelemetry(root,access,true,accessHistory);
assert(all(root).some(n=>n.textContent==='Housing Exclusion'));
assert(all(root).some(n=>n.textContent==='Access to Jobs'));
assert(all(root).some(n=>n.textContent==='Residential Sorting'));
assert.equal(all(root).filter(n=>n.className==='quintile-legend').length,2);
assert(all(root).some(n=>n.textContent==='Q4: — · 0 housed'));
assert(all(root).some(n=>n.tag==='details'));
console.log('PASS: quintile histories, missing commute observations, three primary panels and secondary diagnostics.');
