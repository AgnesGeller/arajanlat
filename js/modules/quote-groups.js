import { measuredItem, unitKind } from './quick-quote-model.js?v=58';

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
 const mode=m.mode==='quantity'?unitKind(item.unit1):m.mode;
 if(!['length','area','volume','hedge','groundcover'].includes(mode))return item;
 m.mode=mode;
 m.length=group.length??'';
 if(['area','volume','groundcover'].includes(mode))m.width=group.width??'';
 const secondaryLength=['cm','mm'].includes(String(item.unit2||'').trim().toLowerCase());
 if((mode==='volume'||secondaryLength)&&!m.custom_height)m.height=group.height??'';
 if(mode==='groundcover'){m.use_dimensions=true;m.area_m2='';}
 const required=['length',...(['area','volume','groundcover'].includes(mode)?['width']:[]),...(mode==='volume'||secondaryLength?['height']:[])];
 const absent=required.some(k=>m[k]===null||m[k]===undefined||String(m[k]).trim()==='');
 return {...item,...(secondaryLength?{quantity2:Number(m.height||0)*(String(item.unit2).trim().toLowerCase()==='cm'?100:1000)}:{}),group_id:group.id,main_item:group.name,measurement:m,pending:{...item.pending,quantity:absent}};
}
export function updateGroup(payload,id,changes) {
 const group=payload.groups.find(g=>g.id===id);if(!group)throw Error('A főtétel nem található.');
 const next={...group,...changes};
 for(const key of ['length','width','height'])if(String(next[key]??'').trim()!==''&&(!Number.isFinite(Number(next[key]))||Number(next[key])<0||Number(next[key])>1e6))throw Error('A főtétel mérete nem megfelelő.');
 const items=payload.items.map(item=>item.group_id===id?measuredItem(inheritGroup({...item,main_item:next.name},next)):item);
 Object.assign(group,next);payload.items=items;return group;
}
export function orderedGroupItems(payload){
 const used=new Set(),items=[];
 for(const group of payload.groups||[])for(const item of payload.items.filter(i=>i.group_id===group.id)){items.push(item);used.add(item.id);}
 return [...items,...payload.items.filter(i=>!used.has(i.id))];
}
export function groupDimensions(group){return [['length','Hossz'],['width','Szélesség'],['height','Vastagság']].filter(([k])=>String(group[k]??'')!=='').map(([k,label])=>`${label}: ${group[k]} m`).join(' · ');}
