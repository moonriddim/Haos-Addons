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
sse=$(echo "$body" | jq -r .s3_sse 2>/dev/null)
kms=$(echo "$body" | jq -r .s3_sse_kms_key_id 2>/dev/null)
ev=$(echo "$body" | jq -r .enable_versioning 2>/dev/null)
watch=$(echo "$body" | jq -r .watch_ha_backups 2>/dev/null)
upload_existing=$(echo "$body" | jq -r .upload_existing 2>/dev/null)
del_local=$(echo "$body" | jq -r .delete_local_after_upload 2>/dev/null)
run_on_start=$(echo "$body" | jq -r .run_on_start 2>/dev/null)
interval=$(echo "$body" | jq -r .backup_interval_hours 2>/dev/null)
cron=$(echo "$body" | jq -r .backup_schedule_cron 2>/dev/null)
keep_last=$(echo "$body" | jq -r .retention_keep_last_s3 2>/dev/null)
ret_days=$(echo "$body" | jq -r .retention_days_s3 2>/dev/null)
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
  --arg sse "$sse" \
  --arg kms "$kms" \
  --argjson ev ${ev:-false} \
  --argjson watch ${watch:-false} \
  --argjson upload ${upload_existing:-false} \
  --argjson del ${del_local:-false} \
  --argjson runstart ${run_on_start:-false} \
  --arg interval "${interval}" \
  --arg cron "${cron}" \
  --arg keep_last "${keep_last}" \
  --arg ret_days "${ret_days}" \
  '.
   | (if $ep != "" then .s3_endpoint_url=$ep else . end)
   | (if $rg != "" then .s3_region_name=$rg else . end)
   | .force_path_style=$fps
   | (if $bkt != "" then .s3_bucket=$bkt else . end)
   | (if $pfx != "" then .s3_prefix=$pfx else . end)
   | (if $ak != "" then .access_key_id=$ak else . end)
   | (if $sk != "" then .secret_access_key=$sk else . end)
   | (if $sse != "" and $sse != "null" then .s3_sse=$sse else . end)
   | (if $kms != "" and $kms != "null" then .s3_sse_kms_key_id=$kms else . end)
   | .enable_versioning=$ev
   | .watch_ha_backups=$watch
   | .upload_existing=$upload
   | .delete_local_after_upload=$del
   | .run_on_start=$runstart
   | (if $interval != "" and $interval != "null" then .backup_interval_hours=($interval|tonumber) else . end)
   | (if $cron != "" and $cron != "null" then .backup_schedule_cron=$cron else . end)
   | (if $keep_last != "" and $keep_last != "null" then .retention_keep_last_s3=($keep_last|tonumber) else . end)
   | (if $ret_days != "" and $ret_days != "null" then .retention_days_s3=($ret_days|tonumber) else . end)
  ' > "$tmp" 2>/dev/null || echo '{}' > "$tmp"
echo '{"status":"ok"}'

