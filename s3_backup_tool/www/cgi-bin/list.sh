#!/bin/sh
echo "Content-Type: application/json"
echo

# Debug-Logging für Backup-Liste
echo "[$(date)] CGI list.sh aufgerufen" >> /tmp/backup_debug.log

# SUPERVISOR_TOKEN aus Datei lesen (Home Assistant Add-on Standard)
if [ -f /tmp/supervisor_token ]; then
  SUPERVISOR_TOKEN=$(cat /tmp/supervisor_token)
  echo "[$(date)] SUPERVISOR_TOKEN gefunden (Länge: ${#SUPERVISOR_TOKEN})" >> /tmp/backup_debug.log
else
  echo "[$(date)] SUPERVISOR_TOKEN nicht gefunden!" >> /tmp/backup_debug.log
  echo '{"error":"supervisor token not found"}'
  exit 1
fi

# Debug: API-Aufruf protokollieren
echo "[$(date)] Rufe Supervisor API auf: http://supervisor/backups" >> /tmp/backup_debug.log

# API-Aufruf mit detailliertem Logging
response=$(curl -sS -w "\nHTTP_STATUS:%{http_code}\nRESPONSE_TIME:%{time_total}" \
     -H "Authorization: Bearer $SUPERVISOR_TOKEN" \
     -X GET http://supervisor/backups 2>&1)

# HTTP-Status und Response-Zeit extrahieren
http_status=$(echo "$response" | grep "HTTP_STATUS:" | cut -d: -f2)
response_time=$(echo "$response" | grep "RESPONSE_TIME:" | cut -d: -f2)
response_body=$(echo "$response" | sed '/HTTP_STATUS:/,$d')

echo "[$(date)] HTTP Status: $http_status, Response Time: ${response_time}s" >> /tmp/backup_debug.log

if [ "$http_status" = "200" ]; then
  echo "[$(date)] Erfolgreiche Antwort erhalten" >> /tmp/backup_debug.log
  echo "$response_body" | jq -c '.' 2>/dev/null || echo '{"error":"json parse failed"}'
else
  echo "[$(date)] Fehler - HTTP $http_status: $response_body" >> /tmp/backup_debug.log
  echo "{\"error\":\"http_status_$http_status\",\"details\":\"$(echo $response_body | sed 's/"/\\\"/g')\"}"
fi

