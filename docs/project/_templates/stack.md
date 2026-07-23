---
id: project.stack
kind: stack
name: stack
status: draft
---

# Stack — инфра VPS

Cross-cutting инфры одного VPS под этот проект + **карта сервисов** (авторитетный инвентарь, из
которого `de-template` выводит `COMPOSE_PROFILES`) + среды. Продуктовый контекст (Problem / Users /
surfaces) живёт в соседнем `<org>/strategy` (`docs/projects/<slug>/`) — здесь не дублируется, читается
cross-repo.

## Service map
<Авторитетный перечень всех частей продукта на стороне инфры. Сервис с hosting: here крутится
контейнером в этом репо и получает `docs/project/services/<name>.md`; external — только строка
контекста (по ней `de-template` печатает cross-repo next-step). Из этой карты выводятся
`COMPOSE_PROFILES` (datastore→postgres/storage, backend→backend).>

| name | subtype | hosting | repo / source | назначение |
|---|---|---|---|---|
| backend | backend | here | `<org>/backend` (форк go-backend-template) | API |
| db | datastore | here | — (postgres в этом репо) | Postgres 17 |
| storage | datastore | here | — (minio в этом репо) | S3 + Console |
| web | frontend | external | `<org>/frontend` (CDN) | SPA |

## Domains
<Корневой `DOMAIN` и сабдомены: какие сервисы публичны и под какими именами
(`api.${DOMAIN}`, `s3.${DOMAIN}`, `minio.${DOMAIN}`). LE-сертификаты (acme_email/caserver из meta).>

## Edge
<Traefik v3 + CrowdSec: какие middleware на public-роутах, нужен ли source-IP whitelist
(egress IP этого VPS — corp-side, см. crowdsec-whitelist). Rate-limit / особые роутеры.>

## Networks
<Сети docker: `proxy` (наружу через traefik), `backend-net` (internal). Кастомные имена для
conflict-free на shared VPS. Кто в какой сети.>

## Backup
<restic-репозиторий (`RESTIC_REPOSITORY`), что бэкапится (pg_dumpall + volume'ы), расписание
crond, retention. `N/A` если storage-профиль не включён.>

## Observability
<Куда идут логи (docker logs). Метрики / трейсы — вне фундамента шаблона; если проекту нужны,
он поднимает свой стек сам. `N/A` если ничего сверх фундамента не решено.>

## Environments
<Какие среды у проекта (dev/staging/prod) — каждая = отдельный VPS с одним ENV. Чем отличаются
(домен, масштаб, какие сервисы включены). `N/A` если среда одна.>

## Generates
<Что de-template родит/изменит из этого артефакта:
- COMPOSE_PROFILES — выводится из Service map выше (subtype + hosting)
- configs/traefik/dynamic/* — клиент-специфичные routers/middlewares
- DOMAIN в .env.example
- crowdsec source-IP next-step (egress IP передать оператору корп-инфры для whitelist)
- acme_email/caserver — meta KV next-step
- для external-строк карты: cross-repo next-step (форкни <repo>)>
