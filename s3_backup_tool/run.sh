#!/usr/bin/with-contenv bashio

set -u

log_info() { bashio::log.info "$1"; }
log_warn() { bashio::log.warning "$1"; }
log_err() { bashio::log.error "$1"; }

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
  local f="/data/overrides.json"
  if [[ -f "$f" ]]; then
    local ep rg fps bkt pfx ak sk vssl acb
    ep=$(jq -r '.s3_endpoint_url // empty' "$f" 2>/dev/null || true)
    rg=$(jq -r '.s3_region_name // empty' "$f" 2>/dev/null || true)
    fps=$(jq -r '.force_path_style // empty' "$f" 2>/dev/null || true)
    bkt=$(jq -r '.s3_bucket // empty' "$f" 2>/dev/null || true)
    pfx=$(jq -r '.s3_prefix // empty' "$f" 2>/dev/null || true)
    ak=$(jq -r '.access_key_id // empty' "$f" 2>/dev/null || true)
    sk=$(jq -r '.secret_access_key // empty' "$f" 2>/dev/null || true)
    vssl=$(jq -r '.verify_ssl // empty' "$f" 2>/dev/null || true)
    acb=$(jq -r '.auto_create_bucket // empty' "$f" 2>/dev/null || true)
  sse=$(jq -r '.s3_sse // empty' "$f" 2>/dev/null || true)
  kms=$(jq -r '.s3_sse_kms_key_id // empty' "$f" 2>/dev/null || true)
  ev=$(jq -r '.enable_versioning // empty' "$f" 2>/dev/null || true)
    if [[ -n "$ep" ]]; then S3_ENDPOINT_URL="$ep"; fi
    if [[ -n "$rg" ]]; then S3_REGION_NAME="$rg"; fi
    if [[ -n "$fps" ]]; then FORCE_PATH_STYLE="$fps"; fi
    if [[ -n "$bkt" ]]; then S3_BUCKET="$bkt"; fi
    if [[ -n "$pfx" ]]; then S3_PREFIX="$pfx"; fi
    if [[ -n "$ak" ]]; then ACCESS_KEY_ID="$ak"; fi
    if [[ -n "$sk" ]]; then SECRET_ACCESS_KEY="$sk"; fi
    if [[ -n "$vssl" ]]; then VERIFY_SSL="$vssl"; fi
    if [[ -n "$acb" ]]; then AUTO_CREATE_BUCKET="$acb"; fi
  if [[ -n "$sse" ]]; then S3_SSE="$sse"; fi
  if [[ -n "$kms" ]]; then S3_SSE_KMS_KEY_ID="$kms"; fi
  if [[ -n "$ev" ]]; then ENABLE_VERSIONING="$ev"; fi
    log_info "Applied provider overrides from /data/overrides.json"
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
  "^/api/backup$" => "/cgi-bin/backup.sh",
  "^/api/list$" => "/cgi-bin/list.sh",
  "^/api/list-s3$" => "/cgi-bin/list-s3.sh",
  "^/api/restore-local$" => "/cgi-bin/restore-local.sh",
  "^/api/restore-s3$" => "/cgi-bin/restore-s3.sh",
  "^/api/set-overrides$" => "/cgi-bin/set-overrides.sh",
  "^/api/log$" => "/cgi-bin/log.sh",
    "^/api/debug-log$" => "/cgi-bin/debug-log.sh",
    "^/api/backup-info$" => "/cgi-bin/backup-info.sh"
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
  local filename key
  filename=$(basename "$path")
  key="${S3_PREFIX}${filename}"

  ensure_bucket_exists || return 1
  log_info "Uploading to s3://$S3_BUCKET/$key"
  if aws s3 cp "$path" "s3://$S3_BUCKET/$key" $AWS_ENDPOINT_ARG $AWS_REGION_ARG $SSL_ARG "${SSE_ARGS[@]}"; then
    log_info "Upload finished: s3://$S3_BUCKET/$key"
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
    log_err "Upload failed: s3://$S3_BUCKET/$key"
    notify_failure "s3://$S3_BUCKET/$key"
    return 1
  fi
}

ensure_bucket_exists() {
  if aws s3 ls "s3://$S3_BUCKET" $AWS_ENDPOINT_ARG $AWS_REGION_ARG $SSL_ARG >/dev/null 2>&1; then
    # Optional: Versionierung sicherstellen, falls gewünscht
    if [[ "${ENABLE_VERSIONING,,}" == "true" ]]; then
      aws s3api put-bucket-versioning --bucket "$S3_BUCKET" --versioning-configuration Status=Enabled $AWS_ENDPOINT_ARG $AWS_REGION_ARG $SSL_ARG >/dev/null 2>&1 || true
    fi
    return 0
  fi
  if [[ "${AUTO_CREATE_BUCKET,,}" == "true" ]]; then
    log_warn "Bucket not found. Attempting to create: $S3_BUCKET"
    if aws s3 mb "s3://$S3_BUCKET" $AWS_ENDPOINT_ARG $AWS_REGION_ARG $SSL_ARG >/dev/null 2>&1; then
      log_info "Bucket created: $S3_BUCKET"
      if [[ "${ENABLE_VERSIONING,,}" == "true" ]]; then
        aws s3api put-bucket-versioning --bucket "$S3_BUCKET" --versioning-configuration Status=Enabled $AWS_ENDPOINT_ARG $AWS_REGION_ARG $SSL_ARG >/dev/null 2>&1 || true
      fi
      return 0
    fi
  fi
  log_err "Bucket does not exist or could not be created: $S3_BUCKET"
  return 1
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

main_loop() {
  if [[ "${RUN_ON_START,,}" == "true" ]]; then
    [[ -n "${HEALTHCHECK_PING_URL:-}" ]] && curl -fsS "${HEALTHCHECK_PING_URL}/start" >/dev/null 2>&1 || true
    create_backup || log_err "Initial backup run failed"
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
  "^/api/backup$" => "/cgi-bin/backup.sh",
  "^/api/list$" => "/cgi-bin/list.sh",
  "^/api/list-s3$" => "/cgi-bin/list-s3.sh",
  "^/api/restore-local$" => "/cgi-bin/restore-local.sh",
  "^/api/restore-s3$" => "/cgi-bin/restore-s3.sh",
  "^/api/set-overrides$" => "/cgi-bin/set-overrides.sh",
  "^/api/log$" => "/cgi-bin/log.sh",
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

main_loop
