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
  echo "{\"status\":\"ok\"}"
else
  echo "{\"status\":\"error\",\"log\":\"$(sed 's/"/\"/g' /tmp/ui.log | tail -n 200)\"}"
fi

