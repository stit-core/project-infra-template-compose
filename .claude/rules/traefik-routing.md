---
description: Правила маршрутизации Traefik в проектной инфре. Грузится при работе с Traefik labels или dynamic-конфигом.
paths:
  - "compose/**"
  - "docker-compose.yml"
  - "configs/traefik/**"
---

# Traefik routing

## Сабдомены

Все сервисы под `<name>.${DOMAIN}` (`DOMAIN` — клиентский домен из `.env`). Не path-based — это ломает редиректы и cookies.

Стандартные имена в шаблоне:
- `api` — backend
- (опц) `admin`, `app`, `worker-status` и т.д. под клиентские нужды

Перед добавлением — `grep -r 'Host(\`<sub>' compose/`.

## Middleware chains

Определены в `configs/traefik/dynamic/middlewares.yml.tpl`:

| Chain | Назначение | Кто |
|---|---|---|
| `crowdsec@file` | WAF / IP-ban | **Все** публичные роуты |
| `secure-headers@file` | HSTS + frame-deny + nosniff | Применяется глобально на `websecure` |
| `rate-limit@file` | Rate limit | Любой публичный POST/API |

**Правило:**
- Любой публичный сервис → минимум `crowdsec@file`.
- Публичный API (backend) → `crowdsec@file,secure-headers@file,rate-limit@file`.
- Внутренние сервисы — без traefik labels вообще.

В шаблоне нет Authentik forward-auth — на проектной стороне нет IDP. Если клиенту нужен SSO — это отдельная интеграция, либо через корп-Authentik с redirect_uri на проектный домен.

## TLS

`websecure` entrypoint всегда применяет `secure-headers` глобально (`configs/traefik/traefik.yml`). LE-сертификаты выпускаются HTTP-01 challenge, хранятся в `traefik-letsencrypt` volume → попадают в restic backup. ACME email — `${ACME_EMAIL}`.

## Dashboard Traefik

**НЕ expose'им** — dashboard на проектной стороне не нужен (single-tenant), `api.insecure: true` отключён в `traefik.yml`. Если для отладки нужен — точечно через `docker exec traefik wget ... /api/...`.

## gRPC / WebSocket

gRPC — `&& Headers(\`Content-Type\`, \`application/grpc\`)` рулом + `loadbalancer.server.scheme: h2c`. WebSocket работает прозрачно.

## После правки

- `compose/*.yml` labels → `make deploy` (Traefik watcher подхватит).
- `configs/traefik/traefik.yml` (static) → **рестарт** Traefik (`make restart SVC=traefik`).
- `configs/traefik/dynamic/*.yml` (dynamic) → подхватится через `watch: true`. `.tpl` рендерятся через `scripts/render-configs.sh`.
