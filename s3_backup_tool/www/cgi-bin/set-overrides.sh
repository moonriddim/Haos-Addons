#!/bin/sh
echo "Content-Type: application/json"
echo
read body
ep=$(echo "$body" | jq -r .s3_endpoint_url 2>/dev/null)
rg=$(echo "$body" | jq -r .s3_region_name 2>/dev/null)
fps=$(echo "$body" | jq -r .force_path_style 2>/dev/null)
mkdir -p /data
tmp=/data/overrides.json
jq -n --arg ep "$ep" --arg rg "$rg" --argjson fps ${fps:-false} '{s3_endpoint_url:$ep, s3_region_name:$rg, force_path_style:$fps}' > "$tmp" 2>/dev/null || echo '{}' > "$tmp"
echo '{"status":"ok"}'

