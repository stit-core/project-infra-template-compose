# Ecosystem — место проектной VPS среди репо

Этот репо — **шаблон проектной инфры**: один форк (`<org>/infra`) = один клиентский проект,
один VPS на среду (`dev`/`prod`/...). Экосистема: 4 форкаемых шаблона `sftbmb-core/*`
(go-backend-template, spa-frontend-template, project-docs-template, project-infra-template-compose)
+ корп control-plane (`sftbmb-infra/infra`) + open-lib `sftbmb-core/golibinfra` + дизайн-система `sftbmb-core/ui-lib`.
Канон карты контрактов живёт в `sftbmb-infra/infra/docs/ecosystem.md` — здесь только роль *этого*
репо и его контракты.

## Репо

| Репо | Роль |
|---|---|
| `sftbmb-infra/infra` | Корп-VPS: Vault, OTel ingest, Gitea registry, CrowdSec. Source of truth контрактов. |
| `sftbmb-core/go-backend-template` | Шаблон Go-бэкенда. Форк `<org>/backend` собирает образ в `git.sftbmb.ru`. |
| `sftbmb-core/project-docs-template` | Шаблон продуктовой аналитики (business → projects: vision/persona/**surface** → interface → screens). Форк `<org>/docs`. |
| `sftbmb-core/project-infra-template-compose` | **Этот.** Шаблон проектной VPS — runtime стека одного проекта. Форк `<org>/infra`. |
| `<org>/infra` + `<org>/docs` + `<org>/backend` + ... | Клиентские форки. Один `<org>/infra` обслуживает N сервис-форков и читает `<org>/docs`. |

## Зависит от `sftbmb-infra/infra` (корп)

| Что корп выдаёт | Как | Адрес |
|---|---|---|
| AppRole `projects-<p>-<env>` + KV `kv/projects/<p>/<env>/*` (read-only) | `onboard-project.sh --name <p> --envs ...` | `vault.sftbmb.ru` |
| Telemetry ingest (OTLP, tenant routing) | otel-token в `kv/.../otel` | `otel.sftbmb.ru` |
| Source + container registry | deploy-key + PAT login | `git.sftbmb.ru` |
| CrowdSec whitelist egress-IP проектной VPS | `--source-ip <env>=<ip>` при онбординге | corp-side |

Один VPS = одна среда, своя AppRole-пара. Детали проектной стороны контракта (KV-layout,
lazy-seed, profile-opt-in) — `.claude/rules/multi-env.md`.

## Обслуживает `<org>/backend`

Runtime для клиентского образа `git.sftbmb.ru/<org>/backend:<tag>`. Deploy нового тега —
корп патчит `vault kv patch kv/projects/<p>/<env>/meta backend_tag=<tag>`, оператор делает
`make ship` (без MSG) → vault-agent перерендерит `meta`, deploy.sh force-recreate'нет backend.
`BACKEND_TAG` в `.env` не лежит — приходит из Vault.

## Sibling `<org>/docs` — продуктовый контекст

Продуктовая аналитика (vision, persona, **surface**, capability) живёт в `<org>/docs` (форк
`project-docs-template`), а инфра — здесь. Граница чистая и **односторонняя**: инфра-репо
**читает** продуктовый контекст, чтобы привязать стек к продукту, но **не редактирует** его;
авторская сторона продукта — только `<org>/docs` (через его deep-dive-скиллы).

**Конвенция размещения — sibling-checkout:** `<org>/docs` склонирован **рядом** с `<org>/infra`
(`../docs` относительно корня этого репо). Путь резолвится так:
1. `DOCS_REPO_PATH` из `.env.local`, если задан (override; см. `.claude/rules/env-local.md`);
2. иначе дефолт `../docs`.

**Кто что читает** (cross-repo, read-only):

| Скилл | Читает из `<org>/docs` | Зачем |
|---|---|---|
| `init-project` | `docs/projects/<slug>/{vision,surface}.md` | scope продукта на старте онбординга |
| `stack-deep-dive` | `docs/projects/<slug>/surface.md` | какие поверхности public → сабдомены/edge |
| `de-template` | `docs/projects/<slug>/vision.md § Problem` | кастомизация `CLAUDE.md` под проект |
| `smartdev` | наличие `<org>/docs` + `vision.md` | sanity при старте сессии |

`<slug>` — папка продукта в `<org>/docs/docs/projects/`. Если sibling-репо не склонирован —
скиллы деградируют gracefully (печатают next-step «склонируй `<org>/docs` рядом»), не падают.

## Что меняешь, тронув корп-контракт

Изменение, требующее действия корп-стороны (новый AppRole/env, seed KV, CrowdSec-whitelist,
новый сабдомен под LE-DNS) — оформляется CORP-HANDOFF-блоком (skill `/corp-handoff`). Проектная
сторона строго read-only на свой `kv/projects/<p>/<env>/*`; никаких write-прав у оператора.
