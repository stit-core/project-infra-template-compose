---
name: secrets-and-env
description: Правила секретов в проектной инфре. Multi-env (kv/projects/<p>/<env>/*), .env только identity+bootstrap, vault-agent рендерит .runtime/, ротация = vault kv patch + force-recreate. Грузится при работе с .env, .tpl, vault-agent.
paths:
  - ".env*"
  - "**/*.tpl"
  - "configs/vault-agent/**"
  - "compose/vault-agent.yml"
---

# Секреты и .env

## Три уровня данных

| Уровень | Что | Где | Кто пишет |
|---|---|---|---|
| Identity | `PROJECT_NAME`, `ENV`, `DOMAIN` | `.env` (gitignored) | `scripts/new-env.sh` |
| Bootstrap auth | `VAULT_ROLE_ID`, `VAULT_SECRET_ID` | `.env` | оператор (из корп онбординга) |
| Local-managed | `CROWDSEC_BOUNCER_API_KEY`, `COMPOSE_PROFILES` | `.env` | auto-register / оператор |
| Корп-константы | `VAULT_ADDR`, `OTEL endpoint` | hardcoded в шаблоне | — |
| Vault-managed конфиг | `BACKEND_TAG`, `ACME_EMAIL`, `ACME_CASERVER` | `kv/projects/<p>/<env>/meta` → `.runtime/env/compose.env` | корп-админ (vault kv put/patch) |
| Vault-managed секреты | DB, OIDC, JWT, OTEL_TOKEN, MinIO, Restic + AWS | `kv/projects/<p>/<env>/{db,oidc,jwt,otel,minio,backup}` → `.runtime/secrets/*.env` | корп-админ |

Consumer-сервисы (postgres, backend, minio, backup, otel-agent) читают **только** `.runtime/secrets/*.env` и `.runtime/env/compose.env` через `env_file:` / compose `--env-file`. Они не знают про Vault напрямую.

## Multi-env

Один проект = N сред = N **отдельных VPS**, каждый со своим `ENV` в `.env` и своим AppRole для пары `(project, env)`. Контракт KV layout / AppRole / onboarding flow — `.claude/rules/multi-env.md` (плюс `stit-infra/infra/docs/ecosystem.md` для общей карты). Этот документ — про **механику секретов на проектной стороне**: что в `.env` vs Vault, vault-agent template syntax, ротация через force-recreate.

## Что куда

| Файл | В репо? | Зачем |
|---|---|---|
| `.env.example` | да | Минимальный набор для bootstrap (5 переменных) |
| `.env` | **нет** (gitignored, permissions.deny) | Реальные identity + AppRole на VPS |
| `.runtime/secrets/*.env` | **нет** | Vault-agent rendered секреты |
| `.runtime/env/compose.env` | **нет** | Vault-agent rendered non-secret конфиг для compose (BACKEND_TAG etc.) |
| `.runtime/configs/traefik.yml` | **нет** | Vault-agent rendered traefik static (acme email/caServer из Vault) |
| `.runtime/configs/vault-health.sh` | **нет** | render-configs.sh generated healthcheck-script под активные profile'ы |
| `.runtime/secrets-bootstrap/{role-id,secret-id}` | **нет** | Trampoline для AppRole login |
| `configs/vault-agent/templates/*.tpl` | да | Consul-template шаблоны (`{{ with secret (printf "kv/data/projects/%s/%s/db" (env "PROJECT_NAME") (env "ENV")) }}`) |
| `configs/vault-agent/agent.hcl.parts/*.hcl` | да | head/<profile>/tail-фрагменты — render-configs.sh собирает agent.hcl под активный `COMPOSE_PROFILES` |
| `configs/<svc>/*.tpl` | да | envsubst-шаблоны с .env-vars (например, middlewares.yml.tpl с `${CROWDSEC_BOUNCER_API_KEY}`) |

## Правила

### .env / .env.example

- `.env*` НИКОГДА не коммитятся (gitignore + `permissions.deny`).
- В `.env.example` живёт минимум: identity, AppRole-bootstrap, профильные switches. Vault-managed vars (`BACKEND_TAG` etc.) присутствуют **как закомментированные declarations** — нужно для `validate.sh` coverage-check, реальное значение приходит из Vault.
- Имена: `<SERVICE>_<PURPOSE>` UPPER_SNAKE_CASE.

### .runtime/

- Полностью gitignored.
- Создаётся `scripts/deploy.sh` (mkdir + touch заглушек) + render-configs.sh + vault-agent.
- В backup НЕ попадает (rendered, восстанавливается из Vault + render-configs).
- Permissions: vault-agent пишет `0400` для secrets, `0444` для configs/env. Не лезь руками.

### Vault KV path: CLI vs API (зачем `kv/data/...`)

KV v2 — два view одного пути:

| Где | Path |
|---|---|
| `vault kv put/get/patch` (CLI) | `kv/projects/<p>/<env>/<kind>` |
| HTTP API + consul-template `secret` | `kv/data/projects/<p>/<env>/<kind>` |

CLI прячет сегмент `data/`. API/template — нет. Если в `.tpl` написать `kv/projects/...` без `data/` — Vault вернёт 404, vault-agent залипнет в retry-loop'е.

Ответ API оборачивает поля в `{ "data": { "data": { ... } } }`, поэтому двойной `.Data.data.<key>` в шаблонах.

### vault-agent шаблоны

`configs/vault-agent/templates/<svc>.{env,yml}.tpl` — **consul-template** (внутри vault-agent), не shell-envsubst:

- `(env "PROJECT_NAME")`, `(env "ENV")` — переменные тянутся через template-function (vault-agent контейнерное окружение).
- `kv/data/projects/...`, не `kv/projects/...`.
- Имена полей в `.Data.data.<key>` точно совпадают с тем, что клали `vault kv put`. Поправка имени в Vault → правка `.tpl`.

```
{{ with secret (printf "kv/data/projects/%s/%s/db" (env "PROJECT_NAME") (env "ENV")) -}}
PG_DSN=postgres://{{ .Data.data.user }}:{{ .Data.data.password }}@postgres:5432/{{ .Data.data.database }}
{{- end }}
```

Каждый новый render-target требует **трёх** правок:
1. Создать `<svc>.{env,yml}.tpl` в `configs/vault-agent/templates/`.
2. Добавить `template {}` блок в соответствующий `configs/vault-agent/agent.hcl.parts/<profile>.hcl` (или `head.hcl` если always-on).
3. Если consumer-сервис в новом profile — добавить `profiles: [<name>]` в `compose/<svc>.yml`.

После — `make ship`. `scripts/deploy.sh` детектит изменения в `templates/` или `agent.hcl.parts/` + смену `COMPOSE_PROFILES` → restart vault-agent + force-recreate consumer'ов автоматически. Вручную:

```bash
docker compose <args> restart vault-agent
docker compose <args> up -d --no-deps --force-recreate <consumer>
```

### Ротация

Источник истины — Vault на корп-стороне:

```bash
# на корп-VPS (stit-infra/infra)
vault kv patch kv/projects/<p>/<env>/db password=<new>
```

Vault-agent на проектном VPS заметит изменение и перерендерит `.runtime/secrets/<svc>.env`. **Но consumer уже прочитал env_file при создании контейнера** — нужен force-recreate, не restart:

```bash
make restart SVC=backend     # ❌ контейнер не пересоздан, env_file не перечитан
docker compose <args> up -d --no-deps --force-recreate backend  # ✅
```

`make ship` (без MSG, на чистом дереве) делает force-recreate автоматически когда видит смену `.tpl` / `parts/` / `COMPOSE_PROFILES` между deploy'ами.

Не редактируй `.runtime/secrets/*.env` руками — vault-agent перетрёт.

### Profile-based opt-in

Минимальный стек (always-on) — traefik / vault-agent / crowdsec / otel-agent / node-exporter / cadvisor / landing. Поднимается на одном лишь `meta` + `otel` seed'е от корпа при онбординге.

Опциональные сервисы за `COMPOSE_PROFILES`:

| Profile | Сервисы | Зависит от KV |
|---|---|---|
| `postgres` | postgres | db |
| `storage` | minio, minio-init, backup | minio, backup, db (+ обязательно `postgres` профиль) |
| `backend` | backend | db, oidc, jwt |

Запрос seed'а — Claude skill `/request-secret` (`.claude/skills/request-secret/SKILL.md`). Печатает stdout-блок `vault kv put kv/projects/<p>/<env>/<name>` для корп-админа; имя — произвольный slug, не enum.

## Что нельзя коммитить (cross-check)

`git diff --cached` перед коммитом — убедись что нет:
- `.env` или `.env.local` / `.env.production`
- `.runtime/` любого уровня
- `.onboard-creds` (legacy, не должен генериться, но safety-net в .gitignore)
- `*.pem`, `*.key`
- Inline-секретов в `compose/*.yml` (значения вида `password: actual_secret` — должно быть `${VAR}` или через vault-agent)

Hook `permissions.deny` страхует, но привычка проверять — золото.

## Чек перед коммитом

- В `.env.example` нет реальных значений (только placeholder / пусто)?
- Любой новый `${VAR}` в compose/configs — добавлен в `.env.example` (как declared / закомментированный, если Vault-managed) или в vault-agent template + соответствующий `agent.hcl.parts/<profile>.hcl`?
- `scripts/tools/validate.sh` зелёный (он ловит missing vars в `.env.example`)?
