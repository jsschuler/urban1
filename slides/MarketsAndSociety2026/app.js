'use strict';
const presets = {
  no_zoning: {label:'Zoning disabled',land_use_eval_every:0,land_use_eval_horizon:5,enable_roads:false},
  zoning: {label:'Zoning enabled · H = 5',land_use_eval_every:10,land_use_eval_horizon:5,enable_roads:false},
  short: {label:'Short horizon · H = 5',land_use_eval_every:10,land_use_eval_horizon:5,enable_roads:false},
  long: {label:'Long horizon · H = 20',land_use_eval_every:10,land_use_eval_horizon:20,enable_roads:false},
  roads_off: {label:'Transport disabled',land_use_eval_every:10,land_use_eval_horizon:5,enable_roads:false},
  roads_on: {label:'Transport enabled',land_use_eval_every:10,land_use_eval_horizon:5,enable_roads:true}
};
// Cross every comparison condition with the displacement mechanism.
// Keep realized housing allocation and zoning forecasts aligned in presets.
for(const [key,preset] of Object.entries({...presets})){
  presets[key]={...preset,label:preset.label+' · displacement off',allow_displacement:false,law_allow_displacement:false};
  presets[key+'_displacement']={...preset,label:preset.label+' · displacement on',allow_displacement:true,law_allow_displacement:true};
}
const common = {n_steps:250,n_search:5,agents_inflow:40,existing_move_share:0.1,
  blender_update_every:10,step_delay:0.1,allow_displacement:false,
  law_allow_displacement:false,law_incumbent_mover_share:0,law_incumbent_can_build:false,
  enable_employer:true,employer_eval_every:1,employer_n_candidates:5,employer_horizon:3,
  road_eval_every:20,road_unit:1.01,n_neighborhoods_sqrt:10,k:8};
let wealthHistory=[];
let parameters={...common,...presets.no_zoning}, hasRun=false, totalSteps=0, batchBase=0;
let position=0, ws=null, running=null, resetting=false, ready=false, stats=null, selected='no_zoning', message='Connect the model to enable controls.', resetTimer=null;
const $=id=>document.getElementById(id);
function current(){return window.SLIDES[position];}
function choices(demo){return demo==='horizons'?['short','long']:demo==='transport'?['roads_off','roads_on']:[demo];}
function el(tag,text,cls){const node=document.createElement(tag);if(text!==undefined)node.textContent=text;if(cls)node.className=cls;return node;}
function rich(tag,markup,cls){const n=el(tag,undefined,cls);n.innerHTML=markup;return n;}
function render(){
  const s=current(),root=$('slide');root.replaceChildren();root.className=s.chart?'results':s.appendix?'appendix':s.kind||'';
  root.append(el('div',s.demo?'Live experiment · switch to Blender':s.chart?'Saved comparisons · overnight experiments':'Urbanization from the bottom up','eyebrow'),el('h1',s.title));
  if(s.body)root.append(rich('p',s.body));
  if(s.author){const author=el('div',undefined,'author');for(const line of s.author)author.append(el('div',line));root.append(author);}
  if(s.bullets){const list=el('ul',undefined,'slide-bullets');for(const bullet of s.bullets)list.append(rich('li',bullet));if(s.demo){const detail=el('details',undefined,'demo-explanation');detail.append(el('summary','Experiment guide'),list);root.append(detail);}else root.append(list);}
  if(s.diagram){const img=el('img',undefined,'law-tree-diagram');img.src=s.diagram.src;img.alt=s.diagram.alt;root.insertBefore(img,root.querySelector('.slide-bullets'));}
  if(s.math)for(const formula of s.math)root.append(rich('div',formula,'math-display'));
  if(s.table){const table=el('table',undefined,'parameter-table');const head=el('thead'),tr=el('tr');for(const h of s.table.headers)tr.append(el('th',h));head.append(tr);table.append(head);const body=el('tbody');for(const row of s.table.rows){const tr=el('tr');for(const cell of row)tr.append(rich('td',cell));body.append(tr);}table.append(body);root.append(table);}
  if(s.source){const a=el('a',s.source.title,'source-link');a.href=s.source.url;a.target='_blank';a.rel='noopener';root.append(a);}
  if(s.equation)root.append(el('div',s.equation,'equation'));
  if(s.chart){if(['zoning','horizons','transport'].includes(s.chart)){const live=el('button','Run this comparison live');live.onclick=()=>{const demo=s.chart==='zoning'?'no_zoning':s.chart;const target=window.SLIDES.findIndex(x=>x.demo===demo);navigate(target-position);};root.append(live);}const img=el('img');img.className='chart';img.alt=s.body;img.src=`charts/${s.chart}.png?v=${Date.now()}`;img.onerror=()=>img.replaceWith(el('div','Awaiting results · '+s.chart+'.png','placeholder'));root.append(img);}
  if(s.demo){
    const opts=Object.keys(presets);
    const controls=el('div',undefined,'controls'),select=el('select');select.id='scenario';select.setAttribute('aria-label','Experiment condition');
    for(const key of opts){const option=el('option',presets[key].label);option.value=key;select.append(option);}select.value=selected;select.onchange=()=>{selected=select.value;loadPreset(selected);render();};controls.append(select);
    for(const [id,label,action] of [['reset','Reset city',reset],['start','Start condition',()=>start(false)],['continue','Continue city',()=>start(true)],['stop','Stop run',stop]]){const b=el('button',label);b.id=id;b.onclick=action;controls.append(b);}root.append(controls);
    const summary=el('div','', 'settings');summary.id='settings-summary';root.append(summary);
    const edit=el('button','Audience experiment / edit settings');edit.onclick=()=>togglePanel(true);root.append(edit);
    const status=el('div',message,'status');status.id='run-status';status.setAttribute('role','status');root.append(status);
    const metrics=el('div',undefined,'metrics');
    for(const [key,label] of [['step','Step'],['housed','Housed / agents'],['vacant','Empty Units'],['pct_laws','Neighborhoods with laws']]){const card=el('div',undefined,'metric'),value=el('strong','—');value.id='metric-'+key;card.append(value,el('span',label));metrics.append(card);}root.append(metrics);
    const charts=el('div',undefined,'telemetry');charts.id='telemetry-inline';root.append(charts);
  }
  const mainCount=window.SLIDES.filter(s=>!s.appendix).length;
  $('counter').textContent=s.appendix?`Reference ${position-mainCount+1} / ${window.SLIDES.length-mainCount}`:`${position+1} / ${mainCount}`;
  $('prev').disabled=position===0;$('next').disabled=position===window.SLIDES.length-1;
  const elapsed=window.SLIDES.slice(0,position).reduce((n,s)=>n+s.seconds,0);
  $('notes').textContent=`Target ${Math.floor(elapsed/60)}:${String(elapsed%60).padStart(2,'0')} · ${s.seconds}s on this slide. ${s.notes||s.body}`;
  $('progress').style.width=`${100*(position+1)/window.SLIDES.length}%`;update();
}
function update(){
  const connected=ws?.readyState===WebSocket.OPEN;
  $('connection').textContent=connected?(running===true?'Model running':running===false?'Model idle':'Synchronizing…'):'Model disconnected';
  $('connect').disabled=!!ws;
  updatePanel(connected);
  window.drawTelemetry($('telemetry-inline'),stats,connected,wealthHistory);
  if(!$('charts-overlay').hidden)window.drawTelemetry($('telemetry-overlay-content'),stats,connected,wealthHistory); 
  if(!$('start'))return;
  $('start').disabled=!connected||running!==false||resetting||!ready;
  $('continue').disabled=!connected||running!==false||resetting||!hasRun;
  $('settings-summary').textContent=summaryText();
  $('reset').disabled=!connected||running!==false||resetting;
  $('stop').disabled=!connected||running!==true||resetting;
  $('scenario').disabled=running===true||resetting;
  $('run-status').textContent=message;
  if(!stats){for(const k of ['step','housed','vacant','pct_laws'])$('metric-'+k).textContent='—';}
  if(stats){$('metric-step').textContent=totalSteps;$('metric-housed').textContent=`${stats.housed??'—'} / ${stats.agents??'—'}`;$('metric-vacant').textContent=stats.vacant??'—';$('metric-pct_laws').textContent=stats.pct_laws==null?'—':stats.pct_laws+'%';}
}
function send(payload){if(ws?.readyState!==WebSocket.OPEN)return false;try{ws.send(JSON.stringify(payload));return true;}catch{message='Command could not be sent. Reconnect and inspect model state.';update();return false;}}
function reset(){if(running!==false||resetting)return;ready=false;hasRun=false;resetting=true;stats=null;message='Waiting for the model to acknowledge reset…';render();if(!send({type:'reset'})){resetting=false;update();return;}resetTimer=setTimeout(()=>{resetting=false;ready=false;message='Reset acknowledgement timed out. Inspect the model, then reset again.';update();},15000);}
function start(continuing=false){
  if(running!==false||resetting||(continuing?!hasRun:!ready)||!validateSettings())return;
  const {label,...payload}=parameters;
  if(send({type:'start',...payload})){
    if(!continuing)wealthHistory=[];batchBase=continuing?totalSteps:0;ready=false;running=null;hasRun=true;
    message=`Requested ${payload.n_steps} ticks${continuing?' on the existing city':''}. ${continuing?'Existing laws and roads remain; batch event clocks restart.':'Switch to Blender once running.'}`;update();
  }
}
function stop(){if(running===true&&send({type:'stop'})){message='Stop requested; waiting for the current model step to finish.';update();}}
function connect(){
  if(ws)return;wealthHistory=[];stats=null;batchBase=0;totalSteps=0;ws=new WebSocket('ws://127.0.0.1:8766');running=null;ready=false;update();
  ws.onopen=()=>{message='Connected. Reset the idle city before starting a condition.';update();};
  ws.onmessage=event=>{let msg;try{msg=JSON.parse(event.data);}catch{return;}
    if(msg.type==='running'){running=msg.value;if(running)ready=false;}
    if(msg.type==='reset_state'){wealthHistory=[];stats=null;hasRun=false;totalSteps=0;batchBase=0;if(resetting){clearTimeout(resetTimer);resetting=false;ready=true;message='City reset. Select a condition and start. Random generator is not reseeded.';}}
    if(msg.type==='stats'){stats=msg;totalSteps=batchBase+(Number(msg.step)||0);wealthHistory=window.recordWealthPoint(wealthHistory,msg,totalSteps);}
    update();
  };
  ws.onerror=()=>{message='Connection failed. Start Julia and connect again.';update();};
  ws.onclose=()=>{clearTimeout(resetTimer);ws=null;running=null;ready=false;hasRun=false;resetting=false;message='Disconnected. Reconnect to check model state; the model may still be running.';update();};
}
function navigate(delta){position=Math.max(0,Math.min(window.SLIDES.length-1,position+delta));location.hash=String(position+1);render();}
function readHash(){const n=Number(location.hash.slice(1));position=Number.isInteger(n)&&n>=1&&n<=window.SLIDES.length?n-1:0;render();}
$('charts-toggle').onclick=()=>{$('charts-overlay').hidden=false;update();};
$('charts-close').onclick=()=>{$('charts-overlay').hidden=true;};
let referenceReturn=0;
$('parameters-toggle').onclick=()=>{if(current().appendix){position=referenceReturn;}else{referenceReturn=position;position=window.SLIDES.findIndex(s=>s.appendix);}location.hash=String(position+1);render();};
$('prev').onclick=()=>navigate(-1);$('next').onclick=()=>navigate(1);$('connect').onclick=connect;
$('notes-toggle').onclick=()=>{$('notes').hidden=!$('notes').hidden;};
$('fullscreen').onclick=async()=>{try{if(document.fullscreenElement)await document.exitFullscreen();else await document.documentElement.requestFullscreen();}catch{message='Fullscreen unavailable; use the browser presentation controls.';update();}};
document.addEventListener('keydown',e=>{if(!$('charts-overlay').hidden){if(e.key==='Escape')$('charts-overlay').hidden=true;return;}if(/INPUT|SELECT|TEXTAREA|BUTTON/.test(e.target.tagName)||e.altKey||e.ctrlKey||e.metaKey)return;if(['ArrowRight','PageDown',' '].includes(e.key)){e.preventDefault();navigate(1);}if(['ArrowLeft','PageUp'].includes(e.key)){e.preventDefault();navigate(-1);}if(e.key.toLowerCase()==='n')$('notes-toggle').click();});

const fields = [
 ['n_steps','Ticks per Batch',1,1000000,1],['agents_inflow','Arrivals per step',0,10000,1],
 ['n_search','Search intensity',1,1000,1],['existing_move_share','Incumbent mover share',0,1,0.01],
 ['land_use_eval_every','Propose laws every N steps (0 = off)',0,1000000,1],
 ['land_use_eval_horizon','Voting horizon H',1,1000,1],['enable_roads','Enable transport'],
 ['road_eval_every','Evaluate transport every N steps',1,1000000,1],['road_unit','Distance per network hop',0.01,1000,0.01],
 ['enable_employer','Enable employer'],['employer_eval_every','Evaluate employer every N steps (0 = fixed)',0,1000000,1],
 ['employer_n_candidates','Employer candidate locations',1,1000,1],['employer_horizon','Employer forecast horizon',1,1000,1],
 ['allow_displacement','Allow budget-based displacement'],['law_allow_displacement','Allow displacement in voting branches'],
 ['law_incumbent_mover_share','Incumbent mover share in voting branches',0,1,0.01],['law_incumbent_can_build','Incumbents may build in voting branches'],
 ['blender_update_every','Blender update interval (0 = end)',0,1000000,1],['step_delay','Delay between steps (seconds)',0,60,0.1]
];
const distributions=[['budget','Budget',1,0.5],['pref_density','Preferred neighborhood median height',3,2],
 ['pref_nh_max_height','Preferred neighborhood maximum height',6,2],['pref_nh_min_height','Preferred neighborhood minimum height',1,1],
 ['pref_height','Preferred building height',3,2],['σ_neighborhood','Neighborhood tolerance',-0.5,0.3],
 ['σ_building','Building tolerance',-0.5,0.3],['proximity_scale','Commute tolerance',2.5,0.5],['copula_θ','Copula θ',0.7,0.4]];
for(const [key,label,mu,sigma] of distributions){
  common[key+'_μ']=mu;common[key+'_σ']=sigma;parameters[key+'_μ']=mu;parameters[key+'_σ']=sigma;
  const log=!key.startsWith('pref_');
  fields.push([key+'_μ',label+(log?' · log mean':' · normal mean'),log?-20:0,log?20:1000,0.1],[key+'_σ',label+(log?' · log SD':' · normal SD'),0,log?10:1000,0.1]);
}
function summaryText(){return `${parameters.n_steps} ticks · ${parameters.agents_inflow} arrivals/step · H = ${parameters.land_use_eval_horizon} · zoning ${parameters.land_use_eval_every?'every '+parameters.land_use_eval_every+' steps':'off'} · transport ${parameters.enable_roads?'on':'off'} · hop ${parameters.road_unit} · displacement ${parameters.allow_displacement?'on':'off'} (voting ${parameters.law_allow_displacement?'on':'off'}) · Blender every ${parameters.blender_update_every} ticks`;}
function loadPreset(key){parameters={...common,...presets[key]};syncFields();if($('scenario'))$('scenario').value=key;}
function syncFields(){for(const [key] of fields){const input=$('param-'+key);if(input){if(input.type==='checkbox')input.checked=parameters[key];else input.value=parameters[key];}}}
function validateSettings(){for(const [key] of fields){const input=$('param-'+key);if(!input.checkValidity()){togglePanel(true);input.reportValidity();return false;}}return true;}
function togglePanel(open){$('experiment-panel').hidden=!open;$('experiments-toggle').setAttribute('aria-expanded',String(open));}
function buildPanel(){
 const panel=$('experiment-panel');panel.append(el('h2','Audience Experiments'));
 const close=el('button','Close ×');close.onclick=()=>togglePanel(false);panel.append(close);
 const label=el('label','Load a preset');const select=el('select');select.id='panel-preset';select.append(el('option','Choose…'));
 for(const [key,preset] of Object.entries(presets)){const option=el('option',preset.label);option.value=key;select.append(option);}
 select.onchange=()=>{if(presets[select.value]){loadPreset(select.value);selected=select.value;if($('scenario'))$('scenario').value=selected;update();}};label.append(select);panel.append(label);
 const actions=el('div',undefined,'controls');
 for(const [id,text,action] of [['reset','Reset city',reset],['start','Start new condition',()=>start(false)],['continue','Continue city',()=>start(true)],['stop','Stop run',stop]]){const button=el('button',text);button.id='panel-'+id;button.onclick=action;actions.append(button);}panel.append(actions);
 const status=el('div','', 'status');status.id='panel-status';status.setAttribute('role','status');panel.append(status);
 const summary=el('div','', 'settings');summary.id='panel-summary';panel.append(summary);
 panel.append(el('p','Reset for a fresh comparison. Continue adds a batch to the existing city; laws and roads remain, and event clocks restart. Edits apply to the next batch.','panel-help'));
 const form=el('div',undefined,'parameter-grid');
 for(const [key,text,min,max,step] of fields){const label=el('label',text);const input=el('input');input.id='param-'+key;
  input.type=min===undefined?'checkbox':'number';if(min!==undefined){input.min=min;input.max=max;input.step=step;input.required=true;}
  input.oninput=()=>{parameters[key]=input.type==='checkbox'?input.checked:input.valueAsNumber;update();};label.append(input);form.append(label);
 }panel.append(form);
 panel.append(el('p','Preference controls apply to new arrivals: preferred heights use floored normal draws; budgets and tolerances use log-normal draws. Existing households keep their preferences. Turning a mechanism off does not erase existing laws, roads, or job assignments: reset for an off-versus-on comparison.','panel-help'));
 syncFields();$('experiments-toggle').onclick=()=>togglePanel($('experiment-panel').hidden);
}
function updatePanel(connected){
 $('panel-start').disabled=!connected||running!==false||resetting||!ready;
 $('panel-continue').disabled=!connected||running!==false||resetting||!hasRun;
 $('panel-reset').disabled=!connected||running!==false||resetting;
 $('panel-stop').disabled=!connected||running!==true||resetting;
 $('panel-status').textContent=message;
 $('panel-summary').textContent=summaryText()+(stats?` · total ticks ${totalSteps} · housed ${stats.housed}/${stats.agents}`:'');
}

window.addEventListener('hashchange',readHash);buildPanel();readHash();
