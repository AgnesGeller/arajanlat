const CACHE='diszkertek-shell-v19';
const STATIC=['./','./index.html','./client.html','./css/app.css','./js/app.js?v=19','./js/modules/app-install.js','./js/client.js?v=19','./js/config.js','./js/services/supabase-service.js','./js/services/email-service.js','./js/modules/quote-calculator.js','./assets/diszkertek-logo.png','./assets/seal-32.png','./assets/seal-180.png','./assets/seal-192.png','./assets/seal-512.png','./assets/seal-maskable-512.png','./assets/favicon.ico?v=16','./assets/share-arajanlat.png','./manifest.json'];
self.addEventListener('install', event => event.waitUntil(caches.open(CACHE).then(cache => cache.addAll(STATIC.map(path=>new Request(path,{cache:'reload'}))))));
self.addEventListener('activate', event => event.waitUntil(caches.keys().then(keys => Promise.all(keys.filter(k => k!==CACHE).map(k=>caches.delete(k))))));
self.addEventListener('fetch', event => {
 const url=new URL(event.request.url);
 if(event.request.method!=='GET'||url.origin!==self.location.origin||!STATIC.some(path=>new URL(path,self.registration.scope).href===url.href)) return;
 event.respondWith(caches.match(event.request).then(cached=>cached||fetch(event.request)));
});
self.addEventListener('message',event=>{if(event.data==='SKIP_WAITING')self.skipWaiting()});
