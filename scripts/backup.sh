#!/usr/bin/env bash
# Restic backup: pg_dumpall + postgres volume → проектный Minio
# (s3://backups). Host-orchestration: вызывает `docker exec` на postgres
# и backup, без bash/docker зависимостей внутри backup-контейнера
# (restic/restic image — alpine без bash, без docker CLI).
#
# Запуск:
#   bash scripts/backup.sh                  # ad-hoc / smoke / make backup
#   /etc/cron.d/<p>-backup                  # nightly через host cron
#                                           # (ставится stit-onboard ansible role)
set -euo pipefail
cd "$(dirname "$0")/.."

[ -f .env ] || { echo "ERR: .env missing" >&2; exit 1; }
# shellcheck disable=SC1091
. ./.env

# Cache живёт на хосте (.runtime/backup-cache), бинд-маунтится в backup
# container как /cache. Так dump-файл доступен и host-script'у (для записи
# pg_dumpall pipe), и restic внутри контейнера (для чтения при backup).
CACHE_HOST=".runtime/backup-cache"
DUMP_DIR_HOST="$CACHE_HOST/dumps"
mkdir -p "$DUMP_DIR_HOST"

DUMP_NAME="pgdump-$(date -u +%Y%m%dT%H%M%SZ).sql.gz"
DUMP_HOST="$DUMP_DIR_HOST/$DUMP_NAME"
DUMP_INSIDE="/cache/dumps/$DUMP_NAME"

# Init restic repo на первом запуске. snapshots проверяет валидность репо.
docker exec backup restic snapshots >/dev/null 2>&1 || docker exec backup restic init

# pg_dumpall: POSTGRES_USER из postgres env_file, креды здесь не нужны.
docker exec postgres sh -c 'pg_dumpall -U "$POSTGRES_USER"' | gzip > "$DUMP_HOST"

# Restic backup: pg-dump + postgres volume snapshot.
docker exec backup restic backup "$DUMP_INSIDE" /data/postgres \
  --tag auto --tag "$(date -u +%Y-%m-%d)" \
  --host "${PROJECT_NAME:-project}"

# Retention: 7 daily / 4 weekly / 3 monthly.
docker exec backup restic forget --prune \
  --keep-daily 7 --keep-weekly 4 --keep-monthly 3 \
  --tag auto

# Чистим локальный dump-кэш старше суток (restic уже сохранил их в Minio).
find "$DUMP_DIR_HOST" -name 'pgdump-*.sql.gz' -mtime +1 -delete

echo "✓ backup done: $DUMP_NAME"
