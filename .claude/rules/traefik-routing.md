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
- корень `${DOMAIN}` и `www` — сайт (`compose/site.yml`, профиль `site`): исключение из сабдоменного канона; его роутеры перебивают заглушку, `www` — редирект на корень
- `api` — backend
- `s3` / `minio` — MinIO S3 API / Console
- (опц) `admin`, `app`, `worker-status` и т.д. под клиентские нужды

Перед добавлением — `grep -r 'Host(\`<sub>' compose/`.

## Middleware chains

Определены в `configs/traefik/dynamic/middlewares.yml.tpl`:

| Chain | Назначение | Кто |
|---|---|---|
| `crowdsec@file` | WAF / IP-ban; отказ — 429, как у лимита частоты | **Все** публичные роуты |
| `secure-headers@file` | HSTS, nosniff, `Referrer-Policy`, `Permissions-Policy` (камера, микрофон и геолокация закрыты); состав общий для всех публичных роутов | Публичные HTTP-роуты сервисов (backend, landing) — label'ом роутера |
| `rate-limit@file` | Rate limit | Любой публичный POST/API |
| `compress@file` | Сжатие `br` / `gzip` | Роуты, отдающие HTML |
| `form-rate-limit@file`, `form-body-limit@file` | Лимит частоты и тела публичной формы | Роут публичного POST формы |
| `retry@file` | Повтор запроса при гонке пересоздания сервиса | Только идемпотентные роуты (GET / HEAD) |
| `www-to-apex@file` | Любой адрес роутера → `https://${DOMAIN}/<путь>` одним 301; хост regexp не называет — его выбрал роутер | Роут `www`, сервис — `noop@internal` |
| `deny-all@file` | 403 на edge, до сервиса | Путь без внешнего доступа |
| `staging@file` | Не-прод контур одной цепочкой: `staging-noindex` (`X-Robots-Tag`), затем `staging-auth` (basicAuth) — состав и порядок заданы в шаблоне | Роуты сайта — хвостом цепочки, пока задан `STAGING_BASIC_AUTH_USERS` |

**Правило:**
- Любой публичный сервис → минимум `crowdsec@file`.
- Публичный API (backend) → `crowdsec@file,secure-headers@file,rate-limit@file`.
- Роутер, который только редиректит, → `service: noop@internal`. Правило `Host()` принимает и `Host` с портом, заглавными или точкой в конце; запрос, на котором regexp редиректа не сработал, middleware передаёт дальше — в сервис роутера, мимо цепочек основного роутера.
- Внутренние сервисы — без traefik labels вообще.

Умолчания безопасности edge держит `make validate` (проверка `edge defaults`, по тексту — без docker и `.env`): у каждого роутера в labels есть цепочка, и она начинается с `crowdsec@file`; правило называет `Host`; сервис с Traefik-роутером не публикует порт; docker-сокет — только у `traefik`; `sanitizePath` не упомянут (умолчание Traefik — включён: по приведённому пути сопоставляются правила на путь); отрендеренный сосед каждого `.tpl` — под `.gitignore`.

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
