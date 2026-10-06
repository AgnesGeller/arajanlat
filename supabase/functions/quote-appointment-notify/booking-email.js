// Booking notifications only. Reminder delivery is exclusively Web Push.
export const needsBookingEmail = event => event.kind === 'booked' && !event.email_sent_at;
export async function sendBookingEmail(event, title, body, transport = fetch) {
 const response = await transport('https://formsubmit.co/ajax/info@diszkertek.hu', {
  method: 'POST', redirect: 'error',
  // Identify the real application whose booking this server worker delivers.
  headers: {'Content-Type': 'application/json', Accept: 'application/json',
   Referer: 'https://agnesgeller.github.io/arajanlat/index.html'},
  body: JSON.stringify({_subject: `Díszkertek – ${title}`, _template: 'table',
   'Értesítés': title, 'Projekt és időpont': body, 'Foglalás azonosítója': event.id,
   'Megnyitás': 'https://agnesgeller.github.io/arajanlat/index.html'}),
  signal: AbortSignal.timeout(10000)
 });
 if (!response.ok) throw Error(`A foglalási emailküldés nem sikerült (HTTP ${response.status}); újrapróbáljuk.`);
 const result = await response.json();
 if (![true, 'true'].includes(result.success) || /activat|confirm|verif/i.test(result.message || '')) {
  throw Error('A foglalási emailküldés nincs visszaigazolva. '+String(result.message||'A szolgáltató nem fogadta el a küldést.').slice(0,240));
 }
}
