import {db,rpc} from '../js/services/supabase-service.js';
import {calculateProject} from '../js/modules/worksheet-calculator.js';
import {calculateProgress} from '../js/modules/work-progress.js';
import {calculateTotal,money} from '../js/modules/quote-calculator.js';
const projectId='df25187d-463a-43d5-845b-ba9cb09aa356';
const steps=['Ügyfél és projekt','Adatbekérő és felmérés','Árajánlat','Ügyfél elfogadása','Első munkalap','Második munkalap','Harmadik munkalap','Befejező munkalap','Javítás hatása','Lezárás'];
const $=s=>document.querySelector(s),esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const number=v=>new Intl.NumberFormat('hu-HU',{maximumFractionDigits:2}).format(v);
let summary,project,requests=[],history=[],position=0;
$('#demo-step').innerHTML=steps.map((s,i)=>`<option value="${i}">${i+1}. ${s}</option>`).join('');
$('#demo-step').onchange=e=>{position=Number(e.target.value);render();};
$('#demo-back').onclick=()=>{position=Math.max(0,position-1);render();};
$('#demo-next').onclick=()=>{position=Math.min(steps.length-1,position+1);render();};
$('#demo-refresh').onclick=()=>load();
async function load(){
 $('#demo-status').textContent='Bemutató betöltése…';$('#demo-refresh').disabled=true;
 try{
  const {data:{session},error}=await db.auth.getSession();if(error)throw error;
  if(!session){$('#demo-status').textContent='A bemutatóhoz először lépj be az Árajánlat appba, majd nyisd meg újra ezt az oldalt.';return;}
  summary=await rpc('quote_project_work_summary',{p_project:projectId});
  const archived=await db.from('quote_work_records').select('source_id,work_date,source_updated_at,form_data').eq('project_id',projectId).eq('active',false).in('source_id',[1,2,3,4].map(n=>'46de071d-68ef-447a-a36b-41b1fd12000'+n)).order('work_date');
  if(archived.error)throw archived.error;
  history=archived.data.map(r=>({id:r.source_id,work_date:r.work_date,updated_at:r.source_updated_at,form_data:r.form_data}));
  const result=await db.from('quote_projects').select('name,status,started_on,project_code').eq('id',projectId).single();if(result.error)throw result.error;project=result.data;
  const received=await db.from('quote_client_requests').select('answers,submitted_at').eq('project_id',projectId).order('submitted_at');if(received.error)throw received.error;requests=received.data;
  $('#demo-status').textContent=history.length?'A Munkalapból törölt tesztadatok az aktuális elszámolásban nem szerepelnek. A korábbi munkanapok kizárólag megőrzött bemutatási előnézetek.':'Az Árajánlatban megőrzött tesztadatok alapján. A korábbi lépések és a javítás hatása csak olvasási előnézet.';render();
 }catch{$('#demo-status').textContent='A bemutató most nem érhető el. Ellenőrizd a belépést és az internetkapcsolatot.';}
 finally{$('#demo-refresh').disabled=false;}
}
function bars(records,settings,preview=false){
 const totals=calculateProject(records,summary.labor_budget),progress=calculateProgress(summary.items,settings,records);
 return `<div class="work-progress"><strong>Munka készültsége</strong>${progress.percent===null?`<p>${progress.missing} tételnél készültségi adat szükséges. A szöveges leírásból nem számolunk.</p>`:`<progress max="100" value="${progress.percent}" aria-label="Munka készültsége"></progress><p>${number(progress.percent)}%</p>`}</div>
 <div class="work-progress"><strong>Munkaórakeret felhasználása</strong>${totals.used_percent===null?'<p>Elfogadott munkadíjkeret szükséges.</p>':`<progress max="100" value="${Math.min(100,totals.used_percent)}" aria-label="Munkaórakeret felhasználása"></progress><p>${number(totals.used_percent)}% · ${number(totals.person_hours)} / ${number(totals.budget_hours)} főóra</p><p class="${totals.remaining_hours<0?'error':''}">${totals.remaining_hours<0?'Túllépés: '+number(-totals.remaining_hours):'Hátralévő: '+number(totals.remaining_hours)} főóra</p>`}</div><p>${preview?'Előnézetben számított':'Számított'} munkadíj: <strong>${money(totals.labor)}</strong></p>`;
}
function render(){
 if(!summary)return;
 $('#demo-step').value=String(position);$('#demo-back').disabled=position===0;$('#demo-next').disabled=position===steps.length-1;
 let content='';const all=history.length===4?history:summary.records,total=calculateTotal(summary.items);
 if(position===0)content=`<p><strong>Geller Ágnes</strong> meglévő közös ügyfél. Új ügyfélmásolat nem készült.</p><p>Projekt: ${esc(project.project_code)} – ${esc(project.name)}.</p><p>A korábbi Támfal építés projekt külön megmaradt.</p>`;
 if(position===1)content=`<p>Az ügyfél tokenes adatbekérőt tölthet ki, regisztráció nélkül. Egy név, email vagy telefonszám elegendő azonosításhoz.</p><p>A projekthez ${requests.length} adatbekérő érkezett.</p>${requests.map(r=>`<p>${esc(r.answers.work_type||'Kertépítés')}: ${esc(r.answers.description||'')} · ${esc(r.answers.area_m2||'')} m²</p>`).join('')}<p>A grillt és a felszereléseket az ügyfél szerzi be. Találkozó szükség esetén időpontfoglalóval egyeztethető.</p>`;
 if(position===2)content=`<div class="demo-table"><table><thead><tr><th>Tétel</th><th>Mennyiség</th><th>Nettó összeg</th></tr></thead><tbody>${summary.items.map(i=>`<tr><td>${esc(i.name)}</td><td>${number(i.quantity1)} ${esc(i.unit1)}</td><td>${money(Number(i.quantity1)*(Number(i.material_unit)+Number(i.labor_unit)))}</td></tr>`).join('')}</tbody></table></div><p>Anyag: ${money(total.material)} · Munkadíj: ${money(total.labor)} · Összesen: <strong>${money(total.gross)}</strong></p><p>A térkő és a növények beszerzése külön tétel. Az ajánlat 0 Ft ÁFÁ-val szerepel.</p>`;
 if(position===3)content=`<p>Az ügyféloldali, nem valódi megrendelést jelentő bemutató elfogadását rögzítettük.</p><p>Elfogadott ajánlatok: ${summary.accepted_versions}.</p><p>Órakeret: ${money(summary.labor_budget)} ÷ 8 500 = <strong>${number(summary.labor_budget/8500)} főóra</strong>.</p>`;
 if(position>=4&&position<=7){const count=position-3,rows=all.slice(0,count),settings=count===all.length?summary.settings:summary.settings.filter(s=>s.source_code).map(s=>({...s,override_completed:null}));content=rows.length?`<p>${rows.length}. munkalap utáni bemutatási előnézet. Csak a kiválasztott lépésig tartó munkalapokkal számolunk; ez nem az aktuális elszámolás.</p>`+bars(rows,settings,true)+`<p>A korábbi lépésekben a külön nem mérhető munkák készültségét még meg kell adni. A végén Ági/Tamás kézi mennyiségei is szerepelnek.</p>`:'<p>Ehhez a lépéshez nincs megőrzött munkalapadat.</p>';}
 if(position===8){const revised=all.map((r,i)=>i===all.length-1?{...r,form_data:{...r.form_data,team_1_departure:'12:00'}}:r);content=all.length?'<p><strong>Javítási előnézet:</strong> az utolsó munkalap távozása 11:00 helyett 12:00. Kizárólag az előnézet változik, mentés nem történik.</p>'+bars(revised,summary.settings,true)+'<p>Az azonos munkalap javítása helyettesíti az előző adatot; nem keletkezik új munkalap.</p>':'<p>A javítás bemutatásához nincs megőrzött munkalapadat.</p>';}
 if(position===9)content=`<h3>Aktuális elszámolás</h3><p>A törölt munkalapok órái és mennyiségei nem számítanak bele. Ági/Tamás külön megadott készültségi mennyiségei megmaradnak.</p>`+bars(summary.records,summary.settings)+`<p>Aktív munkalapok: ${summary.records.length}. Projekt állapota: <strong>${esc(project.status)}</strong>.</p>`+(history.length===4?'<h3>Korábbi bemutató eredménye</h3><p>A négy törölt tesztmunkalap kizárólag ebben az előnézetben szerepel.</p>'+bars(history,summary.settings,true):'')+`<p>A kasszakiadások és valódi bérkifizetések teljes projektkapcsolata későbbi fejlesztés; ezek itt nem kitalált összegek.</p>`;
 $('#demo-content').innerHTML=`<h2>${position+1}. ${steps[position]}</h2>${content}`;
}
load();
