export function composeEmail({ to = '', subject, body }) {
  const link = `mailto:${encodeURIComponent(to)}?subject=${encodeURIComponent(subject)}&body=${encodeURIComponent(body)}`;
  window.location.href = link;
}
export function offerEmail(to, name, link) {
  composeEmail({ to, subject: `Díszkertek árajánlat – ${name}`,
    body: `Kedves Ügyfelünk!\n\nElkészült árajánlatunk. Az alábbi biztonságos linken megtekintheti és jelezheti döntését:\n${link}\n\nÜdvözlettel:\nDíszkertek` });
}
