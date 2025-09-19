#!/bin/sh
echo "Content-Type: application/json"
echo

read body

if [ -f /tmp/supervisor_token ]; then
  SUPERVISOR_TOKEN=$(cat /tmp/supervisor_token)
fi

name=$(echo "$body" | jq -r .name 2>/dev/null)
password=$(echo "$body" | jq -r .password 2>/dev/null)
full=$(echo "$body" | jq -r .full 2>/dev/null)
include_ha=$(echo "$body" | jq -r .homeassistant 2>/dev/null)
folders=$(echo "$body" | jq -c .folders 2>/dev/null)
addons=$(echo "$body" | jq -c .addons 2>/dev/null)

date_str=$(date -u +%Y-%m-%d_%H-%M-%S)
if [ -z "$name" ] || [ "$name" = "null" ]; then
  name="Addon Backup ${date_str}"
fi

payload=$(jq -n --arg name "$name" '{name: $name}')

if [ "$full" = "true" ]; then
  endpoint="http://supervisor/backups/new/full"
else
  endpoint="http://supervisor/backups/new/partial"
  if [ "$include_ha" = "true" ]; then
    payload=$(echo "$payload" | jq '. + {homeassistant: true}')
  fi
  if [ -n "$folders" ] && [ "$folders" != "null" ]; then
    payload=$(echo "$payload" | jq --argjson f "$folders" '. + {folders: $f}')
  fi
  if [ -n "$addons" ] && [ "$addons" != "null" ]; then
    payload=$(echo "$payload" | jq --argjson a "$addons" '. + {addons: $a}')
  fi
fi

if [ -n "$password" ] && [ "$password" != "null" ]; then
  payload=$(echo "$payload" | jq --arg p "$password" '. + {password: $p}')
fi

resp=$(curl -sS -H "Authorization: Bearer $SUPERVISOR_TOKEN" -H "Content-Type: application/json" \
  -X POST "$endpoint" -d "$payload" 2>/dev/null)

echo "$resp" | jq -c '.' 2>/dev/null || echo '{"error":"create failed"}'


