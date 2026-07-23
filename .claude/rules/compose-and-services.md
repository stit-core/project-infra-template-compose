---
name: compose-and-services
description: Инварианты compose-фрагментов — один сервис = один файл compose/<svc>.yml, pinned image (не :latest), обязательные restart/healthcheck/container_name/явные networks, секреты через ${VAR}-интерполяцию environment из .env (декларация в .env.example), environment фиксируется при CREATE (recreate на ротацию), internal-сеть + ports несовместимы. Грузится при правке compose/ или docker-compose.yml.
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
| `proxy` | — | нет | Traefik + публичные сервисы (backend) + outbound (backup → внешний S3) |
| `backend-net` | — | да | postgres, backend |

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

## Секреты сервиса

**Любой сервис с runtime-секретами** получает их через `${VAR}`-интерполяцию
в `environment:` (значения — из `.env` на VPS):

```yaml
environment:
  POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
```

Каждый `${VAR}` обязан быть задекларирован в `.env.example` (активный или
закомментированный) с комментарием как сгенерировать — `make validate` ловит
пропуски. Inline-значений секретов в compose не бывает. См.
`.claude/rules/secrets-and-env.md`.

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

## environment фиксируется при container CREATE, не start

Docker фиксирует environment в container config в момент **создания** контейнера,
не запуска. После смены значения в `.env` недостаточно `make restart SVC=` —
контейнер создан со старым ENV. `make deploy` (финальный `compose up -d`)
сравнивает интерполированный конфиг и пересоздаёт затронутые сервисы сам;
точечно — `make recreate SVC=<svc>`. Bind-mounted конфиги compose так НЕ
отслеживает — сервисы с изменёнными `configs/<dir>/` рестартует `deploy.sh`
по git-diff'у (traefik/crowdsec/postgres).

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

**Никогда не меняй image-тег без явного OK.**

- **Инфра-образы** (traefik/postgres/minio/...) закреплены литеральной версией в `compose/<svc>.yml`. Bump = отдельный коммит `chore(<svc>): bump <name> to <version>` с release-notes в теле.
- **Бампаемые app-образы** (backend и любые будущие) параметризуются `${<SVC>_TAG}` — тег живёт **строго в `.env`** на VPS. Bump = `make bump SVC=<svc> TAG=<tag>` (правит `.env` + force-recreate; compose сам пуллит отсутствующий образ). Rollback — тот же верб со старым тегом.
