# Экосистема — карта репо и операционный флоу

Канон экосистемы stit: из чего состоит проект, как по нему движется работа, как хаб находит соседей
и что каждый репо отдаёт и берёт. Остальные репо держат у себя короткую версию (своя роль, соседи,
как туда приходит работа) и ссылаются сюда. Корень проекта и его `CLAUDE.md` —
[`project-root.md`](project-root.md).

## Карта

Шаблоны `stit-core/*` форкаются в репо клиентской орги `<org>/*`. Проект — папка `~/git/<org>/`:
в её корне — карта проекта `CLAUDE.md` и общие настройки сессии, в папках корня — форки орги
sibling-checkout'ами. Из корня ведётся вся работа ([`project-root.md`](project-root.md)):

```
~/git/<org>/   ← корень проекта (<org>/project): CLAUDE.md, .claude/settings.json, local/
├─ strategy/   ← business-strategy-template
├─ infra/      ← project-infra-template-compose (этот репо)
├─ backend/    ← go-backend-template
├─ frontend/   ← spa-frontend-template
├─ site/       ← seo-frontend-template
├─ <bot>/      ← telegram-bot-template
└─ mobile/     ← mobile-template
```

| Шаблон → форк | Роль |
|---|---|
| `business-strategy-template` → `<org>/strategy` | design-time source of truth: бизнес, AJTBD, SWOT, карта гипотез, продукты (vision/surface, interface, screens, fsd, слой страницы сайта, дизайн, telegram-bot-flow, mobile, services + domains), ИТ-периметр |
| `project-infra-template-compose` → `<org>/infra` | runtime проекта (docker-compose на VPS) и **хаб**: программы сквозных задач, выкатка тегов (`make bump`) |
| `go-backend-template` → `<org>/backend` | Go-сервис |
| `spa-frontend-template` → `<org>/frontend` | React SPA (кабинет, всё за логином) |
| `seo-frontend-template` → `<org>/site` | Astro SEO-сайт (индексируемый контент); в стеке хаба — сервис `site` из коробки |
| `telegram-bot-template` → `<org>/<bot>` | Telegram-бот (Python, aiogram) |
| `mobile-template` → `<org>/mobile` | KMP-приложение Android + iOS; релиз — в магазины |

Библиотеки не форкаются, а подключаются зависимостью: `golibinfra` — Go-киты для Go-сервисов,
`pylibinfra` — Python-киты (потребитель — `telegram-bot-template`). Итого 7 шаблонов + 2 библиотеки.
Git-хостинг и container registry — Gitea `git.stit.tech`.

## Операционный флоу

1. **Корень проекта — первым.** Заводится папка `~/git/<org>/` с картой проекта `CLAUDE.md`; в неё
   клонируются все репо проекта, и из неё ведётся вся работа — одной сессией Claude Code. В каждом
   репо сессия работает **обвязкой этого репо**: сначала его CLAUDE.md (с ним подхватываются правила
   и скиллы репо), дальше — его вербы, скиллы и гейты. Контракты репо живут в нём, поэтому его код в
   обход них не правят. Как корень устроен и как его завести — [`project-root.md`](project-root.md).
2. **Сначала проектирование — `<org>/strategy`.** До кода в нём проектируется всё, что можно:
   бизнес, продукт, домены и сервисы, ИТ-периметр, интерфейсы и экраны, FSD-карта, дизайн. Вход —
   `/entrypoint` (аналитик) и `/entrypoint-for-business` (клиент). Код начинается, когда проект
   продуман.
3. **Реализация — из корня, через хаб `<org>/infra`.**
   - `/init-project` читает strategy и проектирует инфру: стек и карту сервисов, service-doc'и,
     `/de-template`. VPS каждой среды поднимает `/bootstrap-vps`.
   - Сквозная задача — программа в `.claude/plans/` хаба (skill `/plan`, `references/program.md`):
     фазы по репо, у каждой фазы — свой план в репо фазы (`parent: infra:<slug>`). Фазы ведёт
     сессия корня — сама или фоновыми агентами, каждый в папке своего репо (`strategy/`,
     `backend/`, `frontend/`, `site/`, `<bot>/`, `mobile/`).
   - Сервис-репо останавливаются на образе в registry — их `/release`. Выкатка тега — только через
     хаб: `make bump SVC=<svc> TAG=<tag>`.
   - Мобильное приложение выпускается в магазины своим `/release`; деплой хаба его не касается, а
     задачи в `mobile/` приходят так же, из корня.
   - Изменение дизайна по ходу работы — в `strategy/`, скиллами strategy.
4. **Прямой заход в отдельный репо** (сессия в папке репо — например, поработать только в
   backend) — нормальный режим: репо работает своей обвязкой, а последствия для хаба оформляются
   INFRA-HANDOFF-блоком — его печатает `/release` сервис-репо, а в backend, боте и mobile ещё и
   `/infra-handoff` по ходу работы. В хабе блок применяется построчно — «Handoff-блок релиза» ниже.

## Резолв сиблингов

Репо проекта лежат в одном корне, и хаб находит соседа `<name>` так:

1. `<NAME>_REPO_PATH` из `.env.local`, если задан (`STRATEGY_REPO_PATH`, `BACKEND_REPO_PATH`,
   `SITE_REPO_PATH`, …): это путь, не секрет, читается grep'ом — формат файла в
   `.claude/rules/env-local.md`;
2. иначе `../<name>` (`../strategy`, `../backend`, …; имя бот-репо — по карте сервисов
   `docs/project/stack.md § Service map`).

Соседа нет на месте — скиллы не падают: печатают next-step «склонируй `<org>/<name>` рядом» и
продолжают с тем, что есть (например, `/init-project` ведёт стек по словам оператора). Сервис-репо
находят strategy своими полями `project-slug` / `strategy-path` (дефолт `../strategy`) / `surface`
в `docs/stack/service.md`.

## Кто что читает из `<org>/strategy`

Чтение read-only и одностороннее: продукт авторится только в strategy её скиллами, соседи его
читают. Пути — внутри `docs/projects/<slug>/` strategy, где `<slug>` — папка продукта. Контракт со
стороны strategy — её `docs/README.md`, раздел «Что docs отдаёт соседям»: состав, закрытость и снимок
описаны там, здесь — карта.

| Репо | Кто читает | Что | Зачем |
|---|---|---|---|
| `<org>/infra` | `/init-project` | `vision.md`, `surface.md` (тип и род `web-kind` поверхности) | scope продукта → карта сервисов: поверхность `web` рода `landing` или `site` — сервис `site` (код `<org>/site`), рода `app` — `<org>/frontend` |
| | `/stack-deep-dive` | `surface.md` (+ `vision.md § Problem`) | какие поверхности public → сабдомены и edge-роуты |
| | `/de-template` | `vision.md § Problem` (+ `surface.md`) | шапка `CLAUDE.md` / `README.md` под проект |
| | `/smartdev` | наличие strategy, `vision.md`, `surface.md` | sanity на старте сессии |
| | `/plan` | `services/{service,platform}.md`, ИТ-периметр `docs/projects/infrastructure/`, манифесты готовности `design/<surface>/ready.yaml` | контекст программ: что собирать и где, готова ли поверхность к сборке; машиной хаб манифест не читает |
| `<org>/backend` | `/init-service`, `/scaffold` | `services/<svc>/domains/<ctx>/`, `services/_shared/`, паспорт `services/<svc>/README.md` | домены → Go-код сервиса |
| `<org>/frontend` | `/init-service`, `/de-template`, `/scaffold` | `fsd/<surface>/` (+ `interface/`, `screens/` поверхности, `services/*/domains/`, пакет дизайна `design/`) | FSD-карта → слайсы SPA |
| `<org>/site` | `/scaffold`, `/de-template` | слой страницы `site/<surface>/` (бриф, карта, планы, тексты по слотам), факты и голос (`facts.yaml`, `voice*.yaml`), пакет дизайна `design/` и `design/<surface>/` с манифестом готовности `ready.yaml`, получатели заявок `integration.md`, каталоги базы скилла (блоки, формы, события, `head`, боты — `.claude/skills/design-deep-dive/kb/site/…`) — снимком с локом | страницы и коллекции сайта; собирается единица с `ready: true` манифеста |
| `<org>/<bot>` | `/dialog-deep-dive` | `telegram-bot-flow/<surface>/` (+ `interface/<surface>/`, `services/*/domains/`) | флоу диалогов → StatesGroup, окна, фичи |
| `<org>/mobile` | `/init-service`, `/de-template`, `/scaffold` | `mobile/<surface>/` (+ `interface/<surface>/`, `services/*/domains/`) | карта приложения → `shared/`, `androidApp/`, `iosApp/` |

## Контракт сервис-репо ↔ хаб

Сервис-репо собирает образ и пушит его в registry своим `/release`; хаб его выкатывает.

| Сервис | Репо | `SVC=` | Тег в `.env` хаба |
|---|---|---|---|
| backend | `<org>/backend` | `backend` | `BACKEND_TAG` |
| frontend | `<org>/frontend` | `frontend` | `FRONTEND_TAG` |
| site | `<org>/site` | `site` | `SITE_TAG` |
| бот | `<org>/<bot>` | `bot` | `BOT_TAG` |

- **Registry.** Образы — в registry `REGISTRY_HOST` (дефолт `git.stit.tech`). Compose-фрагмент
  сервиса тянет `${REGISTRY_HOST:-git.stit.tech}/${PROJECT_NAME}/<svc>:${<SVC>_TAG}` (образец —
  `compose/backend.yml`), так что `PROJECT_NAME` в `.env` совпадает с org, куда `/release` пушит
  образ. VPS логинится в registry один раз — `docker login` с PAT из Gitea.
- **Тег — строго в `.env`** на VPS: `<SVC>_TAG` (UPPER_SNAKE от `SVC`), не литерал в compose.
- **Выкатка — только здесь:** `make bump SVC=<svc> TAG=<tag>` правит `<SVC>_TAG` в `.env` на VPS,
  пересоздаёт сервис (compose сам пуллит отсутствующий образ) и ждёт healthy; тег без образа или образ, не
  ставший healthy за 90 с, — отказ верба и возврат на прежний тег. Rollback — тот же верб со старым тегом.
- **Из коробки** в стеке — `compose/backend.yml` и `compose/site.yml` (профили `backend` и `site`); frontend и
  бот добавляются `/add-service` по карте сервисов `docs/project/stack.md`.
- **Сайт** — сервис `site` на корне `${DOMAIN}`, `www` — 301 на корень. Его контракт —
  `docs/reference/infra-handoff.md` в `<org>/site`; хаб выполняет его стеком: `compose/site.yml`, middleware
  edge, журнал доступа, CrowdSec с allowlist ботов, смок `-- site --` и приёмка `make accept SVC=site`.
  По контракту strategy каждая поверхность рода `site` или `landing` — свой форк `<org>/site` и свой сервис
  хаба с именем поверхности: в шаблоне это `site` (поле `infra-svc` форка сайта), следующую поверхность
  добавляет `/add-service` (вариант «Node-сервис на корневом домене»).
- **Mobile** в этот контракт не входит: образа и compose-сервиса у приложения нет, релиз в магазины —
  `/release` в `<org>/mobile`. Его инфра-поверхность (например, раздача `.well-known` для deep links,
  хосты API) приходит в хаб INFRA-HANDOFF-блоком.

### Handoff-блок релиза

`/release` сервис-репо печатает блок `=== INFRA HANDOFF · <org>/<svc> vX.Y.Z ===`; хаб применяет его по шагам:

1. `WHAT` — сервиса в стеке нет: сначала `/add-service`.
2. `ENV` — новый ключ: `${VAR}` в `compose/<svc>.yml` и декларация в `.env.example`; значение — в `.env` на VPS.
3. `PROXY` — требование к edge (лимит, редирект, заголовок): labels `compose/<svc>.yml` или
   `configs/traefik/dynamic/middlewares.yml.tpl` по rule `traefik-routing`.
4. `AI-BOTS` (сайт) — версия реестра не та, что в первой строке `configs/crowdsec/ai-bots.sources`:
   `make bots-sources` (сосед `<org>/site` на теге релиза).
5. Правки шагов 2–4 — одним коммитом, `make ship`.
6. `ACTION` — `make bump SVC=<svc> TAG=vX.Y.Z`; `RISK` читается до него, откат — `make bump` с прежним тегом.
7. `AI-BOTS` (сайт) называет другую версию реестра, чем прошлый релиз, — `make allowlist`: списки всех ботов
   обновляются по новому реестру сразу. Политику `robots.txt` нового образа allowlist получает шагом 6 —
   `make bump SVC=site` завершает выкатку сайта недостающими списками и снимает списки закрытых ботов.
8. Сайт — `make accept SVC=site` (код 0) после каждой выкатки; `make status` — блоки `-- edge --` и
   `-- site --` без `ATTENTION`. Что значит каждый ✗ и `ATTENTION` — `docs/reference/runbook.md`.

**Первый релиз сайта на среде** — `ACTION` длиннее:

1. DNS: A-запись `www.<DOMAIN>` на VPS (роутер `site-www`; у среды на поддомене имени `www` обычно нет —
   preflight предупреждает); Docker Engine ≥ 25 — строка `docker engine` в `make doctor`.
2. `.env` на VPS — секция `profile site` по `.env.example` (канал формы). На не-прод среде (`ROBOTS_POLICY=noindex`
   ставит `make new-env`) — ещё замок `STAGING_BASIC_AUTH_USERS` и `make deploy` до профиля: замок рендерится в
   конфиг edge раньше, чем появится содержимое сайта.
3. `site` в `COMPOSE_PROFILES` и сразу `make bump SVC=site TAG=vX.Y.Z` — он ставит `SITE_TAG`, а после healthy
   строит allowlist ботов по `robots.txt` образа: профиль без тега роняет `make deploy` (FAIL `image tags` в
   `make doctor`), а бамп без профиля поднимает сервис, которым `make deploy` не управляет.
4. `make accept SVC=site` — код 0 в профиле среды (прод или не-прод за замком).
