// Globale Zustände
let selectedPreset = null;
let currentTab = 'backups';
let endpointDirty = false;
let regionDirty = false;

// Netzwerk-Helfer
function resolvePath(path) {
  return String(path).replace(/^\//, '');
}

async function call(path, opts = {}) {
  // Für GET-Endpunkte (ohne Body) GET verwenden, sonst POST
  const hasBody = opts && Object.prototype.hasOwnProperty.call(opts, 'body') && opts.body != null;
  const method = hasBody ? 'POST' : 'GET';
  const init = { method, headers: { 'Content-Type': 'application/json' }, ...opts };
  if (!hasBody) {
    // Body-Header entfernen, wenn kein Body gesendet wird
    if (init.headers && init.headers['Content-Type']) delete init.headers['Content-Type'];
  }
  const res = await fetch(resolvePath(path), init);
  const txt = await res.text();
  if (!res.ok) {
    console.error(`HTTP ${res.status}: ${res.statusText} für ${path}`);
    console.error('Response body:', txt);
  }
  return { ok: res.ok, status: res.status, body: txt };
}

// Logging / UI-Status
function out(msg) {
  const el = document.getElementById('output');
  if (!el) return;
  const timestamp = new Date().toLocaleTimeString();
  const line = `[${timestamp}] ${msg}`;
  el.textContent = (el.textContent + "\n" + line).trim();
  const container = el.parentElement;
  if (container) container.scrollTop = container.scrollHeight;
}

function setLoading(isLoading) {
  const spinner = document.getElementById('spinner');
  const statusDot = document.querySelector('.status-dot');
  const statusText = document.querySelector('.status-text');
  if (spinner) spinner.classList.toggle('hidden', !isLoading);
  if (statusDot && statusText) {
    if (isLoading) {
      statusDot.style.background = 'var(--warning)';
      statusText.textContent = 'Arbeitet...';
    } else {
      statusDot.style.background = 'var(--success)';
      statusText.textContent = 'Bereit';
    }
  }
}

// Zahlen-/Format-Utils
function toNumber(val, fallback = 0) {
  const n = typeof val === 'number' ? val : parseFloat(val);
  return Number.isFinite(n) ? n : fallback;
}

function parseHumanSizeToBytes(text) {
  if (text == null) return 0;
  if (typeof text === 'number') return text;
  const str = String(text).trim();
  const num = toNumber(str);
  const lower = str.toLowerCase();
  if (lower.includes('tb') || lower.endsWith('t')) return Math.round(num * 1024 * 1024 * 1024 * 1024);
  if (lower.includes('gb') || lower.endsWith('g')) return Math.round(num * 1024 * 1024 * 1024);
  if (lower.includes('mb') || lower.endsWith('m')) return Math.round(num * 1024 * 1024);
  if (lower.includes('kb') || lower.endsWith('k')) return Math.round(num * 1024);
  if (lower.includes('b')) return Math.round(num);
  return Math.round(num * 1024 * 1024);
}

function getBackupSizeBytes(backup) {
  const sizeInBytes = backup && (backup.size_in_bytes ?? backup.sizeInBytes);
  if (sizeInBytes != null) {
    const bytes = toNumber(sizeInBytes);
    if (bytes > 0) return Math.round(bytes);
  }
  const size = backup && (backup.size ?? backup.Size);
  if (size == null) return 0;
  if (typeof size === 'number') {
    return Math.round(size < 2048 ? size * 1024 * 1024 : size);
  }
  return parseHumanSizeToBytes(size);
}

function formatBytes(bytes) {
  const size = toNumber(bytes, 0);
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  let unitIndex = 0;
  let fileSize = size;
  while (fileSize >= 1024 && unitIndex < units.length - 1) {
    fileSize /= 1024;
    unitIndex++;
  }
  return `${fileSize.toFixed(unitIndex > 0 ? 1 : 0)} ${units[unitIndex]}`;
}

function formatDate(dateStr) {
  if (!dateStr) return '-';
  try {
    const date = new Date(dateStr);
    return date.toLocaleDateString('de-DE', {
      year: 'numeric',
      month: 'short',
      day: 'numeric',
      hour: '2-digit',
      minute: '2-digit'
    });
  } catch (e) {
    return dateStr;
  }
}

function formatSize(sizeStr) {
  if (!sizeStr) return '-';
  const size = parseInt(sizeStr);
  if (isNaN(size)) return sizeStr;
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  let unitIndex = 0;
  let fileSize = size;
  while (fileSize >= 1024 && unitIndex < units.length - 1) {
    fileSize /= 1024;
    unitIndex++;
  }
  return `${fileSize.toFixed(unitIndex > 0 ? 1 : 0)} ${units[unitIndex]}`;
}


