const key=route=>JSON.stringify(['view','customerId','projectId','quoteId','versionId','draftId','step','compact'].map(k=>route[k]??null));

// Only this app's own, current-session entries are handled. Other pages keep normal history behavior.
export function createQuoteNavigation({capture,restore,beforeLeave,onChange,onError}){
 let token=crypto.randomUUID(),active={index:0,route:{view:'start'}},restoring=false,busy=false,pendingBack=null,rollbackIndex=null,queue=Promise.resolve();
 const notify=()=>onChange({route:active.route,canBack:active.index>0||active.route.view!=='start',busy});
 const state=entry=>({...history.state,quote_navigation:{token,...entry}});
 const checkpoint=()=>{active={...active,route:capture(active.route)};history.replaceState(state(active),'');};
 history.replaceState(state(active),'');notify();
 function record(route){
  if(restoring)return;
  if(busy)throw Error('Várd meg a visszalépés befejezését.');
  checkpoint();if(key(active.route)===key(route))return;
  active={index:active.index+1,route};history.pushState(state(active),'');notify();
 }
 async function apply(entry){
  if(rollbackIndex===entry.index){rollbackIndex=null;busy=false;notify();return;}
  const old={...active,route:capture(active.route)};let attempted=false;busy=true;notify();
  try{
   await beforeLeave();restoring=true;attempted=true;await restore(entry.route);active={...entry,route:capture(entry.route)};history.replaceState(state(active),'');
   pendingBack?.resolve();pendingBack=null;
  }catch(error){
   if(attempted){try{await restore(old.route);}catch{/* The original error remains the actionable message. */}}
   active=old;rollbackIndex=old.index;const delta=old.index-entry.index;if(delta)history.go(delta);else rollbackIndex=null;
   pendingBack?.reject(error);pendingBack=null;onError(error);
  }finally{restoring=false;busy=false;notify();}
 }
 const pop=event=>{const entry=event.state?.quote_navigation;if(entry?.token!==token)return;busy=true;notify();queue=queue.catch(()=>{}).then(()=>apply({index:entry.index,route:entry.route}));};
 window.addEventListener('popstate',pop);
 async function back(){
  if(busy)throw Error('Várd meg a visszalépés befejezését.');busy=true;notify();
  try{
   await beforeLeave();checkpoint();
   if(active.index>0){const done=new Promise((resolve,reject)=>{pendingBack={resolve,reject};});history.back();return await done;}
   restoring=true;await restore({view:'start'});active={index:0,route:{view:'start'}};history.replaceState(state(active),'');
  }finally{restoring=false;busy=false;notify();}
 }
 return {record,back,reset(){token=crypto.randomUUID();active={index:0,route:{view:'start'}};history.replaceState(state(active),'');notify();},dispose(){window.removeEventListener('popstate',pop);}};
}
