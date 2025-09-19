#!/usr/bin/with-contenv bashio

set -u

# Log-File für Frontend-Integration
LOG_FILE="/data/s3_addon.log"

# Erweiterte Logging-Funktionen die auch ins Frontend-Log schreiben
log_info() { 
  bashio::log.info "$1"
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: $1" >> "$LOG_FILE" 2>/dev/null || true
}

log_warn() { 
  bashio::log.warning "$1"
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $1" >> "$LOG_FILE" 2>/dev/null || true
}

log_err() { 
  bashio::log.error "$1"
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" >> "$LOG_FILE" 2>/dev/null || true
}

require_bin() {
  local bin="$1"
  if ! command -v "$bin" >/dev/null 2>&1; then
    log_err "Required binary not found: $bin"
    return 1
  fi
}

readonly SUPERVISOR_API="http://supervisor"
readonly SUPERVISOR_TOKEN="${SUPERVISOR_TOKEN:-}"

# Read configuration
S3_ENDPOINT_URL="$(bashio::config 's3_endpoint_url')"
S3_REGION_NAME="$(bashio::config 's3_region_name')"
S3_BUCKET="$(bashio::config 's3_bucket')"
S3_PREFIX="$(bashio::config 's3_prefix')"
ACCESS_KEY_ID="$(bashio::config 'access_key_id')"
SECRET_ACCESS_KEY="$(bashio::config 'secret_access_key')"
BACKUP_INTERVAL_HOURS="$(bashio::config 'backup_interval_hours')"
FULL_BACKUP="$(bashio::config 'full_backup')"
BACKUP_NAME_TEMPLATE="$(bashio::config 'backup_name_template')"
VERIFY_SSL="$(bashio::config 'verify_ssl')"
RUN_ON_START="$(bashio::config 'run_on_start')"
RETENTION_KEEP_LAST_S3="$(bashio::config 'retention_keep_last_s3')"
RETENTION_DAYS_S3="$(bashio::config 'retention_days_s3')"
DELETE_LOCAL_AFTER_UPLOAD="$(bashio::config 'delete_local_after_upload')"
FORCE_PATH_STYLE="$(bashio::config 'force_path_style')"
AUTO_CREATE_BUCKET="$(bashio::config 'auto_create_bucket')"
BACKUP_PASSWORD="$(bashio::config 'backup_password')"
PARTIAL_INCLUDE_HASS="$(bashio::config 'partial_include_homeassistant')"
PARTIAL_FOLDERS="$(bashio::config 'partial_folders')"
PARTIAL_ADDONS="$(bashio::config 'partial_addons')"
WEBHOOK_SUCCESS_URL="$(bashio::config 'webhook_success_url')"
WEBHOOK_FAILURE_URL="$(bashio::config 'webhook_failure_url')"
HEALTHCHECK_PING_URL="$(bashio::config 'healthcheck_ping_url')"
S3_SSE="$(bashio::config 's3_sse')"
S3_SSE_KMS_KEY_ID="$(bashio::config 's3_sse_kms_key_id')"
ENABLE_VERSIONING="$(bashio::config 'enable_versioning')"
BACKUP_SCHEDULE_CRON="$(bashio::config 'backup_schedule_cron')"
ENABLE_RESTORE_HELPER="$(bashio::config 'enable_restore_helper')"
RESTORE_SLUG="$(bashio::config 'restore_slug')"
RESTORE_FROM_S3_KEY="$(bashio::config 'restore_from_s3_key')"
RESTORE_PASSWORD="$(bashio::config 'restore_password')"
WATCH_HA_BACKUPS="$(bashio::config 'watch_ha_backups')"
UPLOAD_EXISTING="$(bashio::config 'upload_existing')"

refresh_runtime_config() {
  # Optionen neu laden
  S3_ENDPOINT_URL="$(bashio::config 's3_endpoint_url')"
  S3_REGION_NAME="$(bashio::config 's3_region_name')"
  S3_BUCKET="$(bashio::config 's3_bucket')"
  S3_PREFIX="$(bashio::config 's3_prefix')"
  ACCESS_KEY_ID="$(bashio::config 'access_key_id')"
  SECRET_ACCESS_KEY="$(bashio::config 'secret_access_key')"
  VERIFY_SSL="$(bashio::config 'verify_ssl')"
  FORCE_PATH_STYLE="$(bashio::config 'force_path_style')"
  AUTO_CREATE_BUCKET="$(bashio::config 'auto_create_bucket')"
  BACKUP_INTERVAL_HOURS="$(bashio::config 'backup_interval_hours')"
  BACKUP_SCHEDULE_CRON="$(bashio::config 'backup_schedule_cron')"
  # Overrides anwenden (falls vorhanden)
  load_overrides
}

load_overrides() {
  local db="/data/overrides.db"
  
  # Debug: Zeige Status der SQLite-Datenbank
  if [[ -f "$db" ]]; then
    log_info "SQLite DB found: $db (size: $(stat -c%s "$db" 2>/dev/null || echo "unknown") bytes)"
  else
    log_info "SQLite DB not found: $db"
  fi
  
  if ! command -v sqlite3 >/dev/null 2>&1; then
    log_warn "sqlite3 command not available"
    return 1
  fi
  
  if [[ -f "$db" ]] && command -v sqlite3 >/dev/null 2>&1; then
    # Test DB-Verbindung
    local test_query
    test_query=$(sqlite3 "$db" "SELECT COUNT(*) FROM kv;" 2>/dev/null || echo "ERROR")
    if [[ "$test_query" == "ERROR" ]]; then
      log_warn "Cannot read from SQLite DB: $db"
      return 1
    fi
    
    log_info "SQLite DB accessible with $test_query override entries"
    
    # Helfer: Wert aus DB lesen und JSON-dekodiert in Variable schreiben (nur wenn gesetzt)  
    _assign_if_present() {
      local var_name="$1"
      local key_name="$2"
      local raw dec
      raw=$(sqlite3 "$db" "SELECT value FROM kv WHERE key = '$key_name' LIMIT 1;" 2>/dev/null || true)
      if [[ -n "$raw" ]]; then
        # Debug logging für wichtige Werte
        if [[ "$key_name" == "s3_bucket" || "$key_name" == "access_key_id" || "$key_name" == "s3_endpoint_url" ]]; then
          log_info "Loading override for $key_name: $(echo "$raw" | cut -c1-20)..."
        fi
        dec=$(jq -r '.' <<<"$raw" 2>/dev/null || true)
        if [[ -n "$dec" && "$dec" != "null" ]]; then
          printf -v "$var_name" '%s' "$dec"
        fi
      fi
    }

    _assign_if_present S3_ENDPOINT_URL s3_endpoint_url
    _assign_if_present S3_REGION_NAME s3_region_name
    _assign_if_present FORCE_PATH_STYLE force_path_style
    _assign_if_present S3_BUCKET s3_bucket
    _assign_if_present S3_PREFIX s3_prefix
    _assign_if_present ACCESS_KEY_ID access_key_id
    _assign_if_present SECRET_ACCESS_KEY secret_access_key
    _assign_if_present VERIFY_SSL verify_ssl
    _assign_if_present AUTO_CREATE_BUCKET auto_create_bucket
    _assign_if_present S3_SSE s3_sse
    _assign_if_present S3_SSE_KMS_KEY_ID s3_sse_kms_key_id
    _assign_if_present ENABLE_VERSIONING enable_versioning
    _assign_if_present WATCH_HA_BACKUPS watch_ha_backups
    _assign_if_present UPLOAD_EXISTING upload_existing
    _assign_if_present BACKUP_INTERVAL_HOURS backup_interval_hours
    _assign_if_present BACKUP_SCHEDULE_CRON backup_schedule_cron
    _assign_if_present RUN_ON_START run_on_start
    _assign_if_present RETENTION_KEEP_LAST_S3 retention_keep_last_s3
    _assign_if_present RETENTION_DAYS_S3 retention_days_s3

    log_info "Applied overrides from SQLite (/data/overrides.db)"
  fi
}

if [[ -z "$SUPERVISOR_TOKEN" ]]; then
  log_err "SUPERVISOR_TOKEN not set. Are we running under Supervisor?"
  exit 1
fi

require_bin jq || exit 1
require_bin curl || exit 1
require_bin aws || exit 1

# SUPERVISOR_TOKEN für CGI-Scripts verfügbar machen (Home Assistant Standard)
echo "$SUPERVISOR_TOKEN" > /tmp/supervisor_token
chmod 600 /tmp/supervisor_token

# Sicherstellen dass CGI-Scripts ausführbar sind
find /www -name "*.sh" -exec chmod +x {} +

# HTTP-UI früh starten, damit Ingress/Frontend erreichbar ist
if ! pgrep -x lighttpd >/dev/null 2>&1; then
  port="$(bashio::addon.ingress_port 2>/dev/null || true)"
  if [[ -z "$port" ]]; then
    port=8099
  fi
  mkdir -p /etc/lighttpd
  cat > /etc/lighttpd/lighttpd.conf <<'EOF'
server.modules = ("mod_access", "mod_alias", "mod_cgi", "mod_rewrite")
server.document-root = "/www"
server.port = __PORT__
server.errorlog = "/tmp/lighttpd_error.log"
server.breakagelog = "/tmp/lighttpd_access.log"

mimetype.assign = (
  ".html" => "text/html",
  ".css" => "text/css",
  ".js" => "application/javascript",
  ".json" => "application/json",
  ".png" => "image/png",
  ".svg" => "image/svg+xml"
)

# CGI-Konfiguration
cgi.assign = ( ".sh" => "/bin/sh" )

# CGI-Verzeichnis verfügbar machen
alias.url = ( "/cgi-bin/" => "/www/cgi-bin/" )

# API-Umschreibung mit besserer Syntax
url.rewrite-once = (
  "^/api/list$" => "/cgi-bin/list.sh",
  "^/api/list-s3$" => "/cgi-bin/list-s3.sh",
  "^/api/restore-local$" => "/cgi-bin/restore-local.sh",
  "^/api/restore-s3$" => "/cgi-bin/restore-s3.sh",
  "^/api/set-overrides$" => "/cgi-bin/set-overrides.sh",
  "^/api/get-overrides$" => "/cgi-bin/get-overrides.sh",
    "^/api/debug-log$" => "/cgi-bin/debug-log.sh",
    "^/api/debug-sqlite$" => "/cgi-bin/debug-sqlite.sh",
    "^/api/test-permissions$" => "/cgi-bin/test-permissions.sh",
    "^/api/debug-save-load$" => "/cgi-bin/debug-save-load.sh",
    "^/api/debug-api-calls$" => "/cgi-bin/debug-api-calls.sh",
    "^/api/get-recent-logs$" => "/cgi-bin/get-recent-logs.sh",
    "^/api/get-backup-history$" => "/cgi-bin/get-backup-history.sh",
    "^/api/add-backup-history$" => "/cgi-bin/add-backup-history.sh",
    "^/api/backup-info$" => "/cgi-bin/backup-info.sh",
    "^/api/service$" => "/cgi-bin/service.sh"
)

# Standard-Index und Fallback
index-file.names = ( "index.html" )
url.rewrite-if-not-file = ( "^/$" => "/index.html" )
EOF
  sed -i "s|__PORT__|${port}|" /etc/lighttpd/lighttpd.conf
  lighttpd -D -f /etc/lighttpd/lighttpd.conf &
fi

if [[ -z "$S3_BUCKET" || -z "$ACCESS_KEY_ID" || -z "$SECRET_ACCESS_KEY" ]]; then
  log_err "s3_bucket, access_key_id and secret_access_key are required. Waiting for configuration..."
  while true; do
    sleep 5
    refresh_runtime_config
    if [[ -n "$S3_BUCKET" && -n "$ACCESS_KEY_ID" && -n "$SECRET_ACCESS_KEY" ]]; then
      log_info "Configuration received. Continuing startup."
      break
    fi
  done
fi

# (AWS Runtime wird nach load_overrides/configure_aws_cli initial gesetzt)

configure_aws_cli() {
  if [[ "${FORCE_PATH_STYLE,,}" == "true" ]]; then
    log_info "AWS CLI: enable path-style addressing"
    aws configure set s3.addressing_style path >/dev/null 2>&1 || true
  fi
}

update_aws_runtime() {
  export AWS_ACCESS_KEY_ID="$ACCESS_KEY_ID"
  export AWS_SECRET_ACCESS_KEY="$SECRET_ACCESS_KEY"
  export AWS_DEFAULT_REGION="$S3_REGION_NAME"
  export AWS_EC2_METADATA_DISABLED=true

  AWS_ENDPOINT_ARG=""
  if [[ -n "$S3_ENDPOINT_URL" ]]; then
    AWS_ENDPOINT_ARG="--endpoint-url $S3_ENDPOINT_URL"
  fi
  AWS_REGION_ARG="--region $S3_REGION_NAME"
  SSL_ARG=""
  if [[ "${VERIFY_SSL,,}" == "false" ]]; then
    SSL_ARG="--no-verify-ssl"
  fi

  SSE_ARGS=()
  case "${S3_SSE^^}" in
    "AES256")
      SSE_ARGS+=("--sse" "AES256")
      ;;
    "KMS")
      SSE_ARGS+=("--sse" "aws:kms")
      if [[ -n "${S3_SSE_KMS_KEY_ID:-}" ]]; then
        SSE_ARGS+=("--sse-kms-key-id" "$S3_SSE_KMS_KEY_ID")
      fi
      ;;
    *)
      ;;
  esac

  configure_aws_cli
}

update_aws_runtime() {
  export AWS_ACCESS_KEY_ID="$ACCESS_KEY_ID"
  export AWS_SECRET_ACCESS_KEY="$SECRET_ACCESS_KEY"
  export AWS_DEFAULT_REGION="$S3_REGION_NAME"
  export AWS_EC2_METADATA_DISABLED=true

  AWS_ENDPOINT_ARG=""
  if [[ -n "$S3_ENDPOINT_URL" ]]; then
    AWS_ENDPOINT_ARG="--endpoint-url $S3_ENDPOINT_URL"
  fi
  AWS_REGION_ARG="--region $S3_REGION_NAME"
  SSL_ARG=""
  if [[ "${VERIFY_SSL,,}" == "false" ]]; then
    SSL_ARG="--no-verify-ssl"
  fi

  SSE_ARGS=()
  case "${S3_SSE^^}" in
    "AES256")
      SSE_ARGS+=("--sse" "AES256")
      ;;
    "KMS")
      SSE_ARGS+=("--sse" "aws:kms")
      if [[ -n "${S3_SSE_KMS_KEY_ID:-}" ]]; then
        SSE_ARGS+=("--sse-kms-key-id" "$S3_SSE_KMS_KEY_ID")
      fi
      ;;
    *)
      ;;
  esac

  configure_aws_cli
}

# Normalize prefix
if [[ -n "$S3_PREFIX" && "${S3_PREFIX: -1}" != "/" ]]; then
  S3_PREFIX="$S3_PREFIX/"
fi

create_backup() {
  local date_str backup_name payload resp result slug file_path
  date_str=$(date -u +"%Y-%m-%d_%H-%M-%S")
  backup_name=${BACKUP_NAME_TEMPLATE//\{date\}/$date_str}
  # Build payload based on full or partial
  if [[ "${FULL_BACKUP,,}" == "true" ]]; then
    payload=$(jq -n --arg name "$backup_name" '{name: $name}')
  else
    # Partial backup: add-ons and/or folders
    local addons_json folders_json include_ha
    include_ha=${PARTIAL_INCLUDE_HASS:-true}
    # PARTIAL_FOLDERS/ADDONS: bashio returns JSON text for YAML list
    addons_json="${PARTIAL_ADDONS:-[]}"
    folders_json="${PARTIAL_FOLDERS:-[]}"
    payload=$(jq -n \
      --arg name "$backup_name" \
      --argjson addons "$addons_json" \
      --argjson folders "$folders_json" \
      --argjson homeassistant "$include_ha" \
      '{name: $name, addons: $addons, folders: $folders, homeassistant: $homeassistant}')
  fi

  log_info "Starting backup: $backup_name"
  local endpoint
  if [[ "${FULL_BACKUP,,}" == "true" ]]; then
    endpoint="$SUPERVISOR_API/backups/new/full"
  else
    endpoint="$SUPERVISOR_API/backups/new/partial"
  fi

  # Optional: add password
  if [[ -n "${BACKUP_PASSWORD:-}" ]]; then
    payload=$(jq --arg pwd "$BACKUP_PASSWORD" '. + {password: $pwd}' <<<"$payload")
  fi

  resp=$(curl -sS -H "Authorization: Bearer $SUPERVISOR_TOKEN" \
               -H "Content-Type: application/json" \
               -X POST "$endpoint" \
               -d "$payload" || true)

  result=$(jq -r '.result // empty' <<<"$resp")
  if [[ "$result" != "ok" ]]; then
    log_err "Backup creation failed: $(jq -c '.' <<<"$resp")"
    return 1
  fi

  slug=$(jq -r '.data.slug // empty' <<<"$resp")
  if [[ -z "$slug" ]]; then
    log_err "Could not get backup slug. Response: $(jq -c '.' <<<"$resp")"
    return 1
  fi

  file_path="/backup/${slug}.tar"
  if ! wait_for_backup_file "$file_path"; then
    log_err "Backup file not created in time: $file_path"
    return 1
  fi

  upload_to_s3 "$file_path"
}

wait_for_backup_file() {
  local path="$1"
  local timeout=900
  local waited=0
  local last_size=0
  local size=0

  while (( waited < timeout )); do
    if [[ -f "$path" ]]; then
      size=$(stat -c %s "$path" 2>/dev/null || stat -f %z "$path" 2>/dev/null || echo 0)
      if [[ "$size" -gt 0 ]]; then
        sleep 5
        last_size="$size"
        size=$(stat -c %s "$path" 2>/dev/null || stat -f %z "$path" 2>/dev/null || echo 0)
        if [[ "$size" -eq "$last_size" ]]; then
          log_info "Backup-Datei bereit: $path (Größe: $size Bytes)"
          return 0
        fi
      fi
    fi
    sleep 5
    (( waited += 5 ))
  done
  return 1
}

upload_to_s3() {
  local path="$1"
  local filename key start_time end_time duration size_bytes
  filename=$(basename "$path")
  key="${S3_PREFIX}${filename}"
  start_time=$(date +%s)
  
  # Dateigröße ermitteln
  size_bytes=$(stat -c %s "$path" 2>/dev/null || stat -f %z "$path" 2>/dev/null || echo 0)

  ensure_bucket_exists || {
    # Backup-History: Failed (Bucket-Problem)
    add_backup_history "$filename" "s3://$S3_BUCKET/$key" "failed" "$size_bytes" 0 "Bucket does not exist or could not be created"
    return 1
  }
  
  log_info "Uploading to s3://$S3_BUCKET/$key"
  if aws s3 cp "$path" "s3://$S3_BUCKET/$key" $AWS_ENDPOINT_ARG $AWS_REGION_ARG $SSL_ARG "${SSE_ARGS[@]}"; then
    end_time=$(date +%s)
    duration=$((end_time - start_time))
    
    log_info "Upload finished: s3://$S3_BUCKET/$key (${duration}s, $(format_bytes "$size_bytes"))"
    
    # Backup-History: Success
    add_backup_history "$filename" "s3://$S3_BUCKET/$key" "success" "$size_bytes" "$duration" ""
    
    if [[ "${DELETE_LOCAL_AFTER_UPLOAD,,}" == "true" ]]; then
      if rm -f -- "$path"; then
        log_info "Removed local backup file: $path"
      else
        log_warn "Could not remove local backup file: $path"
      fi
    fi
    enforce_s3_retention || log_warn "S3 retention could not be fully enforced"
    notify_success "s3://$S3_BUCKET/$key"
  else
    end_time=$(date +%s)
    duration=$((end_time - start_time))
    
    log_err "Upload failed: s3://$S3_BUCKET/$key"
    
    # Backup-History: Failed (Upload-Problem)  
    add_backup_history "$filename" "s3://$S3_BUCKET/$key" "failed" "$size_bytes" "$duration" "Upload failed - check credentials and network"
    
    notify_failure "s3://$S3_BUCKET/$key"
    return 1
  fi
}

ensure_bucket_exists() {
  log_info "=== S3 BUCKET DEBUG ==="
  log_info "Bucket: '$S3_BUCKET'"
  log_info "Endpoint: '$S3_ENDPOINT_URL'"
  log_info "Region: '$S3_REGION_NAME'"
  log_info "AWS_ENDPOINT_ARG: '$AWS_ENDPOINT_ARG'"
  log_info "AWS_REGION_ARG: '$AWS_REGION_ARG'"
  log_info "SSL_ARG: '$SSL_ARG'"
  log_info "AUTO_CREATE_BUCKET: '$AUTO_CREATE_BUCKET'"
  log_info "ACCESS_KEY_ID: '${ACCESS_KEY_ID:0:8}***'" # Nur ersten 8 Zeichen zeigen
  log_info "SECRET_KEY length: ${#SECRET_ACCESS_KEY} chars"
  
  # Bucket-Name Validierung
  if [[ -z "$S3_BUCKET" ]]; then
    log_err "S3_BUCKET ist leer!"
    return 1
  fi
  
  # Überprüfe Bucket-Name auf problematische Zeichen
  if [[ "$S3_BUCKET" =~ [[:space:]] ]]; then
    log_warn "WARNUNG: Bucket-Name enthält Leerzeichen: '$S3_BUCKET'"
    log_warn "S3 Bucket-Namen sollten keine Leerzeichen enthalten!"
  fi
  
  if [[ "$S3_BUCKET" =~ [A-Z] ]]; then
    log_warn "WARNUNG: Bucket-Name enthält Großbuchstaben: '$S3_BUCKET'"
    log_warn "S3 Bucket-Namen sollten nur Kleinbuchstaben enthalten!"
  fi
  
  # Test 1: Bucket existiert bereits?
  log_info "Teste ob Bucket bereits existiert..."
  bucket_check_output=$(aws s3 ls "s3://$S3_BUCKET" $AWS_ENDPOINT_ARG $AWS_REGION_ARG $SSL_ARG 2>&1)
  bucket_check_exit_code=$?
  
  log_info "Bucket-Check Exit Code: $bucket_check_exit_code"
  if [[ $bucket_check_exit_code -eq 0 ]]; then
    log_info "✓ Bucket existiert bereits: $S3_BUCKET"
    # Optional: Versionierung sicherstellen, falls gewünscht
    if [[ "${ENABLE_VERSIONING,,}" == "true" ]]; then
      log_info "Aktiviere Versionierung für Bucket..."
      versioning_output=$(aws s3api put-bucket-versioning --bucket "$S3_BUCKET" --versioning-configuration Status=Enabled $AWS_ENDPOINT_ARG $AWS_REGION_ARG $SSL_ARG 2>&1)
      if [[ $? -eq 0 ]]; then
        log_info "✓ Versionierung aktiviert"
      else
        log_warn "Versionierung konnte nicht aktiviert werden: $versioning_output"
      fi
    fi
    log_info "=== BUCKET DEBUG ENDE ==="
    return 0
  else
    log_warn "✗ Bucket existiert nicht oder Zugriff verweigert"
    log_warn "AWS CLI Ausgabe: $bucket_check_output"
  fi
  
  # Test 2: Bucket erstellen (falls AUTO_CREATE_BUCKET aktiv)
  if [[ "${AUTO_CREATE_BUCKET,,}" == "true" ]]; then
    log_warn "Bucket nicht gefunden. Versuche zu erstellen: '$S3_BUCKET'"
    
    # Test AWS CLI Konnektivität zuerst
    log_info "Teste AWS CLI Konnektivität zum Endpoint..."
    if [[ -n "$S3_ENDPOINT_URL" ]]; then
      connectivity_test=$(curl -s --connect-timeout 10 "$S3_ENDPOINT_URL" 2>&1 || echo "FAILED")
      if [[ "$connectivity_test" == "FAILED" ]]; then
        log_err "✗ Kann Endpoint nicht erreichen: $S3_ENDPOINT_URL"
        log_err "Netzwerk-Problem oder falscher Endpoint?"
      else
        log_info "✓ Endpoint ist erreichbar: $S3_ENDPOINT_URL"
      fi
    fi
    
    # Versuche Bucket zu erstellen
    create_output=$(aws s3 mb "s3://$S3_BUCKET" $AWS_ENDPOINT_ARG $AWS_REGION_ARG $SSL_ARG 2>&1)
    create_exit_code=$?
    
    log_info "Bucket-Creation Exit Code: $create_exit_code"
    log_info "AWS CLI Create Output: $create_output"
    
    if [[ $create_exit_code -eq 0 ]]; then
      log_info "✓ Bucket erfolgreich erstellt: $S3_BUCKET"
      if [[ "${ENABLE_VERSIONING,,}" == "true" ]]; then
        log_info "Aktiviere Versionierung für neuen Bucket..."
        versioning_output=$(aws s3api put-bucket-versioning --bucket "$S3_BUCKET" --versioning-configuration Status=Enabled $AWS_ENDPOINT_ARG $AWS_REGION_ARG $SSL_ARG 2>&1)
        if [[ $? -eq 0 ]]; then
          log_info "✓ Versionierung aktiviert"
        else
          log_warn "Versionierung konnte nicht aktiviert werden: $versioning_output"
        fi
      fi
      log_info "=== BUCKET DEBUG ENDE ==="
      return 0
    else
      log_err "✗ Bucket-Erstellung fehlgeschlagen!"
      log_err "Mögliche Ursachen:"
      log_err "  - Bucket-Name bereits von anderem User belegt"
      log_err "  - Keine Berechtigung zum Erstellen von Buckets"
      log_err "  - Ungültiger Bucket-Name (Leerzeichen, Großbuchstaben, etc.)"
      log_err "  - Falsche AWS Credentials oder Endpoint"
      log_err "  - Netzwerk-Problem"
    fi
  else
    log_info "AUTO_CREATE_BUCKET ist deaktiviert - erstelle Bucket nicht automatisch"
  fi
  
  log_err "Bucket existiert nicht oder konnte nicht erstellt werden: '$S3_BUCKET'"
  log_err "LÖSUNG: Erstelle den Bucket manuell in deinem S3-Provider oder"
  log_err "         ändere den Bucket-Namen (keine Leerzeichen/Großbuchstaben)"
  log_info "=== BUCKET DEBUG ENDE ==="
  return 1
}

# Helper-Funktion: Backup-History hinzufügen
add_backup_history() {
  local filename="$1"
  local s3_key="$2" 
  local status="$3"
  local size_bytes="$4"
  local duration="$5"
  local error_message="$6"
  local timestamp
  
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  
  # JSON für API-Call erstellen
  local json_payload
  json_payload=$(cat << EOF
{
  "timestamp": "$timestamp",
  "filename": "$filename",
  "s3_key": "$s3_key", 
  "status": "$status",
  "size_bytes": $size_bytes,
  "duration_seconds": $duration,
  "error_message": "$error_message"
}
EOF
)
  
  # API-Call im Hintergrund (non-blocking)
  (curl -s -X POST -H "Content-Type: application/json" \
    -d "$json_payload" \
    "http://localhost:8099/api/add-backup-history" >/dev/null 2>&1 &)
}

# Helper-Funktion: Bytes formatieren
format_bytes() {
  local bytes="$1"
  local units=("B" "KB" "MB" "GB" "TB")
  local unit=0
  local size="$bytes"
  
  while [[ $size -gt 1024 && $unit -lt 4 ]]; do
    size=$((size / 1024))
    unit=$((unit + 1))
  done
  
  echo "${size}${units[$unit]}"
}

enforce_s3_retention() {
  local keep_last cutoff keys_by_count keys_by_days to_delete
  keep_last=${RETENTION_KEEP_LAST_S3:-0}
  cutoff=0
  if [[ -n "${RETENTION_DAYS_S3:-}" && "${RETENTION_DAYS_S3}" -gt 0 ]]; then
    cutoff=$(date -u -d "${RETENTION_DAYS_S3} days ago" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || true)
    if [[ -z "$cutoff" ]]; then
      # busybox date Fallback
      local now epoch days
      now=$(date -u +%s)
      days=$(( RETENTION_DAYS_S3 * 86400 ))
      epoch=$(( now - days ))
      cutoff=$(date -u -d @"$epoch" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%SZ)
    fi
  fi

  # List objects
  local list_json
  list_json=$(aws s3api list-objects-v2 --bucket "$S3_BUCKET" --prefix "$S3_PREFIX" --output json $AWS_ENDPOINT_ARG $AWS_REGION_ARG $SSL_ARG 2>/dev/null | jq '.Contents // []') || return 0
  if [[ $(jq 'length' <<<"$list_json") -eq 0 ]]; then
    return 0
  fi

  keys_by_count=""
  if [[ "$keep_last" -gt 0 ]]; then
    keys_by_count=$(jq -r --argjson k "$keep_last" 'sort_by(.LastModified) | reverse | .[$k:] | .[].Key' <<<"$list_json")
  fi

  keys_by_days=""
  if [[ -n "$cutoff" && "$cutoff" != "0" ]]; then
    keys_by_days=$(jq -r --arg cutoff "$cutoff" 'map(select(.LastModified < $cutoff)) | .[].Key' <<<"$list_json")
  fi

  to_delete=$( (printf "%s\n" "$keys_by_count"; printf "%s\n" "$keys_by_days") | sed '/^$/d' | sort | uniq )
  if [[ -z "$to_delete" ]]; then
    return 0
  fi

  log_info "S3 retention: deleting old backups"
  while IFS= read -r key; do
    log_info "Removing s3://$S3_BUCKET/$key"
    aws s3 rm "s3://$S3_BUCKET/$key" $AWS_ENDPOINT_ARG $AWS_REGION_ARG $SSL_ARG >/dev/null 2>&1 || log_warn "Delete failed: s3://$S3_BUCKET/$key"
  done <<< "$to_delete"
}

notify_success() {
  local target="$1"
  [[ -n "${WEBHOOK_SUCCESS_URL:-}" ]] && curl -fsS -X POST -H "Content-Type: application/json" -d "{\"status\":\"success\",\"target\":\"$target\"}" "$WEBHOOK_SUCCESS_URL" >/dev/null 2>&1 || true
  [[ -n "${HEALTHCHECK_PING_URL:-}" ]] && curl -fsS "$HEALTHCHECK_PING_URL" >/dev/null 2>&1 || true
}

notify_failure() {
  local target="$1"
  [[ -n "${WEBHOOK_FAILURE_URL:-}" ]] && curl -fsS -X POST -H "Content-Type: application/json" -d "{\"status\":\"failure\",\"target\":\"$target\"}" "$WEBHOOK_FAILURE_URL" >/dev/null 2>&1 || true
}

run_interval_scheduler() {
  local interval_sec
  interval_sec=$(( BACKUP_INTERVAL_HOURS * 3600 ))
  log_info "Interval scheduler active: every ${BACKUP_INTERVAL_HOURS}h"
  while true; do
    sleep "$interval_sec"
    create_backup || log_err "Scheduled backup (interval) failed"
  done
}

run_cron_scheduler() {
  require_bin crond || true
  if ! command -v crond >/dev/null 2>&1; then
    log_err "crond not available. Falling back to interval mode."
    run_interval_scheduler
    return
  fi
  local cron_expr tmp_cron
  cron_expr="$BACKUP_SCHEDULE_CRON"
  tmp_cron="/etc/crontabs/root"
  echo "$cron_expr /run.sh --oneshot" > "$tmp_cron"
  log_info "Cron scheduler active: '$cron_expr'"
  crond -f -l 8
}

SCHEDULER_PID_FILE="/tmp/scheduler.pid"

start_scheduler() {
  if [[ -f "$SCHEDULER_PID_FILE" ]]; then
    local pid
    pid=$(cat "$SCHEDULER_PID_FILE" 2>/dev/null || true)
    if [[ -n "$pid" ]] && kill -0 "$pid" >/dev/null 2>&1; then
      log_info "Scheduler already running (pid=$pid)"
      return 0
    fi
  fi
  if [[ -n "${BACKUP_SCHEDULE_CRON:-}" ]]; then
    run_cron_scheduler & echo $! > "$SCHEDULER_PID_FILE"
    log_info "Started cron scheduler (pid=$(cat "$SCHEDULER_PID_FILE"))"
  else
    run_interval_scheduler & echo $! > "$SCHEDULER_PID_FILE"
    log_info "Started interval scheduler (pid=$(cat "$SCHEDULER_PID_FILE"))"
  fi
}

stop_scheduler() {
  if [[ -f "$SCHEDULER_PID_FILE" ]]; then
    local pid
    pid=$(cat "$SCHEDULER_PID_FILE" 2>/dev/null || true)
    if [[ -n "$pid" ]] && kill -0 "$pid" >/dev/null 2>&1; then
      kill "$pid" >/dev/null 2>&1 || true
      sleep 1
      if kill -0 "$pid" >/dev/null 2>&1; then kill -9 "$pid" >/dev/null 2>&1 || true; fi
      log_info "Scheduler stopped (pid=$pid)"
    fi
    rm -f "$SCHEDULER_PID_FILE"
  else
    log_info "Scheduler not running"
  fi
}

scheduler_status() {
  if [[ -f "$SCHEDULER_PID_FILE" ]]; then
    local pid
    pid=$(cat "$SCHEDULER_PID_FILE" 2>/dev/null || true)
    if [[ -n "$pid" ]] && kill -0 "$pid" >/dev/null 2>&1; then
      echo "RUNNING $pid"
      return 0
    fi
  fi
  echo "STOPPED"
}
main_loop() {
  if [[ "${RUN_ON_START,,}" == "true" ]]; then
    [[ -n "${HEALTHCHECK_PING_URL:-}" ]] && curl -fsS "${HEALTHCHECK_PING_URL}/start" >/dev/null 2>&1 || true
    create_backup || log_err "Initial backup run failed"
  fi

  # Optional: bestehende lokale Backups beim Start hochladen
  if [[ "${UPLOAD_EXISTING,,}" == "true" ]]; then
    for f in /backup/*.tar; do
      [[ -f "$f" ]] || continue
      log_info "Uploading existing local backup: $f"
      upload_to_s3 "$f" || log_warn "Upload of existing backup failed: $f"
    done
  fi

  # Optional: Watcher für neue HA Backups
  if [[ "${WATCH_HA_BACKUPS,,}" == "true" ]]; then
    if command -v inotifywait >/dev/null 2>&1; then
      log_info "Watching /backup for new backups"
      ( inotifywait -m -e close_write,create --format '%w%f' /backup 2>/dev/null | while read -r path; do
          if [[ "$path" == *.tar ]]; then
            log_info "Detected new backup: $path"
            upload_to_s3 "$path" || log_warn "Auto-upload failed: $path"
          fi
        done ) &
    else
      log_warn "inotifywait not available. Falling back to polling every 60s."
      (
        last_seen=""
        while true; do
          newest=$(ls -1t /backup/*.tar 2>/dev/null | head -n 1 || true)
          if [[ -n "$newest" && "$newest" != "$last_seen" ]]; then
            last_seen="$newest"
            log_info "Detected new backup (poll): $newest"
            upload_to_s3 "$newest" || log_warn "Auto-upload failed: $newest"
          fi
          sleep 60
        done
      ) &
    fi
  fi

  if [[ -n "${BACKUP_SCHEDULE_CRON:-}" ]]; then
    run_cron_scheduler
  else
    run_interval_scheduler
  fi
}

if [[ "${ENABLE_RESTORE_HELPER,,}" == "true" ]]; then
  log_info "Restore helper is active."
fi

restore_from_local_slug() {
  local slug="$1"
  local password_json result
  log_info "Restore from local backup slug: $slug"
  password_json="{}"
  if [[ -n "${RESTORE_PASSWORD:-}" ]]; then
    password_json=$(jq -n --arg password "$RESTORE_PASSWORD" '{password: $password}')
  fi
  if [[ "${RESTORE_INCLUDE_HA:-}" != "" || "${RESTORE_ADDONS:-}" != "" || "${RESTORE_FOLDERS:-}" != "" ]]; then
    # Partielle Wiederherstellung
    local payload
    local include_ha_json addons_json folders_json
    include_ha_json=true
    if [[ -n "${RESTORE_INCLUDE_HA:-}" ]]; then include_ha_json=${RESTORE_INCLUDE_HA}; fi
    addons_json="[]"; folders_json="[]"
    if [[ -n "${RESTORE_ADDONS:-}" ]]; then addons_json=${RESTORE_ADDONS}; fi
    if [[ -n "${RESTORE_FOLDERS:-}" ]]; then folders_json=${RESTORE_FOLDERS}; fi
    payload=$(jq -n \
      --argjson base "$password_json" \
      --argjson homeassistant "$include_ha_json" \
      --argjson addons "$addons_json" \
      --argjson folders "$folders_json" \
      '$base + {homeassistant: $homeassistant, addons: $addons, folders: $folders}')
    result=$(curl -sS -H "Authorization: Bearer $SUPERVISOR_TOKEN" \
                  -H "Content-Type: application/json" \
                  -X POST "$SUPERVISOR_API/backups/$slug/restore/partial" \
                  -d "$payload" || true)
  else
    # Volle Wiederherstellung
    result=$(curl -sS -H "Authorization: Bearer $SUPERVISOR_TOKEN" \
                  -H "Content-Type: application/json" \
                  -X POST "$SUPERVISOR_API/backups/$slug/restore/full" \
                  -d "$password_json" || true)
  fi
  if [[ "$(jq -r '.result // empty' <<<"$result")" == "ok" ]]; then
    log_info "Restore (local) started."
    return 0
  else
    log_err "Restore (local) failed: $(jq -c '.' <<<"$result")"
    return 1
  fi
}

restore_from_s3() {
  local key="$1"
  local tmp_file slug_json slug
  tmp_file="/tmp/restore.tar"
  log_info "Downloading backup from S3: s3://$S3_BUCKET/$key"
  if ! aws s3 cp "s3://$S3_BUCKET/$key" "$tmp_file" $AWS_ENDPOINT_ARG $AWS_REGION_ARG $SSL_ARG >/dev/null 2>&1; then
    log_err "Download from S3 failed"
    return 1
  fi
  log_info "Importing backup into Supervisor"
  slug_json=$(curl -sS -H "Authorization: Bearer $SUPERVISOR_TOKEN" \
                    -F "file=@$tmp_file" \
                    -X POST "$SUPERVISOR_API/backups/new/upload" || true)
  slug=$(jq -r '.data.slug // empty' <<<"$slug_json")
  if [[ -z "$slug" ]]; then
    log_err "Upload to Supervisor failed: $(jq -c '.' <<<"$slug_json")"
    return 1
  fi
  log_info "Starting restore using slug $slug"
  RESTORE_SLUG="$slug" restore_from_local_slug "$slug"
}

log_info "S3 Backup Tool add-on started."
load_overrides
configure_aws_cli
update_aws_runtime

# One-shot Modus, wenn via Cron gestartet
if [[ "${1:-}" == "--oneshot" ]]; then
  create_backup || log_err "One-shot backup failed"
  exit 0
elif [[ "${1:-}" == "--restore" ]]; then
  if [[ -n "${RESTORE_SLUG:-}" ]]; then
    restore_from_local_slug "$RESTORE_SLUG" || exit 1
  elif [[ -n "${RESTORE_FROM_S3_KEY:-}" ]]; then
    restore_from_s3 "$RESTORE_FROM_S3_KEY" || exit 1
  else
    log_err "--restore set, but neither restore_slug nor restore_from_s3_key configured."
    exit 1
  fi
  exit 0
elif [[ "${1:-}" == "--start-scheduler" ]]; then
  start_scheduler
  exit 0
elif [[ "${1:-}" == "--stop-scheduler" ]]; then
  stop_scheduler
  exit 0
elif [[ "${1:-}" == "--scheduler-status" ]]; then
  scheduler_status
  exit 0
fi

# HTTP-UI über Ingress starten
start_http_ui() {
  local port
  # Nicht mehrfach starten
  if pgrep -x lighttpd >/dev/null 2>&1; then
    return
  fi
  
  # SUPERVISOR_TOKEN für CGI-Scripts verfügbar machen
  echo "$SUPERVISOR_TOKEN" > /tmp/supervisor_token
  chmod 600 /tmp/supervisor_token
  
  # Sicherstellen dass CGI-Scripts ausführbar sind
  find /www -name "*.sh" -exec chmod +x {} +
  
  port="$(bashio::addon.ingress_port 2>/dev/null || true)"
  if [[ -z "$port" ]]; then
    port=8099
  fi
  log_info "Starting HTTP UI on port $port"
  mkdir -p /etc/lighttpd
  cat > /etc/lighttpd/lighttpd.conf <<'EOF'
server.modules = ("mod_access", "mod_alias", "mod_cgi", "mod_rewrite")
server.document-root = "/www"
server.port = __PORT__
server.errorlog = "/tmp/lighttpd_error.log"
server.breakagelog = "/tmp/lighttpd_access.log"

mimetype.assign = (
  ".html" => "text/html",
  ".css" => "text/css",
  ".js" => "application/javascript",
  ".json" => "application/json",
  ".png" => "image/png",
  ".svg" => "image/svg+xml"
)

# CGI-Konfiguration
cgi.assign = ( ".sh" => "/bin/sh" )

# CGI-Verzeichnis verfügbar machen
alias.url = ( "/cgi-bin/" => "/www/cgi-bin/" )

# API-Umschreibung mit besserer Syntax
url.rewrite-once = (
  "^/api/list$" => "/cgi-bin/list.sh",
  "^/api/list-s3$" => "/cgi-bin/list-s3.sh",
  "^/api/restore-local$" => "/cgi-bin/restore-local.sh",
  "^/api/restore-s3$" => "/cgi-bin/restore-s3.sh",
  "^/api/set-overrides$" => "/cgi-bin/set-overrides.sh",
  "^/api/get-overrides$" => "/cgi-bin/get-overrides.sh",
    "^/api/debug-log$" => "/cgi-bin/debug-log.sh",
    "^/api/backup-info$" => "/cgi-bin/backup-info.sh"
)

# Standard-Index und Fallback
index-file.names = ( "index.html" )
url.rewrite-if-not-file = ( "^/$" => "/index.html" )
EOF
  sed -i "s|__PORT__|${port}|" /etc/lighttpd/lighttpd.conf
  lighttpd -D -f /etc/lighttpd/lighttpd.conf &
}

start_http_ui

main_loop &
start_scheduler
wait
