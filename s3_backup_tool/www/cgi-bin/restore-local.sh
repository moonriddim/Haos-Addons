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

pwd=$(echo "$body" | jq -r .password //empty 2>/dev/null)
include_ha=$(echo "$body" | jq -r .homeassistant 2>/dev/null)
addons=$(echo "$body" | jq -c .addons 2>/dev/null)
folders=$(echo "$body" | jq -c .folders 2>/dev/null)

if [ -n "$pwd" ] && [ "$pwd" != "null" ]; then export RESTORE_PASSWORD="$pwd"; fi
# Nur setzen, wenn boolescher Wert geliefert wurde
if [ "$include_ha" = "true" ] || [ "$include_ha" = "false" ]; then export RESTORE_INCLUDE_HA="$include_ha"; fi
if [ -n "$addons" ] && [ "$addons" != "null" ]; then export RESTORE_ADDONS="$addons"; fi
if [ -n "$folders" ] && [ "$folders" != "null" ]; then export RESTORE_FOLDERS="$folders"; fi

export RESTORE_SLUG="$slug"
/run.sh --restore >/tmp/ui.log 2>&1
echo '{"status":"started"}'

