---
name: dr-restore
description: Disaster recovery проектной инфры — восстановление сервиса/volume/всего хоста из restic-снапшота (проектный Minio). Каждый destructive шаг требует явного OK. Активируй на "/dr-restore", "восстанови из бэкапа", "вернуть данные", "перезалей volume", "host crashed".
---

# Skill: dr-restore

Восстановление проектной инфры из restic-бэкапа. Главное: **destructive шаги требуют явного OK от пользователя**. Не спеши, спрашивай, верифицируй.

Полный пошаговый runbook — `docs/runbook.md`. Этот skill — interactive-флоу.

## Когда применять

- "Postgres крашнулся, нужно восстановить"
- "Volume X потерян"
- "VPS заменили, нужно вернуть данные"
- "/dr-restore"

## Когда НЕ применять

- Простой restart — `make restart SVC=<x>`.
- Диагностика — сначала `docker logs <svc>`.
- Откат изменений в репо — `git revert`.

## Базовый набор данных

`scripts/backup.sh` каждую ночь делает:
1. `pg_dumpall` для `postgres` контейнера → restic stdin с tag `pg_dump=<container>`.
2. `tar` всех `<project>_*` named volumes → restic stdin с tag `volume=<volname>`.

Restic-репо: `s3:https://s3.${DOMAIN}/backups` — bucket в **проектном** minio, через traefik (тот же endpoint, что использует stit-админ извне). RESTIC_PASSWORD + backup-SA access/secret — в Vault (`kv/data/projects/<p>/{backup,minio}`), vault-agent рендерит в `.runtime/secrets/backup.env`.

Retention зависит от настроек в `backup.sh` — типично 7 daily / 4 weekly / 3 monthly.

## Шаги

### 0. Установить контекст (СПРАШИВАЙ юзера)

- Что точно сломано / потеряно?
- На каком хосте восстанавливаем (текущий или новый)?
- Target snapshot — последний (`latest`) или конкретная дата?
- Scope — один volume / postgres / весь хост?

Без чёткого ответа — НЕ начинай.

### 1. Список снапшотов

На VPS:

```bash
cd /opt/<project>-infra && set -a && . .runtime/secrets/backup.env && set +a && \
  docker run --rm \
    -e RESTIC_REPOSITORY -e RESTIC_PASSWORD \
    -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY \
    --network proxy \
    restic/restic:0.18.1 snapshots --compact
```

Покажи юзеру вывод. Спроси: какой snapshot ID? (или `latest`)

### 2. Сценарии

#### A. Один named volume

1. **Остановить consumer-сервис** (требует OK):
   ```bash
   docker compose -f docker-compose.yml -f compose/<svc>.yml stop <svc>
   ```

2. **Очистить volume** (требует OK — destructive):
   ```bash
   docker run --rm -v <project>_<volume>:/data alpine:3.20 \
     sh -c "rm -rf /data/* /data/.[!.]* /data/..?* 2>/dev/null || true"
   ```

3. **Restore из restic** (idempotent; env из `.runtime/secrets/backup.env` уже в shell):
   ```bash
   docker run --rm \
     -e RESTIC_REPOSITORY -e RESTIC_PASSWORD \
     -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY \
     --network proxy \
     restic/restic:0.18.1 dump <SNAPSHOT_ID> /<volume>.tar | \
   docker run --rm -i -v <project>_<volume>:/restore alpine:3.20 tar -C /restore -xf -
   ```

   Подробности — `docs/runbook.md`.

4. **Запустить сервис**: `make deploy`.

5. **Verify** — healthcheck, данные на месте через UI / логи.

#### B. Postgres

1. **Остановить consumer'ы** (backend и пр., требует OK):
   ```bash
   docker compose stop backend
   ```

2. **Dump из restic** (НЕ запускай restore прямо в running postgres):
   ```bash
   docker run --rm -e RESTIC_REPOSITORY -e RESTIC_PASSWORD \
     -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY --network proxy \
     restic/restic:0.18.1 dump <SNAPSHOT_ID> /postgres.sql > /tmp/postgres.sql
   ```

3. **Drop+recreate database** (требует OK — destructive):
   ```bash
   docker exec postgres psql -U <user> -c "DROP DATABASE <db>; CREATE DATABASE <db>;"
   docker exec -i postgres psql -U <user> -d <db> < /tmp/postgres.sql
   ```

4. Запустить consumer + verify.

#### C. Полный host-restore (новый VPS)

Высокоуровнево:

1. Provision нового VPS.
2. Запустить skill `bootstrap-vps` (ansible-playbook + регистрация deploy-key) — поднимет Docker, склонирует репо.
3. На новом хосте: `bash scripts/new-env.sh` — заполнить `.env` теми же AppRole creds (они scope'ятся к `project-<p>`, не к хосту).
4. DNS → новый IP (cutover).
5. `make deploy` — поднимет пустые сервисы, vault-agent аутентифицируется и отрендерит секреты.
6. Сценарий B для postgres + сценарий A для каждого critical volume.
7. Verify все healthchecks + LE-сертификаты выпустились (HTTP-01).

### 3. Verify

После любого restore:
- `make ps` — всё healthy?
- В UI/API данные на месте?
- LE-сертификаты не пере-выпускались впустую (проверь `docker logs traefik | grep acme`)?

### 4. Логировать восстановление

В `docs/incidents/YYYY-MM-DD-<short>.md` (создать папку если нет): что сломалось, какой snapshot, длительность, lessons.

## Guard'рейлы

- **Каждый destructive шаг — явный OK у пользователя.** Не один общий OK на всё.
- **Не делай drop database без двойной проверки** что снапшот загружен и читается.
- **Backup creds** живут в Vault (`kv/data/projects/<p>/{backup,minio}`), vault-agent рендерит в `.runtime/secrets/backup.env`. Если хост потерян целиком — пересоздаёшь .env с теми же AppRole, vault-agent рендерит секреты автоматически.
- **Restic check** перед критичным restore — `restic check --read-data` (медленно, но валидирует данные).

## Что делать если restic-репо тоже потерян

Backup-репо живёт в **проектном** Minio (тот же бакет в той же VPS, что данные). Если minio-data накроется — теряется и postgres-snapshot, и restic-repo. На проектной стороне off-site защиту шаблон НЕ обеспечивает — настрой `mc mirror backups → corp-S3` отдельным host-cron'ом если нужно. См. `docs/runbook.md` → "Полная замена VPS" для процедуры при сохранившемся репо.
