---
name: dr-restore
description: Disaster recovery проектной инфры — восстановление сервиса/volume/всего хоста из restic-снапшота (проектный Minio). Каждый destructive шаг требует явного OK. Активируй на "/dr-restore", "восстанови из бэкапа", "вернуть данные", "перезалей volume", "host crashed".
---

# Skill: dr-restore

Восстановление проектной инфры из restic-бэкапа. Главное: **destructive шаги требуют явного OK от пользователя**. Не спеши, спрашивай, верифицируй.

Полный пошаговый runbook — `docs/reference/runbook.md`. Этот skill — interactive-флоу.

## Когда применять

- "Postgres крашнулся, нужно восстановить"
- "Volume X потерян"
- "VPS заменили, нужно вернуть данные"
- "/dr-restore"

## Когда НЕ применять

- Простой restart — `make restart SVC=<x>`.
- Диагностика — сначала `make logs SVC=<svc>`.
- Откат изменений в репо — `git revert`.

## Базовый набор данных

Self-contained backup-контейнер (alpine + restic + pg_dumpall + busybox crond) каждую ночь в 03:00 UTC делает:
- `pg_dumpall -h postgres | gzip | restic backup --stdin --stdin-filename "pgdump-<UTC>.sql.gz"`

Snapshot содержит **один файл** — `/pgdump-<UTC>.sql.gz`, не volume-tree. Это критично: `restic restore --target /data` **не сработает**, восстановление только через `restic dump <id> <filename> | gunzip | psql` (см. `scripts/restore-pg.sh`).

**Volumes (minio-data, app-uploads etc.) НЕ бэкапятся** по дефолту — только postgres. Если нужны volume-снапшоты, расширь `containers/backup/backup-now`.

Restic-репо: значение `RESTIC_REPOSITORY` живёт в `.env` на VPS рядом с `RESTIC_PASSWORD` и `BACKUP_AWS_*`. **Local-default нет by design**: на single-VPS host failure уносит и postgres-data, и репо. Оператор обязан задать external endpoint (managed S3 / bare-IP S3 на другом хосте) и продублировать `RESTIC_PASSWORD` + копию `.env` offsite (password-manager).

Retention в `containers/backup/backup-now`: 7 daily / 4 weekly / 3 monthly.

## Шаги

### 0. Установить контекст (СПРАШИВАЙ юзера)

- Что точно сломано / потеряно?
- На каком хосте восстанавливаем (текущий или новый)?
- Target snapshot — последний (`latest`) или конкретная дата?
- Scope — один volume / postgres / весь хост?

Без чёткого ответа — НЕ начинай.

### 1. Список снапшотов

На VPS (backup-контейнер должен быть up; если стек down — поднять `postgres` + `backup` отдельно через compose up). `restic` живёт внутри backup-контейнера и make-обёртки не имеет — `docker exec backup restic …` legit (make-first debug-исключение).

```bash
docker exec backup restic snapshots --compact
```

Покажи юзеру вывод. Спроси: какой snapshot ID? (или `latest`)

### A. Postgres restore (broken data / wrong migration)

Канон — `scripts/restore-pg.sh`. На VPS из `/opt/<p>-infra/`:

```bash
docker exec backup restic snapshots --compact   # покажи юзеру, спроси какой ID
make restore-pg SNAPSHOT=latest                  # либо SNAPSHOT=<id>
```

**Gate перед запуском.** `make restore-pg` останавливает backend и делает `DROP DATABASE` —
это destructive. Перед вызовом задай `AskUserQuestion` («Запустить restore postgres из
snapshot `<id>`? Это остановит backend и пересоздаст БД `$POSTGRES_DB`») с вариантами
`Запустить` / `Сначала restic check` / `Отмена`. Без явного выбора `Запустить` — не вызывай.

Что скрипт делает (внутри также переспрашивает y/N на каждый destructive):
1. Resolve dump-файла в snapshot'е (`/pgdump-<UTC>.sql.gz`).
2. Stop backend.
3. `DROP DATABASE $POSTGRES_DB`.
4. `restic dump | gunzip | psql -d template1` — pg_dumpall сам CREATE'ит DB + `\connect` + загружает.
5. Start backend.

**Не пиши свой restore руками** — скрипт стандартизирован. Если он не подходит (например, нужен restore в throwaway DB для drill) — см. блок «Quarterly DR drill» в `docs/reference/runbook.md`.

### B. Single table / row recovery

Снапшоты — file-level (pg_dumpall.sql.gz), не PITR. Гранулярность — daily snapshots, не запись. Для одной таблицы (throwaway-контейнер вне compose-стека — make-first исключение):

1. Поднять throwaway postgres: `docker run --rm -d --name pg-tmp -e POSTGRES_PASSWORD=tmp postgres:17.9-alpine`.
2. `restic dump <id> /pgdump-<UTC>.sql.gz | gunzip | docker exec -i pg-tmp psql -U postgres`.
3. `pg_dump pg-tmp -t <table> | psql production` — селективно вернуть таблицу.
4. `docker rm -f pg-tmp`.

### C. Полный host-restore (новый VPS)

**Предусловие:** `RESTIC_REPOSITORY` указывал на **external** endpoint (managed S3 / bare-IP другого хоста) и у оператора есть offsite-копия `.env` (минимум `RESTIC_*` + `BACKUP_AWS_*`). Если был local minio — снапшоты ушли вместе с хостом, restore невозможен.

1. Provision нового VPS.
2. Skill `bootstrap-vps` (ansible-playbook + регистрация deploy-key) — поднимет Docker, склонирует репо.
3. На новом хосте: `make new-env` + восстановить секреты в `.env` из offsite-копии (та же пара `(project, env)`): `RESTIC_*`, `BACKUP_AWS_*`, секции активных профилей.
4. DNS cutover на новый IP. **Gate:** перед перепиской DNS-записи задай `AskUserQuestion`
   («Переключить DNS `<domain>` на новый IP `<new-ip>`? Старый хост перестанет принимать
   трафик») с вариантами `Переключить` / `Подождать прогрев стека` / `Отмена`. Cutover
   до готовности стека на новом хосте уронит прод.
5. `make ship` — стек поднимается на секретах из `.env`.
6. Сценарий A выше — для postgres.
7. Volume'ы (minio-data, app-uploads) — не покрыты backup'ом; восстанавливаются из external source / re-uploads / off-site mirror если настроен.
8. Verify все healthchecks + LE-сертификаты выпустились.

### 3. Verify

После любого restore:
- `make ps` — всё healthy?
- В UI/API данные на месте?
- LE-сертификаты не пере-выпускались впустую (`make logs SVC=traefik`, grep `acme`)?

### 4. Логировать восстановление

В `docs/incidents/YYYY-MM-DD-<short>.md` (создать папку если нет): что сломалось, какой snapshot, длительность, lessons.

## Guard'рейлы

- **Каждый destructive шаг — отдельный `AskUserQuestion`, не plain-чат и не один общий OK на всё.**
  Destructive — это: stop backend, `DROP DATABASE`, остановка стека (`compose stop`/`down`),
  DNS cutover, перезалив volume. Перед каждым — `AskUserQuestion` с явным описанием последствия
  и вариантом `Отмена`. Нет ответа `Запустить`/`Переключить` — шаг не выполняется.
- **Не делай drop database без двойной проверки** что снапшот загружен и читается.
- **Backup creds + repository endpoint** живут в `.env` на VPS (`RESTIC_*`, `BACKUP_AWS_*`). Если хост потерян целиком — восстановление возможно только из offsite-копии `.env`; держи её в password-manager'е оператора актуальной.
- **Restic check** перед критичным restore — `restic check --read-data` (медленно, но валидирует данные).

## Что делать если restic-репо тоже потерян

Local-default `s3:http://minio:9000/backups` отсутствует by design — на single-VPS он не даёт DR. Если в `RESTIC_REPOSITORY` всё-таки local minio и хост умер — снапшоты потеряны вместе с базой. Recovery невозможен.

Для prod — `RESTIC_REPOSITORY` в `.env` должен указывать на external endpoint. От local minio защищает только дисциплина оператора при заполнении `.env`.

См. `docs/reference/runbook.md` → «Полная замена VPS» при сохранившемся репо и «Quarterly DR drill» для регулярной проверки что backup восстанавливается.

## Следующий шаг

- Restore прошёл, healthchecks зелёные → `/smartdev` (вернуться в cockpit) и залогировать инцидент в `docs/incidents/` (шаг 4 выше).
- Restore не сходится (snapshot не читается, `restic check` падает, репо потерян) → `/triage` с собранным выводом `restic snapshots` / логами; разобрать корневую причину, не замазывать.
- Тронул corp-поверхность по ходу DR (новый egress-IP под CrowdSec-whitelist, новый сабдомен) → оператор передаёт данные корп-оператору out-of-band до claim «готово».
