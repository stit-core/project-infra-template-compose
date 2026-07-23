---
name: add-service
description: Добавить новый сервис в проектную инфру (compose-фрагмент с pinned image / healthcheck / networks, опционально секреты через .env и traefik labels). Активируй на "/add-service", "добавь сервис X", "запили <name>", "новый контейнер".
---

# Skill: add-service

Чек-лист добавления сервиса в проектный compose-стек. Цель — каждый сервис из коробки имеет healthcheck, корректные networks, секреты через `${VAR}`-интерполяцию из .env (если нужно), traefik labels с WAF (если public).

В отличие от корп-вского `add-service` — здесь нет Authentik OIDC, alerting rules, prom scrape config (это корп-вещи, не проектные).

## Когда применять

- "Добавь worker / cache / search-index"
- "Поставь сервис X"
- "/add-service"

## Когда НЕ применять

- Изменение существующего сервиса (image bump, env change) — это правка одного файла.
- Внутренний sidecar к app — добавь в тот же `compose/<svc>.yml`.

## Шаги

### 0. Собрать вводные

- **Имя** (kebab-case): `worker`, `redis`, `search`.
- **Image + закреплённая версия**: `redis:7.4-alpine`. Никаких `:latest`.
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

3. Сформировать блок значений для `.env` на VPS через skill `/request-secret`
   (генерит пароли сам, печатает copy-paste блок). Без заполненных значений
   сервис стартует с пустым env и падает.

4. В compose добавь `profiles:` (если сервис opt-in):
   ```yaml
   profiles: [<profile>]
   ```

> **Corp-handoff.** Секреты — не corp-поверхность (живут в `.env` на VPS).
> `/corp-handoff` нужен только когда сервису нужен новый образ из registry
> `git.stit.tech` или меняется egress-IP под CrowdSec-whitelist.

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
   smartdev → triage). Контракт — в шапке `scripts/tools/smoke-run.sh`; образец — `10-host.sh`.
2. Префикс `90-` — после базовых `10-host`/`20-containers` (порядок лексикографический).

Так смок «растёт по мере развития инфры»: каждый новый сервис со своим сигналом докладывает файл.

### 7. Validate + ship

1. Локально: `make validate` — compose-syntax, yamllint, .tpl, .env coverage.
2. `make ship MSG="feat(<svc>): add <Service>"` — commit + `make check` (красный → пуш отменён) + push + (на main) ssh-deploy. Канон, не ручной push+deploy.
3. Verify: `make ps`, healthcheck зелёный, `https://<sub>.${DOMAIN}` доступен (если public); `make status` → `== Server ==` видит сервис.

## Чек-лист

- [ ] `compose/<svc>.yml` существует с pinned image
- [ ] Healthcheck указан
- [ ] `networks:` явный список
- [ ] Если public — `proxy` сеть + traefik labels с минимум `crowdsec@file`
- [ ] Если читает секреты — `${VAR}` в `environment:` + декларация в `.env.example` + блок значений для `.env` через `/request-secret`
- [ ] Все `${VAR}` есть в `.env.example`
- [ ] Если новый Postgres — добавлен ещё один `pg_dumpall` блок в `containers/backup/backup-now` (с другим `-h` host'ом и `--stdin-filename`)
- [ ] Если нужен новый образ из registry / новый egress-IP — оформлен `/corp-handoff`-блок **до** claim «готово»
- [ ] `make validate` зелёный
- [ ] (Если bespoke-сигнал вне `docker ps`) — `scripts/tools/smoke.d/90-<svc>.sh` для `== Server ==`

## Anti-patterns

- Сервис без healthcheck — `depends_on: service_healthy` для зависимых не сработает.
- `:latest` "временно" — никогда не временно.
- Public без `crowdsec@file` — открыт миру без WAF.
- Inline-значение секрета в compose (`password: hunter2`) — только `${VAR}` из `.env`.
- Прокидывал секрет через label/command — может попасть в логи.
