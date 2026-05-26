# Ecosystem — место проектной VPS среди 4 репо

Этот репо — **шаблон проектной инфры**: один форк (`<org>/infra`) = один клиентский проект,
один VPS на среду (`dev`/`prod`/...). Канон карты контрактов между всеми 4 репо живёт в
`stit-infra/infra/docs/ecosystem.md` — здесь только роль *этого* репо и его контракты.

## 4 репо

| Репо | Роль |
|---|---|
| `stit-infra/infra` | Корп-VPS: Vault, OTel ingest, Gitea registry, CrowdSec. Source of truth контрактов. |
| `stit-infra/go-backend-template` | Шаблон Go-бэкенда. Форк `<org>/backend` собирает образ в `git.stit.tech`. |
| `stit-infra/project-infra-template-compose` | **Этот.** Шаблон проектной VPS — runtime стека одного проекта. |
| `<org>/infra` + `<org>/backend` + ... | Клиентские форки. Один `<org>/infra` обслуживает N сервис-форков. |

## Зависит от `stit-infra/infra` (корп)

| Что корп выдаёт | Как | Адрес |
|---|---|---|
| AppRole `projects-<p>-<env>` + KV `kv/projects/<p>/<env>/*` (read-only) | `onboard-project.sh --name <p> --envs ...` | `vault.stit.tech` |
| Telemetry ingest (OTLP, tenant routing) | otel-token в `kv/.../otel` | `otel.stit.tech` |
| Source + container registry | deploy-key + PAT login | `git.stit.tech` |
| CrowdSec whitelist egress-IP проектной VPS | `--source-ip <env>=<ip>` при онбординге | corp-side |

Один VPS = одна среда, своя AppRole-пара. Детали проектной стороны контракта (KV-layout,
lazy-seed, profile-opt-in) — `.claude/rules/multi-env.md`.

## Обслуживает `<org>/backend`

Runtime для клиентского образа `git.stit.tech/<org>/backend:<tag>`. Deploy нового тега —
корп патчит `vault kv patch kv/projects/<p>/<env>/meta backend_tag=<tag>`, оператор делает
`make ship` (без MSG) → vault-agent перерендерит `meta`, deploy.sh force-recreate'нет backend.
`BACKEND_TAG` в `.env` не лежит — приходит из Vault.

## Что меняешь, тронув корп-контракт

Изменение, требующее действия корп-стороны (новый AppRole/env, seed KV, CrowdSec-whitelist,
новый сабдомен под LE-DNS) — оформляется CORP-HANDOFF-блоком (skill `/corp-handoff`). Проектная
сторона строго read-only на свой `kv/projects/<p>/<env>/*`; никаких write-прав у оператора.
