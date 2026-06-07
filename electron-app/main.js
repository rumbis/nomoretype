const { app, BrowserWindow, ipcMain, dialog, shell, globalShortcut } = require('electron');
const path = require('path');
const { execFile, spawn, exec } = require('child_process');
const fs = require('fs');

let mainWindow = null;
let hotkeyHelper = null;
let isRecording = false;

// ─── Hotkey Helper Path ────────────────────────────────────────────

function getHelperPath() {
  if (app.isPackaged) {
    return path.join(process.resourcesPath, 'hotkey-helper');
  }
  return path.join(__dirname, 'hotkey-helper', 'hotkey-helper');
}

// ─── Start CGEventTap Hotkey Helper ────────────────────────────────

function startHotkeyHelper() {
  const helperPath = getHelperPath();

  if (!fs.existsSync(helperPath)) {
    console.warn('Hotkey helper not found at:', helperPath);
    return;
  }

  // Kill any existing instance
  if (hotkeyHelper) {
    hotkeyHelper.kill();
    hotkeyHelper = null;
  }

  try {
    hotkeyHelper = spawn(helperPath, [], {
      stdio: ['ignore', 'pipe', 'pipe'],
    });

    let buffer = '';
    hotkeyHelper.stdout.on('data', (data) => {
      buffer += data.toString();
      const lines = buffer.split('\n');
      buffer = lines.pop() || '';

      for (const line of lines) {
        if (!line.trim()) continue;
        try {
          const msg = JSON.parse(line);
          handleHelperMessage(msg);
        } catch {}
      }
    });

    hotkeyHelper.stderr.on('data', (data) => {
      console.warn('[hotkey-helper]', data.toString());
    });

    hotkeyHelper.on('exit', (code) => {
      console.log(`[hotkey-helper] exited (${code}), restarting in 2s...`);
      hotkeyHelper = null;
      setTimeout(startHotkeyHelper, 2000);
    });

    console.log('[hotkey-helper] started');
  } catch (err) {
    console.error('[hotkey-helper] failed to start:', err.message);
  }
}

function handleHelperMessage(msg) {
  if (!mainWindow || mainWindow.isDestroyed()) return;

  switch (msg.event) {
    case 'double-tap':
      // Show & focus the app
      if (mainWindow.isMinimized()) mainWindow.restore();
      mainWindow.showInactive()
      mainWindow.setVisibleOnAllWorkspaces(true);
      mainWindow.focus();
      mainWindow.setVisibleOnAllWorkspaces(false);
      // Start recording
      mainWindow.webContents.send('global:hotkey', 'start-recording');
      break;

    case 'single-tap':
      // Toggle recording (stop if recording, start if not)
      mainWindow.webContents.send('global:hotkey', 'toggle-recording');
      break;

    case 'started':
      console.log('[hotkey-helper] CGEventTap running');
      break;

    case 'permission-granted':
      console.log('[hotkey-helper] Accessibility permission granted');
      break;

    default:
      if (msg.error) {
        console.warn('[hotkey-helper]', msg.error);
        // Notify renderer about accessibility requirement
        mainWindow.webContents.send('global:hotkey', 'accessibility-required');
      }
  }
}

// ─── Fallback GlobalShortcuts (when CGEventTap unavailable) ────────

function registerFallbackShortcuts() {
  globalShortcut.unregisterAll();

  const fallbacks = ['CommandOrControl+Shift+R', 'F6'];
  for (const shortcut of fallbacks) {
    try {
      globalShortcut.register(shortcut, () => {
        if (mainWindow && !mainWindow.isDestroyed()) {
          mainWindow.webContents.send('global:hotkey', 'toggle-recording');
          if (mainWindow.isMinimized()) mainWindow.restore();
          mainWindow.focus();
        }
      });
    } catch {}
  }
}

// ─── IPC: Renderer tells main about recording state ────────────────

ipcMain.handle('recording:state', (_, state) => {
  isRecording = state === 'recording';
});

// ─── IPC: Custom shortcuts ──────────────────────────────────────────

let registeredCustom = null;

ipcMain.handle('shortcut:register', (_, shortcut) => {
  if (registeredCustom) {
    try { globalShortcut.unregister(registeredCustom); } catch {}
  }
  registeredCustom = null;
  if (shortcut) {
    try {
      globalShortcut.register(shortcut, () => {
        if (mainWindow && !mainWindow.isDestroyed()) {
          mainWindow.webContents.send('global:hotkey', 'toggle-recording');
          if (mainWindow.isMinimized()) mainWindow.restore();
          mainWindow.focus();
        }
      });
      registeredCustom = shortcut;
      return true;
    } catch { return false; }
  }
  return true;
});

ipcMain.handle('shortcut:unregisterAll', () => {
  globalShortcut.unregisterAll();
  registerFallbackShortcuts();
  registeredCustom = null;
  return true;
});

ipcMain.handle('helper:restart', () => {
  startHotkeyHelper();
  return true;
});

// ─── App Lifecycle ──────────────────────────────────────────────────

app.whenReady().then(() => {
  createWindow();
  startHotkeyHelper();
  registerFallbackShortcuts();
});

app.on('will-quit', () => {
  globalShortcut.unregisterAll();
  if (hotkeyHelper) { hotkeyHelper.kill(); hotkeyHelper = null; }
});

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit();
});

app.on('activate', () => {
  if (BrowserWindow.getAllWindows().length === 0) createWindow();
});

// ─── Create Window ──────────────────────────────────────────────────

function createWindow() {
  mainWindow = new BrowserWindow({
    width: 1100,
    height: 750,
    minWidth: 850,
    minHeight: 600,
    title: 'NoMoreType',
    backgroundColor: '#0e0e0e',
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: false,
    },
  });

  mainWindow.loadFile(
    app.isPackaged
      ? path.join(process.resourcesPath, 'web-app', 'index.html')
      : path.join(__dirname, '..', 'web-app', 'index.html')
  );
}

// ─── File Dialog ────────────────────────────────────────────────────

ipcMain.handle('dialog:openFile', async () => {
  const result = await dialog.showOpenDialog(mainWindow, {
    properties: ['openFile'],
    filters: [{ name: 'Audio & Video', extensions: ['mp3', 'm4a', 'wav', 'flac', 'ogg', 'mp4', 'webm', 'mov', 'aac', 'wma'] }],
  });
  if (result.canceled) return null;
  const fp = result.filePaths[0];
  const stat = fs.statSync(fp);
  return { path: fp, name: path.basename(fp), size: stat.size, ext: path.extname(fp).toLowerCase().replace('.', '') };
});

ipcMain.handle('file:readChunk', async (_, filePath, offset, length) => {
  const fd = fs.openSync(filePath, 'r');
  const buf = Buffer.alloc(length);
  const br = fs.readSync(fd, buf, 0, length, offset);
  fs.closeSync(fd);
  return buf.slice(0, br).toString('base64');
});

ipcMain.handle('file:getSize', async (_, filePath) => fs.statSync(filePath).size);

ipcMain.handle('yt-dlp:check', async () => {
  const candidates = ['/opt/homebrew/bin/yt-dlp', '/usr/local/bin/yt-dlp', 'yt-dlp'];
  for (const bin of candidates) {
    try {
      await new Promise((res, rej) => execFile(bin, ['--version'], { timeout: 5000 }, (e, o) => e ? rej(e) : res(o)));
      return bin;
    } catch {}
  }
  return null;
});

ipcMain.handle('yt-dlp:execute', async (_, ...args) => {
  return new Promise((res, rej) => {
    exec(args.join(' '), { timeout: 120000, maxBuffer: 50 * 1024 * 1024 }, (e, o, er) => e ? rej(er || e.message) : res(o));
  });
});

ipcMain.handle('dialog:saveFile', async (_, defaultName) => {
  const result = await dialog.showSaveDialog(mainWindow, { defaultPath: defaultName, filters: [{ name: 'Text', extensions: ['txt', 'srt'] }] });
  if (result.canceled) return null;
  return result.filePath;
});

ipcMain.handle('fs:writeFile', async (_, filePath, content) => {
  fs.writeFileSync(filePath, content, 'utf-8');
  return true;
});

ipcMain.handle('shell:showItem', async (_, filePath) => shell.showItemInFolder(filePath));

ipcMain.handle('app:platform', () => process.platform);
ipcMain.handle('app:userDataPath', () => app.getPath('userData'));
