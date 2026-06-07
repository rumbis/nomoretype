/* ═══════════════════════════════════════════════════════════════════════════
   Capacitor Bridge — Native plugin integration for Capacitor (iOS/Android)
   Loaded AFTER platform.js to override with Capacitor-native APIs
   ═══════════════════════════════════════════════════════════════════════════ */

'use strict';

(async () => {
  // Only run inside Capacitor
  if (!window.Capacitor?.isNativePlatform) return;

  const { Capacitor } = window;
  console.log('[Capacitor] Bridge initializing...');

  try {
    // ── File System Plugin ────────────────────────────────────────
    const { Filesystem, Directory, Encoding } = await import('@capacitor/filesystem');

    // ── Share Plugin ─────────────────────────────────────────────
    const { Share } = await import('@capacitor/share');

    // ── Override Platform.saveFile for Capacitor ─────────────────
    const originalSaveFile = window.Platform.saveFile;
    window.Platform.saveFile = async function(content, defaultName, mimeType = 'text/plain') {
      try {
        // Try Capacitor Filesystem first
        const result = await Filesystem.writeFile({
          path: `Documents/${defaultName}`,
          data: btoa(unescape(encodeURIComponent(content))),
          directory: Directory.Data,
          encoding: Encoding.UTF8,
        });

        // Offer to share the file
        try {
          await Share.share({
            title: defaultName,
            text: content.substring(0, 500),
            dialogTitle: 'Save transcription',
          });
        } catch {}

        return true;
      } catch (err) {
        console.warn('[Capacitor] Filesystem save failed, falling back to web download:', err);
        return originalSaveFile(content, defaultName, mimeType);
      }
    };

    // ── Override Platform.pickFile for Capacitor ─────────────────
    // Capacitor doesn't have a built-in file picker, fallback to web <input>
    // The web fallback in platform.js already handles this

    // ── Override Platform.copyToClipboard for Capacitor ──────────
    // Web Clipboard API works on mobile too, no override needed

    console.log('[Capacitor] Bridge ready');
  } catch (err) {
    console.warn('[Capacitor] Some plugins unavailable:', err);
  }
})();
