#!/bin/sh
echo "Content-Type: application/json"
echo
read body
key=$(echo "$body" | jq -r .key 2>/dev/null)
if [ -z "$key" ] || [ "$key" = "null" ]; then
  echo '{"error":"key required"}'
  exit 0
fi
export RESTORE_FROM_S3_KEY="$key"
/run.sh --restore >/tmp/ui.log 2>&1
echo '{"status":"started"}'

