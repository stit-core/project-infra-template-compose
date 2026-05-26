# Project artifacts

Продуктовый слой проектной инфры — **первичный source of truth** и **вход для skill
`de-template`**. Уровень ВЫШЕ кодового `docs/{domains,stack}` бэкенда: там «какая бизнес-логика
одного сервиса», здесь — «из каких сервисов состоит продукт клиента и как этот VPS их хостит».

Заполняется через `/init-project` (оркестратор) → `/service-deep-dive` + `/stack-deep-dive`,
валидируется `scripts/tools/validate-project-doc.sh`, разворачивается `/de-template`.

## Структура

```
docs/project/
├── README.md                ← этот файл
├── _templates/              ← пустые шаблоны для копирования
│   ├── vision.md
│   ├── service.md
│   └── stack.md
├── vision.md                ← kind: vision (singleton) — продукт + карта сервисов
├── services/
│   └── <name>.md            ← kind: service — по одному на hosted-сервис
└── stack.md                 ← kind: stack (singleton) — cross-cutting инфры VPS
```

`services/` и `vision.md`/`stack.md` рождаются deep-dive'ами по карте сервисов — в шаблон не
коммитятся (только `_templates/`).

## Kinds

| kind | файл | что описывает |
|---|---|---|
| `vision` | `vision.md` | продукт: проблема, пользователи, **карта сервисов**, границы, среды |
| `service` | `services/<name>.md` | один **hosted** сервис: хостинг, идентичность, секреты, роут |
| `stack` | `stack.md` | cross-cutting инфры VPS: домены, edge, сети, бэкап, телеметрия |

`vision § Service map` — авторитетный перечень всех частей продукта. Сервис с `hosting: here`
крутится контейнером в ЭТОМ репо и получает свой `services/<name>.md`. Внешние части (frontend-SPA
на CDN, backend-код в отдельном репо) перечислены в карте как контекст — **без** service-doc;
`de-template` печатает по ним cross-repo next-steps.

## Frontmatter

```yaml
# vision.md
id: project.vision
kind: vision
name: vision
status: draft            # draft → stable (через валидатор)
```

```yaml
# services/<name>.md
id: project.<name>       # == project.<basename без .md>
kind: service
subtype: backend         # backend | frontend | datastore | infra
hosting: here            # here (контейнер в этом репо) | external (свой репо/CDN)
name: <name>             # == basename файла без .md
status: draft
```

```yaml
# stack.md
id: project.stack
kind: stack
name: stack
status: draft
```

## Обязательные H2 по kind

| kind | обязательные H2 |
|---|---|
| `vision` | Problem, Users, Service map, Boundaries, Environments |
| `service` | Hosting, Identity, Secrets, Route, Generates |
| `stack` | Domains, Edge, Networks, Backup, Observability, Generates |

Пустые/неприменимые секции — явной пометкой `N/A` или `_нет_` (зеркалит domain-дисциплину).
Пустых таблиц быть не должно.

Каждый `service` и `stack` несёт секцию **Generates** — контракт для `de-template`: что из артефакта
родится/изменится в инфре (профиль, vault-agent part/template, traefik route, edge-конфиг). Маппинг
живёт рядом с источником, не отдельным файлом.

## Generates → инфра (что выводит de-template)

`de-template` **выводит `COMPOSE_PROFILES` из карты сервисов**, не из явного списка:

| subtype сервиса | профиль | хостируемое |
|---|---|---|
| `datastore` (postgres) | `postgres` | `compose/postgres.yml` |
| `datastore` (minio) | `storage` | `compose/minio.yml` + `backup.yml` |
| `backend` (`hosting: here`) | `backend` | `compose/backend.yml` |
| `frontend` (`hosting: here`) | — (always-on `landing`) | `compose/landing.yml` |
| `frontend`/`backend` (`hosting: external`) | — | cross-repo next-step |

Always-on edge/телеметрия (`traefik`/`crowdsec`/`vault-agent`/`otel-agent`/`node-exporter`/
`cadvisor`) — фиксированный фундамент шаблона, не описывается service-doc'ами. `stack § Generates`
несёт только cross-cutting: traefik dynamic routes, `DOMAIN`, crowdsec source-IP next-step.

## Workflow

1. `/init-project` копирует `_templates/vision.md` → `docs/project/vision.md`, ведёт интервью до
   заполненной `Service map`.
2. Per hosted-сервис из карты: `cp _templates/service.md docs/project/services/<name>.md` →
   `/service-deep-dive <name>` — волны вопросов inside-out до `status: stable`.
3. `cp _templates/stack.md docs/project/stack.md` → `/stack-deep-dive` до `stable`.
4. `scripts/tools/validate-project-doc.sh docs/project` зелёный → промоушн `status: draft → stable`.
5. `/de-template` читает stable-артефакты, выводит профили, прунит неиспользуемое, кастомит
   `CLAUDE.md`/README под проект, печатает cross-repo next-steps.

## Gate

`/de-template` не запускается, пока все артефакты не `stable` и валидатор не зелён — зеркалит
domain/stack-gate эталона. `scripts/git-hooks/pre-commit` гонит валидатор на изменённых
`docs/project/**.md`; `make check` — на весь `docs/project`.

## Anti-patterns

- ❌ Заводить `services/<name>.md` для внешнего frontend/backend-кода (`hosting: external`) — он
  только в `vision § Service map`. service-doc — для **hosted** контейнеров этого VPS.
- ❌ Дублировать `COMPOSE_PROFILES` в `stack.md` — профили выводит `de-template` из карты сервисов.
- ❌ Оставлять `Generates` пустым — движку `de-template` не из чего разворачивать.
- ❌ Промоутить `status: stable` руками без зелёного валидатора.
- ❌ Описывать always-on edge/телеметрию service-doc'ом — это фиксированный фундамент шаблона.
