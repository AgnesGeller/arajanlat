import { db, rows } from '../services/supabase-service.js';
import { dateTime } from './quote-calculator.js';
const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const kinds={measurement:'Méret',area:'Terület',plant:'Növény',work:'Munka',note:'Megjegyzés'};
let disposePhotos=()=>{};
export function surveyRecord(data,projectId){
 const record={project_id:projectId,kind:data.kind,name:data.name.trim(),unit:data.unit.trim(),unit2:data.unit2.trim(),note:data.note.trim()};
 if(!kinds[record.kind]||!record.name||record.name.length>300)throw Error('Adja meg a felmérési adat megnevezését (legfeljebb 300 karakter).');
 for(const key of ['quantity','quantity2']){record[key]=data[key]===''?null:Number(data[key]);if(record[key]!==null&&(!Number.isFinite(record[key])||record[key]<0))throw Error('A mennyiség nem lehet negatív.');}
 if(record.quantity!==null&&!record.unit||record.quantity2!==null&&!record.unit2)throw Error('A mennyiségekhez adja meg a mértékegységet is.');
 return record;
}
export async function mountSiteSurvey(container,project,{formDialog,fail,status}){
 disposePhotos();
 try{
 const entries=await rows('quote_survey_entries',q=>q.select('*').eq('project_id',project.id).eq('archived',false).order('measured_at',{ascending:false}));
 if(!container.isConnected)return;
 container.innerHTML=`<details class="source-section"><summary>Helyszíni felmérés · ${entries.length} adat</summary><p>A mérések, területek, növények és munkák ehhez a projekthez tartoznak.</p><button type="button" class="secondary" data-add-survey>+ Felmérési adat</button><div class="survey-list">${entries.map(e=>`<article><strong>${esc(kinds[e.kind])} · ${esc(e.name)}</strong><p>${e.quantity!==null?`${esc(e.quantity)} ${esc(e.unit)}`:''}${e.quantity2!==null?` × ${esc(e.quantity2)} ${esc(e.unit2)}`:''}</p><p>${esc(e.note)}</p><small>${dateTime(e.measured_at)}</small><div class="toolbar"><button type="button" data-survey-edit="${e.id}">Szerkesztés</button><button type="button" data-survey-archive="${e.id}">Eltávolítás</button></div></article>`).join('')||'<p class="muted">Még nincs rögzített felmérési adat.</p>'}</div><h4>Helyszíni képek</h4><p class="muted">A képek ezen az eszközön maradnak. A képadatokat nem töltjük fel; külön a fájlok neve és típusa rögzíthető.</p><label>Képek kiválasztása<input type="file" data-survey-photos accept="image/*" multiple></label><div class="survey-photos"></div><div class="toolbar"><button type="button" data-photo-save hidden>Fájlnevek rögzítése</button><button type="button" data-photo-share hidden>Képek megosztása</button></div><p data-photo-status role="status"></p></details>`;
 const input=(name,label,value='',type='text')=>`<label>${label}<input name="${name}" type="${type}" ${type==='number'?'min="0" step="0.001"':''} value="${esc(value??'')}" ${name==='name'?'required maxlength="300"':''}></label>`;
 const edit=(entry={})=>formDialog('Helyszíni felmérési adat',`<label>Adat típusa<select name="kind">${Object.entries(kinds).map(([k,label])=>`<option value="${k}" ${entry.kind===k?'selected':''}>${label}</option>`).join('')}</select></label>${input('name','Megnevezés',entry.name)}<div class="grid">${input('quantity','Mennyiség / méret',entry.quantity,'number')}${input('unit','Mértékegység',entry.unit)}${input('quantity2','Második mennyiség / méret',entry.quantity2,'number')}${input('unit2','Második mértékegység',entry.unit2)}</div><label>Megjegyzés<textarea name="note">${esc(entry.note)}</textarea></label>`,async data=>{
  const record=surveyRecord(data,project.id);const query=entry.id?db.from('quote_survey_entries').update(record).eq('id',entry.id).eq('project_id',project.id):db.from('quote_survey_entries').insert(record);
  const {error}=await query;if(error)throw error;await mountSiteSurvey(container,project,{formDialog,fail,status});
 });
 container.querySelector('[data-add-survey]').onclick=()=>edit();
 container.querySelectorAll('[data-survey-edit]').forEach(b=>b.onclick=()=>edit(entries.find(e=>e.id===b.dataset.surveyEdit)));
 container.querySelectorAll('[data-survey-archive]').forEach(b=>b.onclick=async()=>{if(!confirm('Eltávolítja ezt a felmérési adatot a listából?'))return;b.disabled=true;try{const {error}=await db.from('quote_survey_entries').update({archived:true}).eq('id',b.dataset.surveyArchive).eq('project_id',project.id);if(error)throw error;await mountSiteSurvey(container,project,{formDialog,fail,status});status('Felmérési adat eltávolítva.')}catch(e){b.disabled=false;fail(e)}});
 let files=[],urls=[];const revoke=()=>{urls.forEach(URL.revokeObjectURL);urls=[];files=[];};
 const observer=new MutationObserver(()=>{if(!container.isConnected){revoke();observer.disconnect();window.removeEventListener('pagehide',revoke)}});observer.observe(document.body,{childList:true,subtree:true});
 window.addEventListener('pagehide',revoke);disposePhotos=()=>{revoke();observer.disconnect();window.removeEventListener('pagehide',revoke)};
 const save=container.querySelector('[data-photo-save]'),share=container.querySelector('[data-photo-share]'),message=container.querySelector('[data-photo-status]');
 container.querySelector('[data-survey-photos]').onchange=event=>{revoke();files=Array.from(event.target.files).filter(f=>f.type.startsWith('image/'));if(files.length>20){files=[];event.target.value='';message.textContent='Egyszerre legfeljebb 20 képet válasszon.'}else message.textContent='';container.querySelector('.survey-photos').innerHTML=files.map(f=>{const url=URL.createObjectURL(f);urls.push(url);return `<figure><img src="${url}" alt="${esc(f.name)}" loading="lazy"><figcaption>${esc(f.name)}</figcaption><a href="${url}" download="${esc(f.name)}">Mentés az eszközre</a></figure>`}).join('');save.hidden=!files.length;share.hidden=!files.length||!navigator.canShare?.({files});save.disabled=false;};
 save.onclick=async()=>{save.disabled=true;try{const {error}=await db.from('quote_received_files').insert(files.map(f=>({project_id:project.id,file_name:f.name,file_type:f.type,note:'Helyszíni felmérés; a kép az eszközön marad.'})));if(error)throw error;message.textContent='A fájlneveket rögzítettük. A képeket külön mentse vagy ossza meg.';}catch(e){save.disabled=false;fail(e)}};
 share.onclick=async()=>{try{await navigator.share({files,title:project.name});message.textContent='A megosztás elindult.'}catch(e){if(e.name!=='AbortError')message.textContent='A megosztás nem sikerült. Mentse a képeket az eszközére.'}};
 }catch(e){if(container.isConnected)container.innerHTML='<p class="error">A felmérési adatok nem töltődtek be. Nyissa meg újra a projektet.</p>';fail(e)}
}
