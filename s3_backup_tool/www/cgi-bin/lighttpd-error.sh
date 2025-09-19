#!/bin/sh
echo "Content-Type: text/plain"
echo
if [ -f /tmp/lighttpd_error.log ]; then
  tail -n 200 /tmp/lighttpd_error.log
else
  echo "kein lighttpd_error.log gefunden"
fi


