#!/bin/sh
echo "Content-Type: application/json"
echo
read body
cmd=$(echo "$body" | jq -r .cmd 2>/dev/null)
case "$cmd" in
  start)
    /run.sh --start-scheduler >/tmp/ui.log 2>&1 &
    echo '{"status":"started"}'
    ;;
  stop)
    /run.sh --stop-scheduler >/tmp/ui.log 2>&1
    echo '{"status":"stopped"}'
    ;;
  status)
    s=$(/run.sh --scheduler-status 2>/dev/null)
    echo "{\"status\":\"$s\"}"
    ;;
  *)
    echo '{"error":"unknown command"}'
    ;;
esac


