import {decimal} from './worksheet-calculator.js';
// Completion is weighted by the accepted item labor amount, never by free text.
export function calculateProgress(items=[],settings=[],records=[]){
  const saved=new Map(settings.map(s=>[s.item_id,s]));
  const unique=new Map();
  for(const r of records){const old=unique.get(r.id);if(!old||String(r.updated_at)>=String(old.updated_at))unique.set(r.id,r);}
  const lines=items.filter(i=>Number(i.labor_unit)>0&&Number(i.quantity1)*(i.unit2?Number(i.quantity2):1)>0).map(item=>{
    const setting=saved.get(item.id),planned=Number(item.quantity1)*(item.unit2?Number(item.quantity2):1);
    let completed=null,invalid=false;
    if(setting?.override_completed!==null&&setting?.override_completed!==undefined)completed=Number(setting.override_completed);
    else if(setting?.source_code){
      completed=0;
      for(const row of unique.values()){
        const raw=row.form_data?.[setting.source_code];
        if(raw===undefined||raw===null||String(raw).trim()==='')continue;
        const n=decimal(raw);if(n===null){invalid=true;break;}completed+=n;
      }
      if(invalid)completed=null;
    }
    const weight=planned*Number(item.labor_unit);
    return {item,setting,planned,completed,weight,percent:completed===null||planned<=0?null:Math.min(100,completed/planned*100),invalid};
  });
  const total=lines.reduce((s,l)=>s+l.weight,0),known=lines.filter(l=>l.percent!==null);
  const knownWeight=known.reduce((s,l)=>s+l.weight,0);
  return {lines,percent:total>0&&known.length===lines.length?known.reduce((s,l)=>s+l.weight*l.percent,0)/total:null,
    coverage:total>0?knownWeight/total*100:0,missing:lines.filter(l=>l.percent===null).length};
}
