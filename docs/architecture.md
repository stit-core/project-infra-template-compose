# Architecture

Single-VPS docker-compose стек одного проекта. Все сервисы — контейнеры на одной машине, сетевая изоляция через docker networks.

## Слои

```
                         Internet
                            │
                       ┌────┴────┐
                       │ Traefik │ ──── HTTP-01 LE → Let's Encrypt
                       │  +CrowdSec │
                       └────┬────┘
                            │ proxy network
        ┌───────────────────┼───────────────┐
        │                   │               │
  ┌─────┴─────┐      ┌──────┴──────┐  ┌─────┴──────┐
  │  Backend  │      │  otel-agent │  │   Vault-   │
  │ (api.D)   │      │ OTLP+scrape │  │   Agent    │
  └─────┬─────┘      └──────┬──────┘  └─────┬──────┘
        │                   │ ↑             │
        │ backend-net       │ │ scrape      │ outbound
        ↓                   ↓ │             ↓
  ┌─────────┐       ┌────────┴────────┐ vault.stit.tech
  │Postgres │       │ cadvisor +      │ (corp Vault)
  └─────────┘       │ node-exporter   │
                    └─────────────────┘
                            ↓
                     otel.stit.tech (corp ingest)
```

Дополнительно:
- **Backup** (restic, профиль `backup`): сидит сбоку, по cron делает `pg_dumpall` + restic backup; пишет в локальный Minio (`s3.${DOMAIN}/backups`).
- **Minio** (профиль `minio`): S3-storage на `s3.${DOMAIN}` / console `minio.${DOMAIN}`; bucket `app-uploads` для backend, `backups` для restic; service-accounts создаёт `minio-init`.
- **Gitea-runner**: pull-based CI, исполняет workflows из `<org>/backend` и `<org>/infra`.
- **cadvisor + node-exporter**: host-/container-метрики, скрейпятся локальным otel-agent'ом и шлются в корп под тем же tenant'ом, что и app-телеметрия (`service.namespace=$OTEL_TENANT`). Видны в корп-Grafana дашбордах cadvisor + Node Exporter Full при выборе `$tenant=<project>`.

## Сети

| Network | Тип | Кто в ней |
|---|---|---|
| `proxy` | bridge, external | Traefik (edge), backend (для входящего HTTPS), vault-agent + otel-agent (исходящий к корпу), backup + runner (исходящий к S3 / Gitea) |
| `backend-net` | bridge, **internal** | postgres, backend, otel-agent (получает OTLP от backend, скрейпит cadvisor + node-exporter), cadvisor, node-exporter, vault-agent (рендерит файлы в shared volume) |

Постгрес НЕ в `proxy` — он недоступен извне. Backend стучится в постгрес по hostname `postgres` через `backend-net`.

## Данные и persistence

| Volume | Что | Backup |
|---|---|---|
| `postgres-data` | PG datadir | да — `pg_dumpall` из `containers/backup` |
| `traefik-acme` | LE cert storage | нет (восстанавливается через ACME) |
| `crowdsec-data` / `-config` | bouncer state, ban-lists | опционально (mostly self-rebuilds) |
| `vault-agent-secrets` | rendered env-files | нет (рендерится из Vault) |
| `vault-agent-bootstrap` | role-id/secret-id files | нет (из .env) |
| `runner-data` | gitea-runner registration creds | нет (re-register если потерять) |
| `.runtime/secrets/` (bind-mount) | env-files для `env_file:` consumer'ов | нет |

`.runtime/secrets/` — bind-mount, а не named volume, потому что compose должен резолвить `env_file:` пути на хосте при создании контейнера.

## Контракт с корпом

| Корп-сервис | Что | Адрес |
|---|---|---|
| Vault | Secrets backend, AppRole-логин для проекта | `https://vault.stit.tech` |
| OTel ingest | Telemetry (logs/metrics/traces) с tenant routing | `https://otel.stit.tech` |
| Gitea | Source + container registry | `https://git.stit.tech` |

Backup пишет в **проектный** Minio (`s3.${DOMAIN}/backups`), не в корп S3 — проектная сторона autonomous по storage. Для off-site защиты — настрой mirror в корп Minio отдельно (`mc mirror` job).

Vault AppRole + observability tenant выдаёт `stit/infra/scripts/onboard-project.sh <project>`. См. `stit/infra/docs/project-secrets.md`.

## Поток секретов

1. Оператор копирует AppRole `role-id/secret-id` в проектный `.env` (после `onboard-project.sh`).
2. На `make deploy`: vault-agent стартует первым.
   - entrypoint пишет `role-id`/`secret-id` в `.runtime/secrets-bootstrap/`.
   - `auto_auth` логинится по AppRole, получает Vault token (TTL 10m, max 30m).
   - templates читают `kv/projects/<p>/{db,oidc,jwt}` + `kv/observability/tenants/<p>`, рендерят `backend.env` и `postgres.env` в `.runtime/secrets/`.
   - Опциональные templates (`minio.env`, `backup.env`) — закомментированы в `agent.hcl.tpl` по умолчанию, раскомментируются после seed'а соответствующих Vault-путей.
   - Healthcheck = backend.env + postgres.env непустые.
3. Postgres + backend + otel-agent ждут `vault-agent: condition: service_healthy`, потом стартуют и читают `env_file: .runtime/secrets/<svc>.env`.
4. На rotation секрета (например `vault kv patch kv/projects/<p>/db password=NEW`):
   - vault-agent видит изменение, перерендеривает `.env`-файлы.
   - В V1 — `make deploy` рестартит зависимые контейнеры (через `restart-on-config-change` логику).
   - В V2 (TBD) — `command` в template-блоке делает `docker restart` автоматически.

## Pull-based deploy

```
<org>/backend             <org>/infra (этот шаблон, скопированный)
   │                          │
   │ tag v*                   │ push main
   ↓                          ↓
git.stit.tech CI         gitea-runner (на VPS, label <project>-prod/<staging>)
   │                          │
   │ build + push image       │ ssh не нужен — runner ЛОКАЛЬНО:
   ↓                          │   git pull && make deploy
git.stit.tech registry        │
                              ↓
                          docker compose up --pull always
                              ↓
                          backend container с новым image:<tag>
```

Деплой инициируется push'ем в backend repo: tag → corp CI билдит → проектный runner подхватывает (label `<project>-prod`) и делает `make deploy`. Никаких SSH ключей в CI-secrets, никакого push'а на VPS извне.

## Что НЕ в шаблоне (overlay-services)

Если проекту нужно — добавляешь fragment в `compose/`:

- **NATS** (event bus) — `compose/nats.yml` + добавь в backend-net.
- **Redis** (cache) — `compose/redis.yml` + backend-net.
- **Frontend** (static SPA или SSR) — `compose/frontend.yml` с traefik labels на корневой `${DOMAIN}`.
- **Worker** (отдельный binary) — `compose/worker.yml`, обычно тот же image что backend, но `command: /app/worker`.

Принцип: один файл = один сервис. Makefile собирает `-f` аргументы автоматически.
