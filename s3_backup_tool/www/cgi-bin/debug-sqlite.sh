#!/bin/sh
echo "Content-Type: application/json"
echo

db="/data/overrides.db"
result="{"

# Data-Verzeichnis Status
if [ -d "/data" ]; then
  data_perms=$(ls -la /data 2>/dev/null | head -2 | tail -1 | awk '{print $1}')
  data_owner=$(ls -la /data 2>/dev/null | head -2 | tail -1 | awk '{print $3":"$4}')
  result="$result\"data_dir\":\"exists\",\"data_perms\":\"$data_perms\",\"data_owner\":\"$data_owner\","
else
  result="$result\"data_dir\":\"missing\","
fi

# SQLite Binary
if command -v sqlite3 >/dev/null 2>&1; then
  sqlite_version=$(sqlite3 --version 2>/dev/null | cut -d' ' -f1)
  result="$result\"sqlite3\":\"available\",\"version\":\"$sqlite_version\","
else
  result="$result\"sqlite3\":\"missing\","
fi

# Datenbank-Datei Status  
if [ -f "$db" ]; then
  db_size=$(stat -c%s "$db" 2>/dev/null || echo "unknown")
  db_perms=$(ls -la "$db" 2>/dev/null | awk '{print $1}')
  db_owner=$(ls -la "$db" 2>/dev/null | awk '{print $3":"$4}')
  result="$result\"db_file\":\"exists\",\"db_size\":$db_size,\"db_perms\":\"$db_perms\",\"db_owner\":\"$db_owner\","
  
  # Teste DB-Zugriff
  if command -v sqlite3 >/dev/null 2>&1; then
    count=$(sqlite3 "$db" "SELECT COUNT(*) FROM kv;" 2>/dev/null || echo "ERROR")
    if [ "$count" = "ERROR" ]; then
      result="$result\"db_access\":\"failed\","
    else
      result="$result\"db_access\":\"ok\",\"entry_count\":$count,"
      
      # Zeige alle Keys (fix JSON array formatting)
      keys=$(sqlite3 "$db" "SELECT key FROM kv;" 2>/dev/null | tr '\n' ',' | sed 's/,$//' || echo "")
      if [ -n "$keys" ]; then
        formatted_keys=$(echo "$keys" | sed 's/,/","/g;s/^/"/;s/$/"/')
        result="$result\"keys\":[$formatted_keys],"
      else
        result="$result\"keys\":[],"
      fi
    fi
  fi
else
  result="$result\"db_file\":\"missing\","
fi

# Schließe JSON ab (entferne letztes Komma)
result=$(echo "$result" | sed 's/,$//')
result="$result}"

echo "$result"
