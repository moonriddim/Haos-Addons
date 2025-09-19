#!/bin/sh
echo "Content-Type: application/json"
echo

# Debug spezifisch für den Bucket-Namen
db="/data/overrides.db"

# JSON Response
cat << EOF
{
  "status": "success",
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "database_path": "$db",
  "database_exists": $([ -f "$db" ] && echo "true" || echo "false"),
EOF

if [ -f "$db" ] && command -v sqlite3 >/dev/null 2>&1; then
  # Hole den exakten s3_bucket Wert
  bucket_value_raw=$(sqlite3 "$db" "SELECT value FROM kv WHERE key = 's3_bucket' LIMIT 1;" 2>/dev/null || echo "")
  bucket_value_decoded=""
  
  if [ -n "$bucket_value_raw" ]; then
    # Versuche JSON zu dekodieren
    bucket_value_decoded=$(echo "$bucket_value_raw" | jq -r '.' 2>/dev/null || echo "$bucket_value_raw")
  fi
  
  # Alle Keys anzeigen
  all_keys=$(sqlite3 "$db" "SELECT key FROM kv ORDER BY key;" 2>/dev/null | paste -sd "," - || echo "")
  
  # Alle s3_ prefixed Keys
  s3_entries=$(sqlite3 "$db" "SELECT key, value FROM kv WHERE key LIKE 's3_%' ORDER BY key;" 2>/dev/null || echo "")
  
  cat << EOF
  "bucket_name_raw": $(echo "$bucket_value_raw" | jq -R '.' 2>/dev/null || echo "null"),
  "bucket_name_decoded": $(echo "$bucket_value_decoded" | jq -R '.' 2>/dev/null || echo "null"),
  "bucket_name_length": ${#bucket_value_decoded},
  "all_keys": "$(echo "$all_keys" | sed 's/"/\\"/g')",
  "s3_related_entries": {
EOF

  # S3-Related entries als JSON
  first=true
  echo "$s3_entries" | while IFS='|' read -r key value; do
    if [ -n "$key" ]; then
      if [ "$first" = "true" ]; then
        first=false
      else
        echo ","
      fi
      decoded_value=$(echo "$value" | jq -r '.' 2>/dev/null || echo "$value")
      printf '    "%s": %s' "$key" "$(echo "$decoded_value" | jq -R '.' 2>/dev/null)"
    fi
  done
  
  echo ""
  echo "  }"
  
else
  cat << EOF
  "error": "Database not accessible or sqlite3 not available"
EOF
fi

echo "}"
EOF
