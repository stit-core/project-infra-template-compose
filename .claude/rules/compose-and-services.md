---
name: compose-and-services
description: Инварианты compose-фрагментов — один сервис = один файл compose/<svc>.yml, pinned image (не :latest), обязательные restart/healthcheck/container_name/явные networks, секреты через ${VAR}-интерполяцию environment из .env (декларация в .env.example), environment фиксируется при CREATE (recreate на ротацию), internal-сеть + ports несовместимы, Node-сервис с рендером (сайт) — без read_only, с init и stop_grace_period. Грузится при правке compose/ или docker-compose.yml.
paths:
  - "compose/*.yml"
  - "docker-compose.yml"
---

# Compose и сервисы

## Топология

Корневой `docker-compose.yml` — только определения сетей и общих volume-ов (если есть). Сервисы — отдельные файлы в `compose/<service>.yml`. Склеиваются `Makefile` через `COMPOSE_ARGS := --env-file .env -f docker-compose.yml $(addprefix -f ,$(wildcard compose/*.yml))`.

**Правило:** один сервис (или тесная группа: app + sidecar) = один файл. Не сваливай несвязанные сервисы.

## Сети

| Сеть | external | internal | Кто |
|---|---|---|---|
| `proxy` | — | нет | Traefik, CrowdSec + публичные сервисы (backend, site, landing) + outbound (backup → внешний S3) |
| `backend-net` | — | да | postgres, backend |

Если новый сервис нужен только внутрь — `backend-net`. Если публичный и ходит в БД — `proxy + backend-net`; публичный без данных стека (сайт, заглушка) — только `proxy`.

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
- `healthcheck.start_interval` — частая проба на старте (Traefik строит роутеры контейнера после первой удачной). Ключу нужен Docker Engine ≥ 25: на старом движке compose не создаёт контейнер, а плагин compose до v2.20.2 не разбирает сам файл — тогда падает любой верб. Версию называет `make doctor` (`docker engine`).

## Node-сервисы с рендером

Образец — `compose/site.yml`: Node-процесс, который на старте штампует origin в выход сборки.

- `init: true` — PID 1 пересылает сигналы и прибирает процессы.
- `read_only` **несовместим** со штамповкой origin: entrypoint пишет в `/app/dist/client`. По той же причине
  нет тома на этом пути и `user:` — файлы принадлежат пользователю образа (`node`).
- `stop_grace_period` больше потолка дренажа образа (`SHUTDOWN_TIMEOUT_MS`, у сайта 15 с → 20 с): меньше —
  SIGKILL посреди дренажа.
- `mem_limit` и `NODE_OPTIONS=--max-old-space-size` ≈ 75 % лимита (512 МБ → 384): без потолка GC узнаёт о лимите
  поздно — OOM-kill вместо сборки мусора.
- `deploy.resources` не используется — лимиты ключами `mem_limit`, `cpus`; `replicas` несовместимы с `container_name`.
- Healthcheck — и у контейнера (`start_interval`), и у сервиса Traefik (`loadbalancer.healthcheck`): Traefik снимает
  сервер с балансировки, не дожидаясь трёх провалов пробы контейнера.
- Ключи профиля в `environment:` — с умолчанием (`${SITE_SMTP_URL:-}`): обязательная переменная (`${VAR:?}`)
  выключенного профиля роняет `compose config` всего стека. Обязательный env образа (`SITE_URL`) выводится из
  `.env` (`https://${DOMAIN}`), а не просится отдельным ключом.

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

Это про сервисы без Traefik-роутера (например, Postgres на db-хосте при split). Сервис с роутером порт не публикует: опубликованный порт — вход мимо edge, без `crowdsec@file`, лимитов и Host-роутинга; `make validate` такой compose отвергает.

## environment фиксируется при container CREATE, не start

Docker фиксирует environment в container config в момент **создания** контейнера,
не запуска. После смены значения в `.env` недостаточно `make restart SVC=` —
контейнер создан со старым ENV. `make deploy` (финальный `compose up -d`)
сравнивает интерполированный конфиг и пересоздаёт затронутые сервисы сам;
точечно — `make recreate SVC=<svc>`. Bind-mounted конфиги compose так НЕ
отслеживает — сервисы с изменёнными `configs/<dir>/` рестартует `deploy.sh`
по git-diff'у (traefik/crowdsec/postgres) от последнего удачного деплоя (`refs/deploy/ok`: её пишут
рестарт и конец деплоя — отказ между pull и рестартом диф не уносит) и ждёт их healthy. Исключение —
задания расписания edge (`configs/crowdsec/*.sh`) и список источников allowlist
(`configs/crowdsec/ai-bots.sources`): контейнер читает их из смонтированного каталога при каждом запуске.

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

`make validate` (compose syntax + yamllint + .tpl + .env coverage). На сервере — `make deploy` → `git pull → render-configs → compose up -d --wait --wait-timeout 180`.

## Bump образа

Image-тег меняется только с явного OK юзера: бамп — это выкатка новой версии в среду.

- **Инфра-образы** (traefik/postgres/minio/...) закреплены литеральной версией в `compose/<svc>.yml`. Bump = отдельный коммит `chore(<svc>): bump <name> to <version>` с release-notes в теле.
- **Образы сервис-репо** (backend, frontend, site, бот) тянутся как `${REGISTRY_HOST:-git.stit.tech}/${PROJECT_NAME}/<svc>:${<SVC>_TAG}` — тег живёт **строго в `.env`** на VPS. Bump = `make bump SVC=<svc> TAG=<tag>` (правит `.env` + force-recreate; compose сам пуллит отсутствующий образ; ждёт healthy). Образ не найден или не стал healthy — верб сам возвращает прежний тег в `.env`, поднимает сервис на нём и выходит с ошибкой. Rollback — тот же верб со старым тегом. Контракт с сервис-репо — `docs/reference/ecosystem.md`.
