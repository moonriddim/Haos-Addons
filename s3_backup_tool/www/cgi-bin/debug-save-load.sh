#!/bin/sh
echo "Content-Type: text/plain"
echo

echo "=== DIRECT SAVE/LOAD TEST ==="
db="/data/overrides.db"

# Test 1: Direkter SQLite-Schreibtest
echo "Test 1: Direkter SQLite-Schreibtest"
testkey="direct_test_$(date +%s)"
testvalue="direct_value_$(date +%N)"

echo "Schreibe: $testkey = $testvalue"

if sqlite3 "$db" "CREATE TABLE IF NOT EXISTS kv (key TEXT PRIMARY KEY, value TEXT NOT NULL);"; then
    echo "✓ Tabelle erstellt/existiert"
else
    echo "✗ Tabelle-Erstellung fehlgeschlagen"
fi

if sqlite3 "$db" "INSERT INTO kv(key,value) VALUES('$testkey','\"$testvalue\"') ON CONFLICT(key) DO UPDATE SET value=excluded.value;"; then
    echo "✓ Direkter SQLite-Insert erfolgreich"
else
    echo "✗ Direkter SQLite-Insert fehlgeschlagen"
fi

# Sofort wieder lesen
result=$(sqlite3 "$db" "SELECT value FROM kv WHERE key='$testkey';" 2>/dev/null)
echo "Gelesener Wert: '$result'"
if [ "$result" = "\"$testvalue\"" ]; then
    echo "✓ Direkter Roundtrip erfolgreich"
else
    echo "✗ Direkter Roundtrip fehlgeschlagen (erwartet: \"$testvalue\", erhalten: $result)"
fi

echo
echo "Test 2: set-overrides.sh Simulation"

# Test 2: Simuliere set-overrides.sh Logik
testkey2="simulated_test_$(date +%s)"
testvalue2="simulated_value_$(date +%N)"

echo "Simuliere set-overrides.sh mit: $testkey2 = $testvalue2"

# JSON wie im echten Script
incoming="{\"$testkey2\":\"$testvalue2\"}"
echo "JSON Input: $incoming"

# Validiere JSON
if printf '%s' "$incoming" | jq -e '.' >/dev/null 2>&1; then
    echo "✓ JSON ist valide"
else
    echo "✗ JSON ist NICHT valide"
fi

# Extrahiere Keys wie im Script
keys=$(printf '%s' "$incoming" | jq -r 'keys[]' 2>/dev/null)
echo "Extrahierte Keys: $keys"

for k in $keys; do
    v=$(printf '%s' "$incoming" | jq -c --arg k "$k" '.[$k]' 2>/dev/null)
    echo "Key: $k, Value: $v"
    
    # Teste Bedingung wie im Script
    if printf '%s' "$v" | jq -e 'if type=="string" then .!="" else .!=null end' >/dev/null 2>&1; then
        echo "✓ Wert passiert Bedingung"
        
        # SQL-Escaping wie im Script
        k_esc=$(printf '%s' "$k" | sed "s/'/''/g")
        v_esc=$(printf '%s' "$v" | sed "s/'/''/g")
        echo "Escaped: k='$k_esc', v='$v_esc'"
        
        # SQL-Ausführung
        sql="INSERT INTO kv(key,value) VALUES('$k_esc','$v_esc') ON CONFLICT(key) DO UPDATE SET value=excluded.value;"
        echo "SQL: $sql"
        
        if sqlite3 "$db" "$sql" 2>/dev/null; then
            echo "✓ Simulierter Insert erfolgreich"
        else
            echo "✗ Simulierter Insert fehlgeschlagen"
        fi
    else
        echo "✗ Wert fällt durch Bedingung"
    fi
done

# Teste ob es lesbar ist
result2=$(sqlite3 "$db" "SELECT value FROM kv WHERE key='$testkey2';" 2>/dev/null)
echo "Gelesener Wert: '$result2'"

echo
echo "Test 3: get-overrides.sh Simulation"
echo "Simuliere get-overrides.sh"

# Alle Einträge wie get-overrides.sh
tmp='{}'
while IFS=$(printf '\t') read -r k v; do
    [ -n "$k" ] || continue
    echo "Lade: k='$k', v='$v'"
    
    if [ "$v" = "NULL" ]; then 
        v='null'
        echo "  NULL -> null konvertiert"
    fi
    
    if printf '%s' "$v" | jq -e '.' >/dev/null 2>&1; then
        echo "  ✓ Wert ist valides JSON"
        tmp=$(printf '%s' "$tmp" | jq --arg k "$k" --argjson v "$v" '. + {($k): $v}' 2>/dev/null || printf '%s' "$tmp")
    else
        echo "  ✓ Wert als String behandelt"
        tmp=$(printf '%s' "$tmp" | jq --arg k "$k" --arg v "$v" '. + {($k): $v}' 2>/dev/null || printf '%s' "$tmp")
    fi
done <<EOF
$(sqlite3 -separator "$(printf '\t')" "$db" "SELECT key, value FROM kv;" 2>/dev/null)
EOF

echo "Finales JSON: $tmp"

echo
echo "=== CURRENT DB STATE ==="
echo "Alle Einträge in der Datenbank:"
sqlite3 "$db" "SELECT key, value FROM kv;" 2>/dev/null | while IFS='|' read -r k v; do
    echo "  $k = $v"
done

count=$(sqlite3 "$db" "SELECT COUNT(*) FROM kv;" 2>/dev/null)
echo "Gesamtanzahl: $count"
