---
name: init-project
description: Оркестратор онбординга проектной инфры из шаблона — ведёт путь vision → проектирование hosted-сервисов (service-deep-dive) → проектирование инфра-стека (stack-deep-dive) → de-template, пока форк не перестанет помнить про шаблон. Активируй когда юзер форкнул project-infra-template-compose и говорит "/init-project", "инициализируй проект", "развернуть инфру из шаблона", "с чего начать новый проект", или когда видишь свежий форк (origin ещё template, нет stable docs/project/vision.md). Сам не проектирует и не де-темплейтит — чейнит специализированные скиллы по порядку.
---

# Skill: init-project (онбординг-оркестратор)

Дирижёр пути «форк шаблона инфры → своя проектная инфра». Стоит **уровнем выше** `init-service`
бэкенда: тот разворачивает один сервис, этот — весь продукт (карта сервисов → инфра VPS). Не
проектирует/не де-темплейтит сам, а **ведёт по этапам и чейнит** специализированные скиллы, держа
фокус: docs первичны, инфра разворачивается по ним. Один проход доводит до инфры, которая ничего
не помнит про шаблон.

Полное описание пути для человека — `docs/getting-started.md`; этот скилл его исполняет на слое
`docs/project/`. Граница: cross-repo (форки backend/frontend, seed секретов) — только next-steps,
не выполнение.

## Когда применять

- "/init-project" / "инициализируй проект" / "развернул форк инфры, что дальше"
- Свежий форк: origin ещё `…project-infra-template-compose…` ИЛИ нет `docs/project/vision.md` со
  `status: stable`
- Юзер: «хочу развернуть инфру под новый клиентский проект»

## Когда НЕ применять

- Инфра уже инициализирована (свой origin `<org>/infra`, `vision.md` stable, профили выставлены) —
  это обычный день-в-день, иди в `/smartdev`.
- Юзер хочет добавить один сервис в уже-свою инфру — это `/add-service`, не онбординг.
- Поднять чистый VPS под уже-инициализированную инфру — это `/bootstrap-vps`.

## Pre-flight

- [ ] Форк создан (Gitea → **Use this template** → `<org>/infra`), склонирован.
- [ ] `make setup` прогнан (git-хуки commit-msg + pre-commit).
- [ ] Если нет — подскажи шаги 0 из `docs/getting-started.md`, дальше не иди.

## Этапы (чейнить по порядку, не делать самому)

### 1. Vision + карта сервисов

- `cp docs/project/_templates/vision.md docs/project/vision.md`.
- Через `AskUserQuestion` добей `Problem`/`Users`/`Service map`/`Boundaries`/`Environments`. Ключевой
  выход — **Service map**: перечень всех частей продукта с `subtype`/`hosting`/repo. Именно карта
  определяет, сколько будет `service-deep-dive` и какие профили родит `de-template`.
- Промоуть `vision.md` → `stable` (валидатор зелёный).

### 2. Спроектировать hosted-сервисы → `service-deep-dive`

- Для каждого сервиса карты с `hosting: here`: `cp _templates/service.md docs/project/services/<name>.md`,
  заполни frontmatter (subtype/hosting/name).
- **Чейнь в `/service-deep-dive <name>`**: волны inside-out до `status: stable`.
- Сервисы `hosting: external` (frontend-SPA/CDN, backend-код-репо) — service-doc НЕ заводим, они
  остаются строкой карты; для них шаг 4 печатает cross-repo next-steps.
- Gate: `make project-check` зелёный по всем `services/*`.

### 3. Спроектировать инфра-стек → `stack-deep-dive`

- `cp _templates/stack.md docs/project/stack.md`.
- **Чейнь в `/stack-deep-dive`**: domains/edge/networks/backup/observability + `Generates` до `stable`.
- Gate: `make project-check` зелёный.

### 4. Развернуть инфру → `de-template`

- Gate перед запуском: vision + все hosted-сервисы + стек `stable`, `make project-check` зелёный.
- **Чейнь в `/de-template`**: выводит `COMPOSE_PROFILES` из карты, прунит неиспользуемые
  `compose/*.yml` + vault-agent parts/templates, кастомит `CLAUDE.md`/README, сбрасывает roadmap,
  печатает cross-repo next-steps. Механика — reviewable diff.

### 5. Финал

`make check` зелёный → инфра больше не помнит про шаблон. Сообщи юзеру: онбординг закрыт, дальше —
`/bootstrap-vps` поднять VPS под env + cross-repo next-steps из `de-template` (форки, seed KV,
корп-онбординг). `docs/getting-started.md` ([META]) удалён движком.

## Что init-project НЕ делает

- ❌ Не интервьюирует по сервисам/стеку сам — это `service-deep-dive`/`stack-deep-dive`.
- ❌ Не прунит инфру руками и не де-темплейтит — это `de-template` (по stable-артефактам).
- ❌ Не запускает `de-template` до зелёного валидатора (gate).
- ❌ Не выполняет cross-repo (форки/seed/онбординг) — только печатает next-steps (граница слоя).

## Anti-patterns

- ❌ Прунить `compose/*` / править `.env.example` до того как спроектированы артефакты.
- ❌ Заводить service-doc для внешнего сервиса (`hosting: external`) — он только в карте.
- ❌ Дублировать процедуру deep-dive внутри этого скилла — он только дирижёр.
- ❌ Пропускать vision ради «быстро прунить compose» — карта первична, иначе движку не из чего выводить профили.
