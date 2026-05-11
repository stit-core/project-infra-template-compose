#!/usr/bin/env bash
# Postgres restore из restic-снапшота. Каждый destructive шаг — явный y/N.
# Format снапшотов — pg_dumpall | gzip | restic backup --stdin (см. containers/backup/backup-now).
#
# Usage:
#   bash scripts/restore-pg.sh latest
#   bash scripts/restore-pg.sh <snapshot-id>
#
# Шаги:
#   1. Resolve snapshot → находит /pgdump-<UTC>.sql.gz внутри.
#   2. Подтверждение (drop+recreate $POSTGRES_DB — destructive).
#   3. Stop backend если в стеке.
#   4. Drop target DB.
#   5. restic dump | gunzip | psql -d template1 → pg_dumpall script сам CREATE'ит DB + \connect + загружает данные.
#   6. Start backend.
#
# Запускать на проектном VPS из /opt/<project>-infra/. Требует backup
# контейнер up и .runtime/secrets/postgres.env отрендеренным.
set -euo pipefail
cd "$(dirname "$0")/.."

target="${1:-}"
[ -n "$target" ] || { echo "usage: $0 <snapshot-id|latest>" >&2; exit 2; }

[ -f .env ] || { echo "ERR: .env missing" >&2; exit 1; }
[ -f .runtime/secrets/postgres.env ] || {
  echo "ERR: .runtime/secrets/postgres.env отсутствует — vault-agent не отрендерил?" >&2
  exit 1
}

docker exec backup restic snapshots >/dev/null 2>&1 || {
  echo "ERR: restic недоступен. Проверь: docker ps | grep backup" >&2
  exit 1
}

ok() {
  local prompt="$1"
  read -r -p "$prompt [y/N]: " ans
  [[ "$ans" =~ ^[Yy]$ ]] || { echo "Отменено."; exit 1; }
}

# Resolve dump-файл внутри snapshot. backup-now пишет один файл /pgdump-<UTC>.sql.gz.
echo "→ Resolving dump file in snapshot $target..."
dumpfile=$(docker exec backup restic ls "$target" 2>/dev/null \
           | grep -E '^/pgdump-.*\.sql\.gz$' | head -1 || true)
[ -n "$dumpfile" ] || {
  echo "ERR: в snapshot $target не нашли /pgdump-*.sql.gz" >&2
  echo "     Список снапшотов: docker exec backup restic snapshots" >&2
  exit 1
}
echo "    found: $dumpfile"

# Подтягиваем postgres-креды из rendered secrets.
set -a; . .runtime/secrets/postgres.env; set +a
: "${POSTGRES_USER:?need POSTGRES_USER}"
: "${POSTGRES_DB:?need POSTGRES_DB}"

echo
echo "=== Restore plan ==="
echo "  Snapshot:  $target"
echo "  Dump:      $dumpfile"
echo "  Target DB: $POSTGRES_DB (user: $POSTGRES_USER)"
echo "  Действия:  stop backend → DROP DATABASE $POSTGRES_DB → restore → start backend"
echo
ok "Продолжить?"

# 1. Stop backend (если запущен — может быть не в стеке без COMPOSE_PROFILES).
STARTED_BACKEND=0
if docker ps --format '{{.Names}}' | grep -qx 'backend'; then
  echo "→ Stop backend..."
  docker stop backend >/dev/null
  STARTED_BACKEND=1
fi

# 2. Drop target DB (подключаемся к template1 — всегда есть, не target).
echo "→ Drop database $POSTGRES_DB..."
docker exec postgres psql -U "$POSTGRES_USER" -d template1 \
  -c "DROP DATABASE IF EXISTS \"$POSTGRES_DB\";" >/dev/null

# 3. Restore. pg_dumpall script содержит CREATE DATABASE + \connect + данные.
#    Ошибки на existing roles (если они уже есть в cluster) — non-fatal noise.
echo "→ Restore from $dumpfile (existing-role warnings — ожидаемы)..."
docker exec backup restic dump "$target" "$dumpfile" \
  | gunzip \
  | docker exec -i postgres psql -U "$POSTGRES_USER" -d template1 \
      >/tmp/restore-pg.log 2>&1 || {
  echo "ERR: psql вернул non-zero. Лог: /tmp/restore-pg.log" >&2
  exit 1
}

# 4. Start backend (если был остановлен).
if [ "$STARTED_BACKEND" -eq 1 ]; then
  echo "→ Start backend..."
  docker start backend >/dev/null
fi

echo
echo "✓ Restore done."
echo "  Verify: docker exec postgres psql -U $POSTGRES_USER -d $POSTGRES_DB -c '\\dt'"
echo "  Log:    /tmp/restore-pg.log"
