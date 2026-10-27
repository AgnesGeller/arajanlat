// Isolated browser test: all backend operations stay in memory; no live credentials or requests.
const nativeFetch=window.fetch.bind(window);
const source=await (await nativeFetch('index.html')).text();
document.body.innerHTML=new DOMParser().parseFromString(source,'text/html').body.innerHTML;
const report=document.createElement('pre');report.id='workflow-test-results';report.style.cssText='white-space:pre-wrap;overflow-wrap:anywhere;font-size:13px;padding:1rem';report.setAttribute('role','status');document.body.prepend(report);
const tables={
 quote_staff:[{user_id:'staff',company_id:'company'}],
 quote_clients:[{id:'customer',name:'Teszt Ügyfél',email:'teszt@example.org',project_address:'Teszt utca 1.\nMásik teszt utca 2.',source_customer_id:'source'}],
 quote_projects:[{id:'project',client_id:'customer',name:'Első kert',project_code:'PR-TESZT-1',work_address:'Teszt utca 1.',status:'Új érdeklődés',meeting_required:false},{id:'project2',client_id:'customer',name:'Másik kert',project_code:'PR-TESZT-2',work_address:'Másik teszt utca 2.',status:'Felmérve',meeting_required:false}],
 quote_quotes:[{id:'quote',project_id:'project',number:'DK-TESZT-1',title:'Első kert',detail_level:'detailed',terms:''}],
 quote_versions:[{id:'version',quote_id:'quote',name:'A változat',status:'draft'}],
 quote_items:[{id:'item',version_id:'version',name:'Tétel',quantity1:2,unit1:'m²',material_unit:1000,labor_unit:500,vat_rate:0,position:1}],
 quote_price_catalog:[{id:'catalog',active:true,category:'Kertépítés',subcategory:'Gyepesítés',description:'Gyep telepítése',unit1:'m²',material_unit:1000,labor_unit:500}],quote_templates:[]
};
let writes=[],failWrite=false;
function query(table){let filters=[],patch,insert=false,single=false,executed;
 const builder={select(){return this},eq(k,v){filters.push(r=>r[k]===v);return this},is(k,v){filters.push(r=>r[k]===v);return this},order(){return this},limit(){return this},gt(){return this},lte(){return this},update(v){patch=v;return this},insert(v){patch=v;insert=true;return this},single(){single=true;return this},then(resolve,reject){
 if(!executed)executed=(async()=>{if(patch&&failWrite)return {data:null,error:Error('Elkülönített mentési hiba')};let list=(tables[table]||=[]).filter(r=>filters.every(f=>f(r)));if(patch){writes.push({table,patch:{...patch}});if(insert){const record={id:crypto.randomUUID(),status:table==='quote_versions'?'draft':undefined,...patch};tables[table].push(record);list=[record]}else list.forEach(r=>Object.assign(r,patch));}return {data:structuredClone(single?list[0]:list),error:null};})();return executed.then(resolve,reject)}
 };return builder;
}
window.supabase={createClient:()=>({auth:{getSession:async()=>({data:{session:{user:{id:'staff',email:'agi@arajanlat.diszkertek.hu'},access_token:'local-fixture'}}}),onAuthStateChange(){},signOut:async()=>({})},from:query,rpc:async name=>({data:name==='quote_clients_list'?structuredClone(tables.quote_clients):name==='quote_request_link_create'?'fixture-only-link':[],error:null})})};
window.fetch=async(url,options)=>{if(String(url).startsWith('https://cszsxjsiwaaibrocibyd.supabase.co/functions/v1/quote-customer-sync'))return new Response('{}',{status:200});if(new URL(url,location.href).origin!==location.origin)throw Error('Külső hálózati kérés tiltva a tesztben');return nativeFetch(url,options)};
const errors=[];window.addEventListener('error',e=>errors.push(e.message));window.addEventListener('unhandledrejection',e=>errors.push(String(e.reason)));
const $=s=>document.querySelector(s),visible=s=>!!$(s)&&!$(s).closest('[hidden]');let passed=0,failed=0;
function check(name,test){if(!test){failed++;report.textContent+='HIBA: '+name+'\n';}else{passed++;report.textContent+='OK: '+name+'\n';}}
async function waitFor(test){for(let i=0;i<200;i++){if(test())return;await new Promise(r=>setTimeout(r,10));}throw Error('Várakozás sikertelen: '+test);}
async function click(selector,ready){$(selector).click();if(ready)await waitFor(ready);else await new Promise(r=>setTimeout(r,20));}
try{
 await import('../js/app.js?v=51');await waitFor(()=>visible('#workspace')&&$('#recent-projects button'));
 check('Belépés után a Kezdés oldal nyílik',visible('#start-view')&&!visible('#customers-view')&&$('#nav [aria-current="page"]').dataset.view==='start');
 check('Négy világos lépés látszik',$('.start-steps').children.length===4);check('Kezdőoldal nem lóg ki',document.documentElement.scrollWidth<=window.innerWidth);
 await click('#begin-quote',()=>visible('#customers-view'));check('Új ajánlat a keresőhöz vezet',document.activeElement===$('#customer-search')&&!visible('#customer-detail'));
 $('#customer-search').value='Te';$('#customer-search').dispatchEvent(new Event('input'));check('Két betű után megjelenik a találat',visible('#customer-results')&&$('#customer-results button'));
 await click('#customer-results button',()=>visible('#customer-detail'));check('Ügyfélnézet nem lóg ki',document.documentElement.scrollWidth<=window.innerWidth);check('Ügyfél után a projekt következik',$('#customer-detail [aria-current="step"] .step-number').textContent==='1'&&$('#new-project'));
 await click('[data-project="project"]',()=>!!$('#project-detail [data-add-survey]'));check('A projekt saját nézetben nyílik',visible('#projects-view')&&!visible('#customers-view')&&!visible('#project-browser')&&$('#project-detail [aria-current="step"] .step-number').textContent==='2');
 check('Projektnézet nem lóg ki',document.documentElement.scrollWidth<=window.innerWidth);await click('#edit-project',()=>$('#form-dialog').open);check('Projekt alapmezői és további adatai megmaradnak',$('#dialog-form [name="name"]')&&$('#dialog-form [name="work_address"]')&&$('#dialog-form details [name="started_on"]'));await click('#dialog-cancel');
 await click('#request-link',()=>$('#form-dialog').open);check('Adatbekérő továbbra is elérhető',$('#generated-link').value.includes('fixture-only-link'));await click('#dialog-cancel');
 await click('#project-detail [data-quote="quote"]',()=>!!$('#add-item'));check('Ajánlat lépéssorral és saját nézetben nyílik',visible('#quotes-view')&&!visible('#quote-browser')&&$('#quote-detail [aria-current="step"] .step-number').textContent==='3');
 check('Az eredeti kalkuláció 3000 Ft nettót ad',$('#quote-detail .summary').textContent.replace(/\s/g,'').includes('Nettó:3000Ft'));
 check('Tételek után következnek a feltételek és a megosztás',!!($('#items-list').compareDocumentPosition($('#terms'))&Node.DOCUMENT_POSITION_FOLLOWING)&&!$('#offer-link').disabled&&$('#print-quote').disabled);
 await click('#add-item',()=>$('#form-dialog').open);check('Árlista és mennyiségek szerkeszthetők',$('#catalog-category')&&$('#catalog-select')&&$('#dialog-form [name="quantity1"]'));await click('#dialog-cancel');
 $('#terms').value='Navigáció előtt mentendő';$('#terms').dispatchEvent(new Event('input'));await click('#back-quote-project',()=>visible('#project-detail'));check('Visszalépés előtt menti az ajánlat feltételeit',tables.quote_quotes[0].terms==='Navigáció előtt mentendő');
 await click('#back-projects',()=>visible('#project-browser'));await click('[data-project-link="project2"]',()=>$('#project-detail h2')?.textContent==='Másik kert');check('Másik projektben nem marad az előző ajánlata',!$('#project-detail [data-quote="quote"]')&&$('#project-detail').textContent.includes('Másik teszt utca 2.'));
 await click('#new-quote',()=>visible('#quote-detail')&&$('#quote-detail .empty-state'));check('Új ajánlat a kiválasztott projekthez jön létre',tables.quote_quotes.at(-1).project_id==='project2'&&$('#quote-detail .empty-state'));
 await click('#back-quotes',()=>visible('#quote-browser'));await click('#quotes-list [data-quote="quote"]',()=>visible('#quote-detail')&&$('#quote-detail h2')?.textContent==='Első kert');
 failWrite=true;$('#terms').value='Nem menthető';$('#terms').dispatchEvent(new Event('input'));await click('#nav [data-view="start"]');await waitFor(()=>$('#status').classList.contains('error'));check('Sikertelen mentés nem enged elnavigálni',visible('#quote-detail')&&$('#status').textContent.includes('mentési hiba'));
 failWrite=false;await click('#nav [data-view="start"]',()=>visible('#start-view'));check('Újrapróbálás után a mentés megmarad',tables.quote_quotes[0].terms==='Nem menthető');
 check('Egyetlen főmenüpont aktív',$('#nav').querySelectorAll('[aria-current="page"]').length===1);
 // Leave a fresh read-only quote on screen for visual inspection (no real records).
 await click('#nav [data-view="quotes"]',()=>visible('#quote-browser'));await click('#quotes-list [data-quote="quote"]',()=>visible('#quote-detail')&&$('#quote-detail h2')?.textContent==='Első kert');
 await click('#offer-link',()=>$('#form-dialog').open&&tables.quote_versions.find(v=>v.id==='version').status==='published');await waitFor(()=>$('#quote-detail [aria-current="step"] .step-number').textContent==='4');check('Véglegesítés után a megosztás és PDF elérhető',!$('#offer-link').disabled&&!$('#print-quote').disabled&&tables.quote_versions.find(v=>v.id==='version').published_snapshot.total.net===3000);await click('#dialog-cancel');
 await click('#offer-link',()=>$('#form-dialog').open);check('Végleges ajánlat linkje újra elkészíthető',!!$('#generated-link'));await click('#dialog-cancel');
 check('Mobilméreten nincs vízszintes kilógás',document.documentElement.scrollWidth<=window.innerWidth);
 await click('#nav [data-view="quick"]',()=>visible('#quick-view'));check('A gyors ajánlat a belső menüből nyílik',!!document.querySelector('#quick-view [data-action="next"]')&&!visible('#quote-detail'));await click('#nav [data-view="start"]',()=>visible('#start-view'));
 check('Nincs váratlan JavaScript-hiba',errors.length===0);
}catch(error){failed++;report.textContent+='HIBA: '+error.stack+'\n';}
report.textContent+=`\nNézet: ${window.innerWidth} × ${window.innerHeight}\nEREDMÉNY: ${passed} sikeres, ${failed} hibás ellenőrzés.\nKizárólag elkülönített tesztadatok; éles írás és emailküldés nélkül.`;
report.dataset.failed=failed;
if(new URLSearchParams(location.search).has('preview')){report.hidden=true;$('#status').textContent='';await click('#nav [data-view="start"]',()=>visible('#start-view'));window.scrollTo({top:0,behavior:'instant'});await new Promise(requestAnimationFrame);await new Promise(requestAnimationFrame);}
