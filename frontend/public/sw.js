// Service worker de l'espace contrôleur seulement (enregistré avec la portée « /controleur »).
// Hors ligne, il ne renvoie la page du contrôleur qu'à une navigation de cet espace : jamais à un client ni à un administrateur.
const CACHE = "axis-controleur-v2";
const SCOPE_PATH = "/controleur";
const SHELL = [SCOPE_PATH, "/manifest-controleur.webmanifest", "/icon-192.png", "/icon-512.png"];

self.addEventListener("install", (event) => {
  event.waitUntil(caches.open(CACHE).then((cache) => cache.addAll(SHELL)).catch(() => undefined));
  self.skipWaiting();
});

self.addEventListener("activate", (event) => {
  event.waitUntil(caches.keys().then((keys) => Promise.all(keys.filter((key) => key !== CACHE).map((key) => caches.delete(key)))));
  self.clients.claim();
});

function inControllerSpace(request) {
  const path = new URL(request.url).pathname;
  return path === SCOPE_PATH || path.startsWith(`${SCOPE_PATH}/`);
}

self.addEventListener("fetch", (event) => {
  if (event.request.method !== "GET") return;
  event.respondWith(
    fetch(event.request).catch(async () => {
      const cached = await caches.match(event.request);
      if (cached) return cached;
      // Navigation du contrôleur hors ligne : sa page. Toute autre requête échoue comme sans service worker.
      if (event.request.mode === "navigate" && inControllerSpace(event.request)) {
        const shell = await caches.match(SCOPE_PATH);
        if (shell) return shell;
      }
      return Response.error();
    }),
  );
});
