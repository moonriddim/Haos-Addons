#!/bin/sh
echo "Content-Type: application/json"
echo

# Liefert den aktuellen Inhalt von /data/overrides.json (oder {} wenn nicht vorhanden)
FILE="/data/overrides.json"
if [ -f "$FILE" ]; then
  cat "$FILE" 2>/dev/null | jq -c '.' 2>/dev/null || echo '{}'
else
  echo '{}'
fi


