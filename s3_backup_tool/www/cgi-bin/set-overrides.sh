#!/bin/sh
echo "Content-Type: application/json"
echo

# Gesamten Request-Body lesen (robust auch ohne Newline)
body="$(cat)"

mkdir -p /data
dest=/data/overrides.json
tmpfile="${dest}.tmp"

# bestehende Datei lesen, falls vorhanden
if [ -f "$dest" ]; then
  base="$(cat "$dest")"
else
  base='{}'
fi

# Eingehenden JSON-Body validieren
incoming="${body:-{}}"
if ! printf '%s' "$incoming" | jq -e '.' >/dev/null 2>&1; then
  echo '{"error":"invalid json"}'
  exit 0
fi

# Nur Felder updaten, die im Request vorhanden sind:
# - Strings: nur wenn nicht leer
# - Booleans/Numbers: auch false/0 werden übernommen
if echo "$base" | jq \
  --argjson incoming "$incoming" \
  '
  def nonempty(v):
    if (v|type) == "string" then (v != "")
    else v != null end;
  . as $base
  | ($incoming // {}) as $i
  | $base * ($i | with_entries(select(nonempty(.value))))
  ' > "$tmpfile" 2>/dev/null; then
  mv "$tmpfile" "$dest" 2>/dev/null || { echo '{"error":"write_failed"}'; exit 0; }
  echo '{"status":"ok"}'
else
  echo '{"error":"jq_failed"}'
fi

