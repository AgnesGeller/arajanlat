const CACHE='diszkertek-arajanlat-v34';
const STATIC=['./bemutato/grill-terasz.html','./bemutato/grill-terasz.js','./css/work-tracking.css','./js/modules/project-work-tracking.js','./js/modules/worksheet-calculator.js','./js/modules/work-progress.js','./','./index.html','./client.html','./css/app.css','./js/app.js?v=34','./js/modules/app-install.js','./js/modules/customer-search.js','./js/modules/app-update.js?v=34','./js/modules/appointments.js','./js/modules/appointment-notifications.js','./js/client.js?v=34','./js/config.js','./js/services/supabase-service.js','./js/services/email-service.js','./js/modules/quote-calculator.js','./assets/diszkertek-logo.png','./assets/seal-32.png','./assets/seal-180.png','./assets/seal-192.png','./assets/seal-512.png','./assets/seal-maskable-512.png','./assets/favicon.ico?v=16','./assets/share-arajanlat.png','./manifest.json','./manifest.json?v=24'];
self.addEventListener('install', event => event.waitUntil(caches.open(CACHE).then(cache => cache.addAll(STATIC.map(path=>new Request(path,{cache:'reload'}))))));
self.addEventListener('activate', event => event.waitUntil(caches.keys().then(keys => Promise.all(keys.filter(k => k!==CACHE&&(k.startsWith('diszkertek-arajanlat-')||/^diszkertek-shell-v\d+$/.test(k))).map(k=>caches.delete(k))))));
self.addEventListener('fetch', event => {
 const url=new URL(event.request.url);
 if(event.request.method!=='GET'||url.origin!==self.location.origin||!STATIC.some(path=>new URL(path,self.registration.scope).href===url.href)) return;
 event.respondWith(caches.open(CACHE).then(cache=>cache.match(event.request)).then(cached=>cached||fetch(event.request)));
});
self.addEventListener('message',event=>{if(event.data==='SKIP_WAITING')self.skipWaiting()});

self.addEventListener('push',event=>{
 let data={};try{data=event.data?.json()||{}}catch{}
 event.waitUntil(self.registration.showNotification(data.title||'Díszkertek Árajánlat',{
  body:data.body||'Új foglalási értesítés érkezett.',icon:new URL('assets/seal-192.png',self.registration.scope).href,
  badge:new URL('assets/seal-32.png',self.registration.scope).href,tag:data.tag||'quote-appointment',
  data:{url:new URL('index.html',self.registration.scope).href},renotify:true,vibrate:[200,100,200]
 }));
});
self.addEventListener('notificationclick',event=>{
 event.notification.close();const target=new URL('index.html',self.registration.scope).href;
 event.waitUntil(clients.matchAll({type:'window',includeUncontrolled:true}).then(async windows=>{
  const existing=windows.find(client=>client.url.startsWith(self.registration.scope)&&new URL(client.url).pathname.endsWith('/index.html'));
  if(existing)return existing.focus();return clients.openWindow(target);
 }));
});
