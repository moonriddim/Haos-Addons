#!/bin/sh
echo "Content-Type: application/json"
echo
read body
ep=$(echo "$body" | jq -r .s3_endpoint_url 2>/dev/null)
rg=$(echo "$body" | jq -r .s3_region_name 2>/dev/null)
fps=$(echo "$body" | jq -r .force_path_style 2>/dev/null)
bkt=$(echo "$body" | jq -r .s3_bucket 2>/dev/null)
pfx=$(echo "$body" | jq -r .s3_prefix 2>/dev/null)
ak=$(echo "$body" | jq -r .access_key_id 2>/dev/null)
sk=$(echo "$body" | jq -r .secret_access_key 2>/dev/null)
mkdir -p /data
tmp=/data/overrides.json

# bestehende Datei lesen, falls vorhanden
if [ -f "$tmp" ]; then
  base=$(cat "$tmp")
else
  base='{}'
fi

# zusammenführen (nur nicht-leere Felder ersetzen)
echo "$base" | jq \
  --arg ep "$ep" \
  --arg rg "$rg" \
  --argjson fps ${fps:-false} \
  --arg bkt "$bkt" \
  --arg pfx "$pfx" \
  --arg ak "$ak" \
  --arg sk "$sk" \
  '.
   | (if $ep != "" then .s3_endpoint_url=$ep else . end)
   | (if $rg != "" then .s3_region_name=$rg else . end)
   | .force_path_style=$fps
   | (if $bkt != "" then .s3_bucket=$bkt else . end)
   | (if $pfx != "" then .s3_prefix=$pfx else . end)
   | (if $ak != "" then .access_key_id=$ak else . end)
   | (if $sk != "" then .secret_access_key=$sk else . end)
  ' > "$tmp" 2>/dev/null || echo '{}' > "$tmp"
echo '{"status":"ok"}'

