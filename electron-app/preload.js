const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('electronAPI', {
  // File dialog
  openFileDialog: () => ipcRenderer.invoke('dialog:openFile'),

  // File reading (chunked for large files)
  readFileChunk: (filePath, offset, length) =>
    ipcRenderer.invoke('file:readChunk', filePath, offset, length),
  getFileSize: (filePath) => ipcRenderer.invoke('file:getSize', filePath),

  // yt-dlp
  checkYtDlp: () => ipcRenderer.invoke('yt-dlp:check'),
  execYtDlp: (...args) => ipcRenderer.invoke('yt-dlp:execute', ...args),

  // Save file
  saveFileDialog: (defaultName) => ipcRenderer.invoke('dialog:saveFile', defaultName),
  writeFile: (filePath, content) => ipcRenderer.invoke('fs:writeFile', filePath, content),

  // Shell
  showItemInFolder: (filePath) => ipcRenderer.invoke('shell:showItem', filePath),

  // Platform
  platform: () => ipcRenderer.invoke('app:platform'),
  userDataPath: () => ipcRenderer.invoke('app:userDataPath'),

  // ─── Global hotkeys ───────────────────────────────────────────────
  onGlobalHotkey: (callback) => {
    ipcRenderer.on('global:hotkey', (_event, action) => callback(action));
  },
  registerCustomShortcut: (shortcut) => ipcRenderer.invoke('shortcut:register', shortcut),
  unregisterAllShortcuts: () => ipcRenderer.invoke('shortcut:unregisterAll'),
  setRecordingState: (state) => ipcRenderer.invoke('recording:state', state),
  restartHelper: () => ipcRenderer.invoke('helper:restart'),
});
