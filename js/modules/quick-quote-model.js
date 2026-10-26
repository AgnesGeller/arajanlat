import { calculateTotal } from './quote-calculator.js';

export const blankQuickQuote = () => ({client_id:null, customer:{name:'',email:'',phone:''},address:'',title:'',items:[],terms:'',valid_until:'',issued_on:new Intl.DateTimeFormat('sv-SE',{timeZone:'Europe/Budapest'}).format(new Date()),issuer:{name:'Díszkertek',address:'',tax_number:'',email:'info@diszkertek.hu',phone:'+36 70 634 9630'}});
const round = (n,places=3) => Number(Number(n).toFixed(places));
const number = (v,label) => {const n=Number(String(v??'').replace(',','.'));if(!Number.isFinite(n)||n<0)throw Error(`Ellenőrizd: ${label}.`);return n;};
const missing=v=>v===null||v===undefined||String(v).trim()==='';
function complete(m){if(m.mode==='groundcover')return m.use_dimensions?!missing(m.length)&&!missing(m.width):!missing(m.area_m2);return !missing(m.length)&&(!['area','volume'].includes(m.mode)||!missing(m.width))&&(m.mode!=='volume'||!missing(m.height))&&(m.mode!=='hedge'||!missing(m.spacing_cm));}
export function unitKind(unit){const normalized=String(unit||'').trim().toLowerCase().replaceAll('³','3').replaceAll('²','2').replaceAll('^','').replaceAll(' ', '');return ({m:'length',fm:'length',m2:'area',m3:'volume'})[normalized]||'quantity';}
export function measuredQuantity(measurement){
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
 if(mode==='length')return round(length);
 const width=number(m.width,'szélesség');
 if(mode==='area')return round(length*width);
 if(mode==='volume')return round(length*width*number(m.height,'magasság / mélység'));
 throw Error('Ismeretlen mérési mód.');
}
export function measuredItem(draft){
 const item={...draft,measurement:{...draft.measurement}};
 item.name=String(item.name||'').trim()||'Egyedi tétel';item.quantity1=measuredQuantity(item.measurement);
 if(item.measurement.mode==='worktime'){
  item.unit1='óra';item.unit2='fő';
  item.quantity2=round(number(item.measurement.people??1,'létszám'));
  item.material_unit=0;item.labor_unit=8500;
 }
 if(item.unit2){item.quantity2=round(number(item.quantity2,'második mennyiség'));}else item.quantity2=null;
 for(const key of ['material_unit','labor_unit','other_cost','vat_rate']){const n=Number(String(item[key]??0).replace(',','.'));if(!Number.isFinite(n)||n<0)throw Error('Az árak és az ÁFA nem lehetnek negatívak.');item[key]=round(n,key==='vat_rate'?4:2);}
 if(item.vat_rate>1)throw Error('Az ÁFA 0 és 100% között lehet.');
 if(item.quantity1<0||item.quantity1>1e8||[item.material_unit,item.labor_unit,item.other_cost].some(v=>v>1e9))throw Error('Ellenőrizd a mennyiséget és az árakat.');
 return item;
}
export function validateQuickQuote(payload,forPromotion=false){
 if(forPromotion&&!payload.client_id)throw Error('A teljes ajánlatkezeléshez válassz ügyfelet, vagy vedd fel az új ügyfelet az első lépésben.');
 if(payload.items.length>200)throw Error('Egy gyors ajánlat legfeljebb 200 tételt tartalmazhat.');
 payload.items.forEach(measuredItem);
 if(payload.items.some(i=>i.pricing_required))throw Error('A piros 1 Ft-os jelzésnél add meg és ellenőrizd a tényleges eladási árat.');
 return calculateTotal(payload.items);
}
export function measurementText(item){const m=item.measurement;if(!m||m.mode==='quantity')return '';if(m.mode==='worktime')return `${m.people??item.quantity2??1} fő × ${m.hours??item.quantity1??0} óra × 8 500 Ft/fő/óra`;if(!complete(m))return '';if(m.mode==='groundcover')return `${m.use_dimensions?[m.length,m.width].join(' × ')+' m':m.area_m2+' m²'} · ${m.density_percent===''?100:m.density_percent??100}% · 100% = 6 db/m²`;if(m.mode==='hedge')return `${m.length} m · ${m.spacing_cm} cm tőtávolság${m.both_ends!==false?' · mindkét végén növénnyel':''}`;return [m.length,...(m.mode==='area'||m.mode==='volume'?[m.width]:[]),...(m.mode==='volume'?[m.height]:[])].join(' × ')+' m';}
