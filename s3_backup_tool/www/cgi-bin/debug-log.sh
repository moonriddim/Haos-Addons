#!/bin/sh
echo "Content-Type: text/plain"
echo

echo "=== Debug Log für Backup API ==="
echo

if [ -f /tmp/backup_debug.log ]; then
  echo "Letzte 50 Log-Einträge:"
  echo "========================"
  tail -n 50 /tmp/backup_debug.log
else
  echo "Keine Debug-Logs gefunden."
fi

echo
echo "=== SUPERVISOR_TOKEN Status ==="
if [ -f /tmp/supervisor_token ]; then
  token_length=$(wc -c < /tmp/supervisor_token)
  echo "Token-Datei gefunden, Länge: $token_length Zeichen"
  echo "Token-Anfang: $(head -c 20 /tmp/supervisor_token)..."
else
  echo "Token-Datei nicht gefunden!"
fi

echo
echo "=== Netzwerk-Test ==="
echo "Ping supervisor:"
ping -c 1 supervisor 2>&1 | head -n 3

echo
echo "=== Dateisystem-Status ==="
ls -la /tmp/supervisor_token 2>&1 || echo "Token-Datei nicht vorhanden"
ls -la /tmp/backup_debug.log 2>&1 || echo "Debug-Log nicht vorhanden"
