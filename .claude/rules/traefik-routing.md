---
name: traefik-routing
description: Инварианты маршрутизации Traefik — сабдомены `<name>.${DOMAIN}` (не path-based), `crowdsec@file` middleware на всех публичных роутах (API ещё +secure-headers+rate-limit), internal-сервисы без traefik-labels, dashboard не expose'им. Грузится при правке configs/traefik/ или compose/*.yml с traefik-labels.
paths:
  - "compose/*.yml"
  - "docker-compose.yml"
  - "configs/traefik/**"
---

# Traefik routing

## Сабдомены

Все сервисы под `<name>.${DOMAIN}` (`DOMAIN` — клиентский домен из `.env`). Не path-based — это ломает редиректы и cookies.

Стандартные имена в шаблоне:
- корень `${DOMAIN}` — landing (роутер с `priority: 1`, любой явный роутер на корень его перебивает)
- `api` — backend
- `s3` / `minio` — MinIO S3 API / Console
- (опц) `admin`, `app`, `worker-status` и т.д. под клиентские нужды

Перед добавлением — `grep -r 'Host(\`<sub>' compose/`.

## Middleware chains

Определены в `configs/traefik/dynamic/middlewares.yml.tpl`:

| Chain | Назначение | Кто |
|---|---|---|
| `crowdsec@file` | WAF / IP-ban | **Все** публичные роуты |
| `secure-headers@file` | HSTS, nosniff, XSS-filter, referrer-policy | Публичные HTTP-роуты сервисов (backend, landing) — label'ом роутера |
| `rate-limit@file` | Rate limit | Любой публичный POST/API |

**Правило:**
- Любой публичный сервис → минимум `crowdsec@file`.
- Публичный API (backend) → `crowdsec@file,secure-headers@file,rate-limit@file`.
- Внутренние сервисы — без traefik labels вообще.

Forward-auth в стеке нет — IDP на проектной стороне нет. Служебный UI (например, MinIO Console) закрыт `crowdsec@file` + `rate-limit@file`; сузить доступ — IP-allowlist'ом или отключением роутера.

## TLS

`websecure` entrypoint по умолчанию выпускает сертификаты резолвером `letsencrypt`; middleware глобально на entrypoint не вешаются — каждый роутер перечисляет свои label'ом (static-конфиг рендерится render-configs.sh из `configs/traefik/traefik.yml.tpl` в `configs/traefik/traefik.yml`, gitignored). LE-сертификаты выпускаются HTTP-01 challenge, `acme.json` хранится в volume `traefik-acme`. Он **не** бэкапится (restic берёт только `pg_dumpall`) — при потере VPS сертификаты перевыпускаются заново. `email`/`caServer` приходят из `.env` (`ACME_EMAIL`/`ACME_CASERVER`).

## Dashboard Traefik

Dashboard не expose'им — на проектной стороне он не нужен (single-tenant): в static-конфиге `api.insecure: false`, роутера на dashboard нет. Если для отладки нужен — точечно через `docker exec traefik wget ... /api/...`.

## gRPC / WebSocket

gRPC — `&& Headers(\`Content-Type\`, \`application/grpc\`)` рулом + `loadbalancer.server.scheme: h2c`. WebSocket работает прозрачно.

## После правки

- `compose/*.yml` labels → `make deploy` (Traefik watcher подхватит).
- `configs/traefik/traefik.yml.tpl` (static-конфиг, security-sensitive; рендерится в `configs/traefik/traefik.yml`) → **рестарт** Traefik (`make restart SVC=traefik`; при deploy git-diff по `configs/traefik/` рестартует его сам).
- `configs/traefik/dynamic/*.yml` (dynamic) → подхватится через `watch: true`. `.tpl` рендерятся через `scripts/render-configs.sh`.
