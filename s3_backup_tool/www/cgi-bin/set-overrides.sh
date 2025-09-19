#!/bin/sh
echo "Content-Type: application/json"
echo

# Gesamten Request-Body lesen (robust auch ohne Newline)
# Body robust lesen (CGI: bevorzugt CONTENT_LENGTH)
if [ -n "${CONTENT_LENGTH:-}" ] 2>/dev/null; then
  body="$(dd bs=1 count="$CONTENT_LENGTH" 2>/dev/null)"
else
  body="$(cat)"
fi

mkdir -p /data
db="/data/overrides.db"

base='{}'

# Eingehenden JSON-Body validieren
incoming="${body:-{}}"
# Bei ungültigem JSON: wie leeres Objekt behandeln (robuster gegen Transport-Besonderheiten)
if ! printf '%s' "$incoming" | jq -e '.' >/dev/null 2>&1; then
  incoming='{}'
fi

# Nur Felder updaten, die im Request vorhanden sind:
# - Strings: nur wenn nicht leer
# - Booleans/Numbers: auch false/0 werden übernommen
# Nur DB: direkt in SQLite upserten
if command -v sqlite3 >/dev/null 2>&1; then
  sqlite3 "$db" "CREATE TABLE IF NOT EXISTS kv (key TEXT PRIMARY KEY, value TEXT NOT NULL);" 2>/dev/null || true
  keys=$(printf '%s' "$incoming" | jq -r 'keys[]' 2>/dev/null)
  for k in $keys; do
    v=$(printf '%s' "$incoming" | jq -c --arg k "$k" '.[$k]' 2>/dev/null)
    # Nur nicht-leere Werte schreiben (wie oben)
    if printf '%s' "$v" | jq -e 'if type=="string" then .!="" else .!=null end' >/dev/null 2>&1; then
      sqlite3 "$db" "INSERT INTO kv(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value;" 2>/dev/null <<EOF
$k
$v
EOF
    fi
  done
  echo '{"status":"ok"}'
else
  echo '{"error":"sqlite_unavailable"}'
fi

