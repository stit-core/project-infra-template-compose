---
name: compose-and-services
description: Инварианты compose-фрагментов — один сервис = один файл compose/<svc>.yml, pinned image (не :latest), обязательные restart/healthcheck/container_name/явные networks, depends_on vault-agent healthy для consumer'ов секретов, env_file фиксируется при CREATE (force-recreate на смену), internal-сеть + ports несовместимы. Грузится при правке compose/ или docker-compose.yml.
paths:
  - "compose/*.yml"
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

- `image` с **закреплённой версией** (никаких `:latest`).
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

## `internal: true` сеть и `ports:` несовместимы

`backend-net` помечена `internal: true` — docker не делает входящий NAT на host-mapped порты для контейнеров, у которых **только** internal-сеть. То есть:

```yaml
networks:
  - backend-net
ports:
  - "8080:8080"        # ❌ декларация есть, реально port forwarding не работает
```

`docker port <svc>` пуст, `ss -tlnp` не показывает 8080, `curl 127.0.0.1:8080` → connection refused.

**Правило:** если у сервиса есть `ports:`, обязательно добавь не-internal сеть (`proxy`) рядом с `backend-net`:

```yaml
networks:
  - proxy            # для published-port forwarding
  - backend-net      # internal-traffic к postgres/minio/etc
```

Backend в шаблоне идёт через traefik (labels), не через `ports:` — там это не блокер. Когда DNS не поднят и сервис временно торчит портом — обязательно proxy.

## env_file читается при container CREATE, не start

Docker фиксирует содержимое `env_file:` в container config в момент **создания** контейнера, не запуска. Это две практические импликации:

1. **На свежем bootstrap'е** vault-agent ещё не отрендерил `.runtime/secrets/*.env`, а compose уже валидирует **существование** этих путей до старта любого сервиса. Решение — `scripts/deploy.sh` делает `touch` пустых файлов перед `compose up`.

2. **После изменения vault-template** (добавил поле, переименовал переменную) недостаточно сделать `docker restart <consumer>` — контейнер уже создан со старым ENV. Нужен `compose up -d --force-recreate <consumer>`. `scripts/deploy.sh` делает это автоматически когда видит изменения в `configs/vault-agent/templates/*.tpl` или `configs/vault-agent/agent.hcl.parts/*.hcl` между prev/new sha, а также на смену активного `COMPOSE_PROFILES` (хранит набор в `.runtime/.profiles-prev`).

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

Backup-контейнер (`containers/backup/`) бэкапит **только** postgres через `pg_dumpall`. Named volumes (`<project>_*`) **не** попадают в backup автоматически. Если хочешь покрыть volume — расширь `containers/backup/backup-now` (tar + restic --stdin). Если добавляешь второй Postgres — там же добавь ещё один `pg_dumpall` блок.

## После любой правки compose

`make validate` (compose syntax + yamllint + .tpl + .env coverage). На сервере — `make deploy` → `git pull → render-configs → compose up -d --wait --wait-timeout 120`.

## Bump образа

**Никогда не меняй image-тег без явного OK.** Bump = отдельный коммит `chore(<svc>): bump <name> to <version>` с release-notes в теле.
