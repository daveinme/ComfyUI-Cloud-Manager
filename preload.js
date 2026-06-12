const { contextBridge, ipcRenderer } = require('electron')

contextBridge.exposeInMainWorld('api', {
  // Config
  loadConfig:        ()    => ipcRenderer.invoke('load-config'),
  saveConfig:        (c)   => ipcRenderer.invoke('save-config', c),

  // SSH Key
  generateSshKey:    ()    => ipcRenderer.invoke('generate-ssh-key'),
  pickSshKey:        ()    => ipcRenderer.invoke('pick-ssh-key'),
  scanSshKeys:       ()    => ipcRenderer.invoke('scan-ssh-keys'),

  // Finestra log staccabile
  openLogWindow:     ()    => ipcRenderer.invoke('open-log-window'),

  // Folder picker
  pickFolder:        ()    => ipcRenderer.invoke('pick-folder'),

  // Libreria script
  getLibrary:        ()    => ipcRenderer.invoke('get-library'),
  pickScript:        ()    => ipcRenderer.invoke('pick-script'),
  addToLibrary:      ()    => ipcRenderer.invoke('add-to-library'),

  // Operazioni remote
  testConnection:    (p)   => ipcRenderer.invoke('test-connection', p),
  deployScript:      (p)   => ipcRenderer.invoke('deploy-script', p),
  stopScript:        ()    => ipcRenderer.invoke('stop-script'),
  downloadCivitai:   (p)   => ipcRenderer.invoke('download-civitai', p),
  fetchOutput:       (p)   => ipcRenderer.invoke('fetch-output', p),
  openInBrowser:     (p)   => ipcRenderer.invoke('open-in-browser', p),

  // Watch output (background)
  watchStart:        (p)   => ipcRenderer.invoke('watch-start', p),
  watchStop:         ()    => ipcRenderer.invoke('watch-stop'),

  // GPU Monitor
  gpuStart:          (p)   => ipcRenderer.invoke('gpu-start', p),
  gpuStop:           ()    => ipcRenderer.invoke('gpu-stop'),

  // Log streaming — payload: { text, replace }
  onLog:             (cb)  => ipcRenderer.on('log',            (_, d) => cb(d)),
  onWatch:           (cb)  => ipcRenderer.on('watch',          (_, d) => cb(d)),
  onGpu:             (cb)  => ipcRenderer.on('gpu',            (_, d) => cb(d)),
  onUpdateAvailable: (cb)  => ipcRenderer.on('update-available',(_, d) => cb(d)),
})
