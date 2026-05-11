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
- **Network unreachable** — `dial tcp: lookup vault.stit.tech: no such host`. Проверь DNS на VPS, проверь outbound-доступ к корпу.
- **Path не существует в KV** — `* permission denied` на `kv/data/projects/<p>/db`. Значит `onboard-project.sh` не отработал до конца или KV-stub'ы кто-то удалил. Перезапусти `seed-project-secrets.sh` или ручной `vault kv put`.

**Recovery:** после исправления — `make restart SVC=vault-agent`, дальше healthcheck подтянется и зависимые сервисы стартуют сами.

## Backend в restart-loop

```bash
docker logs backend --tail=100
```

- **PG_DSN ошибка:** проверь `.runtime/secrets/backend.env` (под root: `cat /opt/<p>-infra/.runtime/secrets/backend.env`). Если `password` там пустой — vault не отдал поле; `vault kv get kv/projects/<p>/db` покажет что в Vault.
- **OTLP timeout:** некритично, backend должен запускаться даже без otel-agent (Init не падает на network ошибках). Если падает — баг в backend, поднимай issue в `<org>/backend`.
- **Migration failed:** `make exec SVC=backend ... migrate up` (если backend не делает auto-migrate на старте). Залогируй какую миграцию.

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

## Postgres dead / volume corrupted

```bash
docker logs postgres --tail=100
```

Если PG не стартует и в логах `database files are incompatible with server` или `corruption detected`:

1. **Останови всё:**
   ```bash
   docker compose -f docker-compose.yml -f compose/postgres.yml stop postgres
   ```
2. **Если есть recent restic snapshot** — восстанови volume (env из `.runtime/secrets/backup.env`):
   ```bash
   set -a; . .runtime/secrets/backup.env; set +a
   docker run --rm -v <project>_postgres-data:/data \
     -e RESTIC_REPOSITORY -e RESTIC_PASSWORD \
     -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY \
     --network proxy \
     restic/restic:0.18.1 restore latest --target /data --include /data/postgres
   ```
3. **Если только pg_dump есть (не raw):**
   ```bash
   # pg сначала надо запустить чистым
   docker volume rm postgres-data   # !!! только если volume точно потерян
   docker compose ... up -d postgres
   docker exec -i postgres psql -U $POSTGRES_USER < /path/to/pgdump.sql
   ```

## Restic backup не идёт

```bash
docker exec backup restic snapshots
docker exec backup restic check
```

- **`Fatal: unable to open repo`**: `RESTIC_PASSWORD` / minio creds ротированы. Меняются в Vault (`kv/data/projects/<p>/{backup,minio}`), vault-agent перерендерит `.runtime/secrets/backup.env`, после — `docker compose ... up -d --no-deps --force-recreate backup` (env_file подхватывается только при CREATE, не restart).
- **Cron не триггерит**: `crontab -l | grep backup`. Должно быть что-то типа `0 3 * * * docker exec backup /usr/local/bin/run-backup.sh >> /var/log/backup.log 2>&1`. Добавь если нет.
- **Disk full на VPS**: `df -h`. `backup-cache` volume может разрастись — `docker exec backup restic cache --cleanup`.

## Gitea-runner offline

**Симптом:** push в main не триггерит staging deploy, в Gitea admin → Runners видно «offline».

```bash
docker logs gitea-runner --tail=50
```

- **Token expired / unregistered:** удали `runner-data` volume и зарегистрируй заново:
  ```bash
  docker compose ... stop gitea-runner
  docker volume rm runner-data
  # получи новый REG_TOKEN из Gitea admin
  echo "GITEA_RUNNER_REG_TOKEN=<new>" >> .env
  make deploy
  ```
- **Network issue:** runner не может достучаться до `git.stit.tech`. Outbound-firewall? DNS?

## Rollback после плохого деплоя

Backend rollback (image tag):

```bash
$EDITOR .env   # BACKEND_TAG=v0.1.0  (предыдущая стабильная)
make deploy
```

Infra rollback (compose/configs):

```bash
git log --oneline -10
git revert <bad-sha>
git push origin main
make deploy   # или подожди пока gitea-runner подхватит push
```

## Полная замена VPS

1. Заказать новый VPS, обновить A-record `api.<DOMAIN>` на новый IP (TTL заранее снизить).
2. `ansible-playbook -i inventory.ini bootstrap.yml` (с обновлённым `ansible_host`).
3. На новом VPS: `bash scripts/new-env.sh` (используй те же AppRole creds — они привязаны к проекту, не к VPS).
4. `make deploy` → стек поднимается, vault-agent логинится, постгрес — пустой.
5. Restore из restic (env приходит из `.runtime/secrets/backup.env`, рендерится после первого `make deploy`):
   ```bash
   set -a; . .runtime/secrets/backup.env; set +a
   docker run --rm -v <project>_postgres-data:/data \
     -e RESTIC_REPOSITORY -e RESTIC_PASSWORD \
     -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY \
     --network proxy \
     restic/restic:0.18.1 restore latest --target /data
   ```
6. Сверь IP в Authentik (если OIDC redirect-uri привязан) и в любых внешних webhook'ах.

## Когда эскалировать на корп

- Vault sealed.
- otel.stit.tech не принимает данные (tenant 401).
- git.stit.tech registry pull fails.

Эскалация в `#corp-infra` Slack или ntfy.stit.tech.
