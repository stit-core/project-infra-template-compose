#!/usr/bin/env bash
# Restic backup: pg_dumpall + volume snapshots → corp Minio (или client S3).
# Бинд-маунтится в `backup` container как /usr/local/bin/run-backup.sh.
# Триггер — host cron: docker exec backup /usr/local/bin/run-backup.sh
set -euo pipefail

# Init репо при первом запуске.
restic snapshots >/dev/null 2>&1 || restic init

# pg_dumpall через docker exec — POSTGRES_USER берётся из его env_file,
# креды здесь не нужны.
DUMP_DIR=/cache/dumps
mkdir -p "$DUMP_DIR"
DUMP_FILE="$DUMP_DIR/pgdump-$(date -u +%Y%m%dT%H%M%SZ).sql.gz"

docker exec postgres pg_dumpall -U "$(docker exec postgres printenv POSTGRES_USER)" \
  | gzip > "$DUMP_FILE"

# Backup: pg-dump + volume.
restic backup "$DUMP_FILE" /data/postgres \
  --tag "auto" --tag "$(date -u +%Y-%m-%d)" \
  --host "${PROJECT_NAME:-project}"

# Retention: 7 daily / 4 weekly / 3 monthly.
restic forget --prune \
  --keep-daily 7 --keep-weekly 4 --keep-monthly 3 \
  --tag auto

# Чистим локальный dump-кэш.
find "$DUMP_DIR" -name 'pgdump-*.sql.gz' -mtime +1 -delete
