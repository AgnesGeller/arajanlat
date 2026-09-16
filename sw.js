const CACHE='diszkertek-shell-v3';
const STATIC=['./','./index.html','./client.html','./css/app.css','./js/app.js','./js/client.js','./js/config.js','./js/services/supabase-service.js','./js/services/email-service.js','./js/modules/quote-calculator.js','./assets/icon.svg','./assets/icon-192.png','./assets/icon-512.png'];
self.addEventListener('install', event => event.waitUntil(caches.open(CACHE).then(cache => cache.addAll(STATIC))));
self.addEventListener('activate', event => event.waitUntil(caches.keys().then(keys => Promise.all(keys.filter(k => k!==CACHE).map(k=>caches.delete(k))))));
self.addEventListener('fetch', event => {
 const url=new URL(event.request.url);
 if(event.request.method!=='GET'||url.origin!==self.location.origin||!STATIC.some(path=>new URL(path,self.registration.scope).href===url.href)) return;
 event.respondWith(caches.match(event.request).then(cached=>cached||fetch(event.request)));
});
self.addEventListener('message',event=>{if(event.data==='SKIP_WAITING')self.skipWaiting()});
