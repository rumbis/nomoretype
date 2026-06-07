/* ═══════════════════════════════════════════════════════════════════════════
   Service Worker — PWA offline caching for NoMoreType
   ═══════════════════════════════════════════════════════════════════════════ */

const CACHE = 'nomoretype-v1';
const ASSETS = [
  './',
  './index.html',
  './styles.css',
  './app.js',
  './recorder.js',
  './services/groqService.js',
  './services/llmService.js',
  './services/youtubeService.js',
  './services/historyStorage.js',
  './manifest.json',
];

self.addEventListener('install', (e) => {
  e.waitUntil(
    caches.open(CACHE).then((cache) => cache.addAll(ASSETS))
  );
});

self.addEventListener('fetch', (e) => {
  e.respondWith(
    caches.match(e.request).then((cached) => cached || fetch(e.request))
  );
});
