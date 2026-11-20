const CACHE = "ds-v2-cache-v21";
const ASSETS = [
  "./",
  "./index.html",
  "./css/styles.css?v=21",
  "./js/app.js?v=21",
  "./js/supabase.min.js?v=21",
  "./js/supabase-config.js?v=21",
  "./js/html2pdf.bundle.min.js",
  "./assets/icon-192.png",
  "./assets/icon-512.png",
  "./assets/omandurar_footer.jpg",
  "./manifest.json"
];

self.addEventListener("install", (e) => {
  e.waitUntil(caches.open(CACHE).then((c) => c.addAll(ASSETS)).catch(() => {}));
  self.skipWaiting();
});

self.addEventListener("activate", (e) => {
  e.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(keys.filter((k) => k.startsWith("ds-v2-cache-") && k !== CACHE).map((k) => caches.delete(k)))
    )
  );
  self.clients.claim();
});

self.addEventListener("fetch", (e) => {
  if (e.request.method !== "GET") return;
  const reqUrl = new URL(e.request.url);
  // Never intercept external API calls (Supabase auth/REST) or other origins
  if (reqUrl.origin !== self.location.origin) return;
  const scopePath = new URL("./", self.location.href).pathname;
  if (!reqUrl.pathname.startsWith(scopePath)) return;

  e.respondWith(
    fetch(e.request).then((res) => {
      if (res && res.ok) {
        const copy = res.clone();
        caches.open(CACHE).then((c) => c.put(e.request, copy));
      }
      return res;
    }).catch(() => caches.match(e.request))
  );
});
