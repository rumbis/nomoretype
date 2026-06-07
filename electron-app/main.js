const { app, BrowserWindow, ipcMain, dialog, shell, globalShortcut, clipboard } = require('electron');
const path = require('path');
const { execFile, spawn, exec } = require('child_process');
const fs = require('fs');

let mainWindow = null;
let hotkeyHelper = null;
let isRecording = false;
let previousAppBundleId = null;
let accessibilityOpened = false;

function getHelperPath() {
  if (app.isPackaged) return path.join(process.resourcesPath, 'hotkey-helper');
  return path.join(__dirname, 'hotkey-helper', 'hotkey-helper');
}

function getFrontmostApp() {
  return new Promise(r => exec("osascript -e 'tell application \"System Events\" to get bundle identifier of first process whose frontmost is true'", {timeout:3000}, (e,o) => r(e ? null : o.trim())));
}

async function insertTextAtCursor(text) {
  const target = previousAppBundleId;
  if (!target) return;
  const old = clipboard.readText();
  try {
    clipboard.writeText(text);
    await new Promise(r => setTimeout(r, 100));
    if (mainWindow && !mainWindow.isDestroyed()) mainWindow.hide();
    await new Promise(r => exec(`osascript -e 'tell application id "${target}" to activate'`, {timeout:3000}, () => r()));
    await new Promise(r => setTimeout(r, 200));
    await new Promise(r => exec("osascript -e 'tell application \"System Events\" to keystroke \"v\" using command down'", {timeout:3000}, () => r()));
    setTimeout(() => { try { clipboard.writeText(old); } catch {} }, 2000);
  } catch(e) { console.warn('insertTextAtCursor error:', e.message); try { clipboard.writeText(old); } catch {} }
}

function startHotkeyHelper() {
  const p = getHelperPath();
  if (!fs.existsSync(p)) return;
  if (hotkeyHelper) { hotkeyHelper.kill(); hotkeyHelper = null; }
  try {
    hotkeyHelper = spawn(p, [], { stdio: ['ignore', 'pipe', 'pipe'] });
    let buf = '';
    hotkeyHelper.stdout.on('data', d => {
      buf += d.toString();
      let i; while ((i = buf.indexOf('\n')) !== -1) {
        const line = buf.slice(0, i).trim(); buf = buf.slice(i + 1);
        if (!line) continue;
        try { handleMsg(JSON.parse(line)); } catch(e) { console.warn('[hotkey-helper] parse error:', e.message); }
      }
    });
    hotkeyHelper.stderr.on('data', d => console.warn('[hotkey-helper]', d.toString()));
    hotkeyHelper.on('exit', c => { console.log(`[hotkey-helper] exited ${c}`); hotkeyHelper = null; setTimeout(startHotkeyHelper, 2000); });
    console.log('[hotkey-helper] started');
  } catch(e) { console.error('[hotkey-helper] failed:', e.message); }
}

async function handleMsg(msg) {
  if (!mainWindow || mainWindow.isDestroyed()) return;
  switch (msg.event) {
    case 'double-tap':
      previousAppBundleId = await getFrontmostApp();
      console.log('[hotkey] Prev app:', previousAppBundleId);
      if (mainWindow.isMinimized()) mainWindow.restore();
      mainWindow.show(); mainWindow.focus();
      mainWindow.webContents.send('global:hotkey', 'start-recording');
      break;
    case 'single-tap':
      if (isRecording) mainWindow.webContents.send('global:hotkey', 'stop-recording');
      break;
    case 'started': console.log('[hotkey-helper] running'); break;
    case 'permission-granted': console.log('[hotkey-helper] permission granted'); break;
    default:
      console.log('[hotkey-helper] event:', JSON.stringify(msg));
      if (msg.error) {
        mainWindow.webContents.send('global:hotkey', 'accessibility-required');
        if (!accessibilityOpened) {
          accessibilityOpened = true;
          exec("open 'x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility'");
          setTimeout(() => {
            if (hotkeyHelper) { hotkeyHelper.kill(); hotkeyHelper = null; }
            startHotkeyHelper();
          }, 10000);
        }
      }
  }
}

function registerFallbackShortcuts() {
  globalShortcut.unregisterAll();
  for (const s of ['CommandOrControl+Shift+R', 'F6']) {
    try {
      globalShortcut.register(s, () => {
        if (mainWindow && !mainWindow.isDestroyed()) {
          mainWindow.webContents.send('global:hotkey', 'toggle-recording');
          if (mainWindow.isMinimized()) mainWindow.restore();
          mainWindow.focus();
        }
      });
    } catch {}
  }
}

ipcMain.handle('recording:state', (_, s) => { isRecording = s === 'recording'; });
ipcMain.handle('transcription:insert', async (_, t) => { if (t) try { await insertTextAtCursor(t); } catch(e) { console.warn('insert failed:', e.message); } });
ipcMain.handle('transcription:show', async () => { if (mainWindow && !mainWindow.isDestroyed()) { mainWindow.show(); mainWindow.focus(); } });

let registeredCustom = null;
ipcMain.handle('shortcut:register', (_, s) => {
  if (registeredCustom) try { globalShortcut.unregister(registeredCustom); } catch {}
  registeredCustom = null;
  if (s) {
    try {
      globalShortcut.register(s, () => {
        if (mainWindow && !mainWindow.isDestroyed()) { mainWindow.webContents.send('global:hotkey', 'toggle-recording'); mainWindow.show(); mainWindow.focus(); }
      });
      registeredCustom = s; return true;
    } catch { return false; }
  }
  return true;
});
ipcMain.handle('shortcut:unregisterAll', () => { globalShortcut.unregisterAll(); registerFallbackShortcuts(); registeredCustom = null; return true; });
ipcMain.handle('helper:restart', () => { startHotkeyHelper(); return true; });

app.whenReady().then(() => { createWindow(); startHotkeyHelper(); registerFallbackShortcuts(); });
app.on('will-quit', () => { globalShortcut.unregisterAll(); if (hotkeyHelper) { hotkeyHelper.kill(); hotkeyHelper = null; } });
app.on('window-all-closed', () => { if (process.platform !== 'darwin') app.quit(); });
app.on('activate', () => { if (BrowserWindow.getAllWindows().length === 0) createWindow(); else if (mainWindow) { mainWindow.show(); mainWindow.focus(); } });

function createWindow() {
  mainWindow = new BrowserWindow({
    width: 1100, height: 750, minWidth: 850, minHeight: 600,
    title: 'NoMoreType', backgroundColor: '#0e0e0e', show: true,
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true, nodeIntegration: false, sandbox: false,
    },
  });
  mainWindow.loadFile(
    app.isPackaged
      ? path.join(process.resourcesPath, 'web-app', 'index.html')
      : path.join(__dirname, '..', 'web-app', 'index.html')
  );
}

ipcMain.handle('dialog:openFile', async () => {
  const r = await dialog.showOpenDialog(mainWindow, { properties: ['openFile'], filters: [{name:'Audio & Video', extensions:['mp3','m4a','wav','flac','ogg','mp4','webm','mov','aac','wma']}] });
  if (r.canceled) return null;
  const f = r.filePaths[0], s = fs.statSync(f);
  return { path: f, name: path.basename(f), size: s.size, ext: path.extname(f).toLowerCase().replace('.','') };
});
ipcMain.handle('file:readChunk', async (_, fp, off, len) => { const fd = fs.openSync(fp,'r'); const b = Buffer.alloc(len); const br = fs.readSync(fd,b,0,len,off); fs.closeSync(fd); return b.slice(0,br).toString('base64'); });
ipcMain.handle('file:getSize', async (_, fp) => fs.statSync(fp).size);
ipcMain.handle('yt-dlp:check', async () => { for (const b of ['/opt/homebrew/bin/yt-dlp','/usr/local/bin/yt-dlp','yt-dlp']) { try { await new Promise((res,rej) => execFile(b,['--version'],{timeout:5000},(e,o) => e?rej(e):res(o))); return b; } catch {} } return null; });
ipcMain.handle('yt-dlp:execute', async (_, ...a) => new Promise((res,rej) => exec(a.join(' '),{timeout:120000,maxBuffer:50*1024*1024},(e,o,er) => e?rej(er||e.message):res(o))));
ipcMain.handle('dialog:saveFile', async (_, n) => { const r = await dialog.showSaveDialog(mainWindow,{defaultPath:n,filters:[{name:'Text',extensions:['txt','srt']}]}); return r.canceled ? null : r.filePath; });
ipcMain.handle('fs:writeFile', async (_, fp, c) => { fs.writeFileSync(fp,c,'utf-8'); return true; });
ipcMain.handle('shell:showItem', async (_, fp) => shell.showItemInFolder(fp));
ipcMain.handle('app:platform', () => process.platform);
ipcMain.handle('app:userDataPath', () => app.getPath('userData'));
