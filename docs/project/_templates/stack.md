---
id: project.stack
kind: stack
name: stack
status: draft
---

# Stack — инфра VPS

Cross-cutting инфры одного VPS под этот проект. Профили НЕ описывает — их выводит `de-template`
из `vision § Service map`. Здесь — то, что общее для всего стека.

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
<otel-agent → otel.stit.tech (OTLP + Prom-scrape host-метрик), resource attrs, accountID/token
из kv otel. cadvisor + node-exporter (always-on).>

## Generates
<Что de-template родит/изменит из этого артефакта:
- configs/traefik/dynamic/* — клиент-специфичные routers/middlewares
- DOMAIN в .env.example
- crowdsec source-IP next-step (corp-handoff: egress IP в whitelist)
- acme_email/caserver — meta KV next-step
(COMPOSE_PROFILES здесь НЕ задаётся — выводится из service-map)>
