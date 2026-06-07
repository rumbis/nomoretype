const { app, BrowserWindow, ipcMain, dialog, shell } = require('electron');
const path = require('path');
const { execFile, exec } = require('child_process');
const fs = require('fs');
const os = require('os');

let mainWindow = null;

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

  mainWindow.loadFile(path.join(__dirname, '..', 'web-app', 'index.html'));
}

app.whenReady().then(createWindow);

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit();
});

app.on('activate', () => {
  if (BrowserWindow.getAllWindows().length === 0) createWindow();
});

// ─── File Dialog ────────────────────────────────────────────────────

ipcMain.handle('dialog:openFile', async () => {
  const result = await dialog.showOpenDialog(mainWindow, {
    properties: ['openFile'],
    filters: [
      {
        name: 'Audio & Video',
        extensions: ['mp3', 'm4a', 'wav', 'flac', 'ogg', 'mp4', 'webm', 'mov', 'aac', 'wma'],
      },
    ],
  });
  if (result.canceled) return null;
  const filePath = result.filePaths[0];
  const stats = fs.statSync(filePath);
  return {
    path: filePath,
    name: path.basename(filePath),
    size: stats.size,
    ext: path.extname(filePath).toLowerCase().replace('.', ''),
  };
});

// ─── Read File (chunked) ────────────────────────────────────────────

ipcMain.handle('file:readChunk', async (_, filePath, offset, length) => {
  const fd = fs.openSync(filePath, 'r');
  const buffer = Buffer.alloc(length);
  const bytesRead = fs.readSync(fd, buffer, 0, length, offset);
  fs.closeSync(fd);
  return buffer.slice(0, bytesRead).toString('base64');
});

ipcMain.handle('file:getSize', async (_, filePath) => {
  return fs.statSync(filePath).size;
});

// ─── Get yt-dlp path ────────────────────────────────────────────────

ipcMain.handle('yt-dlp:check', async () => {
  const candidates = ['/opt/homebrew/bin/yt-dlp', '/usr/local/bin/yt-dlp', 'yt-dlp'];
  for (const bin of candidates) {
    try {
      await new Promise((resolve, reject) => {
        execFile(bin, ['--version'], { timeout: 5000 }, (err, stdout) => {
          err ? reject(err) : resolve(stdout.trim());
        });
      });
      return bin;
    } catch {
      continue;
    }
  }
  return null;
});

ipcMain.handle('yt-dlp:execute', async (_, ...args) => {
  return new Promise((resolve, reject) => {
    exec(args.join(' '), { timeout: 120000, maxBuffer: 50 * 1024 * 1024 }, (err, stdout, stderr) => {
      if (err) return reject(stderr || err.message);
      resolve(stdout);
    });
  });
});

// ─── Save file dialog ───────────────────────────────────────────────

ipcMain.handle('dialog:saveFile', async (_, defaultName) => {
  const result = await dialog.showSaveDialog(mainWindow, {
    defaultPath: defaultName,
    filters: [{ name: 'Text', extensions: ['txt', 'srt'] }],
  });
  if (result.canceled) return null;
  return result.filePath;
});

ipcMain.handle('fs:writeFile', async (_, filePath, content) => {
  fs.writeFileSync(filePath, content, 'utf-8');
  return true;
});

// ─── Open in Finder/Explorer ────────────────────────────────────────

ipcMain.handle('shell:showItem', async (_, filePath) => {
  shell.showItemInFolder(filePath);
});

// ─── Platform info ──────────────────────────────────────────────────

ipcMain.handle('app:platform', () => process.platform);
ipcMain.handle('app:userDataPath', () => app.getPath('userData'));
