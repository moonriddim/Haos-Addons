#!/bin/sh
echo "Content-Type: application/json"
echo

# Gesamten Request-Body lesen (robust auch ohne Newline)
# Body robust lesen (CGI: bevorzugt CONTENT_LENGTH)
echo "DEBUG: CONTENT_LENGTH='${CONTENT_LENGTH:-}'" >&2
if [ -n "${CONTENT_LENGTH:-}" ] && [ "$CONTENT_LENGTH" -gt 0 ] 2>/dev/null; then
  body="$(dd bs=1 count="$CONTENT_LENGTH" 2>/dev/null)"
  echo "DEBUG: Body via dd: '$body'" >&2
else
  body="$(cat)"
  echo "DEBUG: Body via cat: '$body'" >&2
fi

# Sicherstellen dass das data-Verzeichnis existiert und die richtigen Permissions hat
mkdir -p /data
chmod 755 /data
db="/data/overrides.db"

# Debug-Logging für Empfang
echo "DEBUG: Received body length: ${#body}" >&2
echo "DEBUG: Data dir permissions: $(ls -la /data 2>/dev/null || echo 'not accessible')" >&2

base='{}'

# Eingehenden JSON-Body validieren  
# KRITISCHER FIX: Verwende body direkt, nicht mit default {} - das fügt extra } hinzu!
if [ -n "$body" ]; then
  incoming="$body"
else
  incoming="{}"
fi

echo "DEBUG: Raw body: '$body'" >&2
echo "DEBUG: Incoming: '$incoming'" >&2
echo "DEBUG: Body length: ${#body}, Incoming length: ${#incoming}" >&2

# Bei ungültigem JSON: wie leeres Objekt behandeln (robuster gegen Transport-Besonderheiten)
if printf '%s' "$incoming" | jq -e '.' >/dev/null 2>&1; then
  echo "DEBUG: JSON is VALID" >&2
else
  echo "DEBUG: Invalid JSON received, using empty object" >&2
  echo "DEBUG: JQ error output: $(printf '%s' "$incoming" | jq -e '.' 2>&1)" >&2
  incoming='{}'
fi

# Debug: Zeige empfangene Keys
echo "DEBUG: Received keys: $(printf '%s' "$incoming" | jq -r 'keys[]' 2>/dev/null)" >&2

# Nur DB: direkt in SQLite upserten
if command -v sqlite3 >/dev/null 2>&1; then
  # Erstelle Tabelle und setze Permissions
  sqlite3 "$db" "CREATE TABLE IF NOT EXISTS kv (key TEXT PRIMARY KEY, value TEXT NOT NULL);" 2>/dev/null || {
    echo "DEBUG: Failed to create table" >&2
    echo '{"error":"failed_to_create_table"}'
    exit 1
  }
  chmod 666 "$db" 2>/dev/null || true
  keys=$(printf '%s' "$incoming" | jq -r 'keys[]' 2>/dev/null)
  saved_count=0
  for k in $keys; do
    v=$(printf '%s' "$incoming" | jq -c --arg k "$k" '.[$k]' 2>/dev/null)
    # KRITISCHER FIX: Secret Access Key behandeln - leere Strings nicht überschreiben
    # Für secret_access_key: nur schreiben wenn nicht leer (sonst bestehenden Wert beibehalten)
    if [ "$k" = "secret_access_key" ] && printf '%s' "$v" | jq -e '. == "" or . == null' >/dev/null 2>&1; then
      echo "DEBUG: Skipping empty secret_access_key to preserve existing value" >&2
      continue
    fi
    
    # Nur nicht-leere Werte schreiben (wie oben)
    if printf '%s' "$v" | jq -e 'if type=="string" then .!="" else .!=null end' >/dev/null 2>&1; then
      # Einfache SQL-Quoting-Regel: single quotes verdoppeln
      k_esc=$(printf '%s' "$k" | sed "s/'/''/g")
      v_esc=$(printf '%s' "$v" | sed "s/'/''/g")
      if sqlite3 "$db" "INSERT INTO kv(key,value) VALUES('$k_esc','$v_esc') ON CONFLICT(key) DO UPDATE SET value=excluded.value;" 2>/dev/null; then
        saved_count=$((saved_count + 1))
        echo "DEBUG: Saved $k successfully" >&2
      else
        echo "DEBUG: Failed to save $k" >&2
      fi
    else
      echo "DEBUG: Skipped empty/null value for $k" >&2
    fi
  done
  
  # Finale Verifikation
  total_entries=$(sqlite3 "$db" "SELECT COUNT(*) FROM kv;" 2>/dev/null || echo "0")
  echo "DEBUG: Database now contains $total_entries entries" >&2
  echo '{"status":"ok","saved":'"$saved_count"',"total":'"$total_entries"'}'
else
  echo '{"error":"sqlite_unavailable"}'
fi

