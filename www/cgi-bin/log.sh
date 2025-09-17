#!/bin/sh
echo "Content-Type: text/plain"
echo
if [ -f /tmp/ui.log ]; then
  tail -n 200 /tmp/ui.log
fi

