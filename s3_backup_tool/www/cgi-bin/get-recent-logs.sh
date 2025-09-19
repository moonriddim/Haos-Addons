#!/bin/sh
echo "Content-Type: application/json"
echo

# Parameter für Log-Anzahl (default: 50 Zeilen)
lines="${1:-50}"

# EINFACHES LOG-SYSTEM: Lese von unserem eigenen Log-File
LOG_FILE="/data/s3_addon.log"

# Falls Log-File nicht existiert, erstelle es
if [ ! -f "$LOG_FILE" ]; then
  touch "$LOG_FILE" 2>/dev/null || {
    # Falls /data nicht beschreibbar, verwende /tmp
    LOG_FILE="/tmp/s3_addon.log"
    touch "$LOG_FILE" 2>/dev/null
  }
fi

# Lese die letzten Zeilen aus dem Log-File
if [ -f "$LOG_FILE" ]; then
  recent_logs=$(tail -n "$lines" "$LOG_FILE" 2>/dev/null || echo "")
else
  recent_logs="Log-Datei nicht verfügbar"
fi

# Erstelle JSON Array aus Log-Zeilen
create_json_logs() {
  local log_content="$1"
  local json_entries=""
  
  # Wenn keine Logs vorhanden, leeres Array
  if [ -z "$log_content" ] || [ "$log_content" = "Log-Datei nicht verfügbar" ]; then
    echo "[]"
    return
  fi
  
  # Verarbeite jede Log-Zeile
  echo "$log_content" | while IFS= read -r line; do
    if [ -n "$line" ]; then
      # Escape JSON special characters
      escaped_line=$(printf '%s' "$line" | sed 's/\\/\\\\/g; s/"/\\"/g')
      
      # Extrahiere Timestamp falls vorhanden (Format: [YYYY-MM-DD HH:MM:SS] oder [HH:MM:SS])
      timestamp=""
      if echo "$line" | grep -q "^\[.*\]"; then
        timestamp=$(echo "$line" | sed 's/^\[\([^]]*\)\].*/\1/')
      else
        timestamp=$(date -u +"%Y-%m-%d %H:%M:%S")
      fi
      
      # Bestimme Log-Level
      level="info"
      if echo "$line" | grep -qi "error\|fail\|✗"; then
        level="error"
      elif echo "$line" | grep -qi "warn\|warning"; then
        level="warning"
      elif echo "$line" | grep -qi "✓\|success\|completed"; then
        level="success"
      fi
      
      # Ausgabe als JSON-Zeile für bessere Verarbeitung
      printf '{"timestamp":"%s","level":"%s","message":"%s"}\n' "$timestamp" "$level" "$escaped_line"
    fi
  done | {
    # Sammle alle JSON-Zeilen und formatiere als Array
    first=true
    echo "["
    while IFS= read -r json_line; do
      if [ "$first" = "true" ]; then
        first=false
      else
        echo ","
      fi
      printf '%s' "$json_line"
    done
    echo "]"
  }
}

# Erstelle JSON Response
json_logs=$(create_json_logs "$recent_logs")

# Ausgabe
cat << EOF
{
  "status": "success",
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "log_file": "$LOG_FILE",
  "lines_requested": $lines,
  "logs": $json_logs
}
EOF
