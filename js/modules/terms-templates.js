const esc=value=>String(value??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const common=[
 'Munkakezdés: Előzetes egyeztetés alapján, az időjárás és az anyagok rendelkezésre állásának figyelembevételével.',
 'Fizetés: A felek által előzetesen egyeztetett ütemezés szerint, átutalással vagy készpénzzel.',
 'Többletmunka: Az ajánlatban nem szereplő munkákat külön egyeztetés és az ügyfél jóváhagyása után végezzük el.'
];
export const TERMS_TEMPLATES=[
 {id:'garden',name:'Kertépítés',body:[...common,
 'Anyagok: Az ajánlatban szereplő anyagok és növények változtatása előzetes egyeztetés alapján történik.',
 'Mennyiségek: A felméréskor nem pontosítható mennyiségek elszámolása a ténylegesen elvégzett, egyeztetett mennyiség alapján történik.',
 'Munkaterület: A munkavégzéshez szükséges bejutást, valamint az egyeztetett víz- és áramvételi lehetőséget a megrendelő biztosítja.'
 ].join('\n\n')},
 {id:'maintenance',name:'Kertfenntartás',body:[
 'Időpont: A munkavégzés időpontját előzetesen egyeztetjük; kedvezőtlen időjárás esetén új időpontot beszélünk meg.',
 common[1],common[2],
 'Elszámolás: Az ajánlatban megadott elszámolási mód és az egyeztetett mennyiségek szerint.',
 'Hulladék: A zöldhulladék elszállítását az ajánlat akkor tartalmazza, ha külön tételként szerepel benne.'
 ].join('\n\n')},
 {id:'quick',name:'Gyors ajánlat',body:[
 'Az ajánlat a felméréskor rendelkezésre álló adatok és a felsorolt tételek alapján készült.',
 common[0],common[1],common[2]
 ].join('\n\n')}
];
// The textarea remains the authoritative offer content. Templates are explicit copies.
export function mountTermsTemplates(host,{textarea,list=async()=>[],save,onChange=()=>{}}){
 if(!host||!textarea)return;
 host.innerHTML=`<label>Feltételsablon<select data-terms-select><option value="">Válassz sablont (kihagyható)</option></select></label><div class="toolbar"><button type="button" class="secondary" data-terms-apply>Szöveg betöltése</button></div><details><summary>Saját sablon mentése</summary><label>Sablon neve<input data-terms-name maxlength="100" autocomplete="off"></label><button type="button" class="secondary" data-terms-save>Mentés saját sablonként</button></details><p class="muted">A betöltött szöveget szabadon átírhatod. A módosítás csak ezt az ajánlatot érinti. Az érvényességet a dátummezőben add meg.</p><p data-terms-status role="status" aria-live="polite"></p>`;
 const select=host.querySelector('[data-terms-select]'),status=host.querySelector('[data-terms-status]');
 let custom=[];
 const feedback=(text,error=false)=>{status.textContent=text;status.classList.toggle('error',error);};
 const options=()=>{const selected=select.value;select.innerHTML='<option value="">Válassz sablont (kihagyható)</option>'+TERMS_TEMPLATES.map(t=>`<option value="builtin:${t.id}">${esc(t.name)}</option>`).join('')+custom.map(t=>`<option value="custom:${esc(t.id)}">Saját: ${esc(t.name)}</option>`).join('');select.value=selected;};
 options();
 host.querySelector('[data-terms-apply]').onclick=()=>{
  const [kind,id]=select.value.split(':');const template=(kind==='builtin'?TERMS_TEMPLATES:custom).find(t=>t.id===id);
  if(!template){feedback('Előbb válassz egy sablont.',true);return;}
  if(textarea.value.trim()&&textarea.value!==template.body&&!confirm('A sablon lecseréli az ajánlat jelenlegi feltételeit. Betöltöd?'))return;
  textarea.value=template.body;onChange(template.body);feedback('Sablon betöltve. A szöveget az ajánlathoz igazíthatod.');
 };
 host.querySelector('[data-terms-save]').onclick=async event=>{
  const button=event.currentTarget,name=host.querySelector('[data-terms-name]').value.trim(),body=textarea.value.trim();
  if(!name||!body){feedback('A saját sablonhoz add meg a nevét és a feltételek szövegét.',true);return;}
  if(name.length>100||body.length>5000){feedback('A sablon neve legfeljebb 100, szövege legfeljebb 5000 karakter lehet.',true);return;}
  button.disabled=true;
  try{if(!save)throw Error('A sablonmentés most nem elérhető.');const record=await save({name,body});custom=[...custom,record];options();select.value='custom:'+record.id;host.querySelector('[data-terms-name]').value='';feedback('Saját sablon mentve. Más ajánlatnál is kiválasztható.');}
  catch(error){feedback(error.code==='23505'?'Ilyen nevű saját sablon már van. Adj másik nevet.':error.message||'A sablon mentése nem sikerült. Próbáld újra.',true);}
  finally{button.disabled=false;}
 };
 const refresh=async()=>{try{custom=await list();options();}catch{feedback('A saját sablonok nem tölthetők be. A beépített sablonok használhatók.',true);}};
 host.addEventListener('focusin',event=>{if(event.target===select)refresh();});
 refresh();
}
