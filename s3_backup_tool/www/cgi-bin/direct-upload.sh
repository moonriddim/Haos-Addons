#!/bin/sh
echo "Content-Type: application/json"
echo

# Erwartet JSON wie: { "sources": ["config","media"], "name": "direct-2025-09-19" }
read body
name=$(echo "$body" | jq -r .name 2>/dev/null)
sources=$(echo "$body" | jq -c .sources 2>/dev/null)

if [ -z "$sources" ] || [ "$sources" = "null" ]; then
  sources='["config"]'
fi

ts=$(date -u +%Y-%m-%d_%H-%M-%S)
if [ -z "$name" ] || [ "$name" = "null" ]; then
  name="direct_${ts}"
fi

tmpfile="/tmp/${name}.tar"

# Mapping Quellen
paths=""
for src in $(echo "$sources" | jq -r '.[]'); do
  case "$src" in
    config) paths="$paths /config" ;;
    media)  paths="$paths /media" ;;
    share)  paths="$paths /share" ;;
    ssl)    paths="$paths /ssl" ;;
    *) ;;
  esac
done

if [ -z "$paths" ]; then
  echo '{"error":"no valid sources"}'
  exit 0
fi

# Tar erstellen (read-only Quellen; exclude tmp/cache, falls vorhanden)
tar -C / -cf "$tmpfile" $(echo "$paths" | sed 's/^ *//') \
  --exclude='config/.storage/cloud' \
  --exclude='config/.storage/onboarding' \
  --exclude='**/__pycache__' 2>/dev/null

if [ ! -f "$tmpfile" ]; then
  echo '{"error":"tar create failed"}'
  exit 0
fi

/run.sh --upload-file "$tmpfile" >/tmp/ui.log 2>&1
code=$?
if [ $code -eq 0 ]; then
  key=$(grep -E "Upload finished: s3://" /tmp/ui.log | tail -n1 | sed -E 's/.*s3:\/\/(.+)/\1/' )
  echo "{\"status\":\"ok\",\"s3_key\":\"$key\"}"
else
  echo '{"error":"upload failed"}'
fi


