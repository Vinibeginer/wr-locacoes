// Service worker do WR Locações: torna o sistema instalável como aplicativo.
// Não guarda dados nem versões antigas do sistema: tudo vem sempre da internet
// (assim cada atualização publicada chega na hora). Sem conexão, mostra um aviso.
const CACHE = "wr-offline-v1";
const OFFLINE = "offline.html";

self.addEventListener("install", e => {
  e.waitUntil(caches.open(CACHE).then(c => c.addAll([OFFLINE, "icons/icon-192.png"])).then(() => self.skipWaiting()));
});
self.addEventListener("activate", e => {
  e.waitUntil(caches.keys().then(ks => Promise.all(ks.filter(k => k !== CACHE).map(k => caches.delete(k)))).then(() => self.clients.claim()));
});
self.addEventListener("fetch", e => {
  if (e.request.mode !== "navigate") return;   // só a abertura da página; banco e arquivos seguem direto
  e.respondWith(fetch(e.request).catch(() => caches.match(OFFLINE)));
});
