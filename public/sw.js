const CACHE = "eventcore-shell-mobile-navigation-v5";
const SHELL = ["/", "/manifest.webmanifest", "/icon.svg"];
self.addEventListener("install", (event) => {
  event.waitUntil(caches.open(CACHE).then((cache) => cache.addAll(SHELL)).then(() => self.skipWaiting()));
});
self.addEventListener("activate", (event) => {
  event.waitUntil(caches.keys().then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k)))).then(() => self.clients.claim()));
});
self.addEventListener("fetch", (event) => {
  const url = new URL(event.request.url);
  if (event.request.method !== "GET") return;
  if (url.hostname.includes("supabase.co") || url.pathname.startsWith("/api/")) return;
  if (event.request.mode === "navigate") {
    event.respondWith(fetch(event.request).catch(() => caches.match("/")));
    return;
  }
  event.respondWith(caches.match(event.request).then((hit) => hit || fetch(event.request).then((res) => {
    if (res.ok && url.origin === self.location.origin) caches.open(CACHE).then((cache) => cache.put(event.request, res.clone()));
    return res;
  })));
});
