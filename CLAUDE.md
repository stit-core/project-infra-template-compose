# project-infra-template-compose — гайд для агентов

Шаблон проектной инфры stit: docker-compose стек одного VPS на клиентский
проект. Edge (Traefik v3 + CrowdSec) + Postgres + Minio + backend + backup.
Копируется в `<client-org>/infra`, адаптируется под домен/стек.

Этот файл — **always-on ядро + роутер**: здесь только то, что должно быть в контексте всегда
(точка входа, где запускается, жёсткие границы) и карта, куда идти за остальным. Система слоится так:

| Слой | Что держит | Когда грузится |
|---|---|---|
| **`CLAUDE.md`** (этот файл) | ядро + роутер | всегда |
| **`.claude/rules/<topic>.md`** | инварианты по теме | path-scoped — когда matching-файл в контексте |
| **`.claude/skills/<name>/`** | процедуры (`/smartdev`, `/plan`, `/triage`, …) | при вызове скилла |
| **`.claude/plans/roadmap.md`** | активные планы | по запросу; переживает `/clear` |
| **`docs/`** | reference для людей (`README.md` — обзор) | по ссылке |

За деталью — не дублируй здесь, иди по «Карте: где что» ниже.

## Точка входа

- **`/smartdev`** — cockpit сессии: за один проход `make status`, поднимает активный план
  и **сам переключает** в нужный режим (triage / plan / add-service /
  dr-restore / bootstrap-vps). Запускай в начале / после `/clear`.
- **Planning-first.** Любое содержательное изменение идёт через план — секцию в едином
  `.claude/plans/roadmap.md` (skill `/plan`). Прямая правка — только truly-atomic и багфиксы
  (skill `triage`, RED-first). План переживает `/clear`.
- **Дефолтная петля любой правки — RED→GREEN:** `make validate` / `make doctor` красный →
  fix → зелёный. Все действия — через `make <verb>` (`make help`); скрипты за make не дёргаем.

## Где это запускается

Репо живёт на **рабочей станции оператора** — authoring / validate / plan / ship. Живого
стека локально нет: приложения и контейнеры — на удалённом VPS (один VPS = одна среда).
`make ship` пушит и триггерит remote `deploy.sh` по SSH. Ops на VPS (`ps`/`logs`/`deploy`/
`restart`) — через `scripts/tools/ssh.sh` (connection из `.env.local`, fallback
`ansible/inventory.ini`). Локальный SKIP
authoring-проверок без `.env`/docker — норма, не падение.

## Где это в экосистеме

**Роль:** шаблон проектной VPS. Один форк (`<client-org>/infra`) — один проект, один VPS на
env (dev/staging/prod).
**Зависит от:** `corp-infra-template` — хостит registry `git.stit.tech` и ведёт
CrowdSec-whitelist egress-IP проектных VPS.
**Image-теги:** бампаются **строго через `.env`** (`<SVC>_TAG`, верб `make bump SVC= TAG=`).
**Обслуживает:** `<client-org>/backend` (форк `go-backend-template`) — runtime для его образа;
deploy нового тега — `make bump SVC=backend TAG=<tag>` (тег строго в `.env`).
**Читает:** `<client-org>/strategy` (форк `business-strategy-template`) — продуктовый контекст (vision,
surfaces); sibling-checkout рядом с этим репо, read-only. Резолв пути — `docs/reference/ecosystem.md`.

Карта репо и канонические контракты — `corp-infra-template/docs/ecosystem.md`.

## Стек

| Слой | Что | Где |
|---|---|---|
| Edge | Traefik v3 + CrowdSec | `compose/traefik.yml`, `compose/crowdsec.yml` |
| DB | Postgres 17 | `compose/postgres.yml` |
| App | Backend (`git.stit.tech/<client-org>/backend`) | `compose/backend.yml` |
| Storage | Minio (S3 + Console) на `s3.${DOMAIN}` / `minio.${DOMAIN}` | `compose/minio.yml` |
| Backup | restic + pg_dumpall + crond в alpine, пишет в `$RESTIC_REPOSITORY` | `compose/backup.yml`, `containers/backup/` |

Always-on (traefik / crowdsec / landing) поднимается
на identity + ACME из `.env`. `postgres` / `storage` (minio + backup) / `backend`
— opt-in через `COMPOSE_PROFILES`, активируются после заполнения их секций
секретов в `.env` (единственный источник секретов, живёт только на VPS). Сети:
`proxy` (наружу), `backend-net` (internal). См. `.claude/rules/multi-env.md` +
`docs/reference/architecture.md`.

## Команды

Единый словарь `make <verb>`, сгруппирован в `make help`. Concise-by-default; `FORMAT=detailed` —
полный разбор. Канонический gate перед claim «готово» / push — **`make check`** (validate + doctor + plan-check + project-check).

| Группа | Верб | Что |
|---|---|---|
| LOOP | `validate` / `doctor` / `check` | syntax+tpl+.env coverage / live preflight / validate+doctor+plan-check+project-check |
| SHIP | `ship MSG="..."` | commit + check + push + (на main) ssh-deploy. Канон |
| | `deploy` / `render` | server-side: git pull → render → compose up --wait / envsubst для `*.tpl` |
| OPS | `ps` / `logs SVC=` / `restart SVC=` / `recreate SVC=` / `build SVC=` | статус / логи / рестарт / пересоздать (env_file pickup) / сборка образа сервиса |
| | `bump SVC= TAG=` | бамп image-тега: правит `<SVC>_TAG` в `.env` на VPS + force-recreate. Единственный канон бампа |
| | `backup` / `restore-pg SNAPSHOT=` | one-shot backup / restore postgres из restic |
| | `ssh CMD="…"` | произвольная команда на VPS (через `ssh.sh`) |
| INTEL | `status` / `search Q= [P=]` | cockpit-сводка / поиск по compose+configs+scripts+docs |
| PROVISION | `new-env` | bootstrap `.env` на чистом VPS |
| SETUP | `setup` | поставить git-хуки (commit-msg + pre-commit) |
| META | `plan-check` / `project-check` | структура планов / инфра-слой `docs/project/` (stack + сервисы) |

## Карта: где что

| Тема | Где |
|---|---|
| Архитектура, сети, профили, non-goals | `docs/reference/architecture.md` |
| Инфра-слой проекта (stack + карта сервисов + service-doc'и) | `docs/project/README.md` (вход для `/init-project` + `/de-template`) |
| Продуктовый контекст (vision/surfaces) | соседний `<org>/strategy` (форк `business-strategy-template`), читается cross-repo |
| Per-env `.env`-контракт, multi-env, профили | `.claude/rules/multi-env.md` |
| Compose-инварианты сервиса | `.claude/rules/compose-and-services.md` |
| Секреты и `.env` | `.claude/rules/secrets-and-env.md` |
| Корп-контракт (registry + CrowdSec-whitelist) | секция «Корп-контракт» ниже |
| Онбординг / путь потребителя | `docs/getting-started.md` |
| Runbook / инциденты | `docs/reference/runbook.md` |
| Экосистема репо, контракты | `docs/reference/ecosystem.md` (→ канон `corp-infra-template/docs/ecosystem.md`) |

## Корп-контракт

Корп-сторона даёт проектной VPS только два сервиса:

1. **Registry** `git.stit.tech` — pull образов `git.stit.tech/<p>/backend:<tag>`
   (push — разработчик backend-форка).
2. **CrowdSec whitelist** — egress-IP проектной VPS, иначе служебный трафик к
   корп-сервисам режется 403. egress-IP передаётся оператору корп-инфры
   out-of-band для внесения в whitelist.

Секреты корп не выдаёт и не хранит: все секреты оператор пишет сам в `.env` на
VPS по контракту `.env.example`. Подробности — `.claude/rules/multi-env.md`.

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
  `refactor`, `docs`, `test`, `chore`, `meta`.
- Линейная история, push в main напрямую (solo-flow) — или в ветку → PR в Gitea → merge.
- `make ship MSG="..."` — единственный канон: commit + `make check` (красный → пуш отменён) +
  push + (на main) ssh-deploy. На чистом дереве MSG необязателен.
- Хуки ставятся `make setup`.

## Границы

### Делать всегда
- Перед claim «готово» — `make check` (validate + doctor + plan-check + project-check); после деплоя — `make ps`.
- **Изменение — через план** (planning-first; skill `/plan`). Отклонение — осознанное, проговаривается.
- Изменение требует CrowdSec-whitelist'а egress-IP корп-side (whitelist живёт в
  `corp-infra-template`, не здесь) — передай egress-IP оператору корп-инфры
  out-of-band до claim «готово».
- Любая новая `${VAR}` в compose/configs — в `.env.example` сразу.
- Bumps версий образов — отдельным коммитом после явного OK.

### Сначала спросить
- Traefik static-конфиг (`configs/traefik/traefik.yml.tpl` → рендерится в
  `configs/traefik/traefik.yml`) — глобальные изменения требуют рестарта Traefik.
- `containers/backup/` или `compose/backup.yml` — риск потери restore-points.

### Не делать никогда
- `--no-verify` / `--no-gpg-sign`, `git push --force`, `docker volume rm` / `down -v` —
  блокирует `permissions.deny` в `.claude/settings.json`.
- Commit `.env*`, rendered-конфигов, `*.pem`, `*.key`. Image-теги `:latest`.
- Inline-значения секретов в compose/`configs/` — только `${VAR}` из `.env`.
- Писать в auto-memory — отключено (см. ниже).

## Что менять при копировании в `<org>/infra`

1. `.env` — `make new-env` (PROJECT_NAME, ENV, DOMAIN, ACME_EMAIL).
2. `docker-compose.yml` — проверить network names (conflict-free на shared VPS).
3. `compose/backend.yml` — `image:` под клиентский org, healthcheck path под backend API;
   project-specific `${VAR}` в `environment:` + декларация в `.env.example`.
4. `configs/traefik/dynamic/` — клиент-специфичные routers/middlewares (опц.).

Продуктовый слой проекта (vision / surface) — в соседнем `<org>/strategy` (форк
`business-strategy-template` — репо бизнес-стратегии; продукт в `docs/projects/<slug>/`),
проектируется его скиллами; здесь инфру под него ведёт `/init-project` (читает
`<org>/strategy` cross-repo → стек+карта сервисов → service-doc'и → `/de-template`).

Полный путь потребителя — `docs/getting-started.md`.

## Auto-memory

В этом проекте автопамять Claude **отключена**. Всё, что должно пережить сессию, фиксируется в
репо под git — видно команде, ревьюится, воспроизводимо.

| Что | Куда |
|---|---|
| Постоянные правила/предпочтения для агента | `CLAUDE.md` или `.claude/rules/<topic>.md` |
| Архитектурные решения / «почему» | `docs/reference/architecture.md` (inline, present-state) |
| Активные задачи / план работ | `.claude/plans/roadmap.md` (single-file) |
| Reference на внешние системы | `docs/reference/{architecture,ecosystem,runbook}.md`, `docs/getting-started.md` |
| Креды и где используются | вне репо (Vaultwarden, оператор-only заметка) |

Технически: `autoMemoryEnabled: false` + `permissions.deny` на `Write`/`Edit`/`MultiEdit`/
`NotebookEdit` по `**/.claude/projects/**/memory/**` в `.claude/settings.json`. Если правила
«забываются» между сессиями — значит недо-зафиксированы в репо; перенеси в `CLAUDE.md` / `.claude/rules/`.

## Forward-only

Любой текст в репо описывает **только текущее состояние / намерение** — не «было/стало».
История — в `git log` + Conventional Commits. Полное правило — `.claude/rules/forward-only.md`.
