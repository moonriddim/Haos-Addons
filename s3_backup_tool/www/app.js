// Globale Variablen und Utilities
let selectedPreset = null;
let currentTab = 'backups';
let endpointDirty = false; // wurde Endpoint manuell editiert?
let regionDirty = false;   // wurde Region manuell editiert?

// Utility-Funktionen
function resolvePath(path) {
  // Entferne führenden Slash, damit Requests relativ zum Ingress-Pfad erfolgen
  return path.replace(/^\//, '');
}

function toNumber(val, fallback = 0) {
  const n = typeof val === 'number' ? val : parseFloat(val);
  return Number.isFinite(n) ? n : fallback;
}

function parseHumanSizeToBytes(text) {
  if (text == null) return 0;
  if (typeof text === 'number') return text; // bereits Bytes
  const str = String(text).trim();
  const num = toNumber(str);
  const lower = str.toLowerCase();
  if (lower.includes('tb') || lower.endsWith('t')) return Math.round(num * 1024 * 1024 * 1024 * 1024);
  if (lower.includes('gb') || lower.endsWith('g')) return Math.round(num * 1024 * 1024 * 1024);
  if (lower.includes('mb') || lower.endsWith('m')) return Math.round(num * 1024 * 1024);
  if (lower.includes('kb') || lower.endsWith('k')) return Math.round(num * 1024);
  if (lower.includes('b')) return Math.round(num);
  // Keine Einheit gefunden: konservativ als MB interpretieren (Supervisor liefert oft MB)
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
    // Heuristik: Werte < 2.048 deuten i.d.R. auf MB hin; große Werte sind Bytes
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

async function call(path, opts = {}) {
  const res = await fetch(resolvePath(path), { method: 'POST', headers: { 'Content-Type': 'application/json' }, ...opts });
  const txt = await res.text();
  
  // Bessere Fehlerbehandlung für Debugging
  if (!res.ok) {
    console.error(`HTTP ${res.status}: ${res.statusText} für ${path}`);
    console.error('Response body:', txt);
  }
  
  return { ok: res.ok, status: res.status, body: txt };
}

function out(msg) {
  const el = document.getElementById('output');
  const timestamp = new Date().toLocaleTimeString();
  const line = `[${timestamp}] ${msg}`;
  el.textContent = (el.textContent + "\n" + line).trim();
  // Auto-scroll to bottom
  const container = el.parentElement;
  container.scrollTop = container.scrollHeight;
}

function setLoading(isLoading) {
  const spinner = document.getElementById('spinner');
  const statusDot = document.querySelector('.status-dot');
  const statusText = document.querySelector('.status-text');
  
  spinner.classList.toggle('hidden', !isLoading);
  
  if (isLoading) {
    statusDot.style.background = 'var(--warning)';
    statusText.textContent = 'Arbeitet...';
  } else {
    statusDot.style.background = 'var(--success)';
    statusText.textContent = 'Bereit';
  }
}

// Tab-System
function initializeTabs() {
  const tabButtons = document.querySelectorAll('.nav-item');
  const tabPanels = document.querySelectorAll('.tab-panel');
  const pageTitle = document.getElementById('page-title');
  const pageDescription = document.getElementById('page-description');
  
  // Tab-Informationen
  const tabInfo = {
    'backups': {
      title: 'Backup Übersicht',
      description: 'Verwalte deine Home Assistant Backups in der Cloud'
    },
    'providers': {
      title: 'Cloud Provider',
      description: 'Konfiguriere deinen bevorzugten Cloud-Storage-Anbieter'
    },
    'restore': {
      title: 'Backup Wiederherstellen',
      description: 'Stelle deine Home Assistant-Konfiguration wieder her'
    },
    'activity': {
      title: 'System-Aktivität',
      description: 'Überwache laufende Prozesse und Systemlogs'
    }
  };
  
  function switchTab(tabId) {
    // Update active states
    tabButtons.forEach(btn => {
      btn.classList.toggle('active', btn.dataset.tab === tabId);
    });
    
    tabPanels.forEach(panel => {
      panel.classList.toggle('active', panel.id === `${tabId}-panel`);
    });
    
    // Update header
    if (tabInfo[tabId]) {
      pageTitle.textContent = tabInfo[tabId].title;
      pageDescription.textContent = tabInfo[tabId].description;
    }
    
    currentTab = tabId;
    
    // Tab-spezifische Aktionen
    if (tabId === 'backups' || tabId === 'restore') {
      // Für Restore auch laden, damit S3-Liste gefüllt wird
      refresh();
      // Wenn bereits ein Slug gesetzt ist, lade Details zur Vorbelegung
      if (tabId === 'restore') {
        const slugInput = document.getElementById('slug');
        if (slugInput && slugInput.value.trim()) {
          populateRestoreOptionsFromBackup(slugInput.value.trim());
        }
      }
    }
  }
  
  // Event listener für Tab-Buttons
  tabButtons.forEach(button => {
    button.addEventListener('click', (e) => {
      e.preventDefault();
      switchTab(button.dataset.tab);
    });
  });
  
  // Initial tab laden
  switchTab('backups');
}

// Backup-Tabelle rendern
function renderBackups(json) {
  const tbody = document.querySelector('#backup-table tbody');
  const emptyState = document.getElementById('empty-state');
  
  tbody.innerHTML = '';
  const list = (json && json.data && json.data.backups) || [];
  
  emptyState.style.display = list.length ? 'none' : 'block';
  
  for (const backup of list) {
    const tr = document.createElement('tr');
    const sizeBytes = getBackupSizeBytes(backup);
    const date = backup.date || backup.created || '';
    
    tr.innerHTML = `
      <td><strong>${backup.name || 'Unbekannt'}</strong></td>
      <td><code>${backup.slug || ''}</code></td>
      <td>${formatDate(date)}</td>
      <td>${formatBytes(sizeBytes)}</td>
      <td><span class="backup-type">${backup.type || 'Vollständig'}</span></td>
      <td class="text-right">
        <button class="btn btn-secondary btn-sm restore-btn" data-slug="${backup.slug}">Auswählen</button>
        <button class="btn btn-primary btn-sm restore-now-btn" data-slug="${backup.slug}">Wiederherstellen</button>
      </td>
    `;
    tbody.appendChild(tr);
  }
  
  // Event listener für Restore-Buttons
  tbody.querySelectorAll('.restore-btn').forEach(btn => {
    btn.onclick = () => {
      const slug = btn.getAttribute('data-slug');
      document.getElementById('slug').value = slug;
      
      // Zur Restore-Tab wechseln
      document.querySelector('[data-tab="restore"]').click();
      // UI-Auswahl sichtbar machen und mit Backup-Details füllen
      populateRestoreOptionsFromBackup(slug);
      
      // Visuelles Feedback
      btn.textContent = '✓ Ausgewählt';
      setTimeout(() => {
        btn.textContent = 'Auswählen';
      }, 2000);
    };
  });
  
  // Direkt-Wiederherstellen-Buttons
  tbody.querySelectorAll('.restore-now-btn').forEach(btn => {
    btn.onclick = async () => {
      const slug = btn.getAttribute('data-slug');
      await restoreLocalWithSlug(slug);
    };
  });
}

// S3-Tabelle rendern
function renderS3List(json) {
  const tbody = document.querySelector('#s3-table tbody');
  const emptyState = document.getElementById('s3-empty');
  
  tbody.innerHTML = '';
  const list = (json && json.objects) || [];
  
  emptyState.style.display = list.length ? 'none' : 'block';
  
  for (const obj of list) {
    const tr = document.createElement('tr');
    const size = obj.Size || obj.size || '';
    const lastModified = obj.LastModified || obj.lastModified || '';
    const key = obj.Key || obj.key || '';
    
    tr.innerHTML = `
      <td><code>${key}</code></td>
      <td>${formatSize(size)}</td>
      <td>${formatDate(lastModified)}</td>
      <td class="text-right">
        <button class="btn btn-secondary btn-sm pick-s3-btn" data-key="${key}">Auswählen</button>
        <button class="btn btn-primary btn-sm restore-s3-btn" data-key="${key}">Wiederherstellen</button>
      </td>
    `;
    tbody.appendChild(tr);
  }
  
  // Event listener für S3-Buttons
  tbody.querySelectorAll('.pick-s3-btn').forEach(btn => {
    btn.onclick = () => {
      const key = btn.getAttribute('data-key');
      document.getElementById('s3key').value = key;
      
      // Visuelles Feedback
      btn.textContent = '✓ Ausgewählt';
      setTimeout(() => btn.textContent = 'Auswählen', 2000);
    };
  });
  
  tbody.querySelectorAll('.restore-s3-btn').forEach(btn => {
    btn.onclick = async () => {
      const key = btn.getAttribute('data-key');
      document.getElementById('s3key').value = key;
      await restoreFromS3();
    };
  });
}

// Backup-Details laden und Restore-Checkboxen vorbelegen
async function populateRestoreOptionsFromBackup(slug) {
  try {
    const res = await call('api/backup-info', { body: JSON.stringify({ slug }) });
    if (!res.ok) return;
    const info = JSON.parse(res.body);
    const data = info.data || {};
    // Platzhalter ausblenden, Auswahl einblenden
    const placeholder = document.getElementById('restore-placeholder');
    const selection = document.getElementById('restore-selection');
    if (placeholder) placeholder.classList.add('hidden');
    if (selection) selection.classList.remove('hidden');
    const ha = document.getElementById('restore-ha');
    if (ha && typeof data.homeassistant === 'boolean') {
      ha.checked = data.homeassistant;
    }
    // Folders dynamisch rendern, basierend auf den im Backup enthaltenen
    const foldersList = document.getElementById('folders-list');
    if (foldersList) {
      foldersList.innerHTML = '';
      const folders = Array.isArray(data.folders) ? data.folders : [];
      if (!folders.length) {
        foldersList.innerHTML = '<div class="text-muted">Keine Ordner im Backup gefunden.</div>';
      } else {
        folders.forEach(f => {
          const lbl = document.createElement('label');
          lbl.className = 'checkbox-label';
          const name = ({
            homeassistant: 'Einstellungen und Verlauf',
            media: 'Medien',
            ssl: 'SSL-Zertifikate',
            share: 'Share-Ordner'
          })[f] || f;
          lbl.innerHTML = `<input type="checkbox" value="${f}" class="form-checkbox restore-folder"> <span class="checkbox-indicator"></span> ${name}`;
          foldersList.appendChild(lbl);
        });
      }
    }
    // Add-ons dynamisch anzeigen
    const addonsListEl = document.getElementById('addons-list');
    if (addonsListEl) {
      addonsListEl.innerHTML = '';
      const addons = Array.isArray(data.addons) ? data.addons : [];
      if (!addons.length) {
        addonsListEl.innerHTML = '<div class="text-muted">Keine Add-ons im Backup gefunden.</div>';
      } else {
        addons.forEach(a => {
          const slugVal = a.slug || a;
          const nameVal = a.name || slugVal;
          const div = document.createElement('label');
          div.className = 'checkbox-label';
          div.innerHTML = `<input type="checkbox" class="form-checkbox restore-addon" value="${slugVal}"> <span class="checkbox-indicator"></span> ${nameVal}`;
          addonsListEl.appendChild(div);
        });
      }
    }
  } catch (_) {
    // still
  }
}

// Provider-Karten initialisieren
function initializeProviders() {
  const providerCards = document.querySelectorAll('.provider-card');
  
  providerCards.forEach(card => {
    card.onclick = () => {
      // Alle anderen deaktivieren
      providerCards.forEach(c => c.classList.remove('active'));
      
      // Aktuelle aktivieren
      card.classList.add('active');
      
      // Daten extrahieren
      selectedPreset = {
        ep: card.dataset.ep,
        rg: card.dataset.rg,
        fps: card.dataset.fps
      };
      
      // Felder ausfüllen (nur wenn nicht manuell verändert)
      const regionInput = document.getElementById('region-input');
      const regionSelect = document.getElementById('region-select');
      const endpointInput = document.getElementById('endpoint-input');
      const pathStyleCheckbox = document.getElementById('fps-input');
      
      // Region: vorbelegen, solange Nutzer nichts manuell eingegeben hat
      if (selectedPreset.rg && selectedPreset.rg !== 'auto' && !regionDirty) {
        regionInput.value = selectedPreset.rg;
        regionSelect.value = selectedPreset.rg;
      }
      
      // Endpoint: vorbelegen, solange Nutzer nichts manuell eingegeben hat
      if (selectedPreset.ep && !endpointDirty) {
        endpointInput.value = selectedPreset.ep;
      }
      
      // Path Style: immer setzen (ist ja nur ein Checkbox)
      pathStyleCheckbox.checked = selectedPreset.fps === 'true';
      
      // Visuelles Feedback
      out(`Provider ausgewählt: ${card.querySelector('.provider-name').textContent}`);
    };
  });
  
  // Region-Input und Select synchronisieren
  const regionInput = document.getElementById('region-input');
  const regionSelect = document.getElementById('region-select');
  const endpointInput = document.getElementById('endpoint-input');
  
  regionSelect.onchange = () => {
    if (regionSelect.value) {
      regionInput.value = regionSelect.value;
      // Visuelles Feedback für übernommene Region
      out(`Region übernommen: ${regionSelect.value}`);
      regionDirty = true; // Nutzer hat Region über Dropdown angepasst
    }
  };
  
  regionInput.oninput = () => {
    // Prüfen, ob der Wert in der Select-Liste vorhanden ist
    const option = Array.from(regionSelect.options).find(opt => opt.value === regionInput.value);
    regionSelect.value = option ? regionInput.value : '';
    regionDirty = true; // Nutzer tippt in Region
  };
  
  endpointInput.addEventListener('input', () => {
    endpointDirty = true; // Nutzer tippt in Endpoint
  });
  
  // Input-Feld explizit fokussierbar und editierbar machen
  regionInput.removeAttribute('readonly');
  regionInput.removeAttribute('disabled');
  regionInput.style.pointerEvents = 'auto';
  regionInput.style.userSelect = 'text';
  
  // Sicherstellen dass das Input-Feld funktioniert
  regionInput.addEventListener('click', (e) => {
    e.stopPropagation();
    e.preventDefault();
    regionInput.focus();
    regionInput.select(); // Text auswählen falls vorhanden
    // Kein dirty-Flag hier setzen, erst wenn tatsächlich getippt wurde
  });
  
  // Doppelklick für bessere Benutzerfreundlichkeit
  regionInput.addEventListener('dblclick', (e) => {
    e.stopPropagation();
    regionInput.select();
  });
  
  // Placeholder für bessere Benutzerführung dynamisch setzen
  regionInput.addEventListener('focus', () => {
    if (!regionInput.value.trim()) {
      regionInput.placeholder = 'z.B. eu-central-1, us-east-1, ap-southeast-1';
    }
  });
  
  regionInput.addEventListener('blur', () => {
    regionInput.placeholder = 'eu-central-1';
  });
}

// Event Handlers für Buttons
async function runBackup() {
  out('Backup wird gestartet...');
  setLoading(true);
  
  try {
    const result = await call('api/backup');
    try {
      if (result.ok) {
        const json = JSON.parse(result.body || '{}');
        if (json.s3_key) {
          out(`Uploaded: s3://${json.s3_key}`);
        }
      }
    } catch (_) {}
    out(result.body || (result.ok ? 'Backup erfolgreich abgeschlossen!' : 'Fehler beim Backup'));
    
    // Refresh nach erfolgreichem Backup
    if (result.ok) {
      setTimeout(() => refresh(), 2000);
    }
  } catch (error) {
    out(`Fehler: ${error.message}`);
  } finally {
    setLoading(false);
  }
}

async function refresh() {
  out('Lade Backup-Liste...');
  setLoading(true);
  
  try {
    // Lokale Backups laden
    const result = await call('api/list');
    
    if (!result.ok) {
      out(`HTTP ${result.status}: Kann lokale Backups nicht laden`);
      if (result.status === 404) {
        out('Prüfe ob CGI-Scripts richtig konfiguriert sind...');
      }
    } else {
      try {
        renderBackups(JSON.parse(result.body));
        out('Lokale Backups erfolgreich geladen');
      } catch (e) {
        out('Fehler beim Parsen der Backup-Liste: ' + e.message);
        out('Raw response: ' + result.body);
      }
    }
    
    // S3-Liste optional laden (ohne Fehler zu werfen)
    try {
      const s3Result = await call('api/list-s3');
      if (s3Result.ok) {
        try {
          renderS3List(JSON.parse(s3Result.body));
        } catch (e) {
          // Ignoriere Parse-Fehler für S3-Liste
        }
      }
    } catch (e) {
      // S3-Liste ist optional
    }
  } catch (error) {
    out(`Fehler: ${error.message}`);
  } finally {
    setLoading(false);
  }
}

async function applyProviderSettings() {
  const regionInput = document.getElementById('region-input');
  const regionSelect = document.getElementById('region-select');
  const endpointInput = document.getElementById('endpoint-input');
  const pathStyleCheckbox = document.getElementById('fps-input');
  const sseSelect = document.getElementById('sse-select');
  const kmsInput = document.getElementById('kms-input');
  const versioningCheckbox = document.getElementById('versioning-input');
  
  // Priorität: Freitext-Input > Dropdown > Preset > Default
  const region = (regionInput.value && regionInput.value.trim()) || 
                regionSelect.value || 
                (selectedPreset && selectedPreset.rg) || 
                'us-east-1';
                
  const endpoint = endpointInput.value || 
                  (selectedPreset && selectedPreset.ep) || '';
                  
  const pathStyle = pathStyleCheckbox.checked || 
                   (selectedPreset && selectedPreset.fps === 'true') || 
                   false;
  const sse = sseSelect ? sseSelect.value : '';
  const kms = kmsInput ? kmsInput.value.trim() : '';
  const enableVersioning = !!(versioningCheckbox && versioningCheckbox.checked);
  
  if (!region) {
    out('Fehler: Region ist erforderlich');
    return;
  }
  
  out('Wende Provider-Einstellungen an...');
  setLoading(true);
  
  try {
    const result = await call('api/set-overrides', {
      body: JSON.stringify({
        s3_endpoint_url: endpoint,
        s3_region_name: region,
        force_path_style: pathStyle,
        s3_sse: sse,
        s3_sse_kms_key_id: kms,
        enable_versioning: enableVersioning
      })
    });
    
    out(result.body || (result.ok ? 'Provider-Einstellungen erfolgreich gespeichert!' : 'Fehler beim Speichern'));
  } catch (error) {
    out(`Fehler: ${error.message}`);
  } finally {
    setLoading(false);
  }
}

async function applyCredentials() {
  const bucket = document.getElementById('bucket-input').value.trim();
  const accessKey = document.getElementById('ak-input').value.trim();
  const secretKey = document.getElementById('sk-input').value.trim();
  
  if (!bucket || !accessKey || !secretKey) {
    out('Fehler: Bucket-Name, Access Key und Secret Key sind erforderlich');
    return;
  }
  
  out('Speichere Zugangsdaten...');
  setLoading(true);
  
  try {
    const result = await call('api/set-overrides', {
      body: JSON.stringify({
        s3_bucket: bucket,
        access_key_id: accessKey,
        secret_access_key: secretKey
      })
    });
    
    out(result.body || (result.ok ? 'Zugangsdaten erfolgreich gespeichert!' : 'Fehler beim Speichern'));
    
    // Felder leeren aus Sicherheitsgründen
    if (result.ok) {
      document.getElementById('ak-input').value = '';
      document.getElementById('sk-input').value = '';
    }
  } catch (error) {
    out(`Fehler: ${error.message}`);
  } finally {
    setLoading(false);
  }
}

async function restoreLocal() {
  const slug = document.getElementById('slug').value.trim();
  
  if (!slug) {
    out('Fehler: Backup-Slug ist erforderlich');
    return;
  }
  
  await restoreLocalWithSlug(slug);
}

async function restoreLocalWithSlug(slug) {
  out(`Stelle lokales Backup wieder her: ${slug}`);
  setLoading(true);
  try {
    // Prüfe, ob partielle Auswahl im UI getroffen wurde; wenn nichts gewählt, versuche aus Backup-Info zu laden
    let includeHA = document.getElementById('restore-ha')?.checked;
    let folders = Array.from(document.querySelectorAll('.restore-folder:checked')).map(el => el.value);
    let addons = Array.from(document.querySelectorAll('.restore-addon:checked')).map(el => el.value);

    if (folders.length === 0 && addons.length === 0) {
      // Backup-Info vom Supervisor holen und Defaults setzen
      const infoRes = await call('api/backup-info', { body: JSON.stringify({ slug }) });
      if (infoRes.ok) {
        try {
          const info = JSON.parse(infoRes.body);
          const data = info.data || {};
          if (typeof includeHA !== 'boolean' && typeof data.homeassistant === 'boolean') includeHA = data.homeassistant;
          if (Array.isArray(data.folders)) folders = data.folders;
          if (Array.isArray(data.addons)) addons = data.addons.map(a => (a.slug || a));
        } catch (_) {}
      }
    }

    const payload = { slug };
    if (typeof includeHA === 'boolean') payload.homeassistant = includeHA;
    if (folders.length) payload.folders = folders;
    if (addons.length) payload.addons = addons;
    const result = await call('api/restore-local', {
      body: JSON.stringify(payload)
    });
    out(result.body || (result.ok ? 'Lokales Backup erfolgreich wiederhergestellt!' : 'Fehler bei der Wiederherstellung'));
  } catch (error) {
    out(`Fehler: ${error.message}`);
  } finally {
    setLoading(false);
  }
}
async function restoreFromS3() {
  const s3key = document.getElementById('s3key').value.trim();
  
  if (!s3key) {
    out('Fehler: S3-Schlüssel ist erforderlich');
    return;
  }
  
  out(`Stelle Cloud-Backup wieder her: ${s3key}`);
  setLoading(true);
  
  try {
    const result = await call('api/restore-s3', {
      body: JSON.stringify({ key: s3key })
    });
    
    out(result.body || (result.ok ? 'Cloud-Backup erfolgreich wiederhergestellt!' : 'Fehler bei der Wiederherstellung'));
  } catch (error) {
    out(`Fehler: ${error.message}`);
  } finally {
    setLoading(false);
  }
}

// Debug-Logs anzeigen
async function showDebugLogs() {
  out('Lade Debug-Logs...');
  setLoading(true);
  
  try {
    const result = await fetch(resolvePath('api/debug-log'));
    const txt = await result.text();
    
    if (result.ok) {
      out('=== DEBUG LOGS ===');
      out(txt);
      out('=== ENDE DEBUG LOGS ===');
    } else {
      out(`Fehler beim Laden der Debug-Logs: HTTP ${result.status}`);
    }
  } catch (error) {
    out(`Fehler: ${error.message}`);
  } finally {
    setLoading(false);
  }
}


// Hilfsfunktionen für Formatierung
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

// Initialisierung beim Laden der Seite
document.addEventListener('DOMContentLoaded', () => {
  // Tab-System initialisieren
  initializeTabs();
  
  // Provider-Karten initialisieren
  initializeProviders();
  
  // Event Handlers für Buttons
  document.getElementById('btn-backup').onclick = runBackup;
  document.getElementById('btn-refresh').onclick = refresh;
  document.getElementById('btn-apply-preset').onclick = applyProviderSettings;
  document.getElementById('btn-apply-credentials').onclick = applyCredentials;
  document.getElementById('btn-restore-local').onclick = restoreLocal;
  document.getElementById('btn-restore-s3').onclick = restoreFromS3;
  document.getElementById('btn-debug-log').onclick = showDebugLogs;
  
  // Initial Ladung starten
  out('S3 Backup Tool gestartet');
  
  // Automatischer Refresh beim ersten Laden (mit kleiner Verzögerung)
  setTimeout(refresh, 1000);
  
  // Erweiterte Tastatur-Shortcuts
  document.addEventListener('keydown', (e) => {
    // Strg+R für Refresh (aber nur wenn kein Input fokussiert ist)
    if (e.ctrlKey && e.key === 'r' && !['INPUT', 'TEXTAREA'].includes(e.target.tagName)) {
      e.preventDefault();
      refresh();
    }
    
    // Tab-Navigation mit Alt+Nummer
    if (e.altKey && e.key >= '1' && e.key <= '4') {
      e.preventDefault();
      const tabs = ['backups', 'providers', 'restore', 'activity'];
      const tabIndex = parseInt(e.key) - 1;
      if (tabs[tabIndex]) {
        document.querySelector(`[data-tab="${tabs[tabIndex]}"]`).click();
      }
    }
  });
  
  // Enter-Key Handler für Input-Felder
  document.getElementById('slug').addEventListener('keypress', (e) => {
    if (e.key === 'Enter') {
      restoreLocal();
    }
  });
  document.getElementById('slug').addEventListener('blur', (e) => {
    const v = e.target.value.trim();
    if (v) {
      populateRestoreOptionsFromBackup(v);
    }
  });
  
  document.getElementById('s3key').addEventListener('keypress', (e) => {
    if (e.key === 'Enter') {
      restoreFromS3();
    }
  });
  
  // Auto-hide für Success-Messages
  const originalOut = out;
  window.out = (msg) => {
    originalOut(msg);
    
    // Wenn die Nachricht "erfolgreich" enthält, nach 5 Sekunden ausblenden
    if (msg.includes('erfolgreich')) {
      setTimeout(() => {
        const outputEl = document.getElementById('output');
        const lines = outputEl.textContent.split('\n');
        const filteredLines = lines.filter(line => !line.includes(msg.split(']')[1]));
        outputEl.textContent = filteredLines.join('\n');
      }, 5000);
    }
  };
  
  // Periodischer Refresh alle 5 Minuten (nur für Backups-Tab)
  setInterval(() => {
    if (currentTab === 'backups') {
      refresh();
    }
  }, 5 * 60 * 1000);
});

// Error-Handling für unerwartete Fehler
window.addEventListener('error', (e) => {
  out(`JavaScript-Fehler: ${e.message}`);
  console.error('Unerwarteter Fehler:', e.error);
});

window.addEventListener('unhandledrejection', (e) => {
  out(`Promise-Fehler: ${e.reason}`);
  console.error('Unbehandelte Promise-Rejection:', e.reason);
});

  // Export für Debugging (nur in Development)
if (window.location.hostname === 'localhost' || window.location.hostname === '127.0.0.1') {
  window.debugUtils = {
    refresh,
    runBackup,
    applyProviderSettings,
    applyCredentials,
    restoreLocal,
    restoreFromS3,
    selectedPreset: () => selectedPreset,
    currentTab: () => currentTab
  };
}