---
name: add-service
description: Добавить новый сервис в проектную инфру (compose-фрагмент с pinned image / healthcheck / networks, опционально vault-agent template и traefik labels). Активируй на "/add-service", "добавь сервис X", "запили <name>", "новый контейнер".
---

# Skill: add-service

Чек-лист добавления сервиса в проектный compose-стек. Цель — каждый сервис из коробки имеет healthcheck, корректные networks, доступ к секретам через vault-agent (если нужно), traefik labels с WAF (если public).

В отличие от корп-вского `add-service` — здесь нет Authentik OIDC, alerting rules, prom scrape config (это всё на корп-стороне через otel-routing).

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
- **Зависимости**: postgres? нужны ли секреты из Vault?
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
    # Если читает секреты — добавь env_file и depends_on на vault-agent.
    # env_file:
    #   - .runtime/secrets/<svc>.env
    # depends_on:
    #   vault-agent:
    #     condition: service_healthy
    volumes:
      - <svc>-data:/data
    networks:
      - backend-net   # internal-only
      # - proxy       # если публичный
    healthcheck:
      # Для Go-сервисов на sftbmb-core/golibinfra (форк sftbmb-core/go-backend-template):
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

### 2. Секреты через vault-agent (если нужны)

Если сервис читает секреты:

1. Создать `configs/vault-agent/templates/<svc>.env.tpl`. Синтаксис — consul-template,
   а не shell envsubst: `(env "PROJECT_NAME")` / `(env "ENV")`, не `${...}`. KV v2 API
   требует префикс `kv/data/...` в path (в `vault kv put`-CLI префикс не нужен —
   см. `.claude/rules/secrets-and-env.md`).

   ```
   {{ with secret (printf "kv/data/projects/%s/%s/<svc>" (env "PROJECT_NAME") (env "ENV")) -}}
   KEY1={{ .Data.data.key1 }}
   KEY2={{ .Data.data.key2 }}
   {{- end }}
   ```

2. Добавить блок в `configs/vault-agent/agent.hcl.parts/<profile>.hcl` (либо `head.hcl` если сервис always-on; render-configs.sh склеит финальный `agent.hcl` под активный `COMPOSE_PROFILES`):

   ```hcl
   template {
     source      = "/etc/vault-agent/templates/<svc>.env.tpl"
     destination = "/secrets/<svc>.env"
     perms       = 0400
   }
   ```

3. Запросить seed KV-объекта через skill `/request-secret` — оно сформирует stdout-блок `vault kv put kv/projects/<p>/<env>/<svc> field=...` для корп-админа. Без seed'а vault-agent залипнет в retry-loop'е на этом template (preflight также warning'нёт).

4. В compose добавь `profiles:` (если сервис opt-in), `env_file`, `depends_on`:
   ```yaml
   profiles: [<profile>]
   env_file:
     - .runtime/secrets/<svc>.env
   depends_on:
     vault-agent:
       condition: service_healthy
   ```

### 3. Конфиг сервиса (если нужен)

`configs/<svc>/<config>.yaml`. Если конфиг должен содержать значение из `.env` (не секрет, а bootstrap-параметр) — оформи `.tpl` + `${VAR}`, добавь в `.env.example` и в `scripts/render-configs.sh` (если рендер обрабатывается там).

### 4. Bootstrap-переменные в .env.example

Любой новый `${VAR}` в compose/configs (не в vault-agent template) — добавь в `.env.example` с комментарием.

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
- [ ] Если читает секреты — `env_file` на `.runtime/secrets/<svc>.env` + `depends_on: vault-agent: service_healthy` + `<svc>.env.tpl` + блок в `agent.hcl.parts/<profile>.hcl` + seed KV-объекта через `/request-secret`
- [ ] Все `${VAR}` (bootstrap) есть в `.env.example`
- [ ] Если новый Postgres — добавлен ещё один `pg_dumpall` блок в `containers/backup/backup-now` (с другим `-h` host'ом и `--stdin-filename`)
- [ ] `make validate` зелёный
- [ ] (Если требует Vault KV seed) — указано оператору, что нужно сделать на корп-стороне
- [ ] (Если bespoke-сигнал вне `docker ps`) — `scripts/tools/smoke.d/90-<svc>.sh` для `== Server ==`

## Anti-patterns

- Сервис без healthcheck — `depends_on: service_healthy` для зависимых не сработает.
- `:latest` "временно" — никогда не временно.
- Public без `crowdsec@file` — открыт миру без WAF.
- Чтение секрета через `environment:` напрямую из `.env` — на проектной стороне `.env` для bootstrap, runtime-секреты только через vault-agent.
- Прокидывал секрет через label/command — может попасть в логи.
