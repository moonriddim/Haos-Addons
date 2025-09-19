#!/bin/sh
echo "Content-Type: application/json"
echo

DB="/data/overrides.db"

if [ -f "$DB" ] && command -v sqlite3 >/dev/null 2>&1; then
  tmp='{}'
  while IFS=$(printf '\t') read -r k v; do
    [ -n "$k" ] || continue
    # sqlite3 gibt ggf. NULL aus, das behandeln wir als leeres Objekt
    if [ "$v" = "NULL" ]; then v='null'; fi
    if printf '%s' "$v" | jq -e '.' >/dev/null 2>&1; then
      tmp=$(printf '%s' "$tmp" | jq --arg k "$k" --argjson v "$v" '. + {($k): $v}' 2>/dev/null || printf '%s' "$tmp")
    else
      tmp=$(printf '%s' "$tmp" | jq --arg k "$k" --arg v "$v" '. + {($k): $v}' 2>/dev/null || printf '%s' "$tmp")
    fi
  done <<EOF
$(sqlite3 -separator "$(printf '\t')" "$DB" "SELECT key, value FROM kv;" 2>/dev/null)
EOF
  echo "$tmp"
else
  echo '{}'
fi


