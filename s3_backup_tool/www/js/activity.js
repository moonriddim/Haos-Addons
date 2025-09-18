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


