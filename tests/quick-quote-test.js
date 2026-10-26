import { mountQuickQuote } from '../js/modules/quick-quote.js';
import { measuredQuantity,measuredItem,validateQuickQuote,blankQuickQuote,unitKind } from '../js/modules/quick-quote-model.js';
import { calculateTotal } from '../js/modules/quote-calculator.js';
const root=document.querySelector('#quick-view'),report=document.querySelector('#results'),$=s=>root.querySelector(s),records=new Map();
let passed=0,failed=0,promoted=0,created=0,failSave=false,errors=[];
window.addEventListener('error',e=>errors.push(e.message));window.addEventListener('unhandledrejection',e=>errors.push(String(e.reason)));
const check=(name,value)=>{report.textContent+=(value?'OK: ':'HIBA: ')+name+'\n';value?passed++:failed++;};
async function wait(test){for(let i=0;i<400;i++){if(test())return;await new Promise(r=>setTimeout(r,10));}throw Error('Várakozás sikertelen: '+test);}
async function click(s,test){await wait(()=>!root.inert);$(s).click();if(test)await wait(test);else await new Promise(r=>setTimeout(r,20));}
function input(path,value){const el=$(`[data-field="${path}"]`);if(el.type==='checkbox')el.checked=value;else el.value=value;el.dispatchEvent(new Event('input',{bubbles:true}));el.dispatchEvent(new Event('change',{bubbles:true}));}
const customers=[{id:'customer',name:'Teszt Ügyfél',source_customer_id:'shared',project_address:'Kert utca 1.',email:'teszt@example.org'}];
const catalog=[{id:'hours',category:'Kertépítés',subcategory:'Óradíj',unit1:'óra',unit2:'fő',material_unit:0,labor_unit:8500},{id:'area',category:'Kertépítés',subcategory:'Gyepesítés',unit1:'m²',material_unit:1000,labor_unit:500},{id:'volume',category:'Kertépítés',subcategory:'Földmunka',unit1:'m³',material_unit:8000,labor_unit:1000},{id:'length',category:'Kertépítés',subcategory:'Szegély',unit1:'fm',material_unit:2000,labor_unit:500}];
const rpc=async(name,args)=>{
 if(failSave)throw Error('Teszt mentési hiba');
 if(name==='quote_quick_save'){const old=records.get(args.p_id);if(old&&old.revision!==args.p_revision&&JSON.stringify(old.payload)!==JSON.stringify(args.p_payload))throw Error('Elavult mentés');const record={id:args.p_id,number:'GY-TESZT-'+args.p_id.slice(0,8),revision:(old?.revision||0)+1,payload:structuredClone(args.p_payload),promoted_quote_id:old?.promoted_quote_id||null};records.set(record.id,record);return structuredClone(record);}
 if(name==='quote_quick_promote'){const r=records.get(args.p_id);if(!r.promoted_quote_id){r.promoted_quote_id='full-quote';promoted++;}return r.promoted_quote_id;}
 throw Error('Váratlan RPC: '+name);
};
const app=mountQuickQuote(root,{data:()=>({customers,projects:[],catalog,templates:[{id:'template',name:'Minta'}],templateItems:async()=>[{catalog_id:'length',position:1}],loadPlants:async()=>[{id:'plant',name:'Talajtakaró tesztnövény',sku:'N-1',sale_net:null,purchase_net:500,sale_price_placeholder:true}],listDrafts:async()=>[...records.values()].map(d=>structuredClone(d)),loadDraft:async id=>structuredClone(records.get(id))}),rpc,onCreateCustomer:async p=>{created++;return {id:'customer',...p.customer};},onPromoted:async()=>{}});
try{
 check('m, fm, m² és m³ felismerése',unitKind('m')==='length'&&unitKind('fm')==='length'&&unitKind('m²')==='area'&&unitKind('m^3')==='volume');
 check('m² hosszúság × szélesség',measuredQuantity({mode:'area',length:5,width:4})===20);
 check('m³ hosszúság × szélesség × magasság',measuredQuantity({mode:'volume',length:5,width:4,height:.5})===10);
 check('Hiányos mérésnél használható kézi mennyiség',measuredQuantity({mode:'area',length:5,width:'',quantity:7})===7);
 check('Sövény két végén 21 darab',measuredQuantity({mode:'hedge',length:10,spacing_cm:50,both_ends:true})===21);
 check('Sövény végpont-pipa nélkül 20 darab',measuredQuantity({mode:'hedge',length:10,spacing_cm:50,both_ends:false})===20);
 for(const [density,expected] of [[0,0],[50,30],[100,60],[125,75],[200,120]])check('Talajtakaró '+density+'%',measuredQuantity({mode:'groundcover',area_m2:10,density_percent:density})===expected);
 check('Talajtakaró számítása méretekből',measuredQuantity({mode:'groundcover',use_dimensions:true,length:5,width:2,density_percent:100})===60);
 check('Tört növényszám felfelé kerekítve',measuredQuantity({mode:'groundcover',area_m2:1,density_percent:25})===2);
 let rejected=false;try{measuredQuantity({mode:'groundcover',area_m2:10,density_percent:201});}catch{rejected=true;}check('200% feletti sűrűség hibát jelez',rejected);
 check('Üres mezők nem kötelezők a gyors PDF-hez',validateQuickQuote(blankQuickQuote()).gross===0);
 await app.open();await click('[data-action="next"]',()=>!!$('[data-action="add-item"]'));
 check('Név és cím nélkül is továbblép',root.querySelector('[data-step="1"]').getAttribute('aria-expanded')==='true');
 await click('[data-action="add-item"]');input('edit.catalog_id','hours');input('edit.measurement.mode','hedge');const rateProtected=$('[data-field="edit.material_unit"]').value==='1'&&$('[data-field="edit.material_unit"]').classList.contains('price-placeholder');input('edit.catalog_id','area');input('edit.measurement.length','5');input('edit.measurement.width','4');
 check('Mérés azonnali mennyiséget és árat ad',$('[data-measured-result]').textContent.includes('20 m²')&&$('[data-measured-result]').textContent.includes('30'));
 await click('[data-action="commit-item"]',()=>!$('.quick-editor'));check('Árlista eredeti anyag- és munkadíja megmarad',[...records.values()].at(-1).payload.items[0].material_unit===1000&&[...records.values()].at(-1).payload.items[0].labor_unit===500&&rateProtected);
 await click('[data-action="add-plant"]',()=>!!$('[data-field="edit.plant_id"]'));input('edit.plant_id','plant');input('edit.measurement.mode','hedge');input('edit.measurement.length','10');input('edit.measurement.spacing_cm','50');input('edit.measurement.both_ends',false);
 check('Sövény pipa azonnal váltható',$('[data-measured-result]').textContent.includes('20 db'));input('edit.measurement.both_ends',true);input('edit.material_unit','900');input('edit.price_confirmed',true);await click('[data-action="commit-item"]',()=>!$('.quick-editor'));
 const hedge=[...records.values()].at(-1).payload.items[1];check('Növény ára, darabszáma és mérési adatai mentve',hedge.quantity1===21&&hedge.material_unit===900&&hedge.measurement.spacing_cm==='50'&&!hedge.pricing_required);
 await click('[data-action="add-item"]');input('edit.name','Talajtakaró');input('edit.material_unit','1000');input('edit.measurement.mode','groundcover');input('edit.measurement.area_m2','10');input('edit.measurement.density_percent','125');await click('[data-action="commit-item"]',()=>!$('.quick-editor'));
 check('125%-os talajtakaró 75 darabbal mentve',[...records.values()].at(-1).payload.items[2].quantity1===75);
 await click('[data-action="template"]',()=>$('.quick-items').children.length===4);check('Sablon a meglévő árlistából tölti az árat',[...records.values()].at(-1).payload.items[3].material_unit===2000);
 await click('[data-action="next"]',()=>!!$('[data-field="terms"]'));input('terms','Magyar ékezetek: árvíztűrő tükörfúrógép.');await click('[data-action="back"]',()=>!!$('[data-action="add-item"]'));
 await click('[data-edit="'+hedge.id+'"]');check('Visszalépéskor a mérések megmaradnak',$('[data-field="edit.measurement.length"]').value==='10'&&$('[data-field="edit.measurement.both_ends"]').checked);await click('[data-action="cancel-item"]');
 await click('[data-step="3"]',()=>!!$('[data-action="download"]'));await wait(()=>!$('[data-action="download"]').disabled);check('Valódi PDF név és cím nélkül is elkészül',!$('[data-action="download"]').disabled);
 $('[data-promote]').checked=true;$('[data-promote]').dispatchEvent(new Event('change',{bubbles:true}));await click('[data-action="promote"]');check('Ügyfél nélkül csak az átvétel kér ügyfelet, a PDF elérhető',promoted===0&&$('[data-quick-status]').textContent.includes('ügyfelet')&&!$('[data-action="download"]').disabled);
 await click('[data-step="0"]',()=>!!$('[data-quick-customer-search]'));const search=$('[data-quick-customer-search]');search.focus();search.value='Te';search.dispatchEvent(new Event('input'));await click('#quick-customer-results button',()=>!!$('.quick-chosen'));input('title','Nyári kert – sövény és talajtakaró');
 await click('[data-step="3"]',()=>!!$('[data-action="download"]'));await wait(()=>!$('[data-action="download"]').disabled);check('Egyetlen lépés nyitott és nincs vízszintes kilógás',root.querySelectorAll('[aria-expanded="true"][data-step]').length===1&&document.documentElement.scrollWidth<=window.innerWidth);
 const record=structuredClone([...records.values()].at(-1)),{quickQuotePdf}=await import('../js/modules/quick-quote-pdf.js');
 const short=await quickQuotePdf(record);check('PDF fájl valódi PDF és ékezetes címmel készül',short.type==='application/pdf'&&(await short.text()).startsWith('%PDF-'));
 const many=structuredClone(record);many.number='GY-TESZT-TÖBBOLDALAS';many.payload.items=Array.from({length:50},(_,i)=>({...record.payload.items[i%4],name:'Tétel '+(i+1)+' – árvíztűrő növény',main_item:i<25?'Első főtétel':'Második főtétel'}));many.payload.terms='Feltételek: '+('Minden növény és munkadíj egyeztetés szerint. '.repeat(100));
 const long=await quickQuotePdf(many);
 if(new URLSearchParams(location.search).has('capture')){await fetch('/__quick_pdf__/short',{method:'POST',body:short});await fetch('/__quick_pdf__/long',{method:'POST',body:long});}
 failSave=true;await click('[data-step="0"]');input('title','Mentés hiba');await click('[data-action="next"]');check('Mentési hiba esetén nem lép tovább',$('[data-step="0"]').getAttribute('aria-expanded')==='true'&&$('[data-quick-status]').textContent.includes('mentési hiba'));failSave=false;
 await click('[data-step="3"]',()=>!!$('[data-action="download"]'));$('[data-promote]').checked=true;$('[data-promote]').dispatchEvent(new Event('change',{bubbles:true}));await click('[data-action="promote"]');check('Pipával átvehető, a gyors másolat megmarad',promoted===1&&[...records.values()].at(-1).promoted_quote_id==='full-quote');
 check('A közös számítás változatlan',calculateTotal(record.payload.items).net===126400);
 await click('[data-action="new"]',()=>!!$('[data-action="new-customer"]'));await click('[data-action="new-customer"]');input('customer.name','Új tesztügyfél');await click('[data-step="3"]',()=>!!$('[data-action="download"]'));$('[data-promote]').checked=true;$('[data-promote]').dispatchEvent(new Event('change',{bubbles:true}));await click('[data-action="promote"]');check('Megadott névből átvételkor automatikusan ügyfél készül',created===1&&promoted===2&&[...records.values()].at(-1).payload.client_id==='customer');
 check('Nincs váratlan JavaScript-hiba',errors.length===0);
}catch(error){failed++;report.textContent+='HIBA: '+error.stack+'\n';}
report.textContent+=`\nEREDMÉNY: ${passed} sikeres, ${failed} hibás. Nézet: ${window.innerWidth}px.\nKizárólag elkülönített, memóriában tárolt tesztadatok.`;report.dataset.failed=failed;
if(new URLSearchParams(location.search).has('preview')){report.hidden=true;const preview=structuredClone([...records.values()].find(r=>r.payload.items.length>=3));preview.id='preview';preview.promoted_quote_id=null;records.set(preview.id,preview);await app.open();await click('[data-load="preview"]');await click('[data-step="1"]');await click('[data-edit="'+preview.payload.items[2].id+'"]');window.scrollTo(0,0);}
