#!/bin/sh
echo "Content-Type: application/json"
echo
curl -sS -H "Authorization: Bearer $SUPERVISOR_TOKEN" \
     -X GET http://supervisor/backups | jq -c '.' 2>/dev/null || echo '{"error":"list failed"}'

