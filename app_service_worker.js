// Weed ID Trainer - service worker.
//
// What it buys: once a friend has opened the page once, the app keeps working
// with no network at all (plane, subway, dead signal), and a second visit
// starts without re-downloading the renderer or the cards they already saw.
//
// Rules, chosen so a new deploy is never hidden behind a stale copy:
//   * the app shell (html/js/manifests/icons)  -> network first, cache as a
//     fallback, so an updated build is picked up on the next online visit;
//   * card images (they never change between visits of the same build)
//     -> cache first, refreshed in the background;
//   * anything cross-origin -> untouched. There is nothing cross-origin in
//     this app: the web build ships its own CanvasKit and fonts.
//
// build_web.ps1 replaces 20261106150233 on every build, which is what makes
// browsers notice this file changed.

const VERSION = '20261106150233';
const SHELL_CACHE = 'weeds-shell-' + VERSION;
const IMAGE_CACHE = 'weeds-images-' + VERSION;

// Small, always worth having before the network is tried.
const PRECACHE = [
  './',
  './index.html',
  './flutter.js',
  './flutter_bootstrap.js',
  './main.dart.js',
  './manifest.json',
  './icons/Icon-192.png',
  './icons/Icon-512.png',
  './favicon.png',
  './assets/FontManifest.json',
  './assets/AssetManifest.bin.json',
];

const asUrl = (path) => new URL(path, self.registration.scope);

self.addEventListener('install', (event) => {
  // Each file on its own: one missing icon must not lose the whole cache.
  event.waitUntil(
    caches
      .open(SHELL_CACHE)
      .then((cache) =>
        Promise.allSettled(PRECACHE.map((path) => cache.add(asUrl(path))))
      )
      .then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches
      .keys()
      .then((keys) =>
        Promise.all(
          keys
            .filter((key) => key !== SHELL_CACHE && key !== IMAGE_CACHE)
            .map((key) => caches.delete(key))
        )
      )
      .then(() => self.clients.claim())
  );
});

// The deck lives in assets/front and assets/back; on the web those are served
// under assets/assets/... (Flutter prefixes package assets with "assets/").
const isCardImage = (url) => /\/assets\/(front|back)\//.test(url.pathname);

const putInCache = (cacheName, request, response) =>
  caches.open(cacheName).then((cache) => cache.put(request, response));

const matchAnyCache = async (request) => {
  for (const name of [IMAGE_CACHE, SHELL_CACHE]) {
    const hit = await (await caches.open(name)).match(request, {
      ignoreSearch: true,
    });
    if (hit) return hit;
  }
  return null;
};

self.addEventListener('fetch', (event) => {
  const request = event.request;
  if (request.method !== 'GET') return;

  const url = new URL(request.url);
  if (url.origin !== self.location.origin) return; // nothing external, by design

  // Card images: answer from cache immediately, quietly fetch a fresh copy.
  if (isCardImage(url)) {
    event.respondWith(
      caches.open(IMAGE_CACHE).then(async (cache) => {
        const cached = await cache.match(request);
        if (cached) {
          fetch(request)
            .then((response) => {
              if (response && response.ok) cache.put(request, response.clone());
            })
            .catch(() => {});
          return cached;
        }
        const response = await fetch(request);
        if (response && response.ok) cache.put(request, response.clone());
        return response;
      })
    );
    return;
  }

  // Everything else: try the network so a new version is never hidden, and
  // fall back to what we already have when the network is down, blocked, or
  // answering with an error page (a proxy 502 is a *response*, not a failure).
  event.respondWith(
    fetch(request)
      .then(async (response) => {
        if (response && response.ok && response.type === 'basic') {
          event.waitUntil(putInCache(SHELL_CACHE, request, response.clone()));
          return response;
        }
        return (await matchAnyCache(request)) || response;
      })
      .catch(async () => {
        const hit = await matchAnyCache(request);
        if (hit) return hit;
        // A page load while offline still needs the shell.
        if (request.mode === 'navigate') {
          const shell = await (
            await caches.open(SHELL_CACHE)
          ).match(asUrl('./index.html'));
          if (shell) return shell;
        }
        return new Response('offline', { status: 503 });
      })
  );
});
