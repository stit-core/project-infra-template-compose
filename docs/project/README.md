# Infra artifacts

Инфра-слой проектной VPS — **source of truth для `de-template`**: из чего стек состоит и как
этот VPS его хостит. **Продуктовый контекст** (проблема, пользователи, поверхности продукта)
живёт в соседнем репо `business-strategy-template` (форк `<org>/strategy`, `docs/projects/<slug>/`) и
читается **cross-repo** — здесь не дублируется. См. `docs/reference/ecosystem.md § Sibling <org>/strategy`.

Заполняется через `/init-project` (оркестратор) → `/stack-deep-dive` + `/service-deep-dive`,
валидируется `scripts/tools/validate-project-doc.sh`, разворачивается `/de-template`.

## Структура

```
docs/project/
├── README.md                ← этот файл
├── _templates/              ← пустые шаблоны для копирования
│   ├── stack.md
│   └── service.md
├── stack.md                 ← kind: stack (singleton) — cross-cutting + карта сервисов + среды
└── services/
    └── <name>.md            ← kind: service — по одному на hosted-сервис
```

`stack.md` и `services/` рождаются deep-dive'ами — в шаблон не коммитятся (только `_templates/`).

## Kinds

| kind | файл | что описывает |
|---|---|---|
| `stack` | `stack.md` | cross-cutting инфры VPS (домены, edge, сети, бэкап, телеметрия) + **карта сервисов** + среды |
| `service` | `services/<name>.md` | один **hosted** сервис: хостинг, идентичность, секреты, роут |

`stack § Service map` — авторитетный перечень всех частей продукта на стороне инфры. Сервис с
`hosting: here` крутится контейнером в ЭТОМ репо и получает свой `services/<name>.md`. Внешние
части (frontend-SPA на CDN, backend-код в отдельном репо) перечислены в карте как контекст —
**без** service-doc; `de-template` печатает по ним cross-repo next-steps.

## Frontmatter

```yaml
# stack.md
id: project.stack
kind: stack
name: stack
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

## Обязательные H2 по kind

| kind | обязательные H2 |
|---|---|
| `stack` | Service map, Domains, Edge, Networks, Backup, Observability, Environments, Generates |
| `service` | Hosting, Identity, Secrets, Route, Generates |

Пустые/неприменимые секции — явной пометкой `N/A` или `_нет_` (зеркалит domain-дисциплину).
Пустых таблиц быть не должно.

Каждый `service` и `stack` несёт секцию **Generates** — контракт для `de-template`: что из артефакта
родится/изменится в инфре (профиль, секция `.env.example`, traefik route, edge-конфиг). Маппинг
живёт рядом с источником, не отдельным файлом.

## Generates → инфра (что выводит de-template)

`de-template` **выводит `COMPOSE_PROFILES` из `stack § Service map`**, не из явного списка:

| subtype сервиса | профиль | хостируемое |
|---|---|---|
| `datastore` (postgres) | `postgres` | `compose/postgres.yml` |
| `datastore` (minio) | `storage` | `compose/minio.yml` + `backup.yml` |
| `backend` (`hosting: here`) | `backend` | `compose/backend.yml` |
| `frontend` (`hosting: here`) | — (always-on `landing`) | `compose/landing.yml` |
| `frontend`/`backend` (`hosting: external`) | — | cross-repo next-step |

Always-on edge/host-метрики (`traefik`/`crowdsec`/`node-exporter`/
`cadvisor`) — фиксированный фундамент шаблона, не описывается service-doc'ами. `stack § Generates`
несёт только cross-cutting: traefik dynamic routes, `DOMAIN`, crowdsec source-IP next-step.

## Cross-repo: продуктовый контекст

Продуктовый слой (vision / surface / capability) живёт в `<org>/strategy`
(`business-strategy-template` — репо бизнес-стратегии; продукт в `docs/projects/<slug>/`),
склонированном **рядом** с `<org>/infra` (sibling-checkout). Скиллы читают его при старте,
чтобы привязать инфру к продукту:

- `stack-deep-dive` читает `<org>/strategy/.../surface.md` — какие поверхности public (нужны сабдомены).
- `de-template` читает `<org>/strategy/.../vision.md § Problem` — кастомизировать `CLAUDE.md` под проект.

Авторская сторона продуктовых артефактов — **только** `<org>/strategy`; здесь их не редактируем.
Конвенция расположения и pointer — `docs/reference/ecosystem.md`.

## Workflow

1. `/init-project` читает продуктовый контекст из `<org>/strategy` (vision + surfaces) как scope.
2. `cp _templates/stack.md docs/project/stack.md` → `/stack-deep-dive` — волны вопросов до
   заполненной `Service map` + cross-cutting + Environments, до `status: stable`.
3. Per hosted-сервис из карты (`hosting: here`): `cp _templates/service.md
   docs/project/services/<name>.md` → `/service-deep-dive <name>` — до `status: stable`.
4. `scripts/tools/validate-project-doc.sh docs/project` зелёный → промоушн `status: draft → stable`.
5. `/de-template` читает stable-артефакты, выводит профили из `stack § Service map`, прунит
   неиспользуемое, кастомит `CLAUDE.md`/README под проект, печатает cross-repo next-steps.

## Gate

`/de-template` не запускается, пока все артефакты не `stable` и валидатор не зелён — зеркалит
domain/stack-gate эталона. `scripts/git-hooks/pre-commit` гонит валидатор на изменённых
`docs/project/**.md`; `make check` — на весь `docs/project`.

## Anti-patterns

- ❌ Заводить `services/<name>.md` для внешнего frontend/backend-кода (`hosting: external`) — он
  только в `stack § Service map`. service-doc — для **hosted** контейнеров этого VPS.
- ❌ Дублировать `COMPOSE_PROFILES` явным списком в `stack.md` — профили выводит `de-template` из
  `Service map`.
- ❌ Дублировать продуктовую аналитику (Problem / Users / surfaces) здесь — она в `<org>/strategy`,
  читается cross-repo.
- ❌ Оставлять `Generates` пустым — движку `de-template` не из чего разворачивать.
- ❌ Промоутить `status: stable` руками без зелёного валидатора.
- ❌ Описывать always-on edge/телеметрию service-doc'ом — это фиксированный фундамент шаблона.
