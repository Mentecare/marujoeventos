const CACHE = "eventcore-shell-notifications-v9";
const SHELL = ["/", "/manifest.webmanifest", "/icon.svg"];
self.addEventListener("install", (event) => {
  event.waitUntil(caches.open(CACHE).then((cache) => cache.addAll(SHELL)).then(() => self.skipWaiting()));
});
self.addEventListener("activate", (event) => {
  event.waitUntil(caches.keys().then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k)))).then(() => self.clients.claim()));
});
self.addEventListener("fetch", (event) => {
  const url = new URL(event.request.url);
  if (event.request.method !== "GET" || url.origin !== self.location.origin) return;
  // Public previews can close or become private. APIs, documents and authenticated RSC
  // are never cached; old v8 entries are cleared on activation above.
  if (url.pathname.startsWith("/o/") || url.pathname.startsWith("/api/") || url.searchParams.has("_rsc") || event.request.headers.has("RSC") || event.request.headers.has("Authorization")) return;
  if (event.request.mode === "navigate") {
    if (url.pathname !== "/") return;
    event.respondWith(fetch(event.request).catch(() => caches.match("/")));
    return;
  }
  const shellAsset = SHELL.includes(url.pathname) || url.pathname.startsWith("/_next/static/") || /^\/(?:icon|apple-touch-icon)[^/]*\.(?:svg|png)$/.test(url.pathname);
  if (!shellAsset || url.search) return;
  event.respondWith(caches.match(event.request).then((hit) => hit || fetch(event.request).then((res) => {
    if (res.ok && !/no-store|private/i.test(res.headers.get("Cache-Control") || "")) caches.open(CACHE).then((cache) => cache.put(event.request, res.clone()));
    return res;
  })));
});
const NOTIFICATION_UUID = "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}";
const NOTIFICATION_LINK = new RegExp(`^(?:/o/${NOTIFICATION_UUID}|/\\?(?:opportunity|assignment|contract)=${NOTIFICATION_UUID})$`, "i");
self.addEventListener("push", (event) => {
  let payload; try { payload = event.data?.json(); } catch { return; }
  if (!payload || typeof payload.link !== "string" || !NOTIFICATION_LINK.test(payload.link)) return;
  const title = typeof payload.title === "string" ? payload.title.slice(0, 180) : "Atualização EventCore";
  event.waitUntil(self.registration.showNotification(title, { icon: "/icon.svg", data: { link: payload.link } }));
});
self.addEventListener("notificationclick", (event) => {
  event.notification.close();
  const link = event.notification.data?.link;
  if (typeof link !== "string" || !NOTIFICATION_LINK.test(link)) return;
  const target = self.location.origin + link;
  event.waitUntil(self.clients.matchAll({ type: "window", includeUncontrolled: true }).then(async (clients) => {
    const existing = clients.find((client) => client.url === target);
    if (existing) { await existing.navigate(target); return existing.focus(); }
    return self.clients.openWindow(target);
  }));
});
