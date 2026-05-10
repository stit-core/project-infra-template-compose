---
description: Правила docker-compose и сервисов проектной инфры. Грузится при правке compose-фрагментов.
paths:
  - "compose/**"
  - "docker-compose.yml"
---

# Compose и сервисы

## Топология

Корневой `docker-compose.yml` — только определения сетей и общих volume-ов (если есть). Сервисы — отдельные файлы в `compose/<service>.yml`. Склеиваются `Makefile` через `COMPOSE_ARGS := -f docker-compose.yml $(addprefix -f ,$(wildcard compose/*.yml))`.

**Правило:** один сервис (или тесная группа: app + sidecar) = один файл. Не сваливай несвязанные сервисы.

## Сети

| Сеть | external | internal | Кто |
|---|---|---|---|
| `proxy` | — | нет | Traefik + публичные сервисы (backend) + outbound (vault-agent → vault.stit.tech, otel-agent → otel.stit.tech) |
| `backend-net` | — | да | postgres, backend, vault-agent (для bind-mount consumer'ов на одном хосте сеть формальна, но держим internal=true) |

Если новый сервис нужен только внутрь — `backend-net`. Если публичный — `proxy + backend-net` (backend-net чтобы видеть БД), не складывай только в `proxy`.

## Обязательные поля

- `image` с **закреплённой версией** (никаких `:latest`). PreEdit-хук блокирует.
- `container_name` совпадает с ключом сервиса.
- `restart: unless-stopped`.
- `healthcheck` (CMD на сам контейнер).
- `networks` — явный список.
- При наличии `volumes:` — секция `volumes:` в корне файла с named volume.

Опционально:
- `mem_limit` для прожорливых.
- `read_only: true` + `tmpfs: ["/tmp"]` для всего что не пишет в `/data`.
- `depends_on` с `condition: service_healthy`.

## Зависимость от vault-agent

**Любой сервис, читающий runtime-секреты** через `env_file: .runtime/secrets/<svc>.env`, обязан иметь:

```yaml
depends_on:
  vault-agent:
    condition: service_healthy
```

Vault-agent healthy = `.runtime/secrets/.ready` существует = шаблоны отрендерены. Без этого consumer стартует с пустым `env_file` и падает.

## Traefik labels

Публичный сервис — labels на самом сервисе:

```yaml
labels:
  traefik.enable: "true"
  traefik.docker.network: proxy
  traefik.http.routers.<name>.rule: Host(`<sub>.${DOMAIN}`)
  traefik.http.routers.<name>.entrypoints: websecure
  traefik.http.routers.<name>.tls: "true"
  traefik.http.routers.<name>.tls.certresolver: letsencrypt
  traefik.http.routers.<name>.middlewares: crowdsec@file,secure-headers@file,rate-limit@file
  traefik.http.services.<name>.loadbalancer.server.port: "<container-port>"
```

Подробнее — `.claude/rules/traefik-routing.md`.

## Volumes → backup

`scripts/backup.sh` берёт всё `<project>_*` volumes + `pg_dumpall` для postgres. Если добавляешь новый Postgres — добавь его в `pg_dumps=()` массив в `backup.sh`. Если добавляешь app, который пишет в named volume — он попадёт в backup автоматически по префиксу.

## После любой правки compose

`docker compose config -q` (PostToolUse-хук гонит автоматически). На сервере — `make deploy` → `git pull → render-configs → compose up -d --wait --wait-timeout 120`.

## Bump образа

**Никогда не меняй image-тег без явного OK.** Hook `pre-edit-image-bump.sh` блокирует. Bump = отдельный коммит `chore(<svc>): bump <name> to <version>` с release-notes в теле.
