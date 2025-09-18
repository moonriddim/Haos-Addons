async function runBackup() {
  out('Backup wird gestartet...');
  setLoading(true);
  try {
    const result = await call('api/backup');
    try {
      if (result.ok) {
        const json = JSON.parse(result.body || '{}');
        if (json.s3_key) out(`Uploaded: s3://${json.s3_key}`);
      }
    } catch (_) {}
    out(result.body || (result.ok ? 'Backup erfolgreich abgeschlossen!' : 'Fehler beim Backup'));
    if (result.ok) setTimeout(() => refresh(), 2000);
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
    const result = await call('api/list');
    if (!result.ok) {
      out(`HTTP ${result.status}: Kann lokale Backups nicht laden`);
      if (result.status === 404) out('Prüfe ob CGI-Scripts richtig konfiguriert sind...');
    } else {
      try { renderBackups(JSON.parse(result.body)); out('Lokale Backups erfolgreich geladen'); }
      catch (e) { out('Fehler beim Parsen der Backup-Liste: ' + e.message); out('Raw response: ' + result.body); }
      // Auch Restore-Tabelle füllen, wenn vorhanden
      try { renderLocalRestoreTable(JSON.parse(result.body)); } catch (_) {}
    }
    try {
      const s3Result = await call('api/list-s3');
      if (s3Result.ok) { try { renderS3List(JSON.parse(s3Result.body)); } catch (_) {} }
    } catch (_) {}
  } catch (error) {
    out(`Fehler: ${error.message}`);
  } finally {
    setLoading(false);
  }
}

function initializeTabs() {
  const tabButtons = document.querySelectorAll('.nav-item');
  const tabPanels = document.querySelectorAll('.tab-panel');
  const pageTitle = document.getElementById('page-title');
  const pageDescription = document.getElementById('page-description');
  const tabInfo = {
    providers: { title: 'Cloud Provider', description: 'Konfiguriere deinen bevorzugten Cloud-Storage-Anbieter' },
    restore: { title: 'Backup Wiederherstellen', description: 'Stelle deine Home Assistant-Konfiguration wieder her' },
    activity: { title: 'System-Aktivität', description: 'Überwache laufende Prozesse und Systemlogs' }
  };
  function switchTab(tabId) {
    tabButtons.forEach(btn => btn.classList.toggle('active', btn.dataset.tab === tabId));
    tabPanels.forEach(panel => panel.classList.toggle('active', panel.id === `${tabId}-panel`));
    if (tabInfo[tabId]) { pageTitle.textContent = tabInfo[tabId].title; pageDescription.textContent = tabInfo[tabId].description; }
    currentTab = tabId;
    if (tabId === 'restore') {
      refresh();
      if (tabId === 'restore') {
        const slugInput = document.getElementById('slug');
        if (slugInput && slugInput.value.trim()) populateRestoreOptionsFromBackup(slugInput.value.trim());
      }
    }
  }
  tabButtons.forEach(button => { button.addEventListener('click', (e) => { e.preventDefault(); switchTab(button.dataset.tab); }); });
  switchTab('restore');
}

document.addEventListener('DOMContentLoaded', () => {
  initializeTabs();
  initializeProviders();
  document.getElementById('btn-backup').onclick = runBackup;
  document.getElementById('btn-refresh').onclick = refresh;
  document.getElementById('btn-apply-preset').onclick = applyProviderSettings;
  // Zugangsdaten werden jetzt über "Speichern und schließen" übernommen
  document.getElementById('btn-restore-local').onclick = restoreLocal;
  document.getElementById('btn-restore-s3').onclick = restoreFromS3;
  document.getElementById('btn-debug-log').onclick = showDebugLogs;
  out('S3 Backup Tool gestartet');
  setTimeout(refresh, 1000);
  document.addEventListener('keydown', (e) => {
    if (e.ctrlKey && e.key === 'r' && !['INPUT', 'TEXTAREA'].includes(e.target.tagName)) { e.preventDefault(); refresh(); }
    if (e.altKey && e.key >= '1' && e.key <= '4') { e.preventDefault(); const tabs = ['backups', 'providers', 'restore', 'activity']; const tabIndex = parseInt(e.key) - 1; if (tabs[tabIndex]) document.querySelector(`[data-tab="${tabs[tabIndex]}"]`).click(); }
  });
  const slugEl = document.getElementById('slug');
  slugEl.addEventListener('keypress', (e) => { if (e.key === 'Enter') restoreLocal(); });
  slugEl.addEventListener('blur', (e) => { const v = e.target.value.trim(); if (v) populateRestoreOptionsFromBackup(v); });
  const s3El = document.getElementById('s3key');
  s3El.addEventListener('keypress', (e) => { if (e.key === 'Enter') restoreFromS3(); });
  const originalOut = out;
  window.out = (msg) => { originalOut(msg); if (msg.includes('erfolgreich')) { setTimeout(() => { const outputEl = document.getElementById('output'); const lines = outputEl.textContent.split('\n'); const filteredLines = lines.filter(line => !line.includes(msg.split(']')[1])); outputEl.textContent = filteredLines.join('\n'); }, 5000); } };
  setInterval(() => { if (currentTab === 'backups') refresh(); }, 5 * 60 * 1000);
});

window.addEventListener('error', (e) => { out(`JavaScript-Fehler: ${e.message}`); console.error('Unerwarteter Fehler:', e.error); });
window.addEventListener('unhandledrejection', (e) => { out(`Promise-Fehler: ${e.reason}`); console.error('Unbehandelte Promise-Rejection:', e.reason); });


