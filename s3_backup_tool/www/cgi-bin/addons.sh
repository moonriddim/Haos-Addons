#!/bin/sh
echo "Content-Type: application/json"
echo

if [ -f /tmp/supervisor_token ]; then
  SUPERVISOR_TOKEN=$(cat /tmp/supervisor_token)
fi

resp=$(curl -sS -H "Authorization: Bearer $SUPERVISOR_TOKEN" -H "Content-Type: application/json" \
  -X GET "http://supervisor/addons" 2>/dev/null)

echo "$resp" | jq -c '{addons: (.data.addons // []) | map({slug: .slug, name: .name, version: .version, state: .state})}' 2>/dev/null \
  || echo '{"addons": []}'


