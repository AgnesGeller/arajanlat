import { measuredItem, unitKind } from './quick-quote-model.js?v=58';

export const quantityUnits=['db','zsák','fuvar','liter','kg','t','óra','fő','alkalom','csomag','m','fm','m²','m³'];
const absent=value=>value===null||value===undefined||String(value).trim()==='';
export const sameUnit=(a,b)=>{const normalize=v=>{const key=String(v||'').normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLowerCase().replace(/[\s^]/g,'').replaceAll('²','2').replaceAll('³','3');return ({darab:'db',fm:'m',folyometer:'m',l:'liter',h:'ora',tonna:'t'})[key]||key;};return Boolean(normalize(a))&&normalize(a)===normalize(b);};

export function normalizeGroups(payload) {
 payload.groups ??= [];
 if(!Array.isArray(payload.groups))throw Error('A főtételek adatai nem olvashatók. Nyisd meg újra a mentett ajánlatot.');
 const seen=new Set();for(const group of payload.groups){const old=group.id;if(!/^[a-zA-Z0-9_-]{1,80}$/.test(String(old||''))||seen.has(old)){group.id=crypto.randomUUID();for(const item of payload.items)if(item.group_id===old)item.group_id=group.id;}seen.add(group.id);}
 for (const item of payload.items) {
  let group=payload.groups.find(g=>g.id===item.group_id);
  if(!group&&item.main_item)group=payload.groups.find(g=>g.name===item.main_item);
  if(!group&&item.main_item){group={id:crypto.randomUUID(),name:item.main_item,length:'',width:'',height:''};payload.groups.push(group);}
  if(group){item.group_id=group.id;item.main_item=group.name;}
 }
 return payload.groups;
}
export function inheritGroup(item,group) {
 if(!group||item.measurement?.use_group!==true)return item;
 const m={...item.measurement};
 const missingQuantity=reason=>({...item,group_id:group.id,main_item:group.name,measurement:{...m,group_error:reason,quantity:''},pending:{...item.pending,quantity:true}});
 delete m.group_error;
 if(group.measurement_type==='quantity'){
  if(!sameUnit(group.unit,item.unit1))return missingQuantity('A főtétel és az altétel mértékegysége eltér. Kapcsold ki az átvételt, és add meg a tétel saját mennyiségét.');
  return {...item,group_id:group.id,main_item:group.name,measurement:{...m,mode:'quantity',quantity:group.quantity??''},pending:{...item.pending,quantity:absent(group.quantity)}};
 }
 if(group.measurement_type==='worktime'){
  if(!sameUnit(item.unit1,'óra')||!sameUnit(item.unit2,'fő'))return missingQuantity('A főtétel létszám × óra mennyiségét csak óra × fő mértékegységű sor veheti át. Más tételnél kapcsold ki az átvételt.');
  return {...item,group_id:group.id,main_item:group.name,quantity2:group.people??0,measurement:{...m,mode:m.mode==='worktime'?'worktime':'quantity',quantity:group.hours??'',hours:group.hours??'',people:group.people??''},pending:{...item.pending,quantity:absent(group.hours)||absent(group.people)}};
 }
 const mode=m.mode==='quantity'?unitKind(item.unit1):m.mode;
 if(!['length','area','volume','hedge','groundcover'].includes(mode))return missingQuantity('Ehhez a mértékegységhez nincs átvehető méret. Kapcsold ki az átvételt, és add meg külön a mennyiséget.');
 m.mode=mode;
 m.length=group.length??'';
 if(['area','volume','groundcover'].includes(mode))m.width=group.width??'';
 const secondaryLength=['cm','mm'].includes(String(item.unit2||'').trim().toLowerCase());
 if((mode==='volume'||secondaryLength)&&!m.custom_height)m.height=group.height??'';
 if(mode==='groundcover'){m.use_dimensions=true;m.area_m2='';}
 const required=['length',...(['area','volume','groundcover'].includes(mode)?['width']:[]),...(mode==='volume'||secondaryLength?['height']:[])];
 const missingDimension=required.some(k=>absent(m[k]));
 return {...item,...(secondaryLength?{quantity2:Number(m.height||0)*(String(item.unit2).trim().toLowerCase()==='cm'?100:1000)}:{}),group_id:group.id,main_item:group.name,measurement:m,pending:{...item.pending,quantity:missingDimension}};
}
export function updateGroup(payload,id,changes) {
 const group=payload.groups.find(g=>g.id===id);if(!group)throw Error('A főtétel nem található.');
 const next={...group,...changes};if(changes.measurement_type==='quantity'&&absent(next.unit))next.unit='db';
 if(!['dimensions','quantity','length','area','volume','worktime'].includes(next.measurement_type||'dimensions'))throw Error('Válassz mennyiségi típust.');
 if(String(next.unit||'').length>40)throw Error('A mértékegység legfeljebb 40 karakter lehet.');
 for(const key of ['length','width','height','quantity','people','hours'])if(!absent(next[key])&&(!Number.isFinite(Number(next[key]))||Number(next[key])<0||Number(next[key])>1e6))throw Error('A főtétel mennyisége vagy mérete nem megfelelő.');
 const items=payload.items.map(item=>item.group_id===id?measuredItem(inheritGroup({...item,main_item:next.name},next)):item);
 Object.assign(group,next);payload.items=items;return group;
}
export function orderedGroupItems(payload){
 const used=new Set(),items=[];
 for(const group of payload.groups||[])for(const item of payload.items.filter(i=>i.group_id===group.id)){items.push(item);used.add(item.id);}
 return [...items,...payload.items.filter(i=>!used.has(i.id))];
}
export function groupDimensions(group){
 const format=v=>new Intl.NumberFormat('hu-HU',{maximumFractionDigits:3}).format(Number(v));
 if(group.measurement_type==='quantity')return absent(group.quantity)?'':`Mennyiség: ${format(group.quantity)} ${group.unit||'(mértékegység nincs megadva)'}`;
 if(group.measurement_type==='worktime')return [!absent(group.people)?`${format(group.people)} fő`:'',!absent(group.hours)?`${format(group.hours)} óra`:''].filter(Boolean).join(' × ')+(!absent(group.people)&&!absent(group.hours)?` = ${format(Number(group.people)*Number(group.hours))} főóra`:'');
 return [['length','Hossz'],['width','Szélesség'],['height','Vastagság']].filter(([k])=>!absent(group[k])).map(([k,label])=>`${label}: ${format(group[k])} m`).join(' · ');
}
export function publicPdfGroups(groups=[]){return groups.map(g=>Object.fromEntries(['id','name','measurement_type','quantity','unit','length','width','height','people','hours'].filter(k=>g[k]!==undefined).map(k=>[k,g[k]])));}
