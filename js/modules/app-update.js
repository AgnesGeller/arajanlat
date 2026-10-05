// Keep updating available even when the main module or Auth CDN cannot load.
(() => {
 const scope=new URL('../../',document.currentScript.src).href;
 const button=document.querySelector('#refresh-app'),banner=document.querySelector('#update-banner');
 let registration,updating=false,reloading=false;
 function message(text,error=false){const el=document.querySelector('#status');el.textContent=text;el.classList.toggle('error',error)}
 function reload(){if(reloading)return;reloading=true;location.reload()}
 function bounded(promise){return new Promise((resolve,reject)=>{const timer=setTimeout(()=>reject(Error('A frissítés nem érhető el. Ellenőrizd az internetkapcsolatot, majd próbáld újra.')),20000);Promise.resolve(promise).then(resolve,reject).finally(()=>clearTimeout(timer))})}
 function watch(reg){
  if(reg.waiting)banner.hidden=false;
  reg.addEventListener('updatefound',()=>{const worker=reg.installing;worker?.addEventListener('statechange',()=>{if(worker.state==='installed'&&navigator.serviceWorker.controller)banner.hidden=false})});
 }
 function activate(worker){return new Promise((resolve,reject)=>{
  const timer=setTimeout(()=>finish(Error('A frissítés még nem fejeződött be. Ellenőrizd az internetkapcsolatot, majd próbáld újra.')),15000);
  function finish(error){clearTimeout(timer);worker.removeEventListener('statechange',changed);error?reject(error):resolve()}
  function changed(){if(worker.state==='activated')finish();else if(worker.state==='redundant')finish(Error('A frissítés nem sikerült. Próbáld újra.'))}
  worker.addEventListener('statechange',changed);worker.postMessage('SKIP_WAITING');changed();
 })}
 if('serviceWorker'in navigator){
  registration=navigator.serviceWorker.register(new URL('sw.js',scope),{scope,updateViaCache:'none'}).then(reg=>{watch(reg);reg.update().catch(()=>{});return reg});
  // Retain the rejection for the button without an unhandled startup error.
  registration.catch(()=>{});
  let controlled=Boolean(navigator.serviceWorker.controller);
  navigator.serviceWorker.addEventListener('controllerchange',()=>{if(updating)reload();else if(controlled)banner.hidden=false;controlled=true});
 }
 button.onclick=async()=>{
  if(updating)return;
  const pending=[];
  document.dispatchEvent(new CustomEvent('quote:before-update',{detail:{waitUntil:promise=>pending.push(promise)}}));
  updating=true;button.disabled=true;button.textContent='Frissítés…';
  try{
   await Promise.all(pending);message('App frissítése…');
   if(!registration){reload();return}
   const reg=await bounded(registration);
   if(reg.scope!==scope)throw Error('Az Árajánlat frissítése nem elérhető. Nyisd meg újra az Árajánlat saját linkjét.');
   await bounded(reg.update());
   if(reg.installing)await new Promise((resolve,reject)=>{
    const worker=reg.installing,timer=setTimeout(()=>finish(Error('A frissítés letöltése nem fejeződött be. Próbáld újra.')),20000);
    function finish(error){clearTimeout(timer);worker.removeEventListener('statechange',changed);error?reject(error):resolve()}
    function changed(){if(worker.state==='installed'||worker.state==='activated')finish();else if(worker.state==='redundant')finish(Error('A frissítés letöltése nem sikerült. Próbáld újra.'))}
    worker.addEventListener('statechange',changed);changed();
   });
   if(reg.waiting)await activate(reg.waiting);
   reload();
  }catch(error){message(error.message||'A frissítés nem sikerült. Próbáld újra.',true)}
  finally{updating=false;button.disabled=false;button.textContent='Frissítés'}
 };
 setTimeout(()=>{
  if(['login','workspace','setup'].every(id=>document.getElementById(id)?.hidden)){
   message('Az app nem töltődött be. Ellenőrizd az internetkapcsolatot, majd nyomd meg a Frissítés gombot.',true);banner.hidden=false;
  }
 },15000);
})();
