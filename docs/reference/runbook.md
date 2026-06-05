# Runbook

Common failure modes на проектном VPS и что делать. Ordered by likelihood.

## vault-agent unhealthy / `.ready` отсутствует

**Симптом:** backend, postgres, otel-agent в статусе `created` или `restarting`, depends_on на vault-agent.

```bash
docker logs vault-agent --tail=50
```

Возможные причины:
- **AppRole creds невалидны** — `Code: 400. Errors: invalid role or secret ID`. Проверь в `.env` что `VAULT_ROLE_ID`/`VAULT_SECRET_ID` совпадают с тем что вернул `onboard-project.sh`. Если оператор крутил `secret-id` — нужно обновить в `.env` + перезапустить vault-agent.
- **Vault корп-стороны sealed** — `* error performing token check: vault is sealed`. Ничего не починишь с проектной стороны. Эскалировать на корп: оператор делает `vault operator unseal <key>`.
- **Network unreachable** — `dial tcp: lookup vault.sftbmb.ru: no such host`. Проверь DNS на VPS, проверь outbound-доступ к корпу.
- **Path не существует в KV** — `* permission denied` на `kv/data/projects/<p>/<env>/<name>`. Значит корп-сторона не засеяла этот KV-объект (онбординг создаёт только `meta` + `otel`; `db` / `oidc` / `jwt` / `minio` / `backup` запрашиваются по мере включения profile'ов). Запроси seed через skill `/request-secret` — он сформирует `vault kv put` блок для корп-админа.

**Recovery:** после исправления — `make restart SVC=vault-agent`, дальше healthcheck подтянется и зависимые сервисы стартуют сами.

## Backend в restart-loop

```bash
docker logs backend --tail=100
```

- **PG_DSN ошибка:** проверь `.runtime/secrets/backend.env` (под root: `cat /opt/<p>-infra/.runtime/secrets/backend.env`). Если `password` там пустой — vault не отдал поле; `vault kv get kv/projects/<p>/<env>/db` покажет что в Vault.
- **OTLP timeout:** некритично, backend должен запускаться даже без otel-agent (Init не падает на network ошибках). Если падает — баг в backend, поднимай issue в `<org>/backend`.

## Traefik не выдаёт LE-cert

**Симптом:** `curl https://api.<DOMAIN>` отдаёт SELF_SIGNED или TIMEOUT, в логах traefik — `unable to obtain ACME certificate`.

```bash
docker logs traefik --tail=200 | grep -i 'acme\|challenge'
```

Чек-лист:
- A-record на `api.<DOMAIN>` указывает на IP VPS? `dig +short api.<DOMAIN>`.
- Порт 80 открыт извне? HTTP-01 challenge ходит на `:80/.well-known/acme-challenge/...`.
- Rate limit LE: 50 cert/week per registered domain. Если хитанули — ждать неделю или использовать staging endpoint (отдельный `caServer` в traefik.yml).
- `/letsencrypt/acme.json` существует и `chmod 0600`? Иногда после восстановления volume'а права слетают.

## Postgres dead / data lost / wrong migration

Backup-формат — `pg_dumpall | gzip | restic backup --stdin` (один файл `pgdump-<UTC>.sql.gz` внутри snapshot'а, не tree).

**Не делай `restic restore --target /data`** — снапшоты не содержат volume-структуру, restore не вернёт раздел `postgres-data`. Только через `restic dump <id> <filename> | gunzip | psql`.

Канон — helper-скрипт. На VPS из `/opt/<p>-infra/`:

```bash
docker exec backup restic snapshots --compact        # выбрать ID или latest
make restore-pg SNAPSHOT=latest                       # либо SNAPSHOT=<id>
```

Что делает (см. `scripts/restore-pg.sh`):
1. Resolve dump-файла внутри snapshot'а (`/pgdump-<UTC>.sql.gz`).
2. Печатает план и спрашивает `y/N`.
3. Stop backend (если в стеке).
4. `DROP DATABASE $POSTGRES_DB`.
5. `restic dump | gunzip | psql -d template1` — pg_dumpall script сам CREATE'ит DB + `\connect` + загружает данные.
6. Start backend.

Если postgres сам не стартует (corrupted volume, incompatible server version):

```bash
docker logs postgres --tail=100
# Если действительно volume corrupted и есть свежий snapshot:
docker compose <args> stop postgres
docker volume rm <project>_postgres-data    # !!! только когда volume точно потерян
docker compose <args> up -d postgres        # стартует чистый
make restore-pg SNAPSHOT=latest             # подтягивает данные из snapshot'а
```

## Restic backup не идёт

```bash
docker exec backup restic snapshots
docker exec backup restic check
```

- **`Fatal: unable to open repo`**: `RESTIC_PASSWORD` / minio creds / `repository` endpoint ротированы. Меняются в Vault (`kv/data/projects/<p>/<env>/{backup,minio}`), vault-agent перерендерит `.runtime/secrets/backup.env`, после — `make recreate SVC=backup` (env_file подхватывается только при CREATE, не restart) или `make ship` без MSG (deploy.sh сам детектит template-change).
- **Cron не триггерит**: cron внутри контейнера, не на хосте. Проверь `docker exec backup pgrep crond` и `docker logs backup --tail 20`. Если crond упал — `make restart SVC=backup`. Расписание — `containers/backup/crontab`, rebuild при изменении.
- **Disk full на VPS**: `df -h`. Restic-cache в `/root/.cache/restic` внутри backup-контейнера может расти — `docker exec backup restic cache --cleanup`.

## Rollback после плохого деплоя

Backend rollback (image tag):

```bash
# На корп-стороне (vault.sftbmb.ru):
vault kv patch kv/projects/<p>/<env>/meta backend_tag=v0.1.0
# На проектной (laptop / VPS):
make ship   # без MSG, deploy.sh детектит template-change и force-recreate'нёт backend
```

`BACKEND_TAG` приходит из Vault `meta`, не из `.env`. Vault-agent перерендеривает `.runtime/env/compose.env`, compose читает его через `--env-file` (см. Makefile).

Infra rollback (compose/configs):

```bash
git log --oneline -10
git revert <bad-sha>
make ship
```

## Полная замена VPS

**Предусловие:** значение `repository` в `kv/projects/<p>/<env>/backup` указывает на **внешний** S3 (не на проектный minio — он умер вместе с хостом). Если в Vault стояло local minio — снапшоты уже потеряны вместе с host'ом, restore невозможен.

1. Заказать новый VPS, обновить A-record `${DOMAIN}` и сабдомены на новый IP (TTL заранее снизить).
2. `ansible-playbook -i inventory.ini bootstrap.yml` (с обновлённым `ansible_host`). Зарегистрировать deploy-key.
3. На новом VPS: `make new-env` (используй те же per-env AppRole creds — они привязаны к паре `(project, env)`, не к VPS). `RESTIC_REPOSITORY` рендерится из Vault, вводить не нужно.
4. `make ship` (или на VPS `make deploy`) → стек поднимается, vault-agent логинится, postgres стартует пустой.
5. Restore postgres из restic:
   ```bash
   docker exec backup restic snapshots --compact   # выбрать snapshot
   make restore-pg SNAPSHOT=latest
   ```
6. Сверь IP в Authentik (если OIDC redirect-uri привязан) и в любых внешних webhook'ах.
7. App-uploads (minio-data) — не покрыто backup'ом. Если есть external mirror (`mc mirror` job в корп) — оттуда; если нет — данные потеряны.

## Quarterly DR drill

Backup, который ни разу не тестировался, не работает. Раз в квартал:

1. Поднять throwaway-инстанс postgres локально (или на staging VPS): `docker run --rm -d --name pg-drill -e POSTGRES_PASSWORD=drill postgres:17.9-alpine`.
2. Снять последний dump из restic в файл:
   ```bash
   docker exec backup restic ls latest                              # имя файла
   docker exec backup restic dump latest /pgdump-<UTC>.sql.gz \
     | gunzip > /tmp/drill.sql
   ```
3. Загрузить в throwaway: `docker exec -i pg-drill psql -U postgres < /tmp/drill.sql`.
4. Sanity-checks: `\dt` показывает таблицы, `SELECT count(*) FROM <main_table>` адекватен.
5. Записать результат + дату в `docs/incidents/YYYY-MM-DD-dr-drill.md` (создать папку если нет).
6. `docker rm -f pg-drill` + `rm /tmp/drill.sql`.

Если хотя бы один шаг сломался — это инцидент сам по себе. Чини backup-флоу до следующего prod-инцидента.

## Когда эскалировать на корп

- Vault sealed.
- otel.sftbmb.ru не принимает данные (tenant 401).
- git.sftbmb.ru registry pull fails.

Эскалация в `#corp-infra` Slack или ntfy.sftbmb.ru.
