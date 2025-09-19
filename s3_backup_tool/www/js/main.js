
async function refresh() {
  out('Lade Backup-Liste...');
  setLoading(true);
  try {
    const result = await call('api/list');
    if (!result.ok) {
      out(`HTTP ${result.status}: Kann lokale Backups nicht laden`);
      if (result.status === 404) out('Prüfe ob CGI-Scripts richtig konfiguriert sind...');
    } else {
      // Backup-Tabelle wurde entfernt
      out('Lokale Backups geladen (nur für Restore-Funktionalität)');
      try { JSON.parse(result.body); } catch (e) { out('Fehler beim Parsen der Backup-Liste: ' + e.message); }
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
  // Backup-Buttons wurden entfernt
  document.getElementById('btn-apply-preset').onclick = applyProviderSettings;
  // Zugangsdaten werden jetzt über "Speichern und schließen" übernommen
  document.getElementById('btn-restore-local').onclick = restoreLocal;
  document.getElementById('btn-restore-s3').onclick = restoreFromS3;
  document.getElementById('btn-debug-log').onclick = showDebugLogs;
  
  // SQLite Debug buttons - detailliertes Debugging
  out('Lade Debug-Button-Handler...');
  
  const btnSQLiteStatus = document.getElementById('btn-sqlite-status');
  out(`SQLite Status Button: ${btnSQLiteStatus ? 'gefunden' : 'NICHT GEFUNDEN'}`);
  if (btnSQLiteStatus) {
    btnSQLiteStatus.onclick = () => {
      out('🗃️ SQLite Status Button geklickt');
      console.log('SQLite Status button clicked');
      if (window.showSQLiteStatus) {
        window.showSQLiteStatus();
      } else {
        out('Fehler: showSQLiteStatus-Funktion nicht gefunden');
        console.error('showSQLiteStatus function not found on window object');
      }
    };
  }
  
  const btnTestPersistence = document.getElementById('btn-test-persistence'); 
  out(`Persistenz Test Button: ${btnTestPersistence ? 'gefunden' : 'NICHT GEFUNDEN'}`);
  if (btnTestPersistence) {
    btnTestPersistence.onclick = () => {
      out('🧪 Persistenz Test Button geklickt');
      console.log('Persistenz Test button clicked');
      if (window.testSettingsPersistence) {
        window.testSettingsPersistence();
      } else {
        out('Fehler: testSettingsPersistence-Funktion nicht gefunden');
        console.error('testSettingsPersistence function not found on window object');
      }
    };
  }
  
  const btnTestPermissions = document.getElementById('btn-test-permissions'); 
  out(`Permissions Test Button: ${btnTestPermissions ? 'gefunden' : 'NICHT GEFUNDEN'}`);
  if (btnTestPermissions) {
    btnTestPermissions.onclick = () => {
      out('🔐 Permissions Test Button geklickt');
      console.log('Permissions Test button clicked');
      if (window.testPermissions) {
        window.testPermissions();
      } else {
        out('Fehler: testPermissions-Funktion nicht gefunden');
        console.error('testPermissions function not found on window object');
      }
    };
  }

  // Zeige verfügbare Funktionen im window object
  const debugFunctions = ['showSQLiteStatus', 'testSettingsPersistence', 'testPermissions'].filter(fn => window[fn]);
  out(`Verfügbare Debug-Funktionen: ${debugFunctions.join(', ')}`);
  if (debugFunctions.length === 0) {
    out('⚠️ Keine Debug-Funktionen gefunden - möglicherweise Script-Ladung-Problem');
  }
  out('S3 Backup Tool gestartet');
  setTimeout(refresh, 1000);
  document.addEventListener('keydown', (e) => {
    if (e.ctrlKey && e.key === 'r' && !['INPUT', 'TEXTAREA'].includes(e.target.tagName)) { e.preventDefault(); refresh(); }
    if (e.altKey && e.key >= '1' && e.key <= '3') { e.preventDefault(); const tabs = ['providers', 'restore', 'activity']; const tabIndex = parseInt(e.key) - 1; if (tabs[tabIndex]) document.querySelector(`[data-tab="${tabs[tabIndex]}"]`).click(); }
  });
  const slugEl = document.getElementById('slug');
  slugEl.addEventListener('keypress', (e) => { if (e.key === 'Enter') restoreLocal(); });
  slugEl.addEventListener('blur', (e) => { const v = e.target.value.trim(); if (v) populateRestoreOptionsFromBackup(v); });
  const s3El = document.getElementById('s3key');
  s3El.addEventListener('keypress', (e) => { if (e.key === 'Enter') restoreFromS3(); });
  const originalOut = out;
  window.out = (msg) => { originalOut(msg); if (msg.includes('erfolgreich')) { setTimeout(() => { const outputEl = document.getElementById('output'); const lines = outputEl.textContent.split('\n'); const filteredLines = lines.filter(line => !line.includes(msg.split(']')[1])); outputEl.textContent = filteredLines.join('\n'); }, 5000); } };
});

window.addEventListener('error', (e) => { out(`JavaScript-Fehler: ${e.message}`); console.error('Unerwarteter Fehler:', e.error); });
window.addEventListener('unhandledrejection', (e) => { out(`Promise-Fehler: ${e.reason}`); console.error('Unbehandelte Promise-Rejection:', e.reason); });


