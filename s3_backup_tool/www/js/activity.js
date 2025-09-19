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

// Neue Funktion für SQLite-Debug (global verfügbar machen)
window.showSQLiteStatus = async function() {
  out('Überprüfe SQLite-Status...');
  setLoading(true);
  try {
    const result = await fetch(resolvePath('api/debug-sqlite'));
    if (result.ok) {
      const data = JSON.parse(await result.text());
      out('=== SQLite DEBUG STATUS ===');
      out(`Data-Verzeichnis: ${data.data_dir || 'unknown'}`);
      if (data.data_perms) out(`Permissions: ${data.data_perms} (${data.data_owner})`);
      out(`SQLite3: ${data.sqlite3 || 'nicht verfügbar'}`);
      if (data.version) out(`Version: ${data.version}`);
      out(`DB-Datei: ${data.db_file || 'missing'}`);
      if (data.db_size) out(`Größe: ${data.db_size} bytes`);
      if (data.db_perms) out(`DB-Permissions: ${data.db_perms} (${data.db_owner})`);
      out(`DB-Zugriff: ${data.db_access || 'unknown'}`);
      if (data.entry_count !== undefined) out(`Einträge: ${data.entry_count}`);
      if (data.keys && data.keys.length > 0) {
        out(`Gespeicherte Keys: ${data.keys.join(', ')}`);
      }
      out('=== ENDE SQLite STATUS ===');
    } else {
      out(`Fehler beim Laden des SQLite-Status: HTTP ${result.status}`);
    }
  } catch (error) {
    out(`Fehler: ${error.message}`);
  } finally {
    setLoading(false);
  }
};

// Funktion zum Testen der Settings-Persistenz (global verfügbar machen)
window.testSettingsPersistence = async function() {
  out('Teste Settings-Persistenz...');
  setLoading(true);
  
  try {
    // Speichere Test-Einstellung
    const testKey = 'test_persistence_' + Date.now();
    const testValue = 'test_value_' + Math.random();
    
    const saveResult = await call('api/set-overrides', { 
      body: JSON.stringify({ [testKey]: testValue }) 
    });
    
    if (!saveResult.ok) {
      out('Fehler beim Speichern der Test-Einstellung');
      return;
    }
    
    out(`Test-Einstellung gespeichert: ${testKey} = ${testValue}`);
    
    // Lade Einstellungen zurück
    await new Promise(resolve => setTimeout(resolve, 100)); // Kurz warten
    
    const loadResult = await call('api/get-overrides');
    if (!loadResult.ok) {
      out('Fehler beim Laden der Einstellungen');
      return;
    }
    
    const settings = JSON.parse(loadResult.body || '{}');
    const loadedValue = settings[testKey];
    
    if (loadedValue === testValue) {
      out('✓ Persistenz-Test erfolgreich: Einstellung korrekt gespeichert und geladen');
    } else {
      out(`✗ Persistenz-Test fehlgeschlagen: erwartet "${testValue}", erhalten "${loadedValue}"`);
    }
    
  } catch (error) {
    out(`Fehler beim Persistenz-Test: ${error.message}`);
  } finally {
    setLoading(false);
  }
};


