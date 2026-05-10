#!/usr/bin/env bash
# Restic backup: pg_dumpall + volume snapshots → corp Minio (or client S3).
# Mounted into `backup` container at /usr/local/bin/run-backup.sh.
# Triggered by host cron: docker exec backup /usr/local/bin/run-backup.sh
set -euo pipefail

# Init repo on first run.
restic snapshots >/dev/null 2>&1 || restic init

# pg_dumpall via docker exec on postgres (uses POSTGRES_USER from
# its env_file, no creds needed here).
DUMP_DIR=/cache/dumps
mkdir -p "$DUMP_DIR"
DUMP_FILE="$DUMP_DIR/pgdump-$(date -u +%Y%m%dT%H%M%SZ).sql.gz"

docker exec postgres pg_dumpall -U "$(docker exec postgres printenv POSTGRES_USER)" \
  | gzip > "$DUMP_FILE"

# Backup pg dump + volume mount.
restic backup "$DUMP_FILE" /data/postgres \
  --tag "auto" --tag "$(date -u +%Y-%m-%d)" \
  --host "${PROJECT_NAME:-project}"

# Retention: 7 daily, 4 weekly, 3 monthly.
restic forget --prune \
  --keep-daily 7 --keep-weekly 4 --keep-monthly 3 \
  --tag auto

# Trim local dump cache.
find "$DUMP_DIR" -name 'pgdump-*.sql.gz' -mtime +1 -delete
