const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
export function clientEmail(purpose,link,number=''){
 return purpose==='offer'?{subject:`Díszkertek árajánlat – ${number}`,body:`Kedves Ügyfelünk!\n\nElkészült árajánlatunk. Az alábbi biztonságos linken megtekintheti és jelezheti döntését:\n${link}\n\nÜdvözlettel:\nDíszkertek`}:{subject:'Díszkertek – projektadatok',body:`Kedves Ügyfelünk!\n\nKérjük, töltse ki az adatbekérőt:\n${link}\n\nÜdvözlettel:\nDíszkertek`};
}
export function emailLinks({to='',subject='',body=''}){
 const params=new URLSearchParams({subject,body});
 const mailto=`mailto:${encodeURIComponent(to.trim()).replace(/%40/gi,'@')}?${params.toString().replace(/\+/g,'%20')}`;
 const gmail=new URL('https://mail.google.com/mail/');gmail.searchParams.set('extsrc','mailto');gmail.searchParams.set('url',mailto);
 const outlook=new URL('https://outlook.office.com/mail/deeplink/compose');outlook.search=new URLSearchParams({to:to.trim(),subject,body}).toString();
 const personal=new URL(outlook);personal.hostname='outlook.live.com';
 const gmailAccount=new URL('https://accounts.google.com/AccountChooser');gmailAccount.searchParams.set('service','mail');gmailAccount.searchParams.set('continue',gmail.href);
 return {mailto,gmail:gmailAccount.href,outlook:outlook.href,personal:personal.href};
}
export function emailHandoffHtml(to,draft){
 return `<section id="email-handoff"><h3>Küldés emailben</h3><label>Címzett emailcíme<input id="email-recipient" type="email" value="${esc(to)}" autocomplete="email"></label><label>Tárgy<input id="email-subject" value="${esc(draft.subject)}"></label><label>Levél szövege<textarea id="email-body" rows="9">${esc(draft.body)}</textarea></label><div class="toolbar"><a id="email-link" class="secondary">Emailprogram</a><a data-email-provider="gmail" class="secondary" target="_blank" rel="noopener noreferrer" referrerpolicy="no-referrer">Gmail</a><a data-email-provider="personal" class="secondary" target="_blank" rel="noopener noreferrer" referrerpolicy="no-referrer">Outlook.com</a><a data-email-provider="outlook" class="secondary" target="_blank" rel="noopener noreferrer" referrerpolicy="no-referrer">Microsoft 365</a><button id="copy-email-body" type="button" class="secondary">Levélszöveg másolása</button><button id="copy-email-subject" type="button" class="secondary">Tárgy másolása</button></div><p class="muted">Válaszd ki a saját leveleződet; a böngészős levelezőnél jelentkezz be a saját fiókodba. A megnyíló levélben ellenőrizd a címzettet, majd küldd el. Más levelezőhöz másold át a tárgyat és a szöveget. Ha az Emailprogram gomb nem nyit meg semmit, válaszd a böngészős levelezőt vagy a másolást.</p><p id="email-handoff-status" role="status" aria-live="polite"></p></section>`;
}
export function mountEmailHandoff(root){
 const recipient=root.querySelector('#email-recipient'),subject=root.querySelector('#email-subject'),body=root.querySelector('#email-body'),message=root.querySelector('#email-handoff-status');
 const update=()=>{const links=emailLinks({to:recipient.value,subject:subject.value,body:body.value});root.querySelector('#email-link').href=links.mailto;root.querySelectorAll('[data-email-provider]').forEach(a=>a.href=links[a.dataset.emailProvider]);};
 [recipient,subject,body].forEach(input=>input.addEventListener('input',update));update();
 root.querySelectorAll('a').forEach(a=>a.addEventListener('click',event=>{if(!recipient.checkValidity()){event.preventDefault();recipient.reportValidity();message.textContent='Ellenőrizd a címzett emailcímét.';return}message.textContent=recipient.value.trim()?'A levelet a leveleződben tudod elküldeni. Ha nem nyílik meg, használd a másolást.':'A címzett nincs megadva. A leveleződben add meg, mielőtt elküldöd a levelet.';}));
 const copy=async(input,label)=>{input.focus();input.select();try{await navigator.clipboard.writeText(input.value);message.textContent=`${label} másolva. Illeszd be a leveleződbe.`;}catch{input.focus();input.select();message.textContent=`${label} kijelölve. Másold ki a Ctrl+C billentyűvel vagy a készülék Másolás parancsával.`;}};
 root.querySelector('#copy-email-body').onclick=()=>copy(body,'Levélszöveg');root.querySelector('#copy-email-subject').onclick=()=>copy(subject,'Tárgy');
}
