---
name: multi-env
description: Проектная сторона multi-env контракта — vault-agent KV-paths (kv/projects/<p>/<env>/*), как оператор запрашивает seed'ы, profile-based opt-in, lazy-seed, ротация через vault kv patch. Один env = отдельный VPS со своим ENV + AppRole-парой. Грузится при работе с .env, vault-agent config, compose-профилями, ansible-онбордингом.
paths:
  - ".env*"
  - "configs/vault-agent/**"
  - "compose/*.yml"
  - "ansible/roles/sftbmb-onboard/**"
---

# Multi-environment

Один проект может иметь несколько сред (`dev`, `prod`, опционально `staging`/etc). Каждая среда — **отдельный VPS** с одним и тем же compose-шаблоном, но со своим `ENV` в `.env` и своим набором AppRole-credentials. Шаблон агностичен к именам env'ов — это произвольные слаги.

Этот документ описывает **проектную сторону** контракта: как vault-agent в этом шаблоне разрешает KV-paths, как оператор запрашивает seed'ы, как срабатывает profile-based opt-in. Общая карта контрактов tenant/AppRole/KV (что одинаково для всех репо экосистемы) — `corp-infra-template/docs/ecosystem.md`. Корп-side имплементация — `corp-infra-template/scripts/onboard-project.sh` + `corp-infra-template/scripts/seed-project-secrets.sh`.

## Принцип: max в Vault

Vault — единственный источник правды по конфигу проекта. Корп-админ ротирует значения централизованно, vault-agent на VPS перерендерит. `.env` сжимается до identity + secret-zero для AppRole-login.

### Что где живёт

| Категория | Где | Примеры |
|---|---|---|
| Identity | `.env` | `PROJECT_NAME`, `ENV`, `DOMAIN` |
| Bootstrap auth | `.env` | `VAULT_ROLE_ID`, `VAULT_SECRET_ID` |
| Корп-эндпоинты | `.env` (managed-дефолт в коде; self-hosted override) | `VAULT_ADDR=https://vault.sftbmb.ru`, `OTEL_EXPORTER_OTLP_ENDPOINT=https://otel.sftbmb.ru:443`, `REGISTRY_HOST=git.sftbmb.ru` |
| Локально-сгенерированные | `.env` (auto после первого deploy) | `CROWDSEC_BOUNCER_API_KEY` |
| Оператор-управление | `.env` | `COMPOSE_PROFILES` |
| Non-secret конфиг | **Vault** `kv/projects/<p>/<env>/meta` | `backend_tag`, `acme_email`, `acme_caserver` |
| Runtime-секреты | **Vault** `kv/projects/<p>/<env>/<kind>` | `db`, `oidc`, `jwt`, `minio`, `backup`, `otel` |

Любое значение, которое **меняется реже раза в неделю** и должно ротироваться корп-стороной → переезжает в Vault. Любое значение, которое **нужно ДО Vault-login'а** или генерится локально → остаётся в `.env`.

## KV layout

```
kv/projects/<p>/
  _meta                       # { env_<env1>=1, env_<env2>=1, ..., created=<ISO> } — corp-only
  <env>/
    meta                      # { backend_tag, acme_email, acme_caserver, ... }
    otel                      # { token, accountID }
    db                        # { user, password, database }
    oidc                      # { client_id, client_secret }
    jwt                       # { signing_key }
    minio                     # { root_user, root_password, app_access_key, app_secret_key, backup_access_key, backup_secret_key }
    backup                    # { password, access_key, secret_key, repository }
```

`_meta` нужен только корп-стороне для аудита/документации (поле `env_<env>=1` на каждый онбоарденный env плюс `created`). Проектная сторона его не читает — AppRole не имеет прав на этот path. Невозможность залогиниться чужим ENV = валидация.

## Onboarding (что делает корп при создании проекта)

Корп-админ запускает `corp-infra-template/scripts/onboard-project.sh --name <p> --envs <env1>,<env2>,... [--source-ip <env>=<ip>]`. Скрипт:

1. Создаёт/патчит `kv/projects/<p>/_meta` (поле `env_<env>=1` на каждый онбоарденный env плюс `created`). Идемпотентно: повторный вызов с расширенным `--envs` дописывает недостающие env'ы, существующие пропускает.
2. Per env (если ещё не онбоарден):
   1. AppRole `projects-<p>-<env>` (flat, дефис-разделитель — Vault не принимает слеши в `auth/approle/role/<name>`; KV-слой остаётся иерархическим) с policy `projects-<p>-<env>-read`:
      ```hcl
      path "kv/data/projects/<p>/<env>/*"     { capabilities = ["read"] }
      path "kv/metadata/projects/<p>/<env>/*" { capabilities = ["read", "list"] }
      ```
      Token TTL 10m / max 30m, secret_id без срока.
   2. `kv/projects/<p>/<env>/otel` — `{ token, accountID }` (accountID авто-инкрементируется корп-стороной).
   3. `kv/projects/<p>/<env>/meta` с дефолтами:
      - `backend_tag=latest`
      - `acme_email=ops@<placeholder>`
      - `acme_caserver=https://acme-v02.api.letsencrypt.org/directory`
3. Если передан `--source-ip <env>=<ip>` — egress IP проектной VPS дописывается в `configs/crowdsec/whitelists.yaml` корп-side и crowdsec рестартится. Без этого CrowdSec ловит otel-collector UA на `crowdsecurity/http-bad-user-agent` и режет метрики/логи 403'ами. См. `corp-infra-template/.claude/rules/crowdsec-whitelist.md`.
4. Печатает per-env блок для оператора:
   ```
   === <p> / <env> ===
   PROJECT_NAME=<p>
   ENV=<env>
   VAULT_ROLE_ID=<...>
   VAULT_SECRET_ID=<...>
   ```

Никаких db/minio/backup creds на этом шаге — оператор запросит по необходимости (см. ниже).

## Operator flow — bootstrap нового VPS

На каждом VPS отдельный bootstrap (по одному на env):

```bash
make new-env             # prompt: PROJECT_NAME, ENV, DOMAIN, VAULT_ROLE_ID, VAULT_SECRET_ID
make ship                # минимальный стек: traefik + vault-agent + crowdsec + otel + node-exporter + cadvisor
```

Стек сразу виден в OTEL (token уже засеян). Postgres/minio/backup/backend — в `compose.profiles`, не стартуют пока оператор их явно не включит.

## Operator flow — запросить secret для нового сервиса

Когда стек дозрел до `postgres`/`minio`/`backup`/`backend`/etc — зовёшь Claude skill `/request-secret` (`.claude/skills/request-secret/SKILL.md`). Skill:
- спросит имя KV-объекта (произвольный slug: `db`, `minio`, `stripe-key`, ...);
- выяснит поля + значения (случайные пароли генерит сам через `openssl rand`);
- напечатает готовый блок `vault kv put kv/projects/<p>/<env>/<name> field=value ...` для копи-паста.

Skill намеренно не имеет hardcoded enum'а имён — это позволяет одним механизмом seed'ить как стандартные секреты (`db`/`oidc`/`jwt`/`minio`/`backup`/`meta`/`otel`), так и project-specific (`stripe-key`, `sendgrid-creds`). Стандартные имена + их поля задокументированы в SKILL.md как cookbook.

Оператор отправляет блок корп-админу (Slack/PR/ticket — внеконтрактно). Админ выполняет `vault kv put` (либо `corp-infra-template/scripts/seed-project-secrets.sh` с env-like файлом — он патчит существующие paths, не перезатирая). После seed'а:

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

## Контракт со `corp-infra-template` (что обязан гарантировать корп)

1. `corp-infra-template/scripts/onboard-project.sh --name <p> --envs ... [--source-ip <env>=<ip>]` — см. выше.
2. `corp-infra-template/scripts/seed-project-secrets.sh` — admin-tool для seed/patch вторичных KV-объектов из env-like файла (формат `<group>.<field>=<value>`, в т.ч. вложенные `3rd-party.stripe.api_key=`). По запросу оператора (см. skill `/request-secret`) корп-админ либо засеивает через этот скрипт, либо выполняет напрямую `vault kv put kv/projects/<p>/<env>/<name> ...`. Имя — произвольный slug (стандартные: `db`, `oidc`, `jwt`, `minio`, `backup`; project-specific — что угодно).
3. AppRole policy строго `kv/data/projects/<p>/<env>/*` read-only. Никаких write-прав у оператора.
4. `_meta` объект для аудита — корп пишет, проектная сторона не трогает.
5. Любая ротация — `vault kv patch`, без участия проектной стороны (кроме force-recreate на следующем deploy).

Каждая среда — отдельный VPS с собственным `ENV` в `.env` и своей AppRole-парой. Среда не конвертируется in-place: добавление env'а проекту = bootstrap нового VPS под этот env (skill `bootstrap-vps`).
