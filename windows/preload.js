const { contextBridge, ipcRenderer, clipboard } = require('electron');

contextBridge.exposeInMainWorld('trellis', {
  loadLibrary: () => ipcRenderer.invoke('library:load'),
  saveLibrary: (data) => ipcRenderer.invoke('library:save', data),
  chooseDirectory: () => ipcRenderer.invoke('dialog:directory'),
  createProject: (payload) => ipcRenderer.invoke('fs:createProject', payload),
  renameDir: (payload) => ipcRenderer.invoke('fs:renameDir', payload),
  suggestName: (target, base) => ipcRenderer.invoke('fs:suggestName', { target, base }),
  reveal: (target) => ipcRenderer.invoke('fs:reveal', target),
  exportTemplate: (name, data) => ipcRenderer.invoke('dialog:exportTemplate', { name, data }),
  importTemplate: () => ipcRenderer.invoke('dialog:importTemplate'),
  version: () => ipcRenderer.invoke('app:version'),
  readClipboard: () => clipboard.readText(),
  onMenuImport: (cb) => ipcRenderer.on('menu-import', () => cb()),
  onMenuExport: (cb) => ipcRenderer.on('menu-export', () => cb())
});
