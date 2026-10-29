import { DEFAULT_INFORMATION } from './terms-templates.js?v=55';
import { calculateTotal } from './quote-calculator.js?v=47';

export const blankQuickQuote = () => ({client_id:null, customer:{name:'',email:'',phone:''},address:'',title:'',quote_vat_rate:0,items:[],terms:DEFAULT_INFORMATION,valid_until:'',issued_on:new Intl.DateTimeFormat('sv-SE',{timeZone:'Europe/Budapest'}).format(new Date()),issuer:{name:'Díszkertek',address:'',tax_number:'',email:'info@diszkertek.hu',phone:'+36 70 634 9630'}});
const round = (n,places=3) => {const value=Number(n),factor=10**places;return Math.round((value+Number.EPSILON*Math.max(1,Math.abs(value)))*factor)/factor;};
const number = (v,label) => {const n=Number(String(v??'').replace(',','.'));if(!Number.isFinite(n)||n<0)throw Error(`Ellenőrizd: ${label}.`);return n;};
const missing=v=>v===null||v===undefined||String(v).trim()==='';
function complete(m){if(m.mode==='groundcover')return m.use_dimensions?!missing(m.length)&&!missing(m.width):!missing(m.area_m2);return !missing(m.length)&&(!['area','volume'].includes(m.mode)||!missing(m.width))&&(m.mode!=='volume'||!missing(m.height))&&(m.mode!=='hedge'||!missing(m.spacing_cm));}
export function unitKind(unit){const normalized=String(unit||'').trim().toLowerCase().replaceAll('³','3').replaceAll('²','2').replaceAll('^','').replaceAll(' ', '');return ({m:'length',fm:'length',m2:'area',m3:'volume'})[normalized]||'quantity';}
export function measuredQuantity(measurement){
 const base=baseMeasuredQuantity(measurement);if(!['length','area','volume'].includes(measurement?.mode))return round(base);const percent=number(measurement?.allowance_percent??0,'ráhagyás');
 if(percent>200)throw Error('A ráhagyás 0 és 200% között lehet.');
 return round(base*(1+percent/100));
}
function baseMeasuredQuantity(measurement){
 const m=measurement||{},mode=m.mode||'quantity';
 if(mode==='worktime')return round(number(m.hours??m.quantity??1,'munkaóra'));
 if(mode==='quantity')return round(number(m.quantity??1,'mennyiség'));
 const fallback=()=>round(number(m.quantity??1,'kézzel megadott mennyiség'));
 if(mode==='groundcover'){
  const area=m.use_dimensions&&m.length!==''&&m.width!==''?number(m.length,'hosszúság')*number(m.width,'szélesség'):number(m.area_m2,'terület');
  const density=number(m.density_percent===''?100:m.density_percent??100,'sűrűség');if(density>200)throw Error('A sűrűség 0 és 200% között lehet.');
  if(!complete(m))return fallback();
  return Math.ceil(Math.max(0,area*6*density/100-1e-9));
 }
 if(!complete(m))return fallback();
 const length=number(m.length,'hosszúság');
 if(mode==='hedge'){const spacing=number(m.spacing_cm,'ültetési tőtávolság')/100;if(spacing===0)throw Error('A tőtávolság legyen nagyobb nullánál, vagy hagyd üresen a kézi mennyiséghez.');return Math.ceil(Math.max(0,length/spacing-1e-9))+(m.both_ends!==false?1:0);}
 if(mode==='length')return length;
 const width=number(m.width,'szélesség');
 if(mode==='area')return length*width;
 if(mode==='volume')return length*width*number(m.height,'magasság / mélység');
 throw Error('Ismeretlen mérési mód.');
}
export function measuredItem(draft){
 const item={...draft,measurement:{...draft.measurement}};
 if(draft.pending)item.pending={...draft.pending};
 for(const [field,key] of [['material_unit','material'],['labor_unit','labor'],['charge_unit','charge']]){
  if(item[field]===''||(draft.pricing_required&&Number(item[field])===1))item.pending={...item.pending,[key]:true};
 }
 if(item.measurement.quantity===''&&(!complete(item.measurement)||item.measurement.mode==='quantity'))item.pending={...item.pending,quantity:true};
 item.name=String(item.name||'').trim()||'Egyedi tétel';item.quantity1=item.pending?.quantity?0:measuredQuantity(item.measurement);
 if(item.measurement.mode==='worktime'){
  item.unit1='óra';item.unit2='fő';
  item.quantity2=round(number(item.measurement.people??1,'létszám'));
  item.material_unit=0;item.labor_unit=8500;
 }
 if(item.unit2){item.quantity2=round(number(item.quantity2,'második mennyiség'));}else item.quantity2=null;
 if(['transport','total'].includes(item.cost_kind)){
  item.material_unit=0;item.labor_unit=0;
  if(item.charge_unit!==undefined){item.charge_unit=round(number(item.charge_unit,'egységdíj'),2);item.other_cost=round(item.charge_unit*item.quantity1*(item.unit2?item.quantity2:1),2);}
  if(item.pending?.charge)item.other_cost=1;
 }else{
  if(item.pending?.material)item.material_unit=1;
  if(item.pending?.labor)item.labor_unit=1;
 }
 if(item.pending)item.pricing_required=Object.values(item.pending).some(Boolean);
 for(const key of ['material_unit','labor_unit','other_cost','vat_rate']){const n=Number(String(item[key]??0).replace(',','.'));if(!Number.isFinite(n)||n<0)throw Error('Az árak és az ÁFA nem lehetnek negatívak.');item[key]=round(n,key==='vat_rate'?4:2);}
 if(item.vat_rate>1)throw Error('Az ÁFA 0 és 100% között lehet.');
 if(item.quantity1<0||item.quantity1>1e8||[item.material_unit,item.labor_unit,item.other_cost].some(v=>v>1e9))throw Error('Ellenőrizd a mennyiséget és az árakat.');
 return item;
}
export function validateQuickQuote(payload,forPromotion=false){
 if(forPromotion&&!payload.client_id)throw Error('A teljes ajánlatkezeléshez válassz ügyfelet, vagy vedd fel az új ügyfelet az első lépésben.');
 if(payload.items.length>200)throw Error('Egy gyors ajánlat legfeljebb 200 tételt tartalmazhat.');
 payload.items.forEach(measuredItem);
 if(payload.items.some(itemIncomplete))throw Error('Pontosítandó tételek vannak: add meg a hiányzó mennyiségeket és árakat.');
 return calculateTotal(payload.items);
}
export function itemIncomplete(item){return Boolean(item.pricing_required||Object.values(item.pending||{}).some(Boolean));}
export function quoteVatRate(items,fallback=0){const rates=[...new Set(items.map(i=>Number(i.vat_rate||0)))];return rates.length>1?null:rates.length?rates[0]:fallback;}
export function quickTotals(items){return {...calculateTotal(items.filter(i=>!itemIncomplete(i))),pendingCount:items.filter(itemIncomplete).length};}
// Only customer-visible fields enter a published snapshot. Never copy internal notes.
export function publicPdfItems(items,quickItems=[]){return items.map((item,index)=>{
 const linked=quickItems.find(q=>q.full_item_id===item.id||q.id===item.id)||quickItems[index];
 const same=linked&&[linked.main_item,linked.name].filter(Boolean).join(' / ')===item.name;
 const measured=same&&Number(linked.quantity1)===Number(item.quantity1)&&linked.unit1===item.unit1&&Number(linked.quantity2||0)===Number(item.quantity2||0)&&String(linked.unit2||'')===String(item.unit2||'');
 return {name:same?linked.name:item.name,main_item:same?linked.main_item||'':'',description:item.description||'',category:item.category||'',quantity1:item.quantity1,unit1:item.unit1||'',quantity2:item.quantity2,unit2:item.unit2||'',material_unit:item.material_unit,labor_unit:item.labor_unit,other_cost:item.other_cost||0,vat_rate:item.vat_rate||0,calculation_rule:item.calculation_rule||{type:'linear'},pricing_required:Boolean(item.pricing_required),public_note:item.public_note||'',measurement:measured?linked.measurement:{mode:'quantity',quantity:item.quantity1},...(!Number(item.material_unit)&&!Number(item.labor_unit)&&same&&['transport','total'].includes(linked.cost_kind)?{cost_kind:linked.cost_kind}:{} )};
});}
export function editQuickItem(item){
 const draft=structuredClone(item);
 if(['transport','total'].includes(draft.cost_kind)&&(Number(draft.material_unit)||Number(draft.labor_unit))){delete draft.cost_kind;delete draft.charge_unit;}
 draft.measurement??={mode:'quantity',quantity:item.quantity1??1};
 if(!draft.pending&&draft.pricing_required)draft.pending={material:Number(draft.material_unit)===1,labor:Number(draft.labor_unit)===1};
 if(draft.pending&&!Object.values(draft.pending).some(Boolean)&&draft.pricing_required)draft.pending.material=true;
 if(['transport','total'].includes(draft.cost_kind)){
  const multiplier=Number(draft.quantity1)*(draft.unit2?Number(draft.quantity2):1);
  const stored=Number(draft.charge_unit);
  if(!Number.isFinite(stored)||round(stored*multiplier,2)!==Number(draft.other_cost))draft.charge_unit=multiplier>0?round(Number(draft.other_cost||0)/multiplier,2):0;
 }
 return draft;
}
export function measurementText(item){const value=baseMeasurementText(item);return value+(['length','area','volume'].includes(item.measurement?.mode)&&Number(item.measurement?.allowance_percent)>0?` · ${item.measurement.allowance_percent}% ráhagyás`: "");}
function baseMeasurementText(item){const m=item.measurement;if(!m||m.mode==='quantity')return '';if(m.mode==='worktime')return `${m.people??item.quantity2??1} fő × ${m.hours??item.quantity1??0} óra × 8 500 Ft/fő/óra`;if(!complete(m))return '';if(m.mode==='groundcover')return `${m.use_dimensions?[m.length,m.width].join(' × ')+' m':m.area_m2+' m²'} · ${m.density_percent===''?100:m.density_percent??100}% · 100% = 6 db/m²`;if(m.mode==='hedge')return `${m.length} m · ${m.spacing_cm} cm tőtávolság${m.both_ends!==false?' · mindkét végén növénnyel':''}`;return [m.length,...(m.mode==='area'||m.mode==='volume'?[m.width]:[]),...(m.mode==='volume'?[m.height]:[])].join(' × ')+' m';}
