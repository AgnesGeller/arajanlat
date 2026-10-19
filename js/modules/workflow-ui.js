const steps=['Ügyfél','Projekt és felmérés','Ajánlat összeállítása','Ellenőrzés és megosztás'];
export function workflowHtml(current){
 return `<ol class="workflow" aria-label="Az ajánlatkészítés lépései">${steps.map((label,index)=>`<li ${index+1===current?'aria-current="step"':''}><span class="step-number">${index+1}</span><span>${label}</span></li>`).join('')}</ol>`;
}
export function versionLabel(status){return ({draft:'Piszkozat',published:'Véglegesített',accepted:'Elfogadva',rejected:'Elutasítva'})[status]||status;}
