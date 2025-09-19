#!/bin/sh
echo "Content-Type: application/json"
echo

# Parameter für Log-Anzahl (default: 50 Zeilen)
lines="${1:-50}"

# Verschiedene Log-Quellen sammeln
collect_logs() {
  # 1. Supervisord Logs (Home Assistant Add-on Logs)
  if [ -f "/proc/1/fd/1" ]; then
    echo "=== ADDON LOGS ===" >&2
    # Versuche die letzten Logs zu bekommen
    # In Docker/Home Assistant Add-ons sind die Logs oft über journalctl verfügbar
    if command -v journalctl >/dev/null 2>&1; then
      journalctl -u s6-* --no-pager -n "$lines" --output cat 2>/dev/null | tail -n "$lines"
    fi
  fi
  
  # 2. Lighttpd Error Logs (falls vorhanden)
  if [ -f "/tmp/lighttpd_error.log" ]; then
    echo "=== LIGHTTPD ERRORS ===" >&2
    tail -n 20 "/tmp/lighttpd_error.log" 2>/dev/null
  fi
  
  # 3. Custom Log-Datei (falls wir eine erstellen)
  if [ -f "/data/addon.log" ]; then
    echo "=== CUSTOM LOGS ===" >&2
    tail -n "$lines" "/data/addon.log" 2>/dev/null
  fi
  
  # 4. Container-Logs (Docker logs)
  # Diese sind schwer direkt zu lesen, aber wir können es versuchen
  if [ -f "/var/log/messages" ]; then
    echo "=== SYSTEM LOGS ===" >&2
    tail -n 10 "/var/log/messages" 2>/dev/null | grep -i "s3\|backup\|upload" 2>/dev/null
  fi
}

# Sammle alle verfügbaren Logs
all_logs=""

# Versuche über Docker Logs API (wenn verfügbar)
if [ -n "${SUPERVISOR_TOKEN:-}" ] && command -v curl >/dev/null 2>&1; then
  # Home Assistant Supervisor API für Add-on Logs
  addon_logs=$(curl -sS -H "Authorization: Bearer $SUPERVISOR_TOKEN" \
                   "http://supervisor/addons/self/logs" 2>/dev/null || echo "")
  
  if [ -n "$addon_logs" ] && [ "$addon_logs" != "null" ]; then
    all_logs="$addon_logs"
  fi
fi

# Fallback: Sammle andere Log-Quellen
if [ -z "$all_logs" ]; then
  all_logs=$(collect_logs 2>/dev/null || echo "No logs available")
fi

# Formatiere Logs als JSON Array
format_logs_as_json() {
  local logs="$1"
  local json_array="[]"
  
  # Teile in Zeilen und erstelle JSON Array
  echo "$logs" | while IFS= read -r line; do
    if [ -n "$line" ]; then
      # Escape JSON special characters
      escaped_line=$(echo "$line" | sed 's/\\/\\\\/g; s/"/\\"/g; s/$/\\n/' | tr -d '\n')
      timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
      
      # Bestimme Log-Level basierend auf Inhalt
      level="info"
      if echo "$line" | grep -i "error\|fail\|exception" >/dev/null; then
        level="error"
      elif echo "$line" | grep -i "warn\|warning" >/dev/null; then
        level="warning"  
      elif echo "$line" | grep -i "upload\|download\|backup\|success" >/dev/null; then
        level="info"
      fi
      
      # JSON Entry erstellen
      json_entry="{\"timestamp\":\"$timestamp\",\"level\":\"$level\",\"message\":\"$escaped_line\"}"
      
      # Zum Array hinzufügen (vereinfacht)
      if [ "$json_array" = "[]" ]; then
        json_array="[$json_entry]"
      else
        # Entferne schließende Klammer, füge Komma und neuen Eintrag hinzu
        json_array=$(echo "$json_array" | sed 's/]$//')
        json_array="$json_array,$json_entry]"
      fi
    fi
  done
  
  echo "$json_array"
}

# Simple JSON Response mit Logs
cat << EOF
{
  "status": "success",
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "logs": [
$(echo "$all_logs" | tail -n "$lines" | sed 's/.*/"&",/' | sed '$s/,$//')
  ],
  "raw_logs": $(echo "$all_logs" | jq -R -s '.' 2>/dev/null || echo "\"$all_logs\"")
}
EOF
