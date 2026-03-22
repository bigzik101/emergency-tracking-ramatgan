const CACHE = 'emergency-v4';
const PRE = ['./', './index.html',
  'https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.9.4/leaflet.min.js',
  'https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.9.4/leaflet.min.css',
  'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2'];

self.addEventListener('install', e => e.waitUntil(
  caches.open(CACHE).then(c => Promise.allSettled(PRE.map(u => c.add(u).catch(()=>null))))
    .then(() => self.skipWaiting())
));
self.addEventListener('activate', e => e.waitUntil(
  caches.keys().then(ks => Promise.all(ks.filter(k=>k!==CACHE).map(k=>caches.delete(k))))
    .then(() => self.clients.claim())
));
self.addEventListener('fetch', e => {
  const url = new URL(e.request.url);
  // OSM tiles — network first
  if (url.hostname.includes('tile.openstreetmap.org')) {
    e.respondWith(fetch(e.request).then(r=>{caches.open(CACHE).then(c=>c.put(e.request,r.clone()));return r;}).catch(()=>caches.match(e.request)));
    return;
  }
  // Supabase + OSRM + Nominatim — network only
  if (url.hostname.includes('supabase.co') || url.hostname.includes('osrm') || url.hostname.includes('nominatim')) {
    e.respondWith(fetch(e.request).catch(()=>new Response('{"error":"offline"}',{headers:{'Content-Type':'application/json'}})));
    return;
  }
  // App shell — cache first
  e.respondWith(caches.match(e.request).then(c=>c||fetch(e.request).then(r=>{
    if(r?.status===200&&e.request.method==='GET')caches.open(CACHE).then(ca=>ca.put(e.request,r.clone()));
    return r;
  }).catch(()=>e.request.mode==='navigate'?caches.match('./index.html'):undefined)));
});
