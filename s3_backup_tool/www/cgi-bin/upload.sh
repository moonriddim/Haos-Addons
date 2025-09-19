#!/bin/sh
echo "Content-Type: application/json"
echo

# Erwartet: { "slug": "abcdef12" }
read body
slug=$(echo "$body" | jq -r .slug 2>/dev/null)
if [ -z "$slug" ] || [ "$slug" = "null" ]; then
  echo '{"error":"slug required"}'
  exit 0
fi

path="/backup/${slug}.tar"
if [ ! -f "$path" ]; then
  echo '{"error":"backup file not found"}'
  exit 0
fi

# Lade Overrides, falls vorhanden, wird in run.sh-Umgebung ohnehin konfiguriert
# Hier verlassen wir uns auf Umgebungsvariablen aus run.sh (AWS_* und S3_*)

filename=$(basename "$path")
key="${S3_PREFIX}${filename}"

if aws s3 cp "$path" "s3://$S3_BUCKET/$key" $AWS_ENDPOINT_ARG $AWS_REGION_ARG $SSL_ARG >/dev/null 2>&1; then
  echo "{\"status\":\"ok\",\"s3_key\":\"$key\"}"
else
  echo '{"error":"upload failed"}'
fi


