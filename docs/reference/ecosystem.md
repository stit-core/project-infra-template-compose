# Ecosystem — место проектной VPS среди репо

Этот репо — **шаблон проектной инфры**: один форк (`<org>/infra`) = один клиентский проект,
один VPS на среду (`dev`/`prod`/...). Экосистема — 6 форкаемых шаблонов `stit-core/`
(`corp-infra-template`, `go-backend-template`, `spa-frontend-template`,
`telegram-bot-template`, `business-strategy-template`, `project-infra-template-compose`) + 2 общие библиотеки
`stit-core/golibinfra` (Go) и `stit-core/ui-lib` (`@stit/ui`, frontend design-system).
Корп control-plane — это репо `corp-infra-template` (managed = инстанс на `*.stit.tech`;
self-hosted = ваш форк). Канон карты контрактов живёт в
`corp-infra-template/docs/ecosystem.md` — здесь только роль *этого* репо и его контракты.

## Репо

| Репо | Роль |
|---|---|
| `stit-core/corp-infra-template` | Корп control-plane: Gitea registry, CrowdSec, SSO. Source of truth контрактов. Managed = инстанс на `*.stit.tech`, self-hosted = ваш форк. |
| `stit-core/go-backend-template` | Шаблон Go-бэкенда. Форк `<org>/backend` собирает образ в `git.stit.tech`. |
| `stit-core/business-strategy-template` | Шаблон бизнес-стратегии (business → ajtbd → swot → hypothesis-map → опц. продукт `projects/<slug>/`: vision/**surface** → interface → screens). Форк `<org>/strategy`. |
| `stit-core/project-infra-template-compose` | **Этот.** Шаблон проектной VPS — runtime стека одного проекта. Форк `<org>/infra`. |
| `<org>/infra` + `<org>/strategy` + `<org>/backend` + ... | Клиентские форки. Один `<org>/infra` обслуживает N сервис-форков и читает `<org>/strategy`. |

## Зависит от корп control-plane (`corp-infra-template`)

| Что корп выдаёт | Как | Адрес |
|---|---|---|
| Source + container registry | deploy-key + PAT login | `git.stit.tech` |
| CrowdSec whitelist egress-IP проектной VPS | `configs/crowdsec/whitelists.yaml` corp-side | corp-side |

Адрес `git.stit.tech` — managed-инстанс; на self-hosted это адрес вашего форка
`corp-infra-template`, задаётся через `REGISTRY_HOST` (см. `.env.example`).
Вендор-лока нет.

Один VPS = одна среда, свой `.env` (единственный источник секретов — корп в них
не участвует). Детали проектной стороны (`.env`-контракт, profile-opt-in) —
`.claude/rules/multi-env.md`.

## Обслуживает сервис-форки `<org>/{backend,frontend,<bot>}`

Runtime для клиентских образов `git.stit.tech/<org>/<svc>:<tag>`. Из коробки в стеке —
`compose/backend.yml`; frontend / telegram-бот / прочие сервисы проекта добавляются
`/add-service` по карте сервисов `docs/project/stack.md`. Deploy нового тега любого сервиса —
`make bump SVC=<svc> TAG=<tag>`: правит `<SVC>_TAG` в `.env` на VPS + force-recreate, compose
сам пуллит образ. Image-теги живут **строго в `.env`** (конвенция `<SVC>_TAG`: `BACKEND_TAG`,
`FRONTEND_TAG`, `BOT_TAG`, …) — корп-сторона в rollout'е тега не участвует. Сервис-репо
останавливаются на image-in-registry (их `/release`) — деплоем занимается только этот репо.

Этот репо — операционный хаб проекта: задачи входят сюда, агенты расходятся по сиблингам
(`CLAUDE.md § Оркестрация`; канон — `corp-infra-template/docs/ecosystem.md § Операционная
модель агентов`).

## Sibling `<org>/strategy` — продуктовый контекст

Продуктовый слой (vision, **surface**, capability) одного продукта живёт в `<org>/strategy` (форк
`business-strategy-template` — репо бизнес-стратегии, в `docs/projects/<slug>/`), а инфра — здесь.
Граница чистая и **односторонняя**: инфра-репо **читает** продуктовый контекст, чтобы привязать
стек к продукту, но **не редактирует** его; авторская сторона продукта — только `<org>/strategy`
(через его deep-dive-скиллы).

**Конвенция размещения — sibling-checkout:** все форки одной org склонированы **рядом**
(`~/git/<org>/{strategy,infra,backend,frontend,<bot>}`). Путь любого соседа резолвится так:
1. `<NAME>_REPO_PATH` из `.env.local`, если задан (override; `STRATEGY_REPO_PATH`,
   `BACKEND_REPO_PATH`, … — см. `.claude/rules/env-local.md`);
2. иначе дефолт `../<name>` (`../strategy`, `../backend`, `../frontend`; имя бот-репо — по
   карте сервисов `docs/project/stack.md § Service map`).

**Кто что читает** (cross-repo, read-only):

| Скилл | Читает из `<org>/strategy` | Зачем |
|---|---|---|
| `init-project` | `docs/projects/<slug>/{vision,surface}.md` | scope продукта на старте онбординга |
| `stack-deep-dive` | `docs/projects/<slug>/surface.md` | какие поверхности public → сабдомены/edge |
| `de-template` | `docs/projects/<slug>/vision.md § Problem` | кастомизация `CLAUDE.md` под проект |
| `smartdev` | наличие `<org>/strategy` + `vision.md` | sanity при старте сессии |

`<slug>` — папка продукта в `<org>/strategy/docs/projects/`. Если sibling-репо не склонирован —
скиллы деградируют gracefully (печатают next-step «склонируй `<org>/strategy` рядом»), не падают.

## Что меняешь, тронув корп-контракт

Изменение, требующее действия корп-стороны (registry-доступ, CrowdSec-whitelist
egress-IP), передаётся оператору корп-инфры out-of-band. Секреты — не корп-контракт:
оператор пишет их сам в `.env` на VPS по контракту `.env.example`.
