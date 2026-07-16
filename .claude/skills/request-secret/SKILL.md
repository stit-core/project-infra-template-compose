---
name: request-secret
description: Сформировать `vault kv put` блок для корп-админа — seed нового KV-объекта в kv/projects/<p>/<env>/<name>. Активируй на "/request-secret", "выпиши креды", "запроси seed", "нужны креды для X", "блок для админа", "vault kv put для".
---

# Skill: request-secret

Сформировать stdout-блок `vault kv put` для корп-админа: когда оператору нужен новый KV-объект в `kv/projects/<p>/<env>/<name>` (db, oidc, jwt, minio, backup, stripe-key, sendgrid-creds — что угодно).

Skill не действует за оператора — он печатает готовую команду, которую оператор отдаёт корп-админу (out-of-band: Slack / тикет / PR в `corp-infra-template`). Засеивает корп-админ через `vault kv put` напрямую либо через `corp-infra-template/scripts/seed-project-secrets.sh` (env-like формат, идемпотентный patch). Vault-agent на проектной VPS подхватит на следующем render-цикле — на чистом дереве `make ship` без MSG триггерит force-recreate consumer'ов.

**Это частный случай `corp-handoff`** (seed/patch KV). Общий механизм передачи на корп-сторону (онбординг env, CrowdSec-whitelist, DNS) и железобетонное правило «тронул corp-поверхность → блок до claim готово» — skill `corp-handoff` + `.claude/rules/corp-handoff.md`. Если пришёл из `corp-handoff` с ACTION = создать/пропатчить `kv/...` — этот skill и есть твой следующий шаг.

## Когда применять

- "Выпиши креды для postgres / minio / stripe / ..."
- "Нужен блок vault kv put для админа"
- "Засей <something> в проектный Vault"
- "/request-secret"
- Когда `make ship` падает с `vault-preflight: ВНИМАНИЕ — в Vault отсутствуют paths` → один из этих paths нужно seed'ить.

## Когда НЕ применять

- Юзер хочет ротировать существующее поле — это `vault kv patch ... <field>=<new>` (одна строка, без скаффолда). Skill об этом упоминает в конце, но не центрит.
- Юзер хочет seed на корп-Vault напрямую под root-привилегиями Vault — это корп-задача, не проектная.
- Юзер хочет добавить новый сервис в стек — это `/add-service`. Этот skill активируется когда новый сервис уже добавлен и пора засеять его секрет.

## Шаги

### 1. Резолв identity

Цепочка `.env.local → .env → AskUserQuestion`, отдельно по каждому полю. Этот skill чаще
всего бежит **с рабочей станции** оператора, где `.env` нет вовсе (он живёт только на VPS —
см. `.claude/rules/env-local.md`), а `.env.local` присутствует и уже хранит `PROJECT_NAME`.

```bash
# 1) workstation: .env.local (gitignored). PROJECT_NAME/ENV — не секреты, grep легитимен.
# 2) VPS / fallback: .env в корне.
PROJECT_NAME=$(awk -F= '/^PROJECT_NAME=/{print $2; exit}' .env.local 2>/dev/null)
[ -z "$PROJECT_NAME" ] && PROJECT_NAME=$(awk -F= '/^PROJECT_NAME=/{print $2; exit}' .env 2>/dev/null)
ENV=$(awk -F= '/^ENV=/{print $2; exit}' .env.local 2>/dev/null)
[ -z "$ENV" ] && ENV=$(awk -F= '/^ENV=/{print $2; exit}' .env 2>/dev/null)
```

`ENV` в `.env.local` — нестандартный ключ (там обычно только connection + `PROJECT_NAME`),
так что чаще резолвится из `.env` или остаётся пустым. Любое поле, оставшееся пустым после
обоих файлов, — спроси через `AskUserQuestion` (`PROJECT_NAME` / `ENV`), не выдумывай.

Поля identity (`PROJECT_NAME`/`ENV`) — не секреты, `grep`/`awk` по ним легитимен. Сами
**значения** секретов из `.env.local` (токены) так не вытаскивай — security-инвариант
`env-local.md` (доступ к кредам только через tools, без эха в чат) остаётся в силе.

### 2. Определи имя KV-объекта

`<name>` — slug `[a-z0-9-]+` для path `kv/projects/<p>/<env>/<name>`. Стандартные имена (используются vault-agent шаблонами):

| Name | Поля | Используется |
|---|---|---|
| `meta` | `acme_email`, `acme_caserver` (image-теги тут НЕ живут — они в `.env`, `make bump`) | always-on (traefik.yml) |
| `otel` | `token`, `accountID` (сеет корп при онбординге; шаблон читает только `token`) | always-on (otel-agent bearer) |
| `db` | `user`, `password`, `database` | profile postgres + backend + storage |
| `oidc` | `client_id`, `client_secret` | profile backend |
| `jwt` | `signing_key` | profile backend |
| `minio` | `root_user`, `root_password`, `app_access_key`, `app_secret_key`, `backup_access_key`, `backup_secret_key`, `buckets` (опц) | profile storage |
| `backup` | `password`, `repository`, `access_key`, `secret_key` | profile storage |

**Project-specific** — что угодно (`stripe-key`, `sendgrid`, `s3-external-creds`). vault-agent шаблоны нужно расширить отдельно — упомяни оператору если он создаёт новое имя что без правки `.tpl` секрет до consumer'а не доедет.

### 3. Спроси / выясни поля + значения

Для стандартных имён — см. таблицу выше. Для нестандартных — спроси у юзера или прими описание ("нужны email + password от SMTP-сервера"), оформи в `<field>=<value>` парах.

Для случайных значений (пароли, signing keys) — генерируй локально:
```bash
openssl rand -hex 24    # 48-char hex — password / signing_key / restic_password
openssl rand -hex 8     # 16-char hex — S3 access_key (короче нужно для minio SA: access_key 3-20 chars)
openssl rand -hex 16    # 32-char hex — S3 secret_key
```

Не печатай эти команды в выводе — генери значения сам и подставляй в `vault kv put`. Оператор не должен делать дополнительных шагов.

### 4. Печатай блок

Формат — один stdout-блок (plain-текст, чтобы оператор мог copy-paste целиком):

```
================================================================================
ОТНЕСИ ЭТО КОРП-АДМИНУ (corp-infra-template). Seed kv/projects/<p>/<env>/<name>.
--------------------------------------------------------------------------------
vault kv put kv/projects/<p>/<env>/<name> \
  field1='value1' \
  field2='value2'
--------------------------------------------------------------------------------
После seed'а: `make ship`. Ротация: `vault kv patch kv/.../<name> <field>=<new>` + `make ship`.
================================================================================
```

Если значения чувствительные (RESTIC_PASSWORD, generated keys) — напомни оператору продублировать offsite. Без RESTIC_PASSWORD restore из снапшотов невозможен **даже** при сохранённом репозитории.

### 5. Поясни next steps

После seed'а оператору обычно нужно:
1. Обновить `COMPOSE_PROFILES` в `.env` (если name связан с profile — postgres / storage / backend).
2. `make ship` — render-configs обновит `agent.hcl`, vault-agent перерендерит env-файлы, deploy.sh force-recreate consumer'ов.

Скажи юзеру что именно нужно делать дальше — не оставляй его гадать.

## Несколько KV-объектов одного "типа"

Иногда нужно >1 user'а для postgres, >1 OIDC-клиента и т.п. KV-объект — это плоский dict, не array. Два пути:

1. **Дополнительные поля в одном объекте:** `kv/.../db` с `user`, `password`, `database`, плюс `readonly_user`, `readonly_password`. Расширить `configs/vault-agent/templates/postgres.env.tpl` чтобы рендерило все нужные поля. Минус — vault-template должен знать про каждое поле наперёд.

2. **Отдельные KV-объекты:** `kv/.../db` + `kv/.../db-readonly` + `kv/.../db-worker`. Vault-agent template читает несколько `secret`-блоков. Расширить consumer (init.sql, migrations) чтобы создавал доп. юзеров.

Второй путь чище семантически. Запроси у юзера какой больше подходит.

## Anti-patterns

- **Печатать литералы значений без генерации.** Если поле должно быть случайным (`password`, `signing_key`, S3 keys) — генери `openssl rand` САМ, не оставляй `<value>` placeholder. Только для админ-задаваемых полей (`acme_email`, `client_id` от OIDC provider'а, restic `repository`) — placeholder с пояснением.

- **Засеивать creds в .env вместо Vault.** Любой секрет = Vault. `.env` только для identity + AppRole-bootstrap + локально-сгенерированных артефактов (CROWDSEC_BOUNCER_API_KEY).

- **Префиксы env'а в name.** Не `db-prod`/`db-dev` — env-разделение уже в path (`kv/projects/<p>/<env>/db`). Имя описывает _что_, не _где_.

- **Путать seed-блок с tool-only кредами.** Печатаемый `vault kv put` блок — намеренный hand-off
  корп-админу (значения в нём — для copy-paste out-of-band). А вот креды, которые **присылает
  оператор** (готовый токен, connection к VPS), и `VAULT_SECRET_ID`/`ROLE_ID` — НЕ эхо-ить: токен →
  агент пишет в `.env.local`, значение не цитирует (`.claude/rules/env-local.md`).
