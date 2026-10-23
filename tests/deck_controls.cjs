const fs=require('fs'),vm=require('vm'),assert=require('assert');
const nodes={};
class Element{constructor(tag){this.tagName=tag.toUpperCase();this.children=[];this.style={};this.hidden=true;}set id(x){this._id=x;nodes[x]=this;}get id(){return this._id;}append(...x){this.children.push(...x);}replaceChildren(){for(const c of this.children)this.remove(c);this.children=[];}remove(c){if(c.id)delete nodes[c.id];for(const n of c.children||[])this.remove(n);}setAttribute(){}checkValidity(){return this.type!=="number"||(this.value!==""&&Number.isFinite(Number(this.value))&&Number(this.value)>=this.min&&Number(this.value)<=this.max);}reportValidity(){}replaceWith(){}click(){this.onclick();}}
for(const id of ['slide','notes','counter','prev','next','progress','connection','connect','notes-toggle','fullscreen','experiment-panel','experiments-toggle','charts-overlay','charts-toggle','charts-close','telemetry-overlay-content','parameters-toggle']){let n=new Element('div');n.id=id;}
class WS{static OPEN=1;constructor(url){this.url=url;this.readyState=1;this.sent=[];WS.last=this;}send(x){this.sent.push(JSON.parse(x));}}
const ctx={window:{addEventListener(){}},document:{getElementById:id=>nodes[id],createElementNS:(_,t)=>new Element(t),createElement:t=>new Element(t),addEventListener(){}},location:{hash:''},WebSocket:WS,setTimeout:()=>1,clearTimeout(){},console};vm.createContext(ctx);
for(const file of ['slides.js','telemetry.js','app.js'])vm.runInContext(fs.readFileSync('slides/MarketsAndSociety2026/'+file,'utf8'),ctx);
assert.equal(ctx.window.SLIDES.length,36);assert.equal(ctx.window.SLIDES.reduce((a,s)=>a+s.seconds,0),1500);
vm.runInContext("navigate(window.SLIDES.findIndex(s=>s.demo==='no_zoning'))",ctx);assert(nodes.start.disabled);nodes.connect.onclick();const socket=WS.last;socket.onopen();const receive=m=>socket.onmessage({data:JSON.stringify(m)});
receive({type:'running',value:false});assert(nodes.start.disabled);nodes.reset.onclick();assert.equal(socket.sent.at(-1).type,'reset');assert(nodes.start.disabled);
receive({type:'reset_state'});receive({type:'running',value:false});assert(!nodes.start.disabled);nodes.start.onclick();assert.equal(socket.sent.at(-1).type,'start');assert.equal(socket.sent.at(-1).land_use_eval_every,0);assert(nodes.start.disabled);
receive({type:'running',value:true});assert(nodes.reset.disabled);const count=socket.sent.length;vm.runInContext('navigate(1)',ctx);assert.equal(socket.sent.length,count);nodes.stop.onclick();assert.equal(socket.sent.at(-1).type,'stop');assert(nodes.reset.disabled);
receive({type:'running',value:false});nodes.reset.onclick();receive({type:'reset_state'});nodes.start.onclick();assert.equal(socket.sent.at(-1).n_steps,250);
receive({type:'stats',step:500,housed:50,agents:60});receive({type:'running',value:false});assert(!nodes.continue.disabled);
nodes['param-n_steps'].value='1200';nodes['param-n_steps'].valueAsNumber=1200;nodes['param-n_steps'].oninput();nodes.continue.onclick();assert.equal(socket.sent.at(-1).n_steps,1200);assert.equal(socket.sent.at(-1).type,'start');
receive({type:'stats',step:10,housed:55,agents:70});assert.equal(nodes['metric-step'].textContent,510);receive({type:'running',value:false});
nodes['param-n_steps'].value='';nodes['param-n_steps'].valueAsNumber=NaN;nodes['param-n_steps'].oninput();const beforeInvalid=socket.sent.length;nodes.continue.onclick();assert.equal(socket.sent.length,beforeInvalid);
nodes['panel-preset'].value='long';nodes['panel-preset'].onchange();nodes.continue.onclick();assert.equal(socket.sent.at(-1).land_use_eval_horizon,20);

socket.onclose();assert(nodes.start.disabled);assert(nodes.reset.disabled);
for(let i=0;i<36;i++)vm.runInContext(`position=${i};render()`,ctx);
console.log('PASS: custom length, continuation, input validation and horizon preset;  31 main + 5 reference slides; 25-minute budget; offline gating, reset acknowledgement, scenario payloads, navigation isolation, stop/idle and disconnect behavior.');

assert(vm.runInContext("Object.keys(presets).every(key=>{loadPreset(key);return parameters.n_steps===250;})",ctx));
console.log("PASS: every demo preset sends 250 ticks.");
const keys=vm.runInContext('Object.keys(presets)',ctx);
assert.equal(keys.length,12);
for(const key of keys){
  const p=vm.runInContext(`loadPreset(${JSON.stringify(key)});parameters`,ctx);
  assert.equal(p.blender_update_every,10);assert.equal(p.road_unit,1.01);assert.equal(p.n_steps,250);
  assert.equal(p.allow_displacement,key.endsWith('_displacement'));
  assert.equal(p.law_allow_displacement,p.allow_displacement);
}
// Verify the real send path, not just preset metadata.
nodes.connect.onclick();const updatedSocket=WS.last;updatedSocket.onopen();
const receiveUpdated=m=>updatedSocket.onmessage({data:JSON.stringify(m)});
receiveUpdated({type:'running',value:false});
vm.runInContext("loadPreset('roads_on_displacement')",ctx);
nodes['panel-reset'].onclick();receiveUpdated({type:'reset_state'});receiveUpdated({type:'running',value:false});nodes['panel-start'].onclick();
const payload=updatedSocket.sent.at(-1);
assert.equal(payload.type,'start');assert.equal(payload.road_unit,1.01);assert.equal(payload.blender_update_every,10);
assert.equal(payload.enable_roads,true);assert.equal(payload.allow_displacement,true);assert.equal(payload.law_allow_displacement,true);
console.log('PASS: 12 displacement variants and outgoing update/hop/displacement settings.');
