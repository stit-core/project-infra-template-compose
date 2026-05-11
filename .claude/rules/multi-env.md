# Multi-environment

Один проект может иметь несколько сред (`dev`, `prod`, опционально `staging`/etc). Каждая среда — **отдельный VPS** с одним и тем же compose-шаблоном, но со своим `ENV` в `.env` и своим набором AppRole-credentials. Шаблон агностичен к именам env'ов — это произвольные слаги.

## Принцип: max в Vault

Vault — единственный источник правды по конфигу проекта. Корп-админ ротирует значения централизованно, vault-agent на VPS перерендерит. `.env` сжимается до identity + secret-zero для AppRole-login.

### Что где живёт

| Категория | Где | Примеры |
|---|---|---|
| Identity | `.env` | `PROJECT_NAME`, `ENV`, `DOMAIN` |
| Bootstrap auth | `.env` | `VAULT_ROLE_ID`, `VAULT_SECRET_ID` |
| Корп-константы | hardcoded в шаблоне | `VAULT_ADDR=https://vault.stit.tech`, `OTEL_EXPORTER_OTLP_ENDPOINT=otel.stit.tech:443` |
| Локально-сгенерированные | `.env` (auto после первого deploy) | `CROWDSEC_BOUNCER_API_KEY` |
| Оператор-управление | `.env` | `COMPOSE_PROFILES` |
| Non-secret конфиг | **Vault** `kv/projects/<p>/<env>/meta` | `backend_tag`, `acme_email`, `acme_caserver` |
| Runtime-секреты | **Vault** `kv/projects/<p>/<env>/<kind>` | `db`, `oidc`, `jwt`, `minio`, `backup`, `otel` |

Любое значение, которое **меняется реже раза в неделю** и должно ротироваться корп-стороной → переезжает в Vault. Любое значение, которое **нужно ДО Vault-login'а** или генерится локально → остаётся в `.env`.

## KV layout

```
kv/projects/<p>/
  _meta                       # { envs: ["dev","prod"], created: <date> }
  <env>/
    meta                      # { backend_tag, acme_email, acme_caserver, ... }
    otel                      # { token }
    db                        # { user, password, database }
    oidc                      # { client_id, client_secret }
    jwt                       # { signing_key }
    minio                     # { root_user, root_password, app_access_key, app_secret_key, backup_access_key, backup_secret_key }
    backup                    # { password, access_key, secret_key, repository }
```

`_meta` нужен только корп-стороне для аудита/документации списка env'ов. Проектная сторона его не читает — AppRole не имеет прав на этот path. Невозможность залогиниться чужим ENV = валидация.

## Onboarding (что делает корп при создании проекта)

`stit/infra` запускает `onboard-project.sh --name <p> --envs <env1>,<env2>,...`. Скрипт обязан:

1. Создать `kv/projects/<p>/_meta` с `{envs: [...], created: <date>}`.
2. Per env:
   1. Создать AppRole `projects/<p>/<env>` с policy:
      ```hcl
      path "kv/data/projects/<p>/<env>/*" { capabilities = ["read"] }
      ```
   2. Засеять `kv/projects/<p>/<env>/otel` (OTEL-tenant token).
   3. Засеять `kv/projects/<p>/<env>/meta` с дефолтами:
      - `backend_tag=latest`
      - `acme_email=ops@<placeholder>`
      - `acme_caserver=https://acme-v02.api.letsencrypt.org/directory`
3. Вывести per-env блок для оператора:
   ```
   === <p> / <env> ===
   PROJECT_NAME=<p>
   ENV=<env>
   VAULT_ROLE_ID=<...>
   VAULT_SECRET_ID=<...>
   ```

Никаких db/minio/backup creds на этом шаге — оператор запросит по необходимости.

## Operator flow — bootstrap нового VPS

На каждом VPS отдельный bootstrap (по одному на env):

```bash
scripts/new-env.sh       # prompt: PROJECT_NAME, ENV, DOMAIN, VAULT_ROLE_ID, VAULT_SECRET_ID
make ship                # минимальный стек: traefik + vault-agent + crowdsec + otel + node-exporter + cadvisor
```

Стек сразу виден в OTEL (token уже засеян). Postgres/minio/backup/backend — в `compose.profiles`, не стартуют пока оператор их явно не включит.

## Operator flow — запросить secret для нового сервиса

Когда стек дозрел до `postgres`/`minio`/`backup`/`backend`/etc — зовёшь Claude skill `/request-secret` (`.claude/skills/request-secret/SKILL.md`). Skill:
- спросит имя KV-объекта (произвольный slug: `db`, `minio`, `stripe-key`, ...);
- выяснит поля + значения (случайные пароли генерит сам через `openssl rand`);
- напечатает готовый блок `vault kv put kv/projects/<p>/<env>/<name> field=value ...` для копи-паста.

Skill намеренно не имеет hardcoded enum'а имён — это позволяет одним механизмом seed'ить как стандартные секреты (`db`/`oidc`/`jwt`/`minio`/`backup`/`meta`/`otel`), так и project-specific (`stripe-key`, `sendgrid-creds`). Стандартные имена + их поля задокументированы в SKILL.md как cookbook.

Оператор отправляет блок корп-админу (Slack/PR/ticket — внеконтрактно). Админ выполняет `vault kv put`. После seed'а:

```bash
$EDITOR .env   # добавить нужный profile в COMPOSE_PROFILES
make ship      # render-configs обновит agent.hcl, vault-agent рендерит env, force-recreate consumer'ов
```

## Ротация

Источник правды — корп Vault. Любая ротация — `vault kv patch kv/projects/<p>/<env>/<kind> <field>=<new>`. Vault-agent заметит и перерендерит `.runtime/secrets/<kind>.env` (для секретов) или `.runtime/env/compose.env` (для `meta`). Consumer'ы перечитают env только при container CREATE — `scripts/deploy.sh` делает force-recreate на следующем deploy.

Для централизованного `BACKEND_TAG` rollout'а: корп патчит `meta.backend_tag` → оператор `make ship` (без MSG) → vault-agent перерендерит → force-recreate backend.

## Profile-based opt-in

Default-стек поднимается **без** секретов (кроме `otel` и `meta`, которые засеяны при онбординге). Сервисы с runtime-секретами сидят за `compose.profiles`:

| Сервис | Profile | Зависит от KV |
|---|---|---|
| `traefik`, `vault-agent`, `crowdsec`, `otel-agent`, `node-exporter`, `cadvisor`, `landing` | **always-on** | `otel`, `meta` |
| `postgres` | `postgres` | `db` |
| `minio` | `storage` | `minio` |
| `backup` | `storage` | `backup`, `minio`, `db` |
| `backend` | `backend` | `db`, `oidc`, `jwt`, `otel` |

`COMPOSE_PROFILES=postgres,backend make ship` = включить postgres + backend (и их KV-зависимости должны быть засеяны).

`configs/vault-agent/agent.hcl` собирается `scripts/render-configs.sh` из фрагментов под активный список profile'ов — vault-agent не запрашивает KV-объекты, которые не нужны, и не залипает в retry-loop'е на отсутствующих.

## Контракт со `stit/infra` (что обязан гарантировать корп)

1. `onboard-project.sh --name <p> --envs ...` — см. выше.
2. Admin-tool для seed'а вторичных секретов — конкретное название и интерфейс на стороне `stit/infra`, главное — admin может выполнить произвольный `vault kv put kv/projects/<p>/<env>/<name> ...` за оператора по запросу. Имя — произвольный slug (стандартные: `db`, `oidc`, `jwt`, `minio`, `backup`; project-specific — что угодно).
3. AppRole policy строго `kv/data/projects/<p>/<env>/*` read-only. Никаких write-прав у оператора.
4. `_meta` объект для аудита — корп пишет, проектная сторона не трогает.
5. Любая ротация — `vault kv patch`, без участия проектной стороны (кроме force-recreate на следующем deploy).

## Когда переходим на multi-env существующий проект

(Migration path для проектов которые уже на single-env шаблоне — не покрывается этим документом. На момент перехода все проекты в pre-prod, миграция = recreate VPS с новыми env'ами.)
