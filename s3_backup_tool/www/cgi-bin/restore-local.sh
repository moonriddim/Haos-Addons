#!/bin/sh
echo "Content-Type: application/json"
echo
read body
slug=$(echo "$body" | jq -r .slug 2>/dev/null)
if [ -z "$slug" ] || [ "$slug" = "null" ]; then
  echo '{"error":"slug required"}'
  exit 0
fi

# SUPERVISOR_TOKEN aus Datei lesen (Home Assistant Add-on Standard)
if [ -f /tmp/supervisor_token ]; then
  export SUPERVISOR_TOKEN=$(cat /tmp/supervisor_token)
fi

export RESTORE_SLUG="$slug"
/run.sh --restore >/tmp/ui.log 2>&1
echo '{"status":"started"}'

