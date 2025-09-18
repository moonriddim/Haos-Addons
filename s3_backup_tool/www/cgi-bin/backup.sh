#!/bin/sh
echo "Content-Type: application/json"
echo

# SUPERVISOR_TOKEN aus Datei lesen (Home Assistant Add-on Standard)  
if [ -f /tmp/supervisor_token ]; then
  export SUPERVISOR_TOKEN=$(cat /tmp/supervisor_token)
fi

/run.sh --oneshot >/tmp/ui.log 2>&1
code=$?
if [ $code -eq 0 ]; then
  # Versuche, den zuletzt hochgeladenen S3-Key aus Log zu extrahieren
  key=$(grep -E "Upload finished: s3://" /tmp/ui.log | tail -n1 | sed -E 's/.*s3:\/\/(.+)/\1/' )
  if [ -n "$key" ]; then
    echo "{\"status\":\"ok\",\"s3_key\":\"$key\"}"
  else
    echo "{\"status\":\"ok\"}"
  fi
else
  echo "{\"status\":\"error\",\"log\":\"$(sed 's/"/\"/g' /tmp/ui.log | tail -n 200)\"}"
fi

