#!/bin/sh
echo "Content-Type: application/json"
echo

# Body lesen
if [ -n "${CONTENT_LENGTH:-}" ] && [ "$CONTENT_LENGTH" -gt 0 ] 2>/dev/null; then
  body="$(dd bs=1 count="$CONTENT_LENGTH" 2>/dev/null)"
else
  body="$(cat)"
fi

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

# JSON parsen und Backup-Eintrag hinzufügen
if [ -n "$body" ] && command -v jq >/dev/null 2>&1; then
  timestamp=$(echo "$body" | jq -r '.timestamp // ""')
  filename=$(echo "$body" | jq -r '.filename // ""')
  s3_key=$(echo "$body" | jq -r '.s3_key // ""')
  status=$(echo "$body" | jq -r '.status // "unknown"')
  size_bytes=$(echo "$body" | jq -r '.size_bytes // 0')
  duration_seconds=$(echo "$body" | jq -r '.duration_seconds // 0')
  error_message=$(echo "$body" | jq -r '.error_message // ""')
  
  if [ -n "$filename" ] && [ -n "$status" ]; then
    # SQL-Escaping
    timestamp_esc=$(echo "$timestamp" | sed "s/'/''/g")
    filename_esc=$(echo "$filename" | sed "s/'/''/g")
    s3_key_esc=$(echo "$s3_key" | sed "s/'/''/g")
    status_esc=$(echo "$status" | sed "s/'/''/g")
    error_message_esc=$(echo "$error_message" | sed "s/'/''/g")
    
    # In DB einfügen
    if sqlite3 "$DB" "INSERT INTO backup_history (timestamp, filename, s3_key, status, size_bytes, duration_seconds, error_message) VALUES ('$timestamp_esc', '$filename_esc', '$s3_key_esc', '$status_esc', $size_bytes, $duration_seconds, '$error_message_esc');" 2>/dev/null; then
      echo '{"status":"success","message":"Backup history entry added"}'
    else
      echo '{"status":"error","message":"Failed to add history entry"}'
    fi
  else
    echo '{"status":"error","message":"Missing required fields (filename, status)"}'
  fi
else
  echo '{"status":"error","message":"Invalid JSON or missing data"}'
fi
