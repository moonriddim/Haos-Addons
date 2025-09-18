#!/bin/sh
echo "Content-Type: application/json"
echo
read body
mkdir -p /data
tmp=/data/overrides.json

# bestehende Datei lesen, falls vorhanden
if [ -f "$tmp" ]; then
  base=$(cat "$tmp")
else
  base='{}'
fi

# Eingehenden JSON-Body als JSON übernehmen
# Nur Felder updaten, die im Request vorhanden sind:
# - Strings: nur wenn nicht leer
# - Booleans/Numbers: auch false/0 werden übernommen
echo "$base" | jq \
  --argjson incoming "${body:-{}}" \
  '
  def nonempty(v):
    if (v|type) == "string" then (v != "")
    else v != null end;
  . as $base
  | ($incoming // {}) as $i
  | $base * ($i | with_entries(select(nonempty(.value))))
  ' > "$tmp" 2>/dev/null || echo '{}' > "$tmp"
echo '{"status":"ok"}'

