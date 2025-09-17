# HAOS S3 Backup

Simple S3 backups for Home Assistant (Storj, AWS S3, MinIO, R2).

## Install via Add-on repository
1. In Home Assistant: Settings → Add-ons → Add-on Store → top-right “Repositories”.
2. Add this repository URL.
3. Open “HAOS S3 Backup” in the store, install, configure, start.
4. Optional: enable “Show in sidebar” (Ingress UI).

## Quick start (UI)
1. Open the add-on → “Configuration”.
2. Fill required fields:
   - S3 bucket
   - Access key ID
   - Secret access key
3. Storj: endpoint `https://gateway.storjshare.io`, region `us-east-1`.
4. Optional: prefix (e.g. `homeassistant/`).
5. Scheduling: set interval (hours) or cron.
6. Save → back → Start.
7. Optional: enable “Show in sidebar”.

## Features
- Automatic backups (interval or cron)
- Upload to S3-compatible targets (Storj, AWS, MinIO, R2)
- Partial backups, retention, optional password
- SSE (AES256/KMS), webhooks/healthcheck
- Restore helper (local slug or S3 object)
- Ingress UI (run backup, list, restore)

## Notes
- MinIO: set `force_path_style: true` if needed.
- Boot/watchdog enabled (auto-start with HAOS, auto-restart on failure).

## License & Changelog
- License: MIT © 2025 Simon Hediger (`LICENSE`)
- Changes: see `CHANGELOG.md`
