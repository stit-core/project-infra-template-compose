# project-infra-template-compose — гайд для агентов

Шаблон проектной инфры stit: docker-compose стек одного VPS на клиентский
проект. Edge (Traefik v3 + CrowdSec) + Postgres + Minio + backend + сайт + backup.
Копируется в `<client-org>/infra`, адаптируется под домен/стек.

Этот файл — **always-on ядро + роутер**: здесь только то, что должно быть в контексте всегда
(точка входа, где запускается, жёсткие границы) и карта, куда идти за остальным. Система слоится так:

| Слой | Что держит | Когда грузится |
|---|---|---|
| **`CLAUDE.md`** (этот файл) | ядро + роутер | всегда |
| **`.claude/rules/<topic>.md`** | инварианты по теме | path-scoped (`paths:`) — когда matching-файл в контексте |
| **`.claude/skills/<name>/`** | процедуры (`/smartdev`, `/plan`, `/triage`, …) | при вызове скилла |
| **`.claude/plans/`** | активные планы `<slug>.md` (в том числе программы сквозных задач) и `backlog.md` | по запросу; переживает `/clear` |
| **`docs/`** | reference для людей (`README.md` — обзор) | по ссылке |

За деталью — не дублируй здесь, иди по «Карте: где что» ниже.

## Точка входа

- **`/smartdev`** — cockpit сессии: за один проход `make status`, поднимает активный план и сам
  переключает в нужный режим (triage / plan / add-service / dr-restore / bootstrap-vps / задача
  сиблингу). Запускай в начале сессии и после `/clear`.
- **Planning-first.** Содержательное изменение идёт через план — файл в `.claude/plans/` (skill
  `/plan`); сквозная задача — программа с фазами по репо. Прямая правка — только truly-atomic и
  багфиксы (skill `triage`, RED-first).
- **Дефолтная петля любой правки — RED→GREEN:** `make validate` / `make doctor` красный →
  fix → зелёный.

## Где это запускается

Репо живёт на **рабочей станции оператора** — authoring / validate / plan / ship. Живого
стека локально нет: приложения и контейнеры — на удалённом VPS (один VPS = одна среда).
`make ship` пушит и триггерит remote `deploy.sh` по SSH. Ops на VPS (`ps`/`logs`/`deploy`/
`restart`) — через `scripts/tools/ssh.sh` (connection из `.env.local`, fallback
`ansible/inventory.ini`). Локальный SKIP authoring-проверок без `.env`/docker — норма, не падение.

## Где это в экосистеме

**Роль:** runtime проекта и его **операционный хаб**. Один форк (`<org>/infra`) — один проект,
один VPS на среду (dev/staging/prod); отсюда ведутся программы сквозных задач и выкатка тегов, сервис-репо
лежат рядом sibling-checkout'ами. Карта репо, флоу и контракты — канон `docs/reference/ecosystem.md`.
**Образы сервисов** — из registry `REGISTRY_HOST` (дефолт `git.stit.tech`); теги — строго в `.env`
(`<SVC>_TAG`), выкатка — `make bump SVC=<svc> TAG=<tag>`. Из коробки в стеке — `compose/backend.yml` и
`compose/site.yml` (сайт на корне `${DOMAIN}`); frontend и бот добавляются `/add-service`. Handoff-блок
релиза сервис-репо (у сайта — и строки `AI-BOTS`, `PROXY`) хаб применяет по шагам
`docs/reference/ecosystem.md § Handoff-блок релиза`.
**Читает:** `<org>/strategy` (форк `business-strategy-template`) — продуктовый контекст (vision,
surfaces), read-only; резолв пути — `docs/reference/ecosystem.md`.

## Оркестрация: флоу проекта

1. **Сначала strategy.** Бизнес и продукт проектируются в `<org>/strategy` её скиллами
   (`/entrypoint`, клиент — `/entrypoint-for-business`) до инфры; здесь продукт не авторится.
2. **Дальше — отсюда.** `/init-project` читает strategy и проектирует инфру. Сквозная задача —
   программа здесь (`/plan`, фаза на репо) → агенты в сиблингах со своими планами фаз → выкатка здесь.
3. **Агент в сиблинге работает обвязкой того репо** — сначала его CLAUDE.md, дальше его вербы,
   скиллы и гейты: контракты сиблинга живут там, поэтому его код отсюда в обход них не правим.

| Сосед | Что там | Итог работы агента |
|---|---|---|
| `../strategy` | design SoT: продукт, домены, UX, FSD-карта, ИТ-периметр | правка дизайна скиллами strategy |
| `../backend` | Go-сервис | `/release` → образ в registry; здесь `make bump SVC=backend` |
| `../frontend` | React SPA (кабинет) | `/release` → образ; здесь `make bump SVC=frontend` |
| `../site` | Astro SSR-сайт | `/release` → образ; здесь `make bump SVC=site` |
| `../<bot>` | Telegram-бот | `/release` → образ; здесь `make bump SVC=bot` |
| `../mobile` | KMP-приложение | только задачи: релиз в магазины — его `/release`, деплой отсюда не касается |

Прямой заход человека в сервис-репо — нормальный режим: репо работает своей обвязкой, последствия
для хаба приходят INFRA-HANDOFF-блоком. Резолв сиблингов (`<NAME>_REPO_PATH` из `.env.local`,
иначе `../<name>`), что каждый читает из strategy и детали контракта — `docs/reference/ecosystem.md`.

## Стек

| Слой | Что | Где |
|---|---|---|
| Edge | Traefik v3 + CrowdSec: журнал доступа, allowlist ботов, расписание edge | `compose/traefik.yml`, `compose/crowdsec.yml`, `configs/crowdsec/` |
| DB | Postgres 17 | `compose/postgres.yml` |
| App | Backend (`${REGISTRY_HOST}/${PROJECT_NAME}/backend`) | `compose/backend.yml` |
| Site | Индексируемый сайт (`${REGISTRY_HOST}/${PROJECT_NAME}/site`) на корне `${DOMAIN}`, `www` → корень | `compose/site.yml` |
| Storage | Minio (S3 + Console) на `s3.${DOMAIN}` / `minio.${DOMAIN}` | `compose/minio.yml` |
| Backup | restic + pg_dumpall + crond в alpine, пишет в `$RESTIC_REPOSITORY` | `compose/backup.yml`, `containers/backup/` |

Always-on (traefik / crowdsec / landing — заглушка корня до первого деплоя сайта) поднимается на
identity + ACME из `.env`. `postgres` / `storage` (minio + backup) / `backend` / `site` — opt-in через
`COMPOSE_PROFILES`, активируются после заполнения их секций секретов в `.env` (единственный источник
секретов, живёт только на VPS).
Сети: `proxy` (наружу), `backend-net` (internal). См. `.claude/rules/multi-env.md` +
`docs/reference/architecture.md`.

## Команды

Единый словарь `make <verb>`, сгруппирован в `make help`. Concise-by-default; `FORMAT=detailed` —
полный разбор. Канонический gate перед claim «готово» / push — **`make check`** (validate + doctor + plan-check + project-check).

| Группа | Верб | Что |
|---|---|---|
| LOOP | `validate` / `doctor` / `check` | syntax+tpl+.env coverage / live preflight / validate+doctor+plan-check+project-check |
| SHIP | `ship MSG="..."` | commit + check + push + (на main) ssh-deploy. Канон |
| | `deploy` / `render` | server-side: git pull → render → compose up --wait / envsubst для `*.tpl` |
| OPS | `ps` / `logs SVC=` / `restart SVC=` / `recreate SVC=` / `build SVC=` | статус / логи / рестарт / пересоздать (подхват нового значения `.env` или тега) / сборка образа сервиса |
| | `bump SVC= TAG=` | бамп image-тега: правит `<SVC>_TAG` в `.env` на VPS + force-recreate, ждёт healthy; отказ — возврат на прежний тег; `site` — и allowlist ботов. Единственный канон бампа |
| | `backup` / `restore-pg SNAPSHOT=` | one-shot backup / restore postgres из restic |
| | `allowlist` | allowlist ботов в CrowdSec: сети вендоров по `ai-bots.sources` и `robots.txt` сайта |
| | `accept SVC=site` | приёмка сайта после деплоя машиной: смок edge и сайта, адрес, методы, заголовки, форма, UA-проба, журнал, отказ WAF; профиль среды — у контейнера |
| INTEL | `status` / `search Q= [P=]` | cockpit-сводка / поиск по compose+configs+scripts+docs |
| PROVISION | `new-env` | bootstrap `.env` на чистом VPS |
| SETUP | `setup` | git-хуки (commit-msg + pre-commit) + PyYAML для frontmatter-проверки |
| META | `plan-check` / `project-check` | структура планов / инфра-слой `docs/project/` (stack + сервисы) |
| | `bots-sources` | печать реестра ботов соседа `<org>/site` → `configs/crowdsec/ai-bots.sources` |

Произвольная команда на VPS — `bash scripts/tools/ssh.sh exec '<command>'` (одной строкой в
кавычках; задокументированное исключение make-first — make-слой ломает вложенные кавычки,
см. rule `.claude/rules/make-first.md § SSH`).

## Карта: где что

| Тема | Где |
|---|---|
| Архитектура, сети, профили, non-goals | `docs/reference/architecture.md` |
| Инфра-слой проекта (stack + карта сервисов + service-doc'и) | `docs/project/README.md` (вход для `/init-project` + `/de-template`) |
| Экосистема: карта репо, флоу, резолв сиблингов, контракт сервис-репо ↔ хаб, handoff-блок релиза | `docs/reference/ecosystem.md` |
| Продуктовый контекст (vision/surfaces) | соседний `<org>/strategy` (форк `business-strategy-template`), читается cross-repo |
| Per-env `.env`-контракт, multi-env, профили | `.claude/rules/multi-env.md` |
| Compose-инварианты сервиса | `.claude/rules/compose-and-services.md` |
| Edge: роутеры и middleware Traefik, журнал доступа, CrowdSec | `.claude/rules/traefik-routing.md` + `docs/reference/architecture.md` |
| Секреты и `.env` | `.claude/rules/secrets-and-env.md` |
| Онбординг / путь потребителя | `docs/getting-started.md` |
| Runbook / инциденты | `docs/reference/runbook.md` |

## Стиль

- **make-first.** Все операции — через `make <verb>` (`make help`); скрипты за таргетами напрямую
  не дёргаем. Raw-`docker` — только legit-исключения (restic/cscli/mc/ls через `docker exec`,
  throwaway в DR, explanatory deploy.sh-внутренности). Канон и список исключений — rule `.claude/rules/make-first.md`.
- **YAML 2-space indent**, без табов.
- **Image закреплён конкретной версией.** `:latest` запрещён — конвенция, ловится `make validate`.
  Бампаемые теги параметризуются `${<SVC>_TAG}` из `.env` и меняются **только** через
  `make bump`.
- **Каждый сервис имеет** `restart`, `healthcheck`, `container_name`, явный `networks`.
- **Public сервисы** в `proxy` сети + Traefik labels с `crowdsec@file` middleware.
- **Comments — только когда WHY неочевидно.** Не пересказывай YAML.
- **Любой `${VAR}`** в compose/configs обязан быть в `.env.example` с комментарием как сгенерировать.

## Git workflow

- **Conventional Commits** — git-хук `commit-msg` блокирует невалидные. Типы: `feat`, `fix`,
  `refactor`, `docs`, `test`, `chore`, `meta`, `perf`.
- Линейная история, push в main напрямую (solo-flow) — или в ветку → PR в Gitea → merge.
- `make ship MSG="..."` — единственный канон: commit + `make check` (красный → пуш отменён) +
  push + (на main) ssh-deploy. На чистом дереве MSG необязателен.
- Хуки ставятся `make setup`.

## Границы

### Делать всегда
- Перед claim «готово» — `make check` (validate + doctor + plan-check + project-check); после деплоя — `make ps`.
- После выкатки сайта — `make accept SVC=site`; строка `AI-BOTS` его handoff — `make bots-sources` и
  `make allowlist` (порядок — `docs/reference/ecosystem.md § Handoff-блок релиза`).
- Любая новая `${VAR}` в compose/configs — в `.env.example` сразу.
- Бамп инфра-образа (литеральная версия в `compose/<svc>.yml`) — отдельным коммитом после явного OK;
  тег образа сервис-репо — `make bump`.

### Сначала спросить
- Traefik static-конфиг (`configs/traefik/traefik.yml.tpl` → рендерится в
  `configs/traefik/traefik.yml`) — глобальные изменения требуют рестарта Traefik.
- `containers/backup/` или `compose/backup.yml` — риск потери restore-points.

### Не делать никогда
- `--no-verify` / `--no-gpg-sign`, `git push --force`, `docker volume rm` / `down -v` —
  блокирует `permissions.deny` в `.claude/settings.json`.
- Commit `.env*`, rendered-конфигов, `*.pem`, `*.key`. Image-теги `:latest`.
- Inline-значения секретов в compose/`configs/` — только `${VAR}` из `.env`.

## Что менять при копировании в `<org>/infra`

1. `.env` — `make new-env` (PROJECT_NAME, ENV, DOMAIN, ACME_EMAIL).
2. `docker-compose.yml` — проверить network names (conflict-free на shared VPS).
3. `compose/backend.yml` — healthcheck path под backend API; project-specific `${VAR}` в
   `environment:` + декларация в `.env.example` (образ уже собран из `REGISTRY_HOST` /
   `PROJECT_NAME` / `BACKEND_TAG`).
4. `configs/traefik/dynamic/` — клиент-специфичные routers/middlewares (опц.).

Инфру под продукт из `<org>/strategy` ведёт `/init-project` (стек + карта сервисов →
service-doc'и → `/de-template`). Полный путь потребителя — `docs/getting-started.md`.

## Auto-memory

Автопамять Claude в проекте **отключена**: всё, что должно пережить сессию, фиксируется в репо
под git — видно команде, ревьюится, воспроизводимо.

| Что | Куда |
|---|---|
| Постоянные правила/предпочтения для агента | `CLAUDE.md` или `.claude/rules/<topic>.md` |
| Архитектурные решения / «почему» | `docs/reference/architecture.md` (inline, present-state) |
| Активные задачи / план работ | `.claude/plans/` (`<slug>.md` + `backlog.md`) |
| Reference на внешние системы | `docs/reference/{architecture,ecosystem,runbook}.md`, `docs/getting-started.md` |
| Креды | вне git: `.env` на VPS, `.env.local` на рабочей станции (rule `env-local`) |

Технически: `autoMemoryEnabled: false` + `permissions.deny` на `Edit(**/.claude/projects/**/memory/**)`
в `.claude/settings.json`. Если правила «забываются» между сессиями — значит недо-зафиксированы в
репо; перенеси в `CLAUDE.md` / `.claude/rules/`.

## Forward-only

Любой текст в репо описывает **только текущее состояние / намерение** — не «было/стало».
История — в `git log` + Conventional Commits. Полное правило — `.claude/rules/forward-only.md`.
