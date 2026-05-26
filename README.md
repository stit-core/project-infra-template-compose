# project-infra-template-compose

IaC шаблон проектной инфры для stit.tech: docker-compose стек одного VPS на проект. Копируется в новый репо `<client-org>/infra`, дорабатывается под клиентский домен и стек, разворачивается за день.

Часть экосистемы из 4 репо: [`stit-infra/infra`](https://git.stit.tech/stit-infra/infra) (corp control plane) ──► **этот** (форкается в `<org>/infra`) ──► [`stit-infra/go-backend-template`](https://git.stit.tech/stit-infra/go-backend-template) (форкается в `<org>/backend`) → [`stit-infra/golibinfra`](https://git.stit.tech/stit-infra/golibinfra). Канон — [`stit-infra/infra/docs/ecosystem.md`](https://git.stit.tech/stit-infra/infra/src/branch/main/docs/ecosystem.md).

## Что внутри

- **Edge:** Traefik v3 + CrowdSec (HTTP-01 LE, WAF, IP-bans).
- **Core:** Postgres 17, backend (image `git.stit.tech/<client-org>/backend`, opt-in), vault-agent (sidecar для secrets).
- **Telemetry:** otel-agent — proxy на корп `otel.stit.tech` (OTLP + Bearer-token из Vault).
- **Storage:** Minio (S3-compat), opt-in под `COMPOSE_PROFILES=storage` — bucket `app-uploads` для backend, `backups` для restic.
- **Backup:** self-contained контейнер (alpine + restic + pg_dumpall + busybox crond), daily в restic-репо. Endpoint + creds приходят из `kv/projects/<p>/<env>/backup` — корп-сторона выбирает (external managed S3 / bare-IP / local-minio rehearsal).
- **Bootstrap:** ansible (apt + swap + journald + ssh-hardening + docker).

См. `docs/reference/architecture.md` для деталей.

## Использовать как шаблон

В Gitea этот репо помечен `template: true`. Старт нового проекта:

1. Открыть https://git.stit.tech/stit-infra/project-infra-template-compose → **Use this template** → создать `<client-org>/infra`.
2. Дальше идти по Day-0 quickstart ниже — шаг 2 уже выполнен (репо создан, история чистая).

Альтернатива через Gitea API:
```bash
curl -X POST -H "Authorization: token $GITEA_TOKEN" -H "Content-Type: application/json" \
  -d '{"owner":"<client-org>","name":"infra","private":true}' \
  https://git.stit.tech/api/v1/repos/generate \
  --url-query 'template_owner=stit' --url-query 'template_repo=project-infra-template-compose'
```

## Day-0 quickstart

Один проект = N сред (dev/prod/...) = N VPS, по одному на ENV. См. `.claude/rules/multi-env.md` для контракта со `stit-infra/infra`.

1. На корп-стороне (`stit-infra/infra`):
   ```bash
   VAULT_TOKEN=<root> bash scripts/onboard-project.sh --name acme --envs dev,prod
   ```
   Создаст per-env AppRole + засеит `kv/projects/acme/<env>/{meta,otel}`. Вернёт по блоку `PROJECT_NAME/ENV/VAULT_ROLE_ID/VAULT_SECRET_ID` для каждого env.

2. Создать клиентский репо `<client-org>/infra` из шаблона. Клонировать локально:
   ```bash
   git clone git@git.stit.tech:<client-org>/infra.git && cd infra
   ```

3. На каждом VPS (по одному на env) — заполнить `.env`:
   ```bash
   PROJECT_NAME=acme ENV=prod DOMAIN=acme.com \
   VAULT_ROLE_ID=<id> VAULT_SECRET_ID=<id> \
   bash scripts/new-env.sh
   ```
   Создаст `.env` (chmod 600) с 5 переменными. Всё остальное (image tags, ACME, restic endpoint, runtime-секреты) — в Vault.

4. Bootstrap чистого VPS:
   ```bash
   ssh-copy-id root@<vps>
   ansible-playbook -i ansible/inventory.ini ansible/bootstrap.yml
   ```

5. На VPS залогиниться в registry (для pull image'ей):
   ```bash
   ssh root@<vps>
   docker login git.stit.tech -u <user> -p <PAT>      # PAT из gitea: Settings → Applications
   ```

6. (Опц., но **сильно рекомендовано** при ручной сборке с dev-машины)
   Whitelist'нуть IP dev-машины в корпном CrowdSec, иначе `docker push`
   триггерит `crowdsecurity/http-probing` бан.

7. Первый деплой — с laptop'а оператора:
   ```bash
   make ship          # check (validate+doctor+plan-check+project-check) + push + (на main) ssh-deploy. На чистом дереве MSG не нужен.
   ```
   `ship` сам гонит `make check` — красный отменяет пуш. Минимальный стек
   (traefik / vault-agent / crowdsec / otel / metrics / landing) поднимается сразу.
   Полный словарь команд — `make help`; вход для агента — cockpit `/smartdev`.

8. По мере дозревания — запрашивать seed'ы (Claude skill `/request-secret`) и активировать profile'ы:
   - `/request-secret` → Claude формирует блок `vault kv put kv/projects/<p>/<env>/<name>` для корп-админа.
   - После seed'а от админа — добавить нужный profile в `COMPOSE_PROFILES` в `.env` и `make ship`.
   - Стандартные имена: `db` / `minio` / `backup` / `oidc` / `jwt`. Project-specific (`stripe-key`, etc.) — что угодно.

См. `docs/getting-started.md` для полного пути (Day-0/Day-1, активация профилей, /init-project).

## Принципы

- **Конфиг → код.** Всё декларативно в `compose/*.yml` и `configs/`. Никаких "только на сервере, в репо нет".
- **Максимум в Vault.** `.env` минимален (identity + AppRole-bootstrap). Image теги, ACME-config, restic endpoint, OTEL token и runtime-секреты — все в `kv/projects/<p>/<env>/*`, ротируются корп-стороной без правок репо.
- **Multi-env через KV-dimension.** Один шаблон, N VPS, у каждого свой `ENV` и свой scope в Vault. AppRole-policy строго `kv/data/projects/<p>/<env>/*`.
- **Lazy stack.** Минимальный стек поднимается на одном meta+otel seed'е. Постгрес/минио/бэкап/бэкенд — за `COMPOSE_PROFILES`, активируются по мере seed'ов.
- **Локальный CI.** Билд/тесты backend-образа гоняются у разработчика; `make ship` пушит код + ssh-деплоит. Никаких gitea-runner'ов / webhook'ов / push-trigger'ов на сервере.

## Контракт с корпом

- `vault.stit.tech` — secrets backend. AppRole per `(project, env)` создаётся `onboard-project.sh --name <p> --envs ...`. См. `.claude/rules/multi-env.md` для KV-layout и onboarding-флоу.
- `otel.stit.tech` — observability ingest. Tenant routing по `service.namespace=<project>-<env>` + Bearer-token из `kv/projects/<p>/<env>/otel`.
- `git.stit.tech` — registry для backend/worker/frontend images.

Restore из backup'а — `make restore-pg SNAPSHOT=latest`, см. `docs/reference/runbook.md`.
