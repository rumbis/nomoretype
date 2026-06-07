/* ═══════════════════════════════════════════════════════════════════════════
   Platform Bridge — Unified API across Electron, Capacitor, and Web/PWA
   ═══════════════════════════════════════════════════════════════════════════ */

'use strict';

window.Platform = (() => {

  // ── Detection ────────────────────────────────────────────────────

  const isElectron = !!(window.electronAPI);
  const isCapacitor = !!(window.Capacitor?.isNativePlatform);
  const isWeb = !isElectron && !isCapacitor;
  const isMobile = /Android|iPhone|iPad|iPod/i.test(navigator.userAgent);
  const isIOS = /iPhone|iPad|iPod/i.test(navigator.userAgent);

  function log(...args) {
    console.log('[Platform]', ...args);
  }

  // ── File Picker ──────────────────────────────────────────────────

  async function pickFile() {
    // Electron: native dialog
    if (isElectron) {
      try {
        const info = await window.electronAPI.openFileDialog();
        if (!info) return null;
        return {
          name: info.name,
          size: info.size,
          path: info.path,
          blob: null, // will be lazy-loaded
          _electronFile: info,
        };
      } catch (err) {
        log('Electron file picker failed:', err);
        return null;
      }
    }

    // Web / Capacitor: <input type="file">
    return new Promise((resolve) => {
      const input = document.createElement('input');
      input.type = 'file';
      input.accept = '.mp3,.m4a,.wav,.flac,.ogg,.mp4,.webm,.mov,.aac,.wma,.wmv,.mpeg';
      input.onchange = async () => {
        const file = input.files?.[0];
        if (!file) { resolve(null); return; }
        resolve({
          name: file.name,
          size: file.size,
          path: file.name, // no real path on web
          blob: file,
          _file: file,
        });
      };
      input.click();
    });
  }

  // ── Read File as Blob ────────────────────────────────────────────

  async function readFileAsBlob(fileInfo) {
    if (fileInfo.blob) return fileInfo.blob;

    // Electron: read via IPC chunks
    if (isElectron && fileInfo._electronFile) {
      const ef = fileInfo._electronFile;
      const CHUNK = 4 * 1024 * 1024;
      const parts = [];
      let offset = 0;
      while (offset < ef.size) {
        const len = Math.min(CHUNK, ef.size - offset);
        const b64 = await window.electronAPI.readFileChunk(ef.path, offset, len);
        const bin = atob(b64);
        const bytes = new Uint8Array(bin.length);
        for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
        parts.push(bytes);
        offset += len;
      }
      const all = new Uint8Array(ef.size);
      let pos = 0;
      for (const p of parts) { all.set(p, pos); pos += p.length; }
      return new Blob([all]);
    }

    // Web / Capacitor: already have the File object
    if (fileInfo._file) return fileInfo._file;

    throw new Error('Cannot read file: no blob or path available');
  }

  // ── Save File ────────────────────────────────────────────────────

  async function saveFile(content, defaultName, mimeType = 'text/plain') {
    // Electron: native save dialog + fs.writeFile
    if (isElectron) {
      try {
        const savePath = await window.electronAPI.saveFileDialog(defaultName);
        if (!savePath) return false;
        await window.electronAPI.writeFile(savePath, content);
        return true;
      } catch (err) {
        log('Electron save failed:', err);
        return false;
      }
    }

    // Web / Capacitor: download via Blob
    const blob = new Blob([content], { type: mimeType });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = defaultName;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    URL.revokeObjectURL(url);
    return true;
  }

  // ── Show item in folder (Electron only) ──────────────────────────

  async function showItemInFolder(filePath) {
    if (isElectron) {
      try {
        await window.electronAPI.showItemInFolder(filePath);
      } catch {}
    }
  }

  // ── Execute shell command (yt-dlp etc.) ──────────────────────────

  async function execCommand(cmd) {
    if (isElectron) {
      return window.electronAPI.execYtDlp(cmd);
    }
    throw new Error('Shell commands not available on this platform');
  }

  // ── Check yt-dlp availability ────────────────────────────────────

  async function checkYtDlp() {
    if (isElectron) {
      return window.electronAPI.checkYtDlp();
    }
    return null; // yt-dlp not available on web/mobile
  }

  // ── Open URL ─────────────────────────────────────────────────────

  function openUrl(url) {
    if (isElectron) {
      const { shell } = require('electron');
      // Not available in renderer — use external link
      window.open(url, '_blank');
    } else {
      window.open(url, '_blank');
    }
  }

  // ── Get user data path ───────────────────────────────────────────

  async function getUserDataPath() {
    if (isElectron) {
      return window.electronAPI.userDataPath();
    }
    // Fallback for web: use localStorage as storage
    return 'localStorage';
  }

  // ── Copy to clipboard ────────────────────────────────────────────

  async function copyToClipboard(text) {
    try {
      await navigator.clipboard.writeText(text);
      return true;
    } catch {
      // Fallback
      const ta = document.createElement('textarea');
      ta.value = text;
      document.body.appendChild(ta);
      ta.select();
      document.execCommand('copy');
      document.body.removeChild(ta);
      return true;
    }
  }

  // ── YouTube URL validation ───────────────────────────────────────

  function isValidYoutubeUrl(url) {
    return /(?:youtube\.com|youtu\.be)/i.test(url);
  }

  // ── Public API ───────────────────────────────────────────────────

  return {
    isElectron,
    isCapacitor,
    isWeb,
    isMobile,
    isIOS,
    pickFile,
    readFileAsBlob,
    saveFile,
    showItemInFolder,
    execCommand,
    checkYtDlp,
    openUrl,
    getUserDataPath,
    copyToClipboard,
    isValidYoutubeUrl,
    log,
  };
})();
