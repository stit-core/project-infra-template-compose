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
`COMPOSE_PROFILES` (datastore→postgres/storage, backend→backend, сайт `<org>/site` → site).>

| name | subtype | hosting | repo / source | назначение |
|---|---|---|---|---|
| backend | backend | here | `<org>/backend` (форк go-backend-template) | API |
| db | datastore | here | — (postgres в этом репо) | Postgres 17 |
| storage | datastore | here | — (minio в этом репо) | S3 + Console |
| site | frontend | here | `<org>/site` (форк seo-frontend-template) | индексируемый сайт на корне |
| web | frontend | external | `<org>/frontend` (CDN) | SPA |

## Domains
<Корневой `DOMAIN` и сабдомены: какие сервисы публичны и под какими именами
(корень и `www.${DOMAIN}` → сайт, `api.${DOMAIN}`, `s3.${DOMAIN}`, `minio.${DOMAIN}`). LE-сертификаты
(`ACME_EMAIL`/`ACME_CASERVER` — в `.env` на VPS).>

## Edge
<Traefik v3 + CrowdSec: какие middleware на public-роутах (`crowdsec@file`, `secure-headers@file`,
`rate-limit@file` или кастомные). Rate-limit / особые роутеры (у сайта — форма, `/_image`, `www`).
ИИ-боты: allowlist сетей вендоров по `robots.txt` сайта (`ai-bots.sources`).>

## Networks
<Сети docker: `proxy` (наружу через traefik), `backend-net` (internal). Кастомные имена для
conflict-free на shared VPS. Кто в какой сети.>

## Backup
<restic-репозиторий (`RESTIC_REPOSITORY`), что бэкапится (pg_dumpall + volume'ы), расписание
crond, retention. `N/A` если storage-профиль не включён.>

## Observability
<Куда идут логи (docker logs; журнал доступа Traefik — `/var/log/traefik/access.log`, его читает CrowdSec).
Смок `make status` — хост, контейнеры, edge, сайт (`/healthz`, `robots.txt`, `sitemap.xml`). Метрики / трейсы — вне
фундамента шаблона; если проекту нужны, он поднимает свой стек сам. `N/A` если ничего сверх фундамента не решено.>

## Environments
<Какие среды у проекта (dev/staging/prod) — каждая = отдельный VPS с одним ENV. Чем отличаются
(домен, масштаб, какие сервисы включены; сайт не-прод среды — `ROBOTS_POLICY=noindex` и замок). `N/A` если
среда одна.>

## Generates
<Что de-template родит/изменит из этого артефакта:
- COMPOSE_PROFILES — выводится из Service map выше (subtype + hosting)
- configs/traefik/dynamic/* — клиент-специфичные routers/middlewares
- DOMAIN в .env.example
- ACME next-step: ACME_EMAIL/ACME_CASERVER в .env на VPS
- для external-строк карты: cross-repo next-step (форкни <repo>)>
