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
- **Backup** (restic, in-container crond): сидит сбоку, ежедневно делает `pg_dumpall | gzip | restic backup --stdin` (один файл-снапшот, не volume tree). `RESTIC_REPOSITORY` приходит только из Vault (`kv/projects/<p>/<env>/backup.repository`), не из `.env` — нет local-default, чтобы исключить случайный указатель на проектный minio (host failure уносит и postgres-data, и репо).
- **Minio**: S3-storage на `s3.${DOMAIN}` / console `minio.${DOMAIN}`; bucket `app-uploads` для backend, `backups` для restic; service-accounts создаёт `minio-init`.
- **cadvisor + node-exporter**: host-/container-метрики, скрейпятся локальным otel-agent'ом и шлются в корп под тем же tenant'ом, что и app-телеметрия (`service.namespace=$OTEL_TENANT`). Видны в корп-Grafana дашбордах cadvisor + Node Exporter Full при выборе `$tenant=<project>`.

## Сети

| Network | Тип | Кто в ней |
|---|---|---|
| `proxy` | bridge, external | Traefik (edge), backend (для входящего HTTPS), vault-agent + otel-agent (исходящий к корпу), backup (исходящий к S3 / корп при off-site) |
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
| `minio-data` | S3-объекты (uploads + backups) | да (restic в bucket `backups`) |
| `otel-agent-data` | OTel collector queue/state | нет |
| `.runtime/secrets/` (bind-mount) | env-files для `env_file:` consumer'ов | нет |

`.runtime/secrets/` — bind-mount, а не named volume, потому что compose должен резолвить `env_file:` пути на хосте при создании контейнера.

## Контракт с корпом

| Корп-сервис | Что | Адрес |
|---|---|---|
| Vault | Secrets backend, AppRole-логин для проекта | `https://vault.stit.tech` |
| OTel ingest | Telemetry (logs/metrics/traces) с tenant routing | `https://otel.stit.tech` |
| Gitea | Source + container registry | `https://git.stit.tech` |

Backup может писать в любой restic-совместимый endpoint (`RESTIC_REPOSITORY` в Vault `kv/projects/<p>/<env>/backup.repository`). Local-default отсутствует by design — на single-VPS он не даёт DR, host failure уносит и репо. Рекомендация: external managed S3 / corp Minio / bare-IP S3 на другом хосте. App-uploads bucket (`minio-data`) — **не** покрыт backup'ом; если нужен — настрой `mc mirror` job в external storage отдельно.

Per-env AppRole + KV-scope (`kv/data/projects/<p>/<env>/*`) выдаёт `stit-infra/infra/scripts/onboard-project.sh --name <p> --envs dev,prod [--source-ip <env>=<ip>]`. Один VPS = одна среда. Подробно — `.claude/rules/multi-env.md`. Общая карта контрактов между 4 репо — `stit-infra/infra/docs/ecosystem.md`.

## Поток секретов

1. Оператор копирует per-env AppRole `role-id/secret-id` в проектный `.env` (вернул `onboard-project.sh --name <p> --envs ...`). Один VPS = один `ENV`, своя пара AppRole creds для `(project, env)`.
2. На `make deploy`: vault-agent стартует первым.
   - entrypoint пишет `role-id`/`secret-id` в `.runtime/secrets-bootstrap/`.
   - `auto_auth` логинится по AppRole, получает Vault token (TTL 10m, max 30m).
   - `scripts/render-configs.sh` собирает финальный `configs/vault-agent/agent.hcl` из `agent.hcl.parts/{head,<active-profile>,tail}.hcl` под активный `COMPOSE_PROFILES`.
   - Always-on templates (рендерятся всегда): `meta.env.tpl` → `.runtime/env/compose.env` (`BACKEND_TAG` для `compose --env-file`), `traefik.yml.tpl` → `.runtime/configs/traefik.yml` (ACME email/caServer из Vault `meta`), `otel.env.tpl` → `.runtime/secrets/otel.env`.
   - Per-profile templates: `postgres.env`, `backend.env`, `minio.env`, `backup.env` — рендерятся только если соответствующий profile активен (через `agent.hcl.parts/<profile>.hcl`).
   - Все templates читают `kv/data/projects/<p>/<env>/{meta,otel,db,oidc,jwt,minio,backup}` (только то, что нужно под profile-набор).
   - Healthcheck = `.runtime/configs/vault-health.sh` (генерится render-configs.sh под активный profile-набор) — проверяет non-empty все expected output-файлы.
3. Consumer-сервисы (postgres / backend / otel-agent / minio / backup) ждут `vault-agent: condition: service_healthy`, потом стартуют и читают `env_file: .runtime/secrets/<svc>.env`.
4. На rotation секрета (например `vault kv patch kv/projects/<p>/<env>/db password=NEW` на корп-стороне):
   - vault-agent на проектном VPS видит изменение, перерендеривает `.runtime/secrets/<svc>.env`.
   - Но `env_file` фиксируется при container CREATE — простой `restart` старый ENV не пересоздаст. Нужен `make recreate SVC=<consumer>`.
   - `scripts/deploy.sh` делает это автоматически когда видит изменения в `configs/vault-agent/templates/*.tpl` / `agent.hcl.parts/` или смену активного profile-набора между prev/new sha. На чистой ротации (без правок в репо) — `make ship` без MSG триггерит передеплой.

## Deploy-флоу

```
laptop оператора                          VPS
   │                                        │
   │  make ship MSG="..."                    │
   │  ├─ git add -A && git commit -m "..."   │
   │  ├─ git push origin main                │
   │  └─ ssh root@vps 'cd /opt/<p>-infra && bash scripts/deploy.sh'
   ↓                                        ↓
                                       scripts/deploy.sh:
                                         git pull --ff-only
                                         render-configs (envsubst .tpl)
                                         compose up -d --wait
                                         (force-recreate consumers если vault-template менялся)
```

Никаких runner'ов, push-trigger'ов, gitea-CI. Backend-images собирает разработчик локально (`docker buildx build … && docker push git.stit.tech/<client-org>/backend:<tag>`), затем `vault kv patch kv/projects/<p>/<env>/meta backend_tag=<tag>` на корп-стороне + `make ship` (без MSG) для force-recreate. `BACKEND_TAG` в `.env` не лежит — приходит из Vault `meta` через `.runtime/env/compose.env`.

## Cockpit-сводка и серверный смок

`make status` — единая сводка для агента (skill `smartdev`), оркестратор из двух источников:

- **Локально** (`scripts/tools/status.sh`, pure-local — без docker и SSH): git-состояние,
  `== Critical ==` (upstream/deploy-drift), `== Infra-touch ==` (тронутая corp-поверхность),
  активный план из `roadmap.md`.
- **Серверный смок** (`== Server ==`): host-витали (load / RAM / swap / disk / OOM) + здоровье
  контейнеров (unhealthy / exited / restart-loop, автодискавери из `docker ps`). Бежит **на хосте** —
  `scripts/tools/smoke-run.sh` гоняет drop-in `scripts/tools/smoke.d/*.sh` по порядку
  (`10-host`, `20-containers`, далее `90-<svc>` под bespoke-сигнал сервиса).

`.env`-sentinel (как у ops-вербов): на VPS (есть `.env`) смок бежит локально; с workstation
(`.env.local`) — через `scripts/tools/ssh.sh smoke`; нет connection / VPS недоступен → `== Server == SKIP`.
Каждый смок-чек read-only и self-`exit 0`; проблема — строкой `ATTENTION:` в колонке 0 (её ловит
smartdev → чейн в `triage`). Смок расширяется добавлением файла в `smoke.d/` — растёт вместе с инфрой
(skill `add-service`).

## Что НЕ в шаблоне (overlay-services)

Если проекту нужно — добавляешь fragment в `compose/`:

- **NATS** (event bus) — `compose/nats.yml` + добавь в backend-net.
- **Redis** (cache) — `compose/redis.yml` + backend-net.
- **Frontend** (static SPA или SSR) — `compose/frontend.yml` с traefik labels на корневой `${DOMAIN}`.
- **Worker** (отдельный binary) — `compose/worker.yml`, обычно тот же image что backend, но `command: /app/worker`.

Принцип: один файл = один сервис. Makefile собирает `-f` аргументы автоматически.
