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

Self-contained backup-контейнер (alpine + restic + pg_dumpall + busybox crond) каждую ночь делает:
1. `pg_dumpall` через TCP к postgres:5432 → gzip → `restic backup --stdin` с filename `pgdump-<UTC>.sql.gz`.

**Volumes (minio-data, app-uploads etc.) НЕ бэкапятся** по дефолту — только postgres. Если нужны volume-снапшоты, расширь `containers/backup/backup-now`.

Restic-репо: значение `RESTIC_REPOSITORY` из `.env`. Дефолт — `s3:http://minio:9000/backups` (внутренний minio через docker network, без traefik/DNS/TLS — работает сразу на обкатке). Для prod / off-site — `s3:http://<IP>:9000/backups` (внешний bare-IP) или `s3:https://s3.${DOMAIN}/backups` (через traefik, нужен DNS+cert). RESTIC_PASSWORD + backup-SA access/secret — в Vault (`kv/data/projects/<p>/{backup,minio}`), vault-agent рендерит в `.runtime/secrets/backup.env`.

Retention зависит от настроек в `backup.sh` — типично 7 daily / 4 weekly / 3 monthly.

## Шаги

### 0. Установить контекст (СПРАШИВАЙ юзера)

- Что точно сломано / потеряно?
- На каком хосте восстанавливаем (текущий или новый)?
- Target snapshot — последний (`latest`) или конкретная дата?
- Scope — один volume / postgres / весь хост?

Без чёткого ответа — НЕ начинай.

### 1. Список снапшотов

На VPS (backup-контейнер должен быть up; если стек down — поднять `vault-agent` + `postgres` + `backup` отдельно через compose up).

```bash
docker exec backup restic snapshots --compact
```

Покажи юзеру вывод. Спроси: какой snapshot ID? (или `latest`)

### 2. Сценарий: Postgres restore

1. **Остановить consumer'ы** (backend и пр., требует OK):
   ```bash
   docker compose stop backend
   ```

2. **Достать dump из restic** в контейнер postgres напрямую через pipe (`/pgdump-*.sql.gz` — внутри snapshot'а, restic dump пишет в stdout):
   ```bash
   docker exec backup sh -c 'restic dump <SNAPSHOT_ID> /pgdump-<UTC>.sql.gz' \
     > /tmp/pgdump.sql.gz
   # имя файла — точно из restic snapshots --json (или restic ls <id>).
   ```

3. **Drop+recreate database** (требует OK — destructive):
   ```bash
   docker exec postgres psql -U <user> -c "DROP DATABASE <db>; CREATE DATABASE <db>;"
   gunzip -c /tmp/pgdump.sql.gz | docker exec -i postgres psql -U <user> -d <db>
   ```

4. Запустить consumer + verify.

#### C. Полный host-restore (новый VPS)

Высокоуровнево:

1. Provision нового VPS.
2. Запустить skill `bootstrap-vps` (ansible-playbook + регистрация deploy-key) — поднимет Docker, склонирует репо.
3. На новом хосте: `bash scripts/new-env.sh` — заполнить `.env` теми же AppRole creds (они scope'ятся к `project-<p>`, не к хосту).
4. DNS → новый IP (cutover).
5. `make deploy` — поднимет пустые сервисы, vault-agent аутентифицируется и отрендерит секреты.
6. Сценарий "Postgres restore" выше — для базы. Volume'ы (minio-data, app-uploads) **дефолтным бэкапом не покрываются**; данные оттуда восстанавливаются из external source если есть (re-uploads, ETL), либо из off-site mirror'а если настроен.
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

С дефолтом `RESTIC_REPOSITORY=s3:http://minio:9000/backups` backup-репо живёт в **том же VPS**, что и postgres-data. Если хост умрёт целиком — теряется и база, и restic-репо. Это **не off-site DR**, а удобная отправная точка для обкатки.

Для prod — переключи `RESTIC_REPOSITORY` в `.env` на внешний S3 / корп-Minio / другой провайдер: `s3:http://<IP>:9000/backups` или `s3:https://s3.example.com/backups`. Тогда смерть проектного VPS не уносит бэкапы.

См. `docs/runbook.md` → "Полная замена VPS" для процедуры при сохранившемся репо.
