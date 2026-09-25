# Architecture

Single-VPS docker-compose стек одного проекта (дефолт). Все сервисы — контейнеры на одной машине, сетевая изоляция через docker networks. Опционально Postgres / MinIO / edge разносятся по 3-4 хостам — см. «Multi-host split (opt-in)»; single-host не меняется, пока split не выбран явно.

## Слои

```
                    Internet
                       │
                  ┌────┴─────┐
                  │ Traefik  │ ──── HTTP-01 LE → Let's Encrypt
                  │ +CrowdSec │
                  └────┬─────┘
                       │ proxy network
             ┌─────────┴─────────┐
             │                   │
       ┌─────┴─────┐       ┌─────┴─────┐
       │  Landing  │       │  Backend  │
       │    (D)    │       │  (api.D)  │
       └───────────┘       └─────┬─────┘
                                 │ backend-net
                                 ↓
                           ┌─────────┐
                           │Postgres │
                           └─────────┘
```

Дополнительно:
- **Backup** (restic, in-container crond): сидит сбоку, ежедневно делает `pg_dumpall | gzip | restic backup --stdin` (один файл-снапшот, не volume tree). `RESTIC_REPOSITORY` задаётся в `.env` без local-default'а — чтобы исключить случайный указатель на проектный minio (host failure уносит и postgres-data, и репо).
- **Minio**: S3-storage на `s3.${DOMAIN}` / console `minio.${DOMAIN}`; bucket `app-uploads` для backend, `backups` для restic; service-accounts создаёт `minio-init`.

## Сети

| Network | Тип | Кто в ней |
|---|---|---|
| `proxy` | bridge (наружу через traefik) | Traefik (edge), CrowdSec, landing, backend (входящий HTTPS), minio (S3 + Console), backup (исходящий к внешнему S3) |
| `backend-net` | bridge, **internal** | postgres, backend, minio, minio-init, backup |

Постгрес НЕ в `proxy` — он недоступен извне. Backend стучится в постгрес по hostname `postgres` через `backend-net`.

## Данные и persistence

| Volume | Что | Backup |
|---|---|---|
| `postgres-data` | PG datadir | да — `pg_dumpall` из `containers/backup` |
| `traefik-acme` | LE cert storage | нет (восстанавливается через ACME) |
| `crowdsec-data` / `-config` | bouncer state, ban-lists | опционально (mostly self-rebuilds) |
| `minio-data` | S3-объекты (uploads; в rehearsal — ещё restic-bucket `backups`) | нет (см. ниже) |

Секреты в volume'ах не живут: сервисы получают их через `environment:` (интерполяция из `.env`), rendered-конфиги (`configs/traefik/traefik.yml`) пересобираются render-configs.sh на каждом deploy.

## Внешние зависимости

| Что | Где | Задаётся |
|---|---|---|
| Git-хостинг + container registry | Gitea `git.stit.tech` | `REGISTRY_HOST` в `.env` (дефолт `git.stit.tech`); git-хост — из `project_repo_url` ansible-inventory |
| Restic-репозиторий бэкапа | внешний S3-совместимый endpoint | `RESTIC_REPOSITORY` + `BACKUP_AWS_*` в `.env` |

Образы сервис-репо compose тянет как `${REGISTRY_HOST:-git.stit.tech}/${PROJECT_NAME}/<svc>:${<SVC>_TAG}`; выкатка тега — `make bump SVC= TAG=`.

Backup может писать в любой restic-совместимый endpoint (`RESTIC_REPOSITORY` в `.env`). Local-default отсутствует by design — на single-VPS он не даёт DR, host failure уносит и репо. Рекомендация: external managed S3 / bare-IP S3 на другом хосте. App-uploads bucket (`minio-data`) — **не** покрыт backup'ом; если нужен — настрой `mc mirror` job в external storage отдельно.

Один VPS = одна среда. Подробно — `.claude/rules/multi-env.md`. Карта репо экосистемы, флоу и контракт с сервис-репо — `docs/reference/ecosystem.md`.

## Поток секретов

1. Все секреты и конфиг-значения среды оператор держит в `.env` на VPS (chmod 600, gitignored; контракт с комментариями — `.env.example`, откуда оператор берёт набор переменных профиля и заполняет их сам).
2. На `make deploy`:
   - `scripts/render-configs.sh` рендерит envsubst'ом `configs/**/*.tpl` из `.env` (traefik static с `ACME_*`, middlewares с `CROWDSEC_BOUNCER_API_KEY`, landing).
   - compose интерполирует `${VAR}` из `.env` в `environment:` сервисов при `up`.
3. На rotation секрета: правка значения в `.env` + `make deploy` — compose сравнивает интерполированный конфиг и пересоздаёт затронутые сервисы сам (`environment` фиксируется при container CREATE, поэтому `restart` недостаточно; точечно — `make recreate SVC=`). Bind-mounted конфиги compose не отслеживает — `deploy.sh` рестартует traefik/crowdsec/postgres по git-diff'у `configs/`, смена `ACME_*` без коммита требует `make restart SVC=traefik` руками.

## Deploy-флоу

```
laptop оператора                          VPS
   │                                        │
   │  make ship MSG="..."                    │
   │  ├─ git add -A && git commit -m "..."   │
   │  ├─ make check (красный → стоп)         │
   │  ├─ git push origin main                │
   │  └─ ssh root@vps 'cd /opt/<p>-infra && bash scripts/deploy.sh'
   ↓                                        ↓
                                       scripts/deploy.sh:
                                         git pull --ff-only
                                         render-configs (envsubst .tpl)
                                         compose up -d --wait
                                         (пересоздаёт сервисы с изменённым environment сам)
```

Никаких runner'ов, push-trigger'ов, gitea-CI. Образы сервисов собирает и пушит в registry сервис-репо своим `/release`, затем здесь `make bump SVC=<svc> TAG=<tag>` — правит `<SVC>_TAG` в `.env` на VPS и force-recreate'ит сервис. Image-теги живут строго в `.env` (конвенция `<SVC>_TAG`).

## Cockpit-сводка и серверный смок

`make status` — единая сводка для агента (skill `smartdev`), оркестратор из двух источников:

- **Локально** (`scripts/tools/status.sh`, pure-local — без docker и SSH): git-состояние,
  `== Critical ==` (upstream/deploy-drift), активные планы из `.claude/plans/` (`validate-plan.sh --summary`).
- **Серверный смок** (`== Server ==`): host-витали (load / RAM / swap / disk / OOM) + здоровье
  контейнеров (unhealthy / exited / restart-loop, автодискавери из `docker ps`). Бежит **на хосте** —
  `scripts/tools/smoke-run.sh` гоняет drop-in `scripts/tools/smoke.d/*.sh` по порядку
  (`10-host`, `20-containers`, далее `90-<svc>` под bespoke-сигнал сервиса).

`.env`-sentinel (как у ops-вербов): на VPS (есть `.env`) смок бежит локально; с workstation
(`.env.local`) — через `scripts/tools/ssh.sh smoke`; нет connection / VPS недоступен → `== Server == SKIP`.
Каждый смок-чек read-only и self-`exit 0`; проблема — строкой `ATTENTION:` в колонке 0 (её ловит
smartdev → чейн в `triage`). Смок расширяется добавлением файла в `smoke.d/` — растёт вместе с инфрой
(skill `add-service`).

## Multi-host split (opt-in)

Дефолт — single-host (`HOST_ROLE=all`, весь стек на одном VPS). **Split** — opt-in:
Postgres / MinIO+backup / edge+app на отдельных VPS (несколько серверов на одну
среду). Шаблон даёт **только швы**; cross-host сеть, TLS между хостами,
репликация/HA — **дело потребителя** (граница ниже). Включается без изменения
дефолта.

**Швы:**

- **Эндпоинты бэкендов — в `.env`** (не в compose): Postgres — `PG_HOST`/`PG_PORT`
  (дефолт `postgres:5432` через compose-интерполяцию); restic — `RESTIC_REPOSITORY`.
  При split наводятся на целевые хосты, compose не трогается.
- **Таргетинг compose по ролям** (`HOST_ROLE` в `.env`, карта в `scripts/deploy.sh`):

  | Роль | сервисы | профиль |
  |---|---|---|
  | `all` | весь стек (single-host, дефолт) | как в `.env` |
  | `edge` | traefik, crowdsec, landing, backend | `backend` |
  | `db` | postgres | `postgres` |
  | `storage` | minio, backup | `storage` |

  Project name = имя директории; split-хосты — физически разные VPS, коллизий
  томов нет; каждый держит свой `.env` (identity + секреты сервисов его роли).
- **Per-host backup**: при split backup (роль `storage`) делает `pg_dumpall` к
  Postgres на db-хосте по сети; co-location-проверка `storage⇒postgres` активна
  только при `HOST_ROLE=all`.

Раскладку `host → services` ведёт `/stack-deep-dive` (`§ Networks` → single-host vs
split), фиксирует в `state/stack.md § Host layout`. Полная карта швов —
`.claude/skills/stack-deep-dive/references/multi-host.md`.

**Граница (дело потребителя, не шаблона):** docker service-name DNS работает только
внутри одного хоста — при split backend (edge) ходит в Postgres (db) и MinIO
(storage) по адресам из `.env`, нужна private LAN / wireguard / overlay между VPS;
TLS/шифрование cross-host трафика; репликация / HA / failover; `.env` per-host
раскладывает оператор. Это present-state policy: split-шаблон останавливается
на швах, не навязывая HA-топологию.

## Что НЕ в шаблоне (overlay-services)

Если проекту нужно — добавляешь fragment в `compose/`:

- **NATS** (event bus) — `compose/nats.yml` + добавь в backend-net.
- **Redis** (cache) — `compose/redis.yml` + backend-net.
- **Frontend** (static SPA или SSR) — `compose/frontend.yml` с traefik labels на корневой `${DOMAIN}`.
- **Worker** (отдельный binary) — `compose/worker.yml`, обычно тот же image что backend, но `command: /app/worker`.

Принцип: один файл = один сервис. Makefile собирает `-f` аргументы автоматически.
