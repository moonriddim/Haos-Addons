#!/bin/sh
echo "Content-Type: application/json"
echo
/run.sh --oneshot >/tmp/ui.log 2>&1
code=$?
if [ $code -eq 0 ]; then
  echo "{\"status\":\"ok\"}"
else
  echo "{\"status\":\"error\",\"log\":\"$(sed 's/"/\"/g' /tmp/ui.log | tail -n 200)\"}"
fi

