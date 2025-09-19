#!/bin/sh
echo "Content-Type: application/json"
echo

DB="/data/overrides.db"

# Erstelle History-Tabelle falls nicht vorhanden
if command -v sqlite3 >/dev/null 2>&1; then
  sqlite3 "$DB" "CREATE TABLE IF NOT EXISTS backup_history (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp TEXT NOT NULL,
    filename TEXT NOT NULL,
    s3_key TEXT,
    status TEXT NOT NULL,
    size_bytes INTEGER,
    duration_seconds INTEGER,
    error_message TEXT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
  );" 2>/dev/null || true
fi

# Backup-History aus DB laden
if [ -f "$DB" ] && command -v sqlite3 >/dev/null 2>&1; then
  # Hole die letzten 50 Backup-Einträge
  result=$(sqlite3 "$DB" "
    SELECT 
      id,
      timestamp,
      filename,
      s3_key,
      status,
      size_bytes,
      duration_seconds,
      error_message,
      created_at
    FROM backup_history 
    ORDER BY created_at DESC 
    LIMIT 50
  " 2>/dev/null)
  
  # Konvertiere zu JSON
  if [ -n "$result" ]; then
    echo "{"
    echo "  \"status\": \"success\","
    echo "  \"history\": ["
    
    first=true
    echo "$result" | while IFS='|' read -r id timestamp filename s3_key status size_bytes duration_seconds error_message created_at; do
      if [ "$first" = true ]; then
        first=false
      else
        echo ","
      fi
      
      # JSON-Escape für Strings
      filename_escaped=$(echo "$filename" | sed 's/\\/\\\\/g; s/"/\\"/g')
      s3_key_escaped=$(echo "$s3_key" | sed 's/\\/\\\\/g; s/"/\\"/g')
      error_message_escaped=$(echo "$error_message" | sed 's/\\/\\\\/g; s/"/\\"/g')
      
      echo -n "    {"
      echo -n "\"id\":$id,"
      echo -n "\"timestamp\":\"$timestamp\","
      echo -n "\"filename\":\"$filename_escaped\","
      echo -n "\"s3_key\":\"$s3_key_escaped\","
      echo -n "\"status\":\"$status\","
      echo -n "\"size_bytes\":${size_bytes:-0},"
      echo -n "\"duration_seconds\":${duration_seconds:-0},"
      echo -n "\"error_message\":\"$error_message_escaped\","
      echo -n "\"created_at\":\"$created_at\""
      echo -n "    }"
    done
    
    echo ""
    echo "  ]"
    echo "}"
  else
    echo '{"status":"success","history":[]}'
  fi
else
  echo '{"status":"error","message":"Database not available","history":[]}'
fi
