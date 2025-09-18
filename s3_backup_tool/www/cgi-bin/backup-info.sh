#!/bin/sh
echo "Content-Type: application/json"
echo

# Body lesen (Slug)
read body
slug=$(echo "$body" | jq -r .slug 2>/dev/null)
if [ -z "$slug" ] || [ "$slug" = "null" ]; then
  echo '{"error":"slug required"}'
  exit 0
fi

# SUPERVISOR_TOKEN bereitstellen
if [ -f /tmp/supervisor_token ]; then
  SUPERVISOR_TOKEN=$(cat /tmp/supervisor_token)
else
  echo '{"error":"missing supervisor token"}'
  exit 0
fi

# Backup-Details beim Supervisor abfragen
resp=$(curl -sS -H "Authorization: Bearer $SUPERVISOR_TOKEN" \
             -X GET "http://supervisor/backups/$slug/info" 2>/dev/null)

# Direkt die JSON durchreichen (enthält u.a. addons, folders, homeassistant)
echo "$resp" | jq -c '.' 2>/dev/null || echo '{"error":"invalid json"}'


