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
   а не shell envsubst: `(env "PROJECT_NAME")`, не `${PROJECT_NAME}`. KV v2 API
   требует префикс `kv/data/...` в path (в `vault kv put`-CLI префикс не нужен —
   см. `.claude/rules/secrets-and-env.md`).

   ```
   {{ with secret (printf "kv/data/projects/%s/<svc>" (env "PROJECT_NAME")) -}}
   KEY1={{ .Data.data.key1 }}
   KEY2={{ .Data.data.key2 }}
   {{- end }}
   ```

2. Добавить блок в `configs/vault-agent/agent.hcl.tpl`:

   ```hcl
   template {
     source      = "/etc/vault-agent/templates/<svc>.env.tpl"
     destination = "/secrets/<svc>.env"
     perms       = 0400
   }
   ```

3. На корп-стороне (`stit/infra`) — оператор должен seed-нуть Vault KV: `kv/projects/<project>/<svc>` с нужными ключами. Это вне scope'а проектного репо — указать оператору в коммит-сообщении / PR-описании.

4. В compose:
   ```yaml
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

### 6. Validate + deploy

1. Локально: `bash scripts/agent-tools/validate.sh` — compose-syntax, yamllint, .env coverage.
2. Коммит: `feat(<svc>): add <Service>`.
3. Push в main.
4. На сервере: `make deploy`.
5. Verify: `make ps`, healthcheck зелёный, `https://<sub>.${DOMAIN}` доступен (если public).

## Чек-лист

- [ ] `compose/<svc>.yml` существует с pinned image
- [ ] Healthcheck указан
- [ ] `networks:` явный список
- [ ] Если public — `proxy` сеть + traefik labels с минимум `crowdsec@file`
- [ ] Если читает секреты — `env_file` на `.runtime/secrets/<svc>.env` + `depends_on: vault-agent: service_healthy` + `<svc>.env.tpl` + блок в `agent.hcl.tpl`
- [ ] Все `${VAR}` (bootstrap) есть в `.env.example`
- [ ] Если новый Postgres — добавлен ещё один `pg_dumpall` блок в `containers/backup/backup-now` (с другим `-h` host'ом и `--stdin-filename`)
- [ ] `validate.sh` зелёный
- [ ] (Если требует Vault KV seed) — указано оператору, что нужно сделать на корп-стороне

## Anti-patterns

- Сервис без healthcheck — `depends_on: service_healthy` для зависимых не сработает.
- `:latest` "временно" — никогда не временно.
- Public без `crowdsec@file` — открыт миру без WAF.
- Чтение секрета через `environment:` напрямую из `.env` — на проектной стороне `.env` для bootstrap, runtime-секреты только через vault-agent.
- Прокидывал секрет через label/command — может попасть в логи.
