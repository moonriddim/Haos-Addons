#!/bin/sh
echo "Content-Type: application/json"
echo

# Dieses CGI listet Objekte im konfigurierten Bucket/Prefix.
# Verwendet die zur Laufzeit gesetzten AWS_* Variablen aus run.sh Umgebung.

# Versuche, Prefix aus /data/overrides.json zu lesen, falls vorhanden
PFX=""
if [ -f /data/overrides.json ]; then
  PFX=$(jq -r '.s3_prefix // empty' /data/overrides.json 2>/dev/null)
fi

# Supervisor-Umgebung stellt keine direkten Vars bereit; run.sh setzt sie zur Laufzeit.
# Hier verlassen wir uns auf die env des lighttpd-Prozesses (vererbt vom run.sh Start).

if [ -z "$S3_BUCKET" ] || [ -z "$AWS_REGION_ARG" ]; then
  # Fallback: best-effort lesbar aus /data/overrides.json und config.yaml ist komplex; melden wir Info
  # Das Listing klappt trotzdem, wenn AWS_DEFAULT_REGION/AWS_* im Env gesetzt sind.
  :
fi

OUT=$(aws s3api list-objects-v2 \
  --bucket "$S3_BUCKET" \
  --prefix "${S3_PREFIX}" \
  --output json $AWS_ENDPOINT_ARG $AWS_REGION_ARG $SSL_ARG 2>/dev/null)

if [ -z "$OUT" ]; then
  echo '{"objects":[]}'
  exit 0
fi

echo "$OUT" | jq '{objects: (.Contents // [])}' 2>/dev/null || echo '{"objects":[]}'


