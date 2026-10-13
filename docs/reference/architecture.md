# Architecture

Single-VPS docker-compose стек одного проекта (дефолт). Все сервисы — контейнеры на одной машине, сетевая изоляция через docker networks. Опционально Postgres / MinIO / edge разносятся по 3-4 хостам — см. «Multi-host split (opt-in)»; single-host не меняется, пока split не выбран явно.

## Слои

```
                    Internet
                       │
                  ┌────┴─────┐
                  │ Traefik  │ ──── HTTP-01 LE → Let's Encrypt
                  │+CrowdSec │ ──── журнал доступа /var/log/traefik
                  └────┬─────┘
                       │ proxy network
             ┌─────────┴─────────┐
             │                   │
       ┌─────┴─────┐       ┌─────┴─────┐
       │   Site    │       │  Backend  │
       │ (D, www.D)│       │  (api.D)  │
       └───────────┘       └─────┬─────┘
                                 │ backend-net
                                 ↓
                           ┌─────────┐
                           │Postgres │
                           └─────────┘
```

Дополнительно:
- **Site** (`compose/site.yml`, профиль `site`): корень `${DOMAIN}`; `www.${DOMAIN}` — 301 на корень роутером,
  который не проксирует (`noop@internal`); форма `POST /api/contact` — свой роутер с лимитами частоты и тела;
  `/_image` — 403 на edge. Пока сайта нет, корень держит заглушка `landing` — с ней выпускается сертификат
  корня; при сайте на корне её прунит `/de-template`.
- **Backup** (restic, in-container crond): сидит сбоку, ежедневно делает `pg_dumpall | gzip | restic backup --stdin` (один файл-снапшот, не volume tree). `RESTIC_REPOSITORY` задаётся в `.env` без local-default'а — чтобы исключить случайный указатель на проектный minio (host failure уносит и postgres-data, и репо).
- **Minio**: S3-storage на `s3.${DOMAIN}` / console `minio.${DOMAIN}`; bucket `app-uploads` для backend, `backups` для restic; service-accounts создаёт `minio-init`.

## Сети

| Network | Тип | Кто в ней |
|---|---|---|
| `proxy` | bridge (наружу через traefik) | Traefik (edge), CrowdSec, landing, site и backend (входящий HTTPS), minio (S3 + Console), backup (исходящий к внешнему S3) |
| `backend-net` | bridge, **internal** | postgres, backend, minio, minio-init, backup |

Постгрес НЕ в `proxy` — он недоступен извне. Backend стучится в постгрес по hostname `postgres` через `backend-net`.
Сайту данные стека не нужны — он только в `proxy`. Порты наружу публикует один Traefik (80, 443).

## Edge: журнал доступа и CrowdSec

- **Журнал доступа** — файл `/var/log/traefik/access.log` в каталоге хоста (`700`, только root): JSON-строка
  на каждый ответ, с `request_User-Agent` и `X-Request-Id`. Файл, а не docker-источник: сокет демона второму
  контейнеру — права тому, кто разбирает чужой ввод.
- **CrowdSec** читает журнал (`configs/crowdsec/acquis.yaml`) и банит по сценариям обхода и проб; бан bouncer
  Traefik отдаёт ответом 429, как и лимит частоты. Поисковиков бережёт rDNS (постоверфлоу `rdns` и
  `seo-bots-whitelist`), ИИ-ботов — allowlist сетей их вендоров: `configs/crowdsec/ai-bots.sources` (печать
  реестра ботов сайта, `make bots-sources`) против именных групп `robots.txt` сервиса `site`.
- **Расписание edge** — crond в контейнере `crowdsec` (`configs/crowdsec/crontab`): ротация журнала (раз в
  сутки и при 256 МиБ) и allowlist раз в неделю; allowlist обновляют ещё `make deploy` и `make bump SVC=site`
  (недостающие списки) и `make allowlist`.
- **Не-прод контур** — `ROBOTS_POLICY=noindex` у сайта и цепочка `staging@file` (`X-Robots-Tag` и basicAuth)
  хвостом его роутеров, пока задан `STAGING_BASIC_AUTH_USERS`.

Нормы — rule `traefik-routing`, сбои и сигналы смока — `docs/reference/runbook.md`.

## Данные и persistence

| Volume | Что | Backup |
|---|---|---|
| `postgres-data` | PG datadir | да — `pg_dumpall` из `containers/backup` |
| `traefik-acme` | LE cert storage | нет (восстанавливается через ACME) |
| `crowdsec-data` / `-config` | bouncer state, ban-lists | опционально (mostly self-rebuilds) |
| `minio-data` | S3-объекты (uploads; в rehearsal — ещё restic-bucket `backups`) | нет (см. ниже) |
| `/var/log/traefik` (каталог хоста) | журнал доступа и его 14 сжатых копий | нет |

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
   - `scripts/render-configs.sh` рендерит envsubst'ом `configs/**/*.tpl` из `.env` (traefik static с `ACME_*`, middlewares с `CROWDSEC_BOUNCER_API_KEY` и замком не-прод `STAGING_BASIC_AUTH_USERS`, landing); конфиги Traefik — `600`, только root.
   - compose интерполирует `${VAR}` из `.env` в `environment:` сервисов при `up`.
3. На rotation секрета: правка значения в `.env` + `make deploy` — compose сравнивает интерполированный конфиг и пересоздаёт затронутые сервисы сам (`environment` фиксируется при container CREATE, поэтому `restart` недостаточно; точечно — `make recreate SVC=`). Bind-mounted конфиги compose не отслеживает — `deploy.sh` рестартует traefik/crowdsec/postgres по git-diff'у `configs/` от последнего удачного деплоя (`refs/deploy/ok`), смена `ACME_*` без коммита требует `make restart SVC=traefik` руками.

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
                                         форма .env (preflight-env)
                                         git pull --ff-only
                                         render-configs (envsubst .tpl)
                                         crowdsec, затем compose up -d --wait
                                         (пересоздаёт сервисы с изменённым environment сам)
                                         рестарт по дифу configs/ от refs/deploy/ok
                                         allowlist ботов (при профиле site)
```

Никаких runner'ов, push-trigger'ов, gitea-CI. Образы сервисов собирает и пушит в registry сервис-репо своим `/release`, затем здесь `make bump SVC=<svc> TAG=<tag>` — правит `<SVC>_TAG` в `.env` на VPS, force-recreate'ит сервис и ждёт healthy (отказ — возврат на прежний тег). Image-теги живут строго в `.env` (конвенция `<SVC>_TAG`). Сайт после выкатки принимает `make accept SVC=site`; handoff-блок релиза — `docs/reference/ecosystem.md`.

## Cockpit-сводка и серверный смок

`make status` — единая сводка для агента (skill `smartdev`), оркестратор из двух источников:

- **Локально** (`scripts/tools/status.sh`, pure-local — без docker и SSH): git-состояние,
  `== Critical ==` (upstream/deploy-drift), активные планы из `.claude/plans/` (`validate-plan.sh --summary`).
- **Серверный смок** (`== Server ==`): host-витали (load / RAM / swap / disk / OOM) + здоровье
  контейнеров (unhealthy / exited / restart-loop, автодискавери из `docker ps`) + edge (журнал доступа,
  его чтение CrowdSec, allowlist и баны ботов) + сайт (liveness, ответ `/` по среде, `robots.txt`,
  `sitemap.xml`). Бежит **на хосте** — `scripts/tools/smoke-run.sh` гоняет drop-in
  `scripts/tools/smoke.d/*.sh` по порядку (`10-host`, `20-containers`, `30-edge`, `90-site`; `90-<svc>` —
  bespoke-сигнал сервиса).

`.env`-sentinel (как у ops-вербов): на VPS (есть `.env`) смок бежит локально; с workstation
(`.env.local`) — через `scripts/tools/ssh.sh smoke`; нет connection / VPS недоступен → `== Server == SKIP`.
Каждый смок-чек read-only и self-`exit 0`; проблема — строкой `ATTENTION:` в колонке 0 (её ловит
smartdev → чейн в `triage`). Смок расширяется добавлением файла в `smoke.d/` — растёт вместе с инфрой
(skill `add-service`).

`make accept SVC=site` — приёмка первого деплоя сайта машиной (контракт сайта, § 1.7): смок edge и сайта,
форма адреса, записи `Host`, методы, заголовки, лимит формы, UA-проба по `ai-bots.sources`, запись журнала,
отказ WAF. Профиль среды (прод или не-прод за замком) приёмка берёт у контейнера, `.env` не читает; код 0 —
всё зелёное.

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
  | `edge` | traefik, crowdsec, landing, backend, site | `backend`, `site` |
  | `db` | postgres | `postgres` |
  | `storage` | minio, backup | `storage` |

  Project name = имя директории; split-хосты — физически разные VPS, коллизий
  томов нет; каждый держит свой `.env` (identity + секреты сервисов его роли).
  Сайт — в роли `edge`: CrowdSec читает журнал Traefik и `robots.txt` сайта по сети `proxy`.
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
- **Frontend** (SPA за логином) — `compose/frontend.yml` с traefik labels на свой сабдомен (`app.${DOMAIN}`); корень `${DOMAIN}` занимает сайт (`compose/site.yml`, профиль `site`).
- **Worker** (отдельный binary) — `compose/worker.yml`, обычно тот же image что backend, но `command: /app/worker`.

Принцип: один файл = один сервис. Makefile собирает `-f` аргументы автоматически.
