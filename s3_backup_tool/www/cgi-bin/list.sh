#!/bin/sh
echo "Content-Type: application/json"
echo

# SUPERVISOR_TOKEN aus Datei lesen (Home Assistant Add-on Standard)
if [ -f /tmp/supervisor_token ]; then
  SUPERVISOR_TOKEN=$(cat /tmp/supervisor_token)
else
  echo '{"error":"supervisor token not found"}'
  exit 1
fi

curl -sS -H "Authorization: Bearer $SUPERVISOR_TOKEN" \
     -X GET http://supervisor/backups | jq -c '.' 2>/dev/null || echo '{"error":"list failed"}'

