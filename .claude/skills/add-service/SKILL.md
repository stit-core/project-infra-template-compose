---
name: add-service
description: Добавить новый сервис в проектную инфру — compose-фрагмент с pinned image / healthcheck / networks, опционально секреты через .env и traefik labels. Вызывай, когда в стек нужен новый контейнер — сервис из сиблинг-репо (frontend, бот, следующая поверхность сайта — Node-сервис на корневом домене), движок (cache, search, очередь) или воркер, в том числе по INFRA-HANDOFF из сервис-репо.
---

# Skill: add-service

Чек-лист добавления сервиса в проектный compose-стек. Цель — каждый сервис из коробки имеет healthcheck, корректные networks, секреты через `${VAR}`-интерполяцию из .env (если нужно), traefik labels с WAF (если public).

## Когда применять

- "Добавь worker / cache / search-index"
- Сервис из сиблинг-репо выходит в стек (frontend, бот, следующая поверхность сайта) — в том числе по
  INFRA-HANDOFF-блоку его `/release`; сайт первой поверхности (`compose/site.yml`) в стеке из коробки
- "/add-service"

## Когда не применять

- Изменение существующего сервиса (image bump, env change) — это правка одного файла.
- Внутренний sidecar к app — добавь в тот же `compose/<svc>.yml`.

## Шаги

### 0. Собрать вводные

- **Имя** (kebab-case): `worker`, `redis`, `search`.
- **Image + закреплённая версия**: `redis:7.4-alpine`. Никаких `:latest`.
  Образ сервис-репо (frontend, бот, поверхность сайта) — как `compose/backend.yml` или `compose/site.yml`:
  `image: ${REGISTRY_HOST:-git.stit.tech}/${PROJECT_NAME}/<svc>:${<SVC>_TAG}`, тег — `# <SVC>_TAG=`
  в `.env.example`, выкатка — `make bump SVC=<svc> TAG=<tag>` (контракт — `docs/reference/ecosystem.md`).
- **Сабдомен** (если public): `<sub>.${DOMAIN}`. Проверить: `grep -r 'Host(\`<sub>' compose/`.
- **Тип доступа**:
  - public с UI/API (требует WAF + rate-limit) → `crowdsec@file,secure-headers@file,rate-limit@file`
  - сервис-сервис → не в `proxy`, без traefik labels
- **Persistence**: нужен ли named volume?
- **Зависимости**: postgres? нужны ли секреты (новые `${VAR}` в .env)?
- **Ресурсы**: mem_limit?

### 1. Compose-фрагмент

Создай `compose/<svc>.yml`:

```yaml
volumes:
  <svc>-data:

services:
  <svc>:
    image: <repo>:<version>
    container_name: <svc>
    restart: unless-stopped
    environment:
      KEY1: value
      # Секреты — через ${VAR}-интерполяцию из .env (декларация в .env.example):
      # SVC_API_KEY: ${SVC_API_KEY}
    volumes:
      - <svc>-data:/data
    networks:
      - backend-net   # internal-only
      # - proxy       # если публичный
    healthcheck:
      # Для Go-сервисов на stit-core/golibinfra (форк stit-core/go-backend-template):
      # httpkit регистрирует /health (liveness) и /ready (с probes). Для
      # docker compose depends_on достаточно /health.
      test: ["CMD", "wget", "-qO-", "http://127.0.0.1:<port>/health"]
      interval: 30s
      timeout: 5s
      retries: 5
      start_period: 30s
    # labels:        # только если публичный
    #   traefik.enable: "true"
    #   traefik.docker.network: proxy
    #   traefik.http.routers.<svc>.rule: Host(`<sub>.${DOMAIN}`)
    #   traefik.http.routers.<svc>.entrypoints: websecure
    #   traefik.http.routers.<svc>.tls: "true"
    #   traefik.http.routers.<svc>.tls.certresolver: letsencrypt
    #   traefik.http.routers.<svc>.middlewares: crowdsec@file,secure-headers@file,rate-limit@file
    #   traefik.http.services.<svc>.loadbalancer.server.port: "<port>"
```

Используй `compose/backend.yml` как образец для public-сервиса с секретами; `compose/postgres.yml` — для internal с persistence.

### 1a. Вариант: Node-сервис на корневом домене

Следующая поверхность strategy рода `site` или `landing` — свой форк `<org>/site` и свой сервис с именем поверхности —
или другой Node-сервис с рендером на своём домене. Образец — `compose/site.yml` целиком; нормы — rules
`compose-and-services` («Node-сервисы с рендером») и `traefik-routing` («Корневой домен и www»):

- имя сервиса, `container_name`, профиль, `<SVC>_TAG` и роутеры — по имени поверхности; домен — свой (переменная
  `.env` с комментарием в `.env.example`), а не `${DOMAIN}` сайта первой поверхности;
- два роутера на домен: корень и `www`; `www` только редиректит — сервис `noop@internal` и свой `redirectRegex` на
  этот домен в `configs/traefik/dynamic/middlewares.yml.tpl`: домен — из `.env`, файл рендерится (общий
  `www-to-apex@file` ведёт на `${DOMAIN}`);
- обязательный env образа — origin (`SITE_URL: https://<домен>`) из `.env`; ключи профиля — с умолчанием `${…:-}`;
- `init: true`; без `read_only`, тома на выходе сборки и `user:` — их ломает штамповка origin; `stop_grace_period`
  больше дренажа образа; `mem_limit` и `--max-old-space-size` ≈ 75 %;
- healthcheck `/healthz` — у контейнера (`start_interval`) и у сервиса Traefik (`loadbalancer.healthcheck`);
- публичный POST — свой роутер с лимитом частоты и тела (`form-rate-limit@file`, `form-body-limit@file`), без
  `retry` и `compress`; `/_image` — `deny-all@file`;
- сервису, которому нужны камера, микрофон или геолокация (видеосвязь, карта «рядом со мной»), — свой
  headers-middleware вместо `secure-headers@file`: тот же состав и свой `permissionsPolicy`, а не послабление общего,
  иначе браузер молча отвечает `NotAllowedError`, в логах ничего;
- фрагмент — в `ROLE_FILES[edge]` (`scripts/deploy.sh`), запись `www` — в `scripts/preflight-dns.sh`.

Что знает только сервис `site`: allowlist ботов читает `robots.txt` сервиса `site`, смок edge и `make accept` —
тоже его. Вторую поверхность принимают списком «Приёмки первого деплоя» контракта сайта (`infra-handoff.md § 1.7`)
руками, а политику её ИИ-ботов сверяют с политикой `site` (allowlist у CrowdSec общий).

### 2. Секреты через .env (если нужны)

Если сервис читает секреты:

1. Добавить `${VAR}` в `environment:` сервиса:

   ```yaml
   environment:
     SVC_API_KEY: ${SVC_API_KEY}
     SVC_PASSWORD: ${SVC_PASSWORD}
   ```

2. Задекларировать переменные в `.env.example` (закомментированными, в секции
   профиля) с комментарием как сгенерировать / откуда взять.

3. Оператор дописывает значения в `.env` на VPS по `.env.example` (генерирует
   пароли где нужно). Без заполненных значений сервис стартует с пустым env и падает.

4. В compose добавь `profiles:` (если сервис opt-in):
   ```yaml
   profiles: [<profile>]
   ```

### 3. Конфиг сервиса (если нужен)

`configs/<svc>/<config>.yaml`. Если конфиг должен содержать значение из `.env` (не секрет, а bootstrap-параметр) — оформи `.tpl` + `${VAR}`, добавь в `.env.example` и в `scripts/render-configs.sh` (если рендер обрабатывается там).

### 4. Bootstrap-переменные в .env.example

Любой новый `${VAR}` в compose/configs — добавь в `.env.example` с комментарием.

### 5. Backup coverage

- Backup-контейнер дефолтом бэкапит **только** postgres (через `pg_dumpall`). Если новый сервис хранит state в named volume — он **не** попадает в backup автоматически.
- Если нужен — расширь `containers/backup/backup-now` (например `tar` volume → restic stdin).
- Если добавляешь ещё один Postgres — обнови `backup-now` чтоб бэкапить и его (либо отдельным host'ом в restic, либо ещё один pg_dumpall с другим target'ом).

### 6. Smoke-проверка (если нужна bespoke-проверка на входе cockpit)

Серверный смок (`== Server ==` в `make status`, см. skill `smartdev`) **автодискаверит**
здоровье всех compose-контейнеров из живого `docker ps` — обычному сервису с healthcheck
ничего регистрировать не надо, он подхватится сам.

Заводи drop-in только под **bespoke**-сигнал, которого нет в `docker ps` (глубина очереди,
лаг репликации, размер спец-volume, внешний endpoint):

1. `scripts/tools/smoke.d/90-<svc>.sh` — бежит **на хосте**, read-only, self exit 0; печатает
   блок `-- <svc> --` + строки; на проблеме — `ATTENTION: <msg>` в колонке 0 (его ловит
   smartdev → triage). Контракт — в шапке `scripts/tools/smoke-run.sh`; образец — `10-host.sh`, HTTP-сервис —
   `90-site.sh`.
2. Префикс `90-` — после базовых `10-host`/`20-containers` (порядок лексикографический).

Так смок «растёт по мере развития инфры»: каждый новый сервис со своим сигналом докладывает файл.

### 7. Validate + ship

1. Локально: `make validate` — compose-syntax, yamllint, .tpl, .env coverage, умолчания edge.
2. `make ship MSG="feat(<svc>): add <Service>"` — commit + `make check` (красный → пуш отменён) + push + (на main) ssh-deploy. Канон, не ручной push+deploy.
   Образ сервис-репо: профиль в `COMPOSE_PROFILES` и сразу `make bump SVC=<svc> TAG=<tag>` — профиль без тега роняет
   `make deploy` (FAIL `image tags` в `make doctor`).
3. Verify: `make ps`, healthcheck зелёный, `https://<sub>.${DOMAIN}` доступен (если public); `make status` → `== Server ==` видит сервис.

## Чек-лист

- [ ] `compose/<svc>.yml` существует с pinned image
- [ ] Healthcheck указан
- [ ] `networks:` явный список
- [ ] Если public — `proxy` сеть + traefik labels с минимум `crowdsec@file`
- [ ] Если читает секреты — `${VAR}` в `environment:` + декларация в `.env.example` + оператор дописал значения в `.env` на VPS
- [ ] Все `${VAR}` есть в `.env.example`
- [ ] Если новый Postgres — добавлен ещё один `pg_dumpall` блок в `containers/backup/backup-now` (с другим `-h` host'ом и `--stdin-filename`)
- [ ] Если образ сервис-репо — `${REGISTRY_HOST:-git.stit.tech}/${PROJECT_NAME}/<svc>:${<SVC>_TAG}` + `# <SVC>_TAG=` в `.env.example`
- [ ] `make validate` зелёный
- [ ] (Если bespoke-сигнал вне `docker ps`) — `scripts/tools/smoke.d/90-<svc>.sh` для `== Server ==`
- [ ] (Node-сервис на корне) — роутеры корня и `www` (`noop@internal`), `/healthz` у контейнера и Traefik, без `read_only`, origin из `.env`

## Anti-patterns

- Сервис без healthcheck — `depends_on: service_healthy` для зависимых не сработает.
- `:latest` "временно" — никогда не временно.
- Public без `crowdsec@file` — открыт миру без WAF.
- Inline-значение секрета в compose (`password: hunter2`) — только `${VAR}` из `.env`.
- Прокидывал секрет через label/command — может попасть в логи.
