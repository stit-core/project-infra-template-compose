---
name: de-template
description: Развернуть форк project-infra-template-compose в самостоятельную проектную инфру по stable-артефактам docs/project — вывести COMPOSE_PROFILES из карты сервисов, прунить неиспользуемые compose/*.yml + vault-agent parts/templates, кастомить CLAUDE.md/README под проект, печатать cross-repo next-steps. Активируй когда юзер форкнул шаблон и говорит "/de-template", "разверни инфру", "де-темплейтизируй", "убери шаблонную мету", или когда init-project дошёл до развёртывания (vision+сервисы+стек stable). Движок skill-only — reviewable edits под этой процедурой. НЕ запускать на каноническом шаблоне.
---

# Skill: de-template (движок развёртывания инфры)

Превращает форк `project-infra-template-compose` в проектную инфру, которая ничего не помнит про
шаблон. Читает **stable** `docs/project/{vision,services/*,stack}` и: выводит `COMPOSE_PROFILES`
из карты сервисов, прунит неиспользуемые compose/vault-agent-фрагменты, кастомит идентичность,
печатает cross-repo next-steps. Движок **skill-only**: нет committed-скрипта — детерминированная
механика идёт как **reviewable edits** под этой процедурой.

Запускается **один раз** на форке. Финал — зелёный `make validate`/`make check` и репо без следов
«шаблона».

## Когда применять

- "/de-template" / "разверни инфру" / "сделай из шаблона свой проект"
- `/init-project` дошёл до развёртывания (vision + все hosted-сервисы + стек `stable`, валидатор зелён)

## Когда НЕ применять

- Артефакты ещё не `stable` — сначала `/service-deep-dive` + `/stack-deep-dive` (gate ниже).
- Репо уже де-темплейтизирован (свой origin `<org>/infra`, profiles выставлены) — обычный
  день-в-день через `/smartdev`.
- **Канонический шаблон** — никогда (guard ниже). Только форк/копия.

## Gate (проверить ДО любых правок)

1. **Не канонический шаблон.**
   ```bash
   git remote get-url origin
   ```
   Если origin == `…stit-infra/project-infra-template-compose…` И каталог — не временная тест-копия
   → СТОП. Запуск на шаблоне сносит его compose-фрагменты. Спроси юзера явно подтвердить, что это
   форк (`<client-org>/infra`) или throwaway-копия, прежде чем продолжать.
2. **Артефакты stable.**
   ```bash
   make project-check
   ```
   Зелёный И vision + все `services/*` + stack — `status: stable`, секции `Generates` непусты.
   Иначе СТОП → `/service-deep-dive`/`/stack-deep-dive`.

## Phase A — детерминированная механика

Каждый шаг — отдельный reviewable дифф.

### A.1 Вывести COMPOSE_PROFILES из карты сервисов

Из `docs/project/vision.md § Service map` + `services/*.md` (subtype + hosting):

| service-doc (hosting: here) | профиль |
|---|---|
| `datastore` postgres | `postgres` |
| `datastore` minio | `storage` |
| `backend` | `backend` |
| `frontend` (landing) | — (always-on) |

Собери активный набор. Пропиши дефолт в `.env.example` (`COMPOSE_PROFILES=<набор>`) и напомни
юзеру выставить тот же набор в `.env` после bootstrap (профили активируются только после seed'а
их KV — `.claude/rules/multi-env.md`).

### A.2 Прунить неиспользуемые compose/*.yml

Always-on (никогда не прунятся): `traefik` `crowdsec` `vault-agent` `otel-agent` `node-exporter`
`cadvisor` `landing`. Profiled — удаляй `compose/<name>.yml`, если сервис НЕ в карте:

```bash
# пример: проект без объектного хранилища → нет minio/backup
git rm compose/minio.yml compose/backup.yml
# нет своего backend-контейнера (только внешний API):
git rm compose/backend.yml
```

`COMPOSE_ARGS` в Makefile глобит `compose/*.yml` через `$(wildcard …)` — удаление файла само
исключает сервис, Makefile править не надо. `landing` оставляй, даже если frontend external
(дефолтная заглушка корня).

### A.3 Прунить vault-agent parts/templates под активный профиль-набор

`configs/vault-agent/agent.hcl.parts/`: `head.hcl`+`tail.hcl` всегда; `postgres.hcl`/`storage.hcl`/
`backend.hcl` — только под активный профиль. `configs/vault-agent/templates/`: `meta.env.tpl`+
`otel.env.tpl`+`traefik.yml.tpl` всегда; per profile — `postgres.env.tpl` (postgres),
`minio.env.tpl`+`backup.env.tpl` (storage), `backend.env.tpl` (backend). Удали неиспользуемые:

```bash
# пример: профили только postgres,backend → нет storage
git rm configs/vault-agent/agent.hcl.parts/storage.hcl \
       configs/vault-agent/templates/minio.env.tpl \
       configs/vault-agent/templates/backup.env.tpl
```

`scripts/render-configs.sh` собирает `agent.hcl` из parts под `COMPOSE_PROFILES` — лишних parts
после прунинга не остаётся.

### A.4 Кастомить идентичность

- `CLAUDE.md` — шапка/стек под имя проекта из vision; убрать «шаблон stit.tech», «копируется в
  `<client-org>/infra`», секцию «Что менять при копировании». Карта где-что и rules остаются.
- `README.md` (корневой) — проектная шапка вместо «шаблон проектной инфры»; убрать «форкни».
- Reference-доки (`docs/reference/*`, `docs/contributing.md`) — общие, остаются ссылками.

### A.5 Strip scaffolding

- `docs/getting-started.md` ([META] «как форкнуть шаблон») — удалить, форку не нужен.
- `.claude/plans/roadmap.md` — сбросить к пустому fork-start (history шаблона ≠ история форка):
  шапка + пустые `## Active` / `## Backlog`.
- `docs/project/{vision,services/*,stack}.md` — **оставить**: это теперь продуктовые доки проекта.
  `docs/project/_templates/` и deep-dive/init-project скилы — тоже остаются (система наследуется).

## Phase B — cross-repo next-steps (печатать, НЕ выполнять)

de-template **не делает** cross-repo действий — печатает чеклист оператору:

- **Внешние сервисы из карты** (`hosting: external`): форкнуть `<org>/backend` (go-backend-template) /
  `<org>/frontend`; backend-образ пушится в `git.stit.tech/<org>/backend`, tag → `meta.backend_tag`.
- **Корп-онбординг** (если ещё нет): `onboard-project.sh --name <p> --envs …` на корп-VPS
  (см. `docs/getting-started.md` Day-0) → AppRole + otel + meta.
- **Seed вторичных KV** под активные профили: чейн `/request-secret` на `db`/`minio`/`backup`/`jwt`/
  `oidc` → блок `vault kv put` корп-админу. Профиль активируется только после seed'а.
- **Edge** из `stack § Generates`: egress-IP VPS в crowdsec-whitelist (corp-handoff); сабдомены под LE-DNS.

## Verify

```bash
make validate    # фрагменты после прунинга консистентны
make check       # перед claim «готово»
```

Зелёный `make validate` на развёрнутом форке + отсутствие «шаблон»-нарратива — критерий движка.

## Anti-patterns

- ❌ Запуск на каноническом шаблоне (см. Gate) — сносит его compose/vault-agent-фрагменты.
- ❌ Старт до `stable`-артефактов — движку не из чего выводить профили/прунинг.
- ❌ Прунить always-on edge/телеметрию — это фиксированный фундамент.
- ❌ Выполнять cross-repo (форки/seed) самому — только печатать next-steps (граница продуктового слоя).
- ❌ `docker volume rm`/`down -v` при прунинге — не нужно и deny-blocked; удаляем только файлы фрагментов.
- ❌ Удалять `docs/project/*`-артефакты — это продуктовые доки проекта, не scaffolding.

## См. также

- `docs/project/README.md` — контракт артефактов + таблица «subtype→профиль».
- `.claude/skills/init-project/SKILL.md` — оркестратор, чейнит сюда последним шагом.
- `.claude/rules/multi-env.md` — profile-based opt-in, lazy-seed KV.
