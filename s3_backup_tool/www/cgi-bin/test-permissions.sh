#!/bin/sh
echo "Content-Type: text/plain"
echo

echo "=== PERMISSIONS TEST ==="
echo "Current user: $(whoami)"
echo "Current groups: $(groups 2>/dev/null || id)"
echo

echo "=== /data VERZEICHNIS ==="
if [ -d "/data" ]; then
    echo "/data existiert"
    ls -la /data/
    echo "Permissions: $(ls -ld /data | awk '{print $1}')"
    echo "Owner: $(ls -ld /data | awk '{print $3":"$4}')"
else 
    echo "/data existiert NICHT"
    echo "Versuche /data zu erstellen..."
    if mkdir -p /data 2>&1; then
        echo "✓ /data erfolgreich erstellt"
        ls -ld /data
    else
        echo "✗ Fehler beim Erstellen von /data"
    fi
fi

echo
echo "=== SCHREIBRECHTE TEST ==="
testfile="/data/permission_test_$(date +%s).txt"
if touch "$testfile" 2>/dev/null; then
    echo "✓ Kann Dateien in /data erstellen"
    echo "Test content" > "$testfile"
    if [ -f "$testfile" ]; then
        echo "✓ Kann in /data schreiben"
        content=$(cat "$testfile" 2>/dev/null)
        if [ "$content" = "Test content" ]; then
            echo "✓ Kann aus /data lesen"
        else
            echo "✗ Kann NICHT aus /data lesen"
        fi
        rm -f "$testfile" 2>/dev/null
    else
        echo "✗ Kann NICHT in /data schreiben"
    fi
else
    echo "✗ Kann KEINE Dateien in /data erstellen"
fi

echo
echo "=== SQLite TEST ==="
db="/data/test.db"
if command -v sqlite3 >/dev/null 2>&1; then
    echo "✓ sqlite3 verfügbar: $(which sqlite3)"
    echo "Version: $(sqlite3 --version)"
    
    # Test SQLite Funktionalität
    if sqlite3 "$db" "CREATE TABLE test (id INTEGER, value TEXT);" 2>/dev/null; then
        echo "✓ Kann SQLite-Tabelle erstellen"
        
        if sqlite3 "$db" "INSERT INTO test (id, value) VALUES (1, 'test');" 2>/dev/null; then
            echo "✓ Kann Daten in SQLite einfügen"
            
            result=$(sqlite3 "$db" "SELECT value FROM test WHERE id=1;" 2>/dev/null)
            if [ "$result" = "test" ]; then
                echo "✓ Kann Daten aus SQLite lesen"
            else
                echo "✗ Kann NICHT aus SQLite lesen (erhalten: '$result')"
            fi
        else
            echo "✗ Kann NICHT in SQLite einfügen"
        fi
        
        # Cleanup
        rm -f "$db" 2>/dev/null
    else
        echo "✗ Kann KEINE SQLite-Tabelle erstellen"
    fi
else
    echo "✗ sqlite3 NICHT verfügbar"
fi

echo
echo "=== AKTUELLE DATENBANK ==="
realdb="/data/overrides.db"
if [ -f "$realdb" ]; then
    echo "overrides.db existiert:"
    ls -la "$realdb"
    
    if command -v sqlite3 >/dev/null 2>&1; then
        count=$(sqlite3 "$realdb" "SELECT COUNT(*) FROM kv;" 2>/dev/null || echo "ERROR")
        echo "Einträge in DB: $count"
        
        if [ "$count" != "ERROR" ] && [ "$count" != "0" ]; then
            echo "Vorhandene Keys:"
            sqlite3 "$realdb" "SELECT key FROM kv;" 2>/dev/null || echo "Fehler beim Lesen der Keys"
        fi
    fi
else
    echo "overrides.db existiert NICHT"
fi

echo
echo "=== PROZESS INFO ==="
echo "PID: $$"
echo "PPID: $PPID"
echo "Working directory: $(pwd)"
echo "Environment variables related to user:"
env | grep -E "^(USER|HOME|UID|GID|GROUPS)" || echo "Keine User-Env-Vars gefunden"
