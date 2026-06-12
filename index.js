const { app, BrowserWindow, ipcMain, dialog, shell, Tray, Menu, nativeImage } = require('electron')
const { spawn, execFile } = require('child_process')
const fs   = require('fs')
const path = require('path')
const os   = require('os')

const CONFIG_PATH   = path.join(os.homedir(), '.config', 'comfy-cloud-manager', 'config.json')
const DOWNLOAD_DIR  = path.join(__dirname, 'scripts', 'download')
const SSH_KEY_PATH  = path.join(os.homedir(), '.ssh', 'comfy_manager')

// Script filename → display metadata
const LIBRARY_META = {
  '10Eros_v1-fp8mixed.sh':              { name: '10Eros v1 FP8',              gb: '~65 GB', category: 'video', author: 'LTX Studio',    desc: 'LTX 2.3 checkpoint + Gemma 3 12B encoder + upscaler' },
  'Sulphur2-dev-FP8-mixed.sh':          { name: 'Sulphur-2 FP8',              gb: '~43 GB', category: 'video', author: 'LTX Studio',    desc: 'LTX 2.3 Sulphur-2 checkpoint + encoder + VAE' },
  'LTX23-Distilled-1.1.sh':             { name: 'LTX 2.3 Distilled 1.1',      gb: '~55 GB', category: 'video', author: 'LTX Studio',    desc: 'LTX 2.3 22B distilled full pack + IC-LoRA + enhancers' },
  'Wan22_Bernini_fp8.sh':               { name: 'Wan 2.2 Bernini FP8',        gb: '~43 GB', category: 'video', author: 'Wan Video',     desc: 'Bernini HIGH+LOW 14B FP8 + UMT5 encoder + Lightning LoRA' },
  'wan2.2_i2v_high_noise_14B_fp8_scaled.sh': { name: 'Wan 2.2 I2V FP8',      gb: '~29 GB', category: 'video', author: 'Wan Video',     desc: 'Wan 2.2 Image-to-Video High+Low noise 14B FP8' },
  'FireRed-Image-Edit.1.1.sh':          { name: 'FireRed Image Edit 1.1',      gb: '~20 GB', category: 'image', author: 'FireRed',       desc: 'FireRed 1.1 transformer + Qwen 2.5 VL encoder + Lightning LoRA' },
  'Qwen-Image-Edit-Rapid-AIO-V23.sh':   { name: 'Qwen Image Edit AIO v23',    gb: '~35 GB', category: 'image', author: 'Qwen / Alibaba', desc: 'Qwen-Image-Edit-Rapid AIO NSFW v23 + encoder + VAE' },
  'Z-Image-Turbo-FP8.sh':              { name: 'Z-Image Turbo FP8',           gb: '~20 GB', category: 'image', author: 'Z-Image',       desc: 'Z-Image Turbo diffusion BF16 + Qwen 3.4B FP8 encoder' },
}

let win, tray, logWin
let watchProc  = null
let gpuProc    = null
let deployProc = null

// --- Finestra principale ---

function createWindow() {
  win = new BrowserWindow({
    width: 1100,
    height: 720,
    minWidth: 820,
    minHeight: 560,
    title: 'ComfyUI Cloud Manager',
    icon: path.join(__dirname, 'assets', 'icon.png'),
    webPreferences: {
      nodeIntegration: false,
      contextIsolation: true,
      preload: path.join(__dirname, 'preload.js')
    }
  })
  win.loadFile('index.html')
  win.setMenuBarVisibility(false)
}

// --- System tray ---

function createTray() {
  const icon = nativeImage.createEmpty()
  tray = new Tray(icon)
  tray.setToolTip('ComfyUI Cloud Manager')
  updateTrayMenu()
}

function updateTrayMenu(watchActive = false, newFiles = 0) {
  const label = watchActive
    ? `Watch active${newFiles > 0 ? ` — ${newFiles} new files` : ''}`
    : 'Watch not active'
  const menu = Menu.buildFromTemplate([
    { label: 'ComfyUI Cloud Manager', enabled: false },
    { type: 'separator' },
    { label, enabled: false },
    { type: 'separator' },
    { label: 'Show window', click: () => { win.show(); win.focus() } },
    { label: 'Quit', click: () => app.quit() }
  ])
  tray.setContextMenu(menu)
}

// --- Config ---

function loadConfig() {
  try { return JSON.parse(fs.readFileSync(CONFIG_PATH, 'utf8')) }
  catch { return { conn: null, civitaiToken: '', hfToken: '', localOutputPaths: defaultOutputPaths() } }
}

function defaultOutputPaths() {
  const home = os.homedir()
  // Try localized desktop names common on Linux (Italian, Spanish, French, German)
  const candidates = ['Desktop', 'Scrivania', 'Escritorio', 'Bureau', 'Schreibtisch']
  let desktop = path.join(home, 'Desktop')
  for (const name of candidates) {
    const p = path.join(home, name)
    if (fs.existsSync(p)) { desktop = p; break }
  }
  return [{ label: 'Desktop', path: desktop }]
}

function saveConfig(config) {
  fs.mkdirSync(path.dirname(CONFIG_PATH), { recursive: true })
  fs.writeFileSync(CONFIG_PATH, JSON.stringify(config, null, 2), { mode: 0o600 })
}

// --- SSH helpers ---

function sshArgs(conn) {
  return [
    '-p', conn.port,
    '-i', conn.sshKey,
    '-o', 'StrictHostKeyChecking=no',
    '-o', 'ConnectTimeout=15',
    '-o', 'BatchMode=yes'
  ]
}

function outputPath(conn) {
  // Se l'utente ha personalizzato il percorso, usalo
  if (conn.outputPath) return conn.outputPath
  return conn.provider === 'runpod'
    ? '/workspace/runpod-slim/ComfyUI/output'
    : '/workspace/ComfyUI/output'
}

function modelsBase(conn) {
  if (conn.modelsPath) return conn.modelsPath
  return conn.provider === 'runpod'
    ? '/workspace/runpod-slim/ComfyUI/models'
    : '/workspace/ComfyUI/models'
}

// Log lines to suppress (provider system messages)
const LOG_SUPPRESS = [
  /Welcome to vast\.ai/,
  /If authentication fails, try again/,
  /Have fun!/,
  /^\s*$/,
]

function filterLogLine(line) {
  return LOG_SUPPRESS.some(re => re.test(line))
}

function cleanOutput(raw) {
  return raw
    .split('\n')
    .filter(line => !filterLogLine(line))
    .join('\n')
    // Evita blocchi di righe vuote consecutive
    .replace(/\n{3,}/g, '\n\n')
}

// Regex che individua righe di progresso wget/curl (sovrascrivibili con \r)
const PROGRESS_RE = /(\d+)%|\d+[KMG].*--:--|^\s*\d+\s+\d+[KMG]/

// Streamma stdout/stderr di un processo sul canale IPC indicato.
// Invia { text, replace: bool } — replace=true quando è una riga progress in-place.
function streamProc(event, args, channel, procRef) {
  return new Promise((resolve) => {
    const proc = spawn(args[0], args.slice(1))
    if (procRef) procRef.current = proc

    let lineBuffer = ''

    const sendChunk = (raw) => {
      // Splitto su \r e \n per gestire progress bar in-place
      const parts = raw.split(/(\r|\n)/)
      for (const part of parts) {
        if (part === '\n') {
          const cleaned = cleanOutput(lineBuffer)
          if (cleaned.trim()) {
            event.sender.send(channel, { text: cleaned + '\n', replace: false })
            sendToLogWin(channel, cleaned + '\n')
          }
          lineBuffer = ''
        } else if (part === '\r') {
          // Carriage return = sovrascrittura riga (progress bar wget/curl)
          if (lineBuffer.trim()) {
            const cleaned = lineBuffer.replace(/\x1b\[[0-9;]*m/g, '') // strip ANSI
            event.sender.send(channel, { text: cleaned, replace: true })
            sendToLogWin(channel, cleaned + '\n')
          }
          lineBuffer = ''
        } else {
          lineBuffer += part
        }
      }
    }

    proc.stdout.on('data', d => sendChunk(d.toString()))
    proc.stderr.on('data', d => sendChunk(d.toString()))
    proc.on('close', code => {
      if (lineBuffer.trim()) {
        event.sender.send(channel, { text: lineBuffer + '\n', replace: false })
      }
      const msg = `\n[exit: ${code}]\n`
      event.sender.send(channel, { text: msg, replace: false })
      sendToLogWin(channel, msg)
      if (procRef) procRef.current = null
      resolve(code)
    })
    proc.on('error', err => {
      const msg = `\n[error: ${err.message}]\n`
      event.sender.send(channel, { text: msg, replace: false })
      sendToLogWin(channel, msg)
      if (procRef) procRef.current = null
      resolve(-1)
    })
  })
}

// --- IPC handlers ---

ipcMain.handle('load-config', () => loadConfig())

ipcMain.handle('save-config', (_, config) => {
  saveConfig(config)
  return true
})

// Generate dedicated SSH key for the app
ipcMain.handle('generate-ssh-key', async () => {
  if (fs.existsSync(SSH_KEY_PATH)) {
    const pub = fs.readFileSync(SSH_KEY_PATH + '.pub', 'utf8').trim()
    return { existed: true, pubKey: pub, keyPath: SSH_KEY_PATH }
  }
  return new Promise((resolve) => {
    const proc = spawn('ssh-keygen', [
      '-t', 'ed25519',
      '-f', SSH_KEY_PATH,
      '-N', '',
      '-C', 'comfy-cloud-manager'
    ])
    proc.on('close', (code) => {
      if (code !== 0) { resolve({ error: 'ssh-keygen failed' }); return }
      const pub = fs.readFileSync(SSH_KEY_PATH + '.pub', 'utf8').trim()
      resolve({ existed: false, pubKey: pub, keyPath: SSH_KEY_PATH })
    })
    proc.on('error', () => resolve({ error: 'ssh-keygen not found' }))
  })
})

// File picker for alternate SSH key
ipcMain.handle('pick-ssh-key', async () => {
  const result = await dialog.showOpenDialog(win, {
    title: 'Select SSH private key',
    defaultPath: path.join(os.homedir(), '.ssh'),
    properties: ['openFile']
  })
  return result.canceled ? null : result.filePaths[0]
})

// Scans ~/.ssh/ for private key files — no hard-coded preference
ipcMain.handle('scan-ssh-keys', () => {
  const sshDir = path.join(os.homedir(), '.ssh')
  const found = []
  const skip = new Set(['.pub', 'known_hosts', 'known_hosts.old', 'authorized_keys', 'config'])

  try {
    const all = fs.readdirSync(sshDir)
    for (const f of all) {
      if (f.endsWith('.pub') || skip.has(f)) continue
      const p = path.join(sshDir, f)
      try {
        const stat = fs.statSync(p)
        if (!stat.isFile()) continue
        const head = fs.readFileSync(p, { encoding: 'utf8', flag: 'r' }).slice(0, 80)
        if (head.includes('PRIVATE KEY') || head.includes('BEGIN OPENSSH')) {
          found.push({ name: f, path: p })
        }
      } catch {}
    }
  } catch {}

  return found
})

// File picker for local folder
ipcMain.handle('pick-folder', async () => {
  const result = await dialog.showOpenDialog(win, {
    title: 'Select destination folder',
    properties: ['openDirectory', 'createDirectory']
  })
  return result.canceled ? null : result.filePaths[0]
})

// File picker for custom script
ipcMain.handle('pick-script', async () => {
  const result = await dialog.showOpenDialog(win, {
    title: 'Select .sh script',
    defaultPath: DOWNLOAD_DIR,
    filters: [{ name: 'Shell Script', extensions: ['sh'] }]
  })
  return result.canceled ? null : result.filePaths[0]
})

// Libreria script dalla cartella download
ipcMain.handle('get-library', () => {
  try {
    const files = fs.readdirSync(DOWNLOAD_DIR).filter(f => f.endsWith('.sh'))
    return files.map(f => ({
      file: f,
      path: path.join(DOWNLOAD_DIR, f),
      ...(LIBRARY_META[f] || { name: f.replace('.sh', ''), gb: '', category: 'other', desc: '' })
    }))
  } catch { return [] }
})

// Aggiunge uno script custom alla libreria (copia in scripts/download/)
ipcMain.handle('add-to-library', async () => {
  const result = await dialog.showOpenDialog(win, {
    title: 'Add script to library',
    filters: [{ name: 'Shell Script', extensions: ['sh'] }],
    properties: ['openFile']
  })
  if (result.canceled || !result.filePaths.length) return null
  const src  = result.filePaths[0]
  const name = path.basename(src)
  const dest = path.join(DOWNLOAD_DIR, name)
  if (fs.existsSync(dest)) return { error: `"${name}" already exists in the library.` }
  fs.copyFileSync(src, dest)
  return { file: name, path: dest, name: name.replace('.sh', ''), gb: '', category: 'other', desc: '' }
})

// Test connessione
ipcMain.handle('test-connection', async (event, conn) => {
  const args = ['ssh', ...sshArgs(conn), `root@${conn.host}`,
    "echo '=== CONNESSIONE OK ===' && uname -a && echo '' && nvidia-smi --query-gpu=name,memory.total --format=csv,noheader 2>/dev/null && echo '' && df -h /workspace 2>/dev/null || df -h /"
  ]
  return streamProc(event, args, 'log')
})

// Deploy script (da libreria o custom) con progresso migliorato
ipcMain.handle('deploy-script', async (event, { conn, scriptPath, hfToken }) => {
  const remote = '/tmp/' + path.basename(scriptPath)
  const key = conn.sshKey
  const token = hfToken || ''

  event.sender.send('log', { text: `\n📤 Uploading ${path.basename(scriptPath)}...\n`, replace: false })
  const scpArgs = [
    'scp', '-P', conn.port, '-i', key,
    '-o', 'StrictHostKeyChecking=no',
    scriptPath, `root@${conn.host}:${remote}`
  ]
  const scpRef = { current: null }
  deployProc = scpRef
  const scpCode = await streamProc(event, scpArgs, 'log', scpRef)
  if (scpCode !== 0) return scpCode

  event.sender.send('log', { text: `\n🚀 Running ${path.basename(scriptPath)}...\n`, replace: false })

  const envExport = token ? `export HF_TOKEN="${token}" && ` : ''
  const runArgs = ['ssh', '-t', ...sshArgs(conn), `root@${conn.host}`,
    `chmod +x ${remote} && ${envExport}script -q -c "${remote}" /dev/null 2>&1 || bash ${remote} 2>&1`
  ]
  const runRef = { current: null }
  deployProc = runRef
  const code = await streamProc(event, runArgs, 'log', runRef)
  deployProc = null
  return code
})

ipcMain.handle('stop-script', () => {
  if (deployProc?.current) {
    deployProc.current.kill('SIGTERM')
    deployProc = null
    return true
  }
  return false
})

// Normalizza URL Civitai: civitai.com → civitai.red (stesso CDN, autenticazione più stabile)
function normalizeCivitaiUrl(url) {
  return url.replace(/^(https?:\/\/)civitai\.com(\/)/i, '$1civitai.red$2')
}

// Download da Civitai direttamente sul server con progresso
ipcMain.handle('download-civitai', async (event, { conn, url, folder, filename, token }) => {
  const dest = `${modelsBase(conn)}/${folder}`
  const resolvedUrl = normalizeCivitaiUrl(url)
  // Usa script per simulare TTY e vedere la barra di progresso
  const remoteCmd =
    `mkdir -p ${dest} && ` +
    `REDIR=$(curl -sI -L -H "Authorization: Bearer ${token}" -H "User-Agent: Mozilla/5.0" ` +
    `-w "%{url_effective}" -o /dev/null "${resolvedUrl}") && ` +
    `script -q -c 'curl -L --progress-bar -o "${dest}/${filename}.safetensors" "$REDIR"' /dev/null`
  return streamProc(event, ['ssh', '-t', ...sshArgs(conn), `root@${conn.host}`, remoteCmd], 'log')
})

// Fetch output one-shot
ipcMain.handle('fetch-output', async (event, { conn, localPath }) => {
  fs.mkdirSync(localPath, { recursive: true })
  const before = countFiles(localPath)
  const args = [
    'rsync', '-av', '--append-verify',
    '-e', `ssh -p ${conn.port} -i ${conn.sshKey} -o StrictHostKeyChecking=no -o ConnectTimeout=15`,
    `root@${conn.host}:${outputPath(conn)}/`,
    localPath + '/'
  ]
  const code = await streamProc(event, args, 'log')
  const downloaded = countFiles(localPath) - before
  if (downloaded > 0 && !win.isDestroyed()) {
    new (require('electron').Notification)({
      title: 'ComfyUI Cloud Manager',
      body: `${downloaded} file(s) downloaded to ${localPath}`
    }).show()
  }
  return code
})

// Apri ComfyUI nel browser
ipcMain.handle('open-in-browser', (_, conn) => {
  let url
  if (conn.provider === 'runpod') {
    // Estrae pod-id dall'host (es: xxxxx-8188.proxy.runpod.net o host diretto)
    const hostClean = conn.host.replace(/^https?:\/\//, '')
    if (hostClean.includes('.proxy.runpod.net')) {
      url = `https://${hostClean}`
    } else {
      // host diretto RunPod → costruiamo l'URL proxy se abbiamo il pod id
      // altrimenti apriamo su porta 8188 diretta
      url = `http://${conn.host}:8188`
    }
  } else if (conn.provider === 'vast') {
    // Vast usa port forwarding SSH, ComfyUI è su localhost
    url = `http://localhost:8188`
  } else {
    url = `http://${conn.host}:8188`
  }
  shell.openExternal(url)
  return url
})

// Watch output continuo (background)
ipcMain.handle('watch-start', (event, { conn, localPath, intervalSec = 15 }) => {
  if (watchProc) watchProc.kill()

  fs.mkdirSync(localPath, { recursive: true })

  const sshE = `ssh -p ${conn.port} -i ${conn.sshKey} -o StrictHostKeyChecking=no -o ConnectTimeout=10`
  let totalNew = 0

  const tick = () => {
    const before = countFiles(localPath)
    const proc = spawn('rsync', [
      '-a', '--append-verify',
      '-e', sshE,
      `root@${conn.host}:${outputPath(conn)}/`,
      localPath + '/'
    ])
    proc.on('close', () => {
      const after = countFiles(localPath)
      const nuovi = after - before
      if (nuovi > 0) {
        totalNew += nuovi
        const msg = `[${timestamp()}] ${nuovi} file(s) downloaded (total: ${totalNew})\n`
        if (!win.isDestroyed()) {
          win.webContents.send('watch', { text: msg, replace: false })
          new (require('electron').Notification)({
            title: 'ComfyUI Cloud Manager',
            body: `${nuovi} new file(s) downloaded`
          }).show()
        }
        sendToLogWin('watch', msg)
        updateTrayMenu(true, totalNew)
      } else {
        const msg = `[${timestamp()}] no new files\n`
        if (!win.isDestroyed()) win.webContents.send('watch', { text: msg, replace: false })
        sendToLogWin('watch', msg)
      }
    })
  }

  tick()
  watchProc = setInterval(tick, intervalSec * 1000)
  updateTrayMenu(true, 0)
  return true
})

ipcMain.handle('watch-stop', () => {
  if (watchProc) { clearInterval(watchProc); watchProc = null }
  updateTrayMenu(false)
  return true
})

// GPU Monitor
ipcMain.handle('gpu-start', (event, conn) => {
  if (gpuProc) gpuProc.kill()

  const cmd = `while true; do nvidia-smi --query-gpu=name,temperature.gpu,memory.used,memory.total,utilization.gpu --format=csv,noheader,nounits 2>/dev/null || echo 'nvidia-smi not available'; sleep 5; done`
  gpuProc = spawn('ssh', [...sshArgs(conn), `root@${conn.host}`, cmd])
  gpuProc.stdout.on('data', d => {
    if (!win.isDestroyed()) win.webContents.send('gpu', d.toString())
    sendToLogWin('gpu', d.toString())
  })
  gpuProc.on('close', () => { gpuProc = null })
  return true
})

ipcMain.handle('gpu-stop', () => {
  if (gpuProc) { gpuProc.kill(); gpuProc = null }
  return true
})

// --- Utility ---

function countFiles(dir) {
  try {
    return fs.readdirSync(dir).filter(f => {
      try { return fs.statSync(path.join(dir, f)).isFile() } catch { return false }
    }).length
  } catch { return 0 }
}

function timestamp() {
  return new Date().toLocaleTimeString('it-IT', { hour: '2-digit', minute: '2-digit', second: '2-digit' })
}

// --- Update checker ---

const GITHUB_REPO = 'daveinme/ComfyUI-Cloud-Manager'
const CURRENT_VERSION = require('./package.json').version

async function checkForUpdates() {
  try {
    const https = require('https')
    const data = await new Promise((resolve, reject) => {
      const req = https.get(
        `https://api.github.com/repos/${GITHUB_REPO}/releases/latest`,
        { headers: { 'User-Agent': 'comfy-cloud-manager' } },
        (res) => {
          let body = ''
          res.on('data', d => body += d)
          res.on('end', () => { try { resolve(JSON.parse(body)) } catch { reject() } })
        }
      )
      req.on('error', reject)
      req.setTimeout(8000, () => req.destroy())
    })

    const latest = (data.tag_name || '').replace(/^v/, '')
    if (!latest || latest === CURRENT_VERSION) return

    const [majL, minL, patL] = latest.split('.').map(Number)
    const [majC, minC, patC] = CURRENT_VERSION.split('.').map(Number)
    const isNewer = majL > majC || (majL === majC && minL > minC) || (majL === majC && minL === minC && patL > patC)
    if (!isNewer) return

    if (!win.isDestroyed()) {
      win.webContents.send('update-available', { current: CURRENT_VERSION, latest, url: data.html_url })
      new Notification({
        title: 'ComfyUI Cloud Manager — Update available',
        body: `Version ${latest} is available. Click to open the release page.`
      }).show()
    }
  } catch {}
}

// --- App lifecycle ---

app.whenReady().then(() => {
  createWindow()
  createTray()
  setTimeout(checkForUpdates, 5000)
})

app.on('window-all-closed', () => {
  // Su macOS l'app rimane attiva nel tray; altrove esci
  if (process.platform !== 'darwin') app.quit()
})

// Detachable log window
ipcMain.handle('open-log-window', () => {
  if (logWin && !logWin.isDestroyed()) { logWin.focus(); return }
  logWin = new BrowserWindow({
    width: 700,
    height: 480,
    minWidth: 400,
    minHeight: 200,
    title: 'ComfyUI Cloud Manager — Log',
    webPreferences: {
      nodeIntegration: false,
      contextIsolation: true,
      preload: path.join(__dirname, 'preload.js')
    }
  })
  logWin.loadFile('log_window.html')
  logWin.setMenuBarVisibility(false)
  logWin.on('closed', () => { logWin = null })
})

// Relay log events to the detached log window
function sendToLogWin(channel, data) {
  if (logWin && !logWin.isDestroyed()) {
    logWin.webContents.send(channel, data)
  }
}

app.on('before-quit', () => {
  if (watchProc) clearInterval(watchProc)
  if (gpuProc)   gpuProc.kill()
})
