#!/bin/sh
echo "Content-Type: text/plain"
echo

echo "=== API CALL DEBUG ==="
echo "Datum: $(date)"
echo "Script: $0"
echo "Methode: ${REQUEST_METHOD:-'UNKNOWN'}"
echo "Content-Type: ${CONTENT_TYPE:-'UNKNOWN'}"
echo "Content-Length: ${CONTENT_LENGTH:-'UNKNOWN'}"
echo

echo "=== ENVIRONMENT ==="
env | grep -E "^(REQUEST_|CONTENT_|HTTP_)" | sort
echo

echo "=== AKTUELLER PROCESS ==="
echo "PID: $$"
echo "Working Dir: $(pwd)"
echo "User: $(whoami)"
echo

echo "=== /data STATUS ==="
ls -la /data/
echo

echo "=== ÜBERPRÜFUNG der ECHTEN CGI-SCRIPTS ==="
echo "set-overrides.sh vorhanden: $([ -f /www/cgi-bin/set-overrides.sh ] && echo 'JA' || echo 'NEIN')"
echo "get-overrides.sh vorhanden: $([ -f /www/cgi-bin/get-overrides.sh ] && echo 'JA' || echo 'NEIN')"
echo "set-overrides.sh ausführbar: $([ -x /www/cgi-bin/set-overrides.sh ] && echo 'JA' || echo 'NEIN')"
echo "get-overrides.sh ausführbar: $([ -x /www/cgi-bin/get-overrides.sh ] && echo 'JA' || echo 'NEIN')"
echo

echo "=== TESTE ECHTE set-overrides.sh API ==="
# Teste mit dem gleichen JSON wie der Persistenz-Test
test_json='{"test_real_api_'$(date +%s)'":"test_real_value_'$(date +%N)'"}'
echo "Test-JSON: $test_json"

# Simuliere POST-Request zu set-overrides.sh
echo "$test_json" | CONTENT_TYPE="application/json" CONTENT_LENGTH=${#test_json} REQUEST_METHOD="POST" /www/cgi-bin/set-overrides.sh 2>&1

echo
echo "=== TESTE ECHTE get-overrides.sh API ==="
# Teste get-overrides.sh direkt
REQUEST_METHOD="GET" /www/cgi-bin/get-overrides.sh 2>&1

echo
echo "=== VERGLEICHE SIMULATION VS REALITÄT ==="
db="/data/overrides.db"
if [ -f "$db" ]; then
    echo "Aktuelle DB-Einträge:"
    sqlite3 "$db" "SELECT key, value FROM kv ORDER BY key;" 2>/dev/null | while IFS='|' read -r k v; do
        echo "  $k = $v"
    done
    
    echo
    echo "Anzahl Einträge: $(sqlite3 "$db" "SELECT COUNT(*) FROM kv;" 2>/dev/null)"
    
    # Suche nach echten Provider-Keys
    echo
    echo "Provider-relevante Keys in DB:"
    sqlite3 "$db" "SELECT key, value FROM kv WHERE key LIKE '%bucket%' OR key LIKE '%access_key%' OR key LIKE '%endpoint%' OR key LIKE '%s3_%';" 2>/dev/null | while IFS='|' read -r k v; do
        echo "  PROVIDER: $k = $v"
    done
else
    echo "DB existiert nicht!"
fi
