// Költségvetés 2026: csak számszerű adatok; a munkaleírás nem árazási adat.
export const HOURLY_RATE = 8500;
export const RULES = [
  ['maintenance_0','Zöldhulladék ömlesztett','m³',9000],
  ['maintenance_1','Zöldhulladék zsákos','zsák',1300],
  ['maintenance_2','Zöldhulladék big bag','db',null],
  ['maintenance_3','Növényvédelem','tartály (15L)',null,'spray'],
  ['maintenance_4','Lemosó permetezés','tartály (15L)',null,'wash'],
  ['maintenance_5','Bio permetezés','tartály (15L)',15000],
  ['maintenance_6','Gyomirtó','liter',1400],
  ['maintenance_7','Talajpermet','tartály (15L)',null,'spray'],
  ['maintenance_8','Fűmag','adagoló',6000],
  ['maintenance_9','Műtrágya általános','adagoló',6000],
  ['maintenance_10','Műtrágya mohairtó','adagoló',9000],
  ['maintenance_11','Műtrágya gyomirtó','adagoló',12000],
  ['maintenance_12','Marhatrágya 20L','zsák',1500],
  ['maintenance_13','Marhatrágya 50L','zsák',3000],
  ['maintenance_14','Termőföld 20L','zsák',1500],
  ['maintenance_15','Termőföld 40/50L','zsák',null],
  ['maintenance_16','Karó cserjének','db',null],
  ['maintenance_17','Karó fának','db',null],
  ['maintenance_18','Geotextília','m²',700],
  ['maintenance_19','Fatörzsvédő','db',900],
  ['maintenance_20','Öntözőrendszer anyagok','tétel',null],
  ['maintenance_21','Egyéb1','tétel',null],
  ['maintenance_22','Egyéb2','tétel',null],
  ['construction_0','Fuvarok száma','fuvar',null],
  ['construction_1','Fuvaronként megtett út','km',null],
  ['construction_2','Fuvarozás összes megtett út','km',null],
  ['construction_3','Földelszállítás','m³',8000,'earth'],
  ['construction_4','Szemét elszállítás','m³',null],
  ['construction_5','Termőföld','m³',null],
  ['construction_6','Murva/andezit teherhordó réteg','m³',null],
  ['construction_7','Murva/andezit ágyazó réteg','m³',null],
  ['construction_8','Kulé kavics','m³',null],
  ['construction_9','Homok','m³',null],
  ['construction_10','Beton C20 ömlesztett','m³',null],
  ['construction_11','Beton CKT ömlesztett','m³',null],
  ['construction_12','Sóder','m³',null],
  ['construction_13','Cement','25kg/db',null],
  ['construction_14','Beton kész zsákos','db',null],
  ['construction_15','Beton gyorsan kötő','db',null],
  ['construction_16','C20 beton ömlesztett','m³',null],
  ['construction_17','CKT beton ömlesztett','m³',null],
  ['construction_18','Raklap','db',null],
  ['construction_19','Egyéb1','tétel',null],
  ['construction_20','Egyéb2','tétel',null],
  ['construction_21','Egyéb3','tétel',null],
  ['construction_22','Egyéb4','tétel',null]
];
export function decimal(input) {
  const text=String(input??'').trim().replace(',', '.');
  if(!/^\d+(?:\.\d+)?$/.test(text))return null;
  const n=Number(text);return Number.isFinite(n)&&n<=1000000?n:null;
}
function minutes(input) {
  const m=/^(\d{1,2}):(\d{2})(?::00)?$/.exec(String(input??''));
  return m&&Number(m[1])<24&&Number(m[2])<60?Number(m[1])*60+Number(m[2]):null;
}
const filled=value=>value!==null&&value!==undefined&&String(value).trim()!=='';
export function tierPrice(quantity,kind) {
  if(quantity===0)return 0;
  if(!Number.isInteger(quantity)||quantity<0) return null;
  const [first,next,later]=kind==='wash'?[20000,12000,7000]:[25000,17000,12000];
  return first+Math.min(quantity-1,3)*next+Math.max(quantity-4,0)*later;
}
export function calculateWorksheet(row) {
  const data=row.form_data??row.data??{}, lines=[], issues=[];let personMinutes=0;
  for(let i=1;i<=5;i++){
    const size=data[`team_${i}_size`],from=data[`team_${i}_arrival`],to=data[`team_${i}_departure`];
    if(!filled(size)&&!filled(from)&&!filled(to))continue;
    const n=decimal(size),a=minutes(from),b=minutes(to);
    if(n===0&&(!filled(from)||a===0)&&(!filled(to)||b===0))continue;
    if(n===null||!Number.isInteger(n)||n<=0||n>1000||a===null||b===null||b<=a){issues.push(`Csapat ${i}: hiányos vagy hibás létszám/munkaidő.`);continue;}
    const count=n*(b-a);personMinutes+=count;
    lines.push({code:`team_${i}`,name:`Csapat ${i}`,quantity:count/60,unit:'főóra',unit_price:HOURLY_RATE,amount:count*HOURLY_RATE/60,kind:'labor'});
  }
  if(!lines.length&&!issues.length)issues.push('Nincs megadott munkaidő.');
  for(const [code,name,unit,price,rule] of RULES){
    if(!filled(data[code]))continue;
    const quantity=decimal(data[code]);if(quantity===0)continue;
    let amount=null;
    if(quantity!==null){if(rule==='earth')amount=quantity*8000;else if(rule==='spray'||rule==='wash')amount=tierPrice(quantity,rule);else if(price!==null)amount=quantity*price;}
    if(amount===null)issues.push(`${name}: ${quantity===null?'a mennyiség nem számszerű':'az ár vagy az árazási szabály hiányzik'}.`);
    lines.push({code,name,quantity,raw_value:String(data[code]),unit,unit_price:price,amount,kind:'item',rule:rule??'linear'});
    if(rule==='earth'&&quantity!==null)lines.push({code:'earth_transport',name:'Földelszállítás egyszeri szállítási díja',quantity:1,unit:'alkalom',unit_price:10000,amount:10000,kind:'item',rule:'fixed'});
  }
  for(const code of ['subcontractor','rental1','rental2','rental3'])if(filled(data[code])){
    const name=code==='subcontractor'?'Alvállalkozó':'Gépbérlés';issues.push(`${name}: árazás szükséges.`);
    lines.push({code,name,raw_value:String(data[code]),quantity:null,unit:'tétel',unit_price:null,amount:null,kind:'item'});
  }
  const labor=personMinutes*HOURLY_RATE/60;
  const knownTotal=lines.reduce((sum,line)=>sum+(line.amount??0),0);
  return {person_minutes:personMinutes,person_hours:personMinutes/60,labor,known_total:knownTotal,total:issues.length?null:knownTotal,complete:issues.length===0,lines,issues};
}
export function calculateProject(worksheets,laborBudget){
  // A source UUID is one worksheet: corrections replace, never add a second day.
  const unique=new Map();for(const row of worksheets){const old=unique.get(row.id);if(!old||String(row.updated_at??'')>=String(old.updated_at??''))unique.set(row.id,row);}
  const results=[...unique.values()].map(calculateWorksheet),issues=results.flatMap(r=>r.issues);
  const personHours=results.reduce((sum,r)=>sum+r.person_hours,0),labor=personHours*HOURLY_RATE;
  const budget=typeof laborBudget==='number'&&Number.isFinite(laborBudget)&&laborBudget>=0?laborBudget:null;
  return {person_hours:personHours,labor,budget_hours:budget===null?null:budget/HOURLY_RATE,remaining_hours:budget===null?null:budget/HOURLY_RATE-personHours,used_percent:budget>0?labor/budget*100:null,known_total:results.reduce((sum,r)=>sum+r.known_total,0),complete:!issues.length,issues,worksheets:results};
}
