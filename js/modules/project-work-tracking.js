import {calculateProject,RULES} from './worksheet-calculator.js';
import {calculateProgress} from './work-progress.js';
import {money,dateTime} from './quote-calculator.js';
const esc=value=>String(value??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const number=value=>new Intl.NumberFormat('hu-HU',{maximumFractionDigits:2}).format(value);
export function renderProjectWorkTracking(container,project,summary,onEdit){
  if(!project.started_on){container.hidden=true;container.replaceChildren();return;}
  container.hidden=false;
  const totals=calculateProject(summary.records,summary.labor_budget);
  const used=totals.used_percent;
  const progress=calculateProgress(summary.items,summary.settings,summary.records);
  const last=summary.records.map(r=>r.synced_at).filter(Boolean).sort().at(-1);
  const timeInvalid=totals.issues.some(s=>s.startsWith('Csapat ')||s==='Nincs megadott munkaidő.');
  container.innerHTML=`<section class="panel work-tracking"><h3>Projekt haladása</h3>
    <p class="muted">Kezdés: ${esc(project.started_on)}${last?' · Utolsó munkalapfrissítés: '+esc(dateTime(last)):''}</p>
    <div class="work-progress"><strong>Munka készültsége</strong>${progress.percent===null?`<p>Készültségi adat hiányzik.${progress.missing?' '+progress.missing+' tételnél mennyiség vagy összerendelés szükséges.':''}</p>`:`<progress value="${progress.percent}" max="100" aria-label="Munka készültsége"></progress><p>${number(progress.percent)}%</p>`}</div>
    <div class="work-progress"><strong>Munkaórakeret felhasználása</strong>
    ${used===null||timeInvalid?`<p>${timeInvalid?'A munkaidőadatok ellenőrzése szükséges.':summary.accepted_versions>1?'Több elfogadott ajánlat van; az órakeret alapját meg kell adni.':'Nincs kiszámítható, elfogadott munkadíjkeret.'}</p>`:
    `<progress value="${Math.min(100,used)}" max="100" aria-label="Munkaórakeret felhasználása"></progress><p>${number(used)}% · ${number(totals.person_hours)} / ${number(totals.budget_hours)} főóra</p><p class="${totals.remaining_hours<0?'error':''}">${totals.remaining_hours<0?'Túllépés: '+number(-totals.remaining_hours):'Hátralévő: '+number(totals.remaining_hours)} főóra</p>`}</div>
    <p>Munkadíj: <strong>${money(totals.labor)}</strong>${timeInvalid?' · hiányos munkaidőadatok':''}</p>
    <p>${totals.complete?'Összesen':'Ismert tételek részösszege'}: <strong>${money(totals.known_total)}</strong></p>
    ${progress.lines.length?`<details><summary>Tételek készültsége</summary><div class="work-lines">${progress.lines.map(l=>`<div><span>${esc(l.item.name)}<small>${l.completed===null?'Nincs készültségi adat':number(l.completed)+' / '+number(l.planned)+' '+esc(l.item.unit2?l.item.unit1+' × '+l.item.unit2:l.item.unit1)}${l.setting?.override_completed!=null?' · kézzel megadva':''}</small></span>${onEdit?`<button type="button" class="secondary" data-work-item="${esc(l.item.id)}">Módosítás</button>`:''}</div>`).join('')}</div></details>`:''}
    ${!summary.records.length?'<p class="muted">Még nincs ehhez a projekthez átvett munkalap.</p>':''}
    ${summary.records.map(row=>{const calc=row.calculation;return `<details><summary>${esc(row.work_date)} · ${number(calc.person_hours)} főóra · ${money(calc.labor)} munkadíj</summary><div class="work-lines">${calc.lines.map(line=>`<div><span>${esc(line.name)}<small>${line.quantity===null?esc(line.raw_value):number(line.quantity)+' '+esc(line.unit)}</small></span><strong class="${line.amount===null?'error':''}">${line.amount===null?'Árazás szükséges':money(line.amount)}</strong></div>`).join('')}</div>${calc.issues.length?'<ul class="error">'+calc.issues.map(issue=>'<li>'+esc(issue)+'</li>').join('')+'</ul>':''}</details>`;}).join('')}
    </section>`;
  if(onEdit)container.querySelectorAll('[data-work-item]').forEach(b=>b.onclick=()=>onEdit(progress.lines.find(l=>l.item.id===b.dataset.workItem)));
}

export async function mountProjectWorkTracking(container,project,{db,rpc,formDialog}){
  if(!project.started_on){container.hidden=true;return;}
  container.hidden=false;container.textContent='Munkalapadatok betöltése…';
  const refresh=async(sync=false)=>{
    if(!container.isConnected)return;
    let warning='';
    if(sync){const result=await db.functions.invoke('quote-work-sync',{body:{action:'sync'}});if(result.error)warning='A munkalapfrissítés nem sikerült. A korábban átvett adatok láthatók.';else warning=(result.data.issues||[]).join(' ');}
    const summary=await rpc('quote_project_work_summary',{p_project:project.id});
    if(!container.isConnected)return;
    renderProjectWorkTracking(container,project,summary,line=>{
      const unit=v=>String(v||'').trim().toLowerCase().replaceAll('²','2').replaceAll('³','3');
      const options=line.item.unit2?[]:RULES.filter(r=>r[2]!=='tétel'&&unit(r[2])===unit(line.item.unit1));
      formDialog('Tétel készültsége',`<p>${esc(line.item.name)}</p><label>Munkalap mennyiségmezője<select name="source_code"><option value="">Nincs összerendelés</option>${options.map(r=>`<option value="${r[0]}" ${line.setting?.source_code===r[0]?'selected':''}>${esc(r[1])} (${esc(r[2])})</option>`).join('')}</select></label><label>Elkészült mennyiség<input name="override_completed" type="number" min="0" max="1000000" step="any" value="${line.setting?.override_completed??''}"></label><p class="muted">Üres mennyiség esetén a munkalapból számolunk. A megadott mennyiség felülírja az automatikus eredményt.</p>`,async data=>{
        const {data:auth,error:authError}=await db.auth.getUser();if(authError)throw authError;
        const {error}=await db.from('quote_work_progress').upsert({item_id:line.item.id,version_id:line.item.version_id,project_id:project.id,source_code:data.source_code||null,override_completed:data.override_completed===''?null:Number(data.override_completed),modified_by:auth.user.id,modified_at:new Date().toISOString()});
        if(error)throw Error(error.code==='23505'?'Ezt a munkalapmezőt már másik tételhez rendelted.':error.message);
        await refresh();return 'Készültség mentve.';
      });
    });
    const button=document.createElement('button');button.type='button';button.className='secondary';button.textContent='Munkalapok frissítése';
    button.onclick=async()=>{button.disabled=true;try{await refresh(true);}catch{button.textContent='Nem sikerült. Próbáld újra.';button.disabled=false;}};
    container.querySelector('section').prepend(button);
    if(warning){const p=document.createElement('p');p.className='error';p.textContent=warning;container.append(p);}
  };
  try{await refresh(true);}catch{container.textContent='A projektkövetés most nem érhető el. A többi funkció használható.';}
}
