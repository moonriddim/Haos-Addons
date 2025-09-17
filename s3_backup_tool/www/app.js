// Globale Variablen und Utilities
let selectedPreset = null;
let currentTab = 'backups';

// Utility-Funktionen
async function call(path, opts = {}) {
  const res = await fetch(path, { method: 'POST', headers: { 'Content-Type': 'application/json' }, ...opts });
  const txt = await res.text();
  return { ok: res.ok, body: txt };
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
    if (tabId === 'backups') {
      refresh();
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
    const size = backup.size || backup.size_in_bytes || '';
    const date = backup.date || backup.created || '';
    
    tr.innerHTML = `
      <td><strong>${backup.name || 'Unbekannt'}</strong></td>
      <td><code>${backup.slug || ''}</code></td>
      <td>${formatDate(date)}</td>
      <td>${formatSize(size)}</td>
      <td><span class="backup-type">${backup.type || 'Vollständig'}</span></td>
      <td class="text-right">
        <button class="btn btn-secondary btn-sm restore-btn" data-slug="${backup.slug}">
          <svg class="btn-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
            <path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/>
            <polyline points="7,10 12,15 17,10"/>
            <line x1="12" y1="15" x2="12" y2="3"/>
          </svg>
          Auswählen
        </button>
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
      
      // Visuelles Feedback
      btn.innerHTML = '<span>✓ Ausgewählt</span>';
      setTimeout(() => {
        btn.innerHTML = `
          <svg class="btn-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
            <path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/>
            <polyline points="7,10 12,15 17,10"/>
            <line x1="12" y1="15" x2="12" y2="3"/>
          </svg>
          Auswählen
        `;
      }, 2000);
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
      
      // Felder ausfüllen
      const regionInput = document.getElementById('region-input');
      const regionSelect = document.getElementById('region-select');
      const endpointInput = document.getElementById('endpoint-input');
      const pathStyleCheckbox = document.getElementById('fps-input');
      
      if (selectedPreset.rg && selectedPreset.rg !== 'auto') {
        regionInput.value = selectedPreset.rg;
        regionSelect.value = selectedPreset.rg;
      }
      
      if (selectedPreset.ep) {
        endpointInput.value = selectedPreset.ep;
      }
      
      pathStyleCheckbox.checked = selectedPreset.fps === 'true';
      
      // Visuelles Feedback
      out(`Provider ausgewählt: ${card.querySelector('.provider-name').textContent}`);
    };
  });
  
  // Region-Input und Select synchronisieren
  const regionInput = document.getElementById('region-input');
  const regionSelect = document.getElementById('region-select');
  
  regionSelect.onchange = () => {
    if (regionSelect.value) {
      regionInput.value = regionSelect.value;
    }
  };
  
  regionInput.oninput = () => {
    if (regionInput.value) {
      // Prüfen, ob der Wert in der Select-Liste vorhanden ist
      const option = Array.from(regionSelect.options).find(opt => opt.value === regionInput.value);
      regionSelect.value = option ? regionInput.value : '';
    }
  };
}

// Event Handlers für Buttons
async function runBackup() {
  out('Backup wird gestartet...');
  setLoading(true);
  
  try {
    const result = await call('/api/backup');
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
    const result = await call('/api/list');
    try {
      renderBackups(JSON.parse(result.body));
    } catch (e) {
      out('Fehler beim Parsen der Backup-Liste');
    }
    
    out(result.body || (result.ok ? 'Liste erfolgreich geladen' : 'Fehler beim Laden'));
    
    // S3-Liste optional laden (ohne Fehler zu werfen)
    try {
      const s3Result = await call('/api/list-s3');
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
  
  if (!region) {
    out('Fehler: Region ist erforderlich');
    return;
  }
  
  out('Wende Provider-Einstellungen an...');
  setLoading(true);
  
  try {
    const result = await call('/api/set-overrides', {
      body: JSON.stringify({
        s3_endpoint_url: endpoint,
        s3_region_name: region,
        force_path_style: pathStyle
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
    const result = await call('/api/set-overrides', {
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
  
  out(`Stelle lokales Backup wieder her: ${slug}`);
  setLoading(true);
  
  try {
    const result = await call('/api/restore-local', {
      body: JSON.stringify({ slug })
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
    const result = await call('/api/restore-s3', {
      body: JSON.stringify({ key: s3key })
    });
    
    out(result.body || (result.ok ? 'Cloud-Backup erfolgreich wiederhergestellt!' : 'Fehler bei der Wiederherstellung'));
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