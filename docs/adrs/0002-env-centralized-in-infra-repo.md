# ADR 0002 — Production env централизован в `<project>/infra` repo

**Status:** accepted
**Date:** 2026-05-10

## Context

У клиентского проекта обычно несколько сервис-репо: `<org>/backend`, `<org>/frontend`, `<org>/worker`. Раньше каждый из них держал production-уровневый `.env.example` со ссылками на корп-инфру (OTEL_TENANT, OTEL_TOKEN-via-vault, и т.д.).

Это создавало дублирование и риск рассинхрона: документация в backend repo «где взять OTEL_TOKEN» могла отстать от actual flow в infra repo. Также в проекте может быть несколько backend-сервисов под одной инфрой — у каждого свой production-контракт хранить в своём repo не имеет смысла.

## Decision

Production env (всё что попадает в проектный VPS `.env` + всё что vault-agent рендерит в `.runtime/secrets/*.env`) живёт **только** в `<project>/infra` repo.

Сервис-репо (`<org>/backend`, `frontend`, `worker`) держат `.env.example` **только** для local-dev: безопасные дефолты для `go run` / `npm run dev` / etc., безусловно. Никаких упоминаний production-значений, корп-эндпоинтов, OIDC-flow.

## Why

- **Single source of truth:** один `.env.example` в infra repo + один набор vault-agent шаблонов. Контракт «какие env нужны бекенду в prod» доступен в одной точке.
- **Несколько сервисов под одной инфрой:** если завтра появится `<org>/billing-service`, ему нужен `BILLING_DB_DSN`, `BILLING_OTEL_SERVICE_NAME` etc. Эти добавки делаются в `<project>/infra/.env.example` + `configs/vault-agent/templates/billing.env.tpl` — атомарный set без хождения по 5 репо.
- **Сервис-разработчик не читает корп-доки:** backend-разработчику нужно «как мне локально поднять backend и потыкать ручки», не «как deploy в prod на корп-VPS». Минималистичный local-only `.env.example` это даёт.
- **Безопаснее:** меньше мест где случайно закоммитить реальный токен.

## Consequences

- `stit-infra/go-backend-template/.env.example` урезан до local-dev minimum.
- Production-контракт документирован в `stit-infra/infra/docs/project-secrets.md` (KV-layout + lazy-seed + AppRole), `stit-infra/infra/docs/ecosystem.md` (карта 4 репо), и в этом шаблоне (`CLAUDE.md` §Корп-контракт + `.env.example` + `.claude/rules/multi-env.md`).
- Если проекту нужны новые production env — правишь шаблон/копию `<project>/infra`, не сервис-репо.

## Когда пересмотреть

- Появляется требование что сервис-репо должен запускаться standalone в production (не как часть проектного стека). Тогда нужен "профиль" в `.env.example` с пометкой `# production-standalone`.
- Production env становится unmanageable большой (>50 переменных) — рассмотреть split на `core.env` + `feature.env`.
