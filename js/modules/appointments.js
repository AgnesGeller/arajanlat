import { rows, rpc } from '../services/supabase-service.js';
import { dateTime } from './quote-calculator.js';

const esc = value => String(value ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
export const appointmentLabel = slot => `${dateTime(slot.starts_at)} – ${new Intl.DateTimeFormat('hu-HU', {hour:'2-digit',minute:'2-digit',timeZone:'Europe/Budapest'}).format(new Date(slot.ends_at))}`;
const localDate = iso => {
 const date = new Date(iso);
 return `${date.getFullYear()}-${String(date.getMonth()+1).padStart(2,'0')}-${String(date.getDate()).padStart(2,'0')}T${String(date.getHours()).padStart(2,'0')}:${String(date.getMinutes()).padStart(2,'0')}`;
};

export function requestAppointments(data) {
 if (!data.meeting_required) return '';
 const content = data.appointment
  ? `<p>A találkozó időpontja: <strong>${esc(appointmentLabel(data.appointment))}</strong></p><p>Módosításhoz hívjon bennünket.</p>`
  : `<p>Válasszon a felkínált időpontok közül. A foglalás az adatok elküldésekor végleges.</p>
   <div class="appointment-choices">${(data.slots || []).map(slot => `<label class="check-label"><input type="radio" name="meeting_choice" value="${esc(slot.id)}" required><span>${esc(appointmentLabel(slot))}</span></label>`).join('') || '<p>Jelenleg nincs szabad időpont. Kérjen telefonos egyeztetést.</p>'}
   <label class="check-label"><input type="radio" name="meeting_choice" value="phone" required><span>Telefonos egyeztetést kérek</span></label></div>`;
 return `<section class="appointment-section" id="request-appointments"><h2>Találkozó időpontja</h2>${content}<a class="secondary appointment-call" href="tel:+36706349630">Nem megfelelő egyik időpont sem – telefonos egyeztetés<small>+36 70 634 9630</small></a></section>`;
}

export async function mountAppointments(container, project, {formDialog, refreshProject, fail, status}) {
 if (!container) return;
 const [slots, bookings] = await Promise.all([
  rows('quote_appointment_slots', q => q.select('*').eq('withdrawn', false).gt('ends_at', new Date().toISOString()).order('starts_at')),
  rows('quote_appointments', q => q.select('*,slot:quote_appointment_slots(*)').eq('status','booked'))
 ]);
 if (!container.isConnected) return;
 const booking = bookings.find(b => b.project_id === project.id);
 const free = slots.filter(s => new Date(s.starts_at) > new Date() && !bookings.some(b => s.starts_at < b.slot.ends_at && b.slot.starts_at < s.ends_at));
 const upcoming = slots.filter(s => !bookings.some(b => b.slot_id === s.id));
 container.innerHTML = `<h3>Időpontfoglalás</h3><p>${project.meeting_required ? 'Az ügyfél az adatbekérőben tud időpontot választani.' : 'Ehhez a projekthez nincs bekapcsolva a találkozó. A Projekt szerkesztése alatt kapcsolható be.'}</p>
 ${booking ? `<p><strong>Foglalt időpont: ${esc(appointmentLabel(booking.slot))}</strong></p><div class="toolbar"><button type="button" class="secondary" data-reschedule>Időpont módosítása</button><button type="button" class="danger" data-cancel-booking>Foglalás lemondása</button></div>` : `<p class="muted">A projekthez még nincs foglalás.</p>${project.meeting_required?'<button type="button" class="secondary" data-book-appointment>Egyeztetett időpont rögzítése</button>':''}`}
 <details class="appointment-management"><summary>Szabad időpontok kezelése</summary><p>Az itt felvett időpontokat minden találkozót igénylő projekt ügyfele választhatja. Az időpontok budapesti idő szerint jelennek meg.</p><button type="button" class="secondary" data-add-slot>+ Szabad időpont</button>
 ${upcoming.map(slot => `<div class="appointment-row"><span>${esc(appointmentLabel(slot))}${free.some(s=>s.id===slot.id)?'':' · Másik foglalással ütközik'}</span><div class="toolbar"><button type="button" class="text-btn" data-edit-slot="${slot.id}">Szerkesztés</button><button type="button" class="text-btn" data-withdraw-slot="${slot.id}">Visszavonás</button></div></div>`).join('') || '<p class="muted">Nincs felkínálható szabad időpont.</p>'}</details>`;
 const edit = (slot = {}) => formDialog(slot.id ? 'Szabad időpont szerkesztése' : 'Új szabad időpont', `<div class="grid"><label>Kezdés<input name="start" type="datetime-local" required value="${slot.starts_at ? localDate(slot.starts_at) : ''}"></label><label>Befejezés<input name="end" type="datetime-local" required value="${slot.ends_at ? localDate(slot.ends_at) : ''}"></label></div><p class="muted">A beírt időpont az eszköz helyi időzónáját használja. A listában budapesti idő szerint jelenik meg.</p>`, async values => {
  if (new Date(values.end) <= new Date(values.start)) throw Error('A befejezésnek a kezdés után kell lennie.');
  await rpc('quote_appointment_slot_save', {p_id:slot.id || null,p_start:new Date(values.start).toISOString(),p_end:new Date(values.end).toISOString(),p_withdrawn:false,p_expected:slot.updated_at || null});
  await refreshProject();
 });
 container.querySelector('[data-add-slot]').onclick = () => edit();
 container.querySelectorAll('[data-edit-slot]').forEach(button => button.onclick = () => edit(slots.find(s=>s.id===button.dataset.editSlot)));
 container.querySelectorAll('[data-withdraw-slot]').forEach(button => button.onclick = () => {
  const slot = slots.find(s=>s.id===button.dataset.withdrawSlot);
  formDialog('Szabad időpont visszavonása',`<p>${esc(appointmentLabel(slot))}</p><label class="check-label"><input type="checkbox" required> Visszavonom ezt a szabad időpontot.</label>`,async()=>{
   await rpc('quote_appointment_slot_save',{p_id:slot.id,p_start:slot.starts_at,p_end:slot.ends_at,p_withdrawn:true,p_expected:slot.updated_at});await refreshProject();return 'Az időpontot visszavontuk.';
  });
 });
 const cancel = container.querySelector('[data-cancel-booking]');
 if (cancel) cancel.onclick = () => {
  formDialog('Foglalás lemondása',`<p>${esc(appointmentLabel(booking.slot))}</p><p>Az ügyféllel egyeztessétek a változást.</p><label class="check-label"><input type="checkbox" required> Lemondom a foglalást.</label>`,async()=>{
   await rpc('quote_appointment_change',{p_id:booking.id,p_slot:null,p_expected:booking.updated_at});await refreshProject();return 'A foglalást lemondtuk.';
  });
 };
 const change = container.querySelector('[data-reschedule]');
 const book = container.querySelector('[data-book-appointment]');
 const choose = modifying => {
  if (!free.length) {status('Előbb vegyél fel egy új szabad időpontot.',true);return;}
  formDialog(modifying?'Foglalás módosítása':'Egyeztetett időpont rögzítése', `<label>Időpont<select name="slot" required><option value="">Válassz időpontot</option>${free.map(slot=>`<option value="${slot.id}">${esc(appointmentLabel(slot))}</option>`).join('')}</select></label><p>Az ügyféllel egyeztessétek az időpontot.</p>`, async values => {
   if(modifying)await rpc('quote_appointment_change',{p_id:booking.id,p_slot:values.slot,p_expected:booking.updated_at});
   else await rpc('quote_appointment_book',{p_project:project.id,p_slot:values.slot});
   await refreshProject();
  });
 };
 if(change)change.onclick=()=>choose(true);
 if(book)book.onclick=()=>choose(false);
}
