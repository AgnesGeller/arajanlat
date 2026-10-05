import { rows, rpc } from '../services/supabase-service.js';
import { dateTime } from './quote-calculator.js';
const titles={booked:'Új találkozófoglalás',cancelled:'Találkozó lemondva',reminder:'Találkozó 3 órán belül',phone:'Telefonos időpont-egyeztetés'};
let timer, activeUser, running=false;
const box=()=>document.querySelector('#appointment-notifications');
async function subscription() {return (await navigator.serviceWorker.getRegistration())?.pushManager?.getSubscription();}
async function enable() {
 const button=box().querySelector('[data-enable-notifications]');button.disabled=true;
 const message=box().querySelector('[data-notification-status]');
 try {
  if(!('Notification' in window)||!('PushManager' in window)||!('serviceWorker' in navigator))throw Error('Ez a böngésző nem támogatja az appértesítést. Használj Chrome-ot vagy Edge-et.');
  const publicKey=await rpc('quote_notification_public_key');
  if(!publicKey)throw Error('A riasztás most nem állítható be. Próbáld újra később.');
  if(await Notification.requestPermission()!=='granted')throw Error('Az értesítéshez engedély szükséges a böngésző beállításaiban.');
  const registration=await navigator.serviceWorker.ready;
  if(registration.waiting)throw Error('Előbb frissítsd az appot a megjelent Frissítés gombbal, majd kapcsold be a riasztást.');
  const key=Uint8Array.from(atob(publicKey.replace(/-/g,'+').replace(/_/g,'/')+'='.repeat((4-publicKey.length%4)%4)),c=>c.charCodeAt(0));
  const current=await registration.pushManager.getSubscription()||await registration.pushManager.subscribe({userVisibleOnly:true,applicationServerKey:key});
  await rpc('quote_push_subscribe',{p_subscription:current.toJSON()});
  message.textContent='A riasztást bekapcsoltuk ezen az eszközön. A rendszer és a böngésző értesítési beállításai is legyenek engedélyezve.';
 }catch(error){message.textContent=error?.message||'Az értesítés bekapcsolása nem sikerült.';}finally{button.disabled=false;}
}
async function poll() {
 if(!activeUser||running||!box()||document.hidden)return;
 running=true;const user=activeUser;
 try {
  const [events,seen]=await Promise.all([
   rows('quote_appointment_events',q=>q.select('*,project:quote_projects(name,project_code),appointment:quote_appointments(slot:quote_appointment_slots(starts_at))').eq('cancelled',false).lte('due_at',new Date().toISOString()).order('due_at',{ascending:false}).limit(100)),
   rows('quote_appointment_event_reads',q=>q.select('event_id').eq('user_id',user))
  ]);
  if(user!==activeUser)return;
  const unread=events.filter(e=>!seen.some(s=>s.event_id===e.id));
  box().querySelector('[data-notification-count]').textContent=unread.length?`Értesítések (${unread.length} új)`:'Értesítések';
  const list=box().querySelector('[data-notification-list]');list.replaceChildren();
  if(!unread.length){const p=document.createElement('p');p.textContent='Nincs új foglalási értesítés.';list.append(p);}
  unread.forEach(event=>{
   const row=document.createElement('div');row.className='appointment-row';
   const text=document.createElement('p');text.textContent=`${titles[event.kind]} · ${event.project.project_code} – ${event.project.name}${event.appointment?.slot?' · '+dateTime(event.appointment.slot.starts_at):''}`;
   const button=document.createElement('button');button.type='button';button.className='secondary';button.textContent='Elolvastam';
   button.onclick=async()=>{button.disabled=true;try{await rpc('quote_appointment_event_seen',{p_id:event.id});await poll();}catch{button.disabled=false;box().querySelector('[data-notification-status]').textContent='Az értesítés nem jelölhető olvasottnak. Próbáld újra.';}};
   row.append(text,button);list.append(row);
  });
 }catch {box().querySelector('[data-notification-status]').textContent='Az értesítések most nem frissíthetők. Újrapróbáljuk.';}finally{running=false;}
}
export function startAppointmentNotifications(userId) {
 clearInterval(timer);activeUser=userId;
 if(!box())return;
 if(!userId){box().replaceChildren();return;}
 box().innerHTML='<details><summary data-notification-count>Értesítések</summary><div class="toolbar"><button type="button" class="secondary" data-enable-notifications>Riasztás bekapcsolása ezen az eszközön</button><button type="button" class="text-btn" data-disable-notifications>Riasztás kikapcsolása ezen az eszközön</button><button type="button" class="text-btn" data-refresh-notifications>Értesítések frissítése</button></div><p class="muted" data-notification-status role="status"></p><div data-notification-list></div></details>';
 box().querySelector('[data-enable-notifications]').onclick=enable;
 box().querySelector('[data-refresh-notifications]').onclick=poll;
 box().querySelector('[data-disable-notifications]').onclick=async()=>{const user=activeUser;try{await stopAppointmentNotifications();startAppointmentNotifications(user);box().querySelector('details').open=true;box().querySelector('[data-notification-status]').textContent='A riasztást kikapcsoltuk ezen az eszközön.';}catch{box().querySelector('[data-notification-status]').textContent='A riasztás kikapcsolása nem sikerült. Próbáld újra.';}};
 poll();timer=setInterval(poll,60000);
 if('Notification' in window&&Notification.permission==='granted')subscription().then(current=>{if(current&&activeUser===userId)return rpc('quote_push_subscribe',{p_subscription:current.toJSON()});}).catch(()=>{});
}
export async function stopAppointmentNotifications() {
 // Remove this device's subscription before ending its authenticated session.
 if('serviceWorker' in navigator){const current=await subscription();if(current){const results=await Promise.allSettled([rpc('quote_push_unsubscribe',{p_endpoint:current.endpoint}),current.unsubscribe()]);if(results.some(r=>r.status==='rejected'))throw Error('A riasztás kikapcsolása nem sikerült.');}}
 startAppointmentNotifications(null);
}
document.addEventListener('visibilitychange',()=>{if(!document.hidden)poll();});
