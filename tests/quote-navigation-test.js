import { createQuoteNavigation } from '../js/modules/quote-navigation.js?v=59';
const report=document.querySelector('#results');let route={view:'start'},passed=0,failed=0,saves=0,failSave=false,restores=0,lastState;
const check=(label,ok)=>{ok?passed++:failed++;report.textContent+=(ok?'OK: ':'HIBA: ')+label+'\n';};
const wait=async fn=>{for(let n=0;n<200;n++){if(fn())return;await new Promise(r=>setTimeout(r,10));}throw Error('Időtúllépés');};
const nav=createQuoteNavigation({capture:r=>r.view==='quick'?{...r,draftId:'saved-draft',step:1,compact:true}:r,restore:async r=>{restores++;route=r;},beforeLeave:async()=>{saves++;if(failSave)throw Error('Próba: a mentés nem sikerült.');},onChange:s=>{lastState=s;},onError:()=>{}});
const visit=r=>{nav.record(r);route=r;};
try{
 check('Kezdéskor nincs félrevezető aktív visszalépés',!lastState.canBack);
 visit({view:'customers',customerId:'client'});visit({view:'projects',projectId:'garden'});await nav.back();check('A Vissza az előző ügyfélhez vezet',route.customerId==='client'&&saves>=1);
 history.forward();await wait(()=>route.projectId==='garden');check('A böngésző Előre gombja is a megfelelő oldalra visz',route.projectId==='garden');
 failSave=true;let blocked=false;try{await nav.back();}catch{blocked=true;}check('Sikertelen mentéskor nem hagyja el az oldalt',blocked&&route.projectId==='garden');failSave=false;
 visit({view:'quick',draftId:'saved-draft',step:0,compact:true});visit({view:'library'});await nav.back();check('A gyorsajánlat pontos szerkesztési helye visszaáll',route.view==='quick'&&route.draftId==='saved-draft'&&route.step===1&&route.compact===true);
 history.back();await wait(()=>route.projectId==='garden');check('A böngésző Vissza gombja is az alkalmazáson belül működik',route.projectId==='garden');
 const before=restores;nav.record({view:'projects',projectId:'garden'});check('Azonos oldal nem hoz létre felesleges visszalépési lépést',restores===before);
 failSave=true;const cursor=history.state.quote_navigation.index,popped=new Promise(resolve=>window.addEventListener('popstate',resolve,{once:true}));history.back();await popped;await wait(()=>history.state.quote_navigation.index===cursor&&!lastState.busy);check('A böngésző visszalépésekor fellépő mentési hiba sem dobja el az oldalt',route.projectId==='garden');failSave=false;
 await nav.back();check('Mentési hiba után újra lehet próbálkozni',route.customerId==='client');
 nav.reset();route={view:'start'};check('Kijelentkezési alaphelyzetben az előzmények nem maradnak aktívak',!lastState.canBack&&!lastState.busy);
}catch(error){check(error.stack,false);}finally{nav.dispose();}
report.textContent+=`\nEREDMÉNY: ${passed} sikeres, ${failed} hibás.`;report.dataset.failed=failed;
