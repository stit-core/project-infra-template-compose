---
description: Правила секретов в проектной инфре. .env для оператора, vault-agent рендерит .runtime/secrets/*.env, ротация = vault kv patch + рестарт. Грузится при работе с .env, .tpl, vault-agent.
paths:
  - ".env*"
  - "**/*.tpl"
  - "configs/vault-agent/**"
  - "compose/vault-agent.yml"
---

# Секреты и .env

## Два уровня секретов

| Уровень | Что | Где | Кто пишет |
|---|---|---|---|
| Оператор | bootstrap: `PROJECT_NAME`, `DOMAIN`, `ACME_EMAIL`, `VAULT_ROLE_ID`, `VAULT_SECRET_ID`, `OTEL_*`, image tags, `CROWDSEC_BOUNCER_API_KEY` | `.env` (gitignored, на VPS) | оператор через `scripts/new-env.sh` |
| Runtime | DB-пароль, OIDC client_secret, JWT key, OTEL_TOKEN, MinIO root + SA, RESTIC_PASSWORD + AWS_* | `.runtime/secrets/*.env` (gitignored, рендерится vault-agent'ом) | vault-agent из `kv/projects/<p>/{db,oidc,jwt,minio,backup}` + `kv/observability/tenants/<p>` |

Backend / postgres / other consumer-сервисы читают **только** `.runtime/secrets/*.env` через `env_file:`. Они не знают про Vault напрямую.

## Что куда

| Файл | В репо? | Зачем |
|---|---|---|
| `.env.example` | да | Список всех bootstrap-переменных, как сгенерировать |
| `.env` | **нет** (gitignored, permissions.deny) | Реальные оператор-секреты на VPS |
| `.runtime/secrets/*.env` | **нет** (gitignored, .runtime/ полностью) | Vault-agent output |
| `.runtime/secrets-bootstrap/{role-id,secret-id}` | **нет** | Trampoline-файлы для AppRole login |
| `configs/vault-agent/templates/*.env.tpl` | да | Vault-agent шаблоны на consul-template (`{{ with secret (printf "kv/data/projects/%s/db" (env "PROJECT_NAME")) }}...{{ end }}`) |
| `configs/vault-agent/agent.hcl.tpl` | да | Список template-блоков (один блок на render-target) |
| `configs/<svc>/*.tpl` | да | Не-секретные шаблоны с bootstrap-vars (например, `${CROWDSEC_BOUNCER_API_KEY}` для traefik dynamic) |

## Правила

### .env / .env.example

- `.env*` НИКОГДА не коммитятся (gitignore + `permissions.deny`).
- Любая новая bootstrap-переменная в compose/configs — обязана появиться в `.env.example` с комментарием как сгенерировать.
- `${VAR}`, который использует только vault-agent template — **не** в `.env.example` (он живёт в Vault KV, а не в `.env`).
- Имена: `<SERVICE>_<PURPOSE>` UPPER_SNAKE_CASE.

### .runtime/

- Полностью gitignored: `.runtime/` в `.gitignore`.
- Создаётся автоматически vault-agent'ом и `scripts/deploy.sh` (через `mkdir -p`).
- В backup НЕ попадает (rendered, восстанавливается из Vault).
- Permissions: vault-agent пишет `0400`. Не лезь руками.

### Vault KV path: CLI vs API (зачем `kv/data/...`)

KV v2 даёт два разных view на один и тот же путь:

| Где | Path | Пример |
|---|---|---|
| `vault kv put/get/patch` (CLI) | `kv/<path>` | `vault kv put kv/projects/roc/minio root_user=admin ...` |
| HTTP API + consul-template `secret` | `kv/data/<path>` | `secret (printf "kv/data/projects/%s/minio" ...)` |

CLI прячет сегмент `data/` для удобства. API/template — нет, там path буквальный.
Если в `.tpl` написать `kv/projects/...` без `data/` — Vault вернёт 404, vault-agent залипнет в retry-loop'е.

Аналогично у ответа: HTTP API оборачивает поля в `{ "data": { "data": { ... } } }`,
поэтому в шаблонах двойной `.Data.data.<key>` (первый — envelope, второй — твои поля).

### vault-agent шаблоны

`configs/vault-agent/templates/<svc>.env.tpl` — это **consul-template** (внутри vault-agent),
не shell-envsubst. Поэтому:

- `(env "PROJECT_NAME")`, **не** `${PROJECT_NAME}` — переменные окружения тянутся через
  template-function.
- `kv/data/projects/...`, не `kv/projects/...` — см. блок выше.
- Имена полей в `.Data.data.<key>` точно совпадают с ключами, которыми клали через
  `vault kv put` (`user`, `password`, `database`, ...). Поправка имени в Vault → правка `.tpl`.

```
{{ with secret (printf "kv/data/projects/%s/db" (env "PROJECT_NAME")) -}}
PG_DSN=postgres://{{ .Data.data.user }}:{{ .Data.data.password }}@postgres:5432/{{ .Data.data.database }}
{{- end }}
```

Каждый новый рендер-таргет требует двух правок:
1. Создать `.tpl` в `configs/vault-agent/templates/`.
2. Добавить `template { source = ...; destination = "/secrets/<svc>.env"; perms = 0400 }` блок в `agent.hcl.tpl`.

После — рестарт vault-agent + **force-recreate** consumer'ов. Просто `restart` НЕ работает: docker фиксирует `env_file` при container CREATE, не start, поэтому повторное чтение требует пересоздать контейнер. `scripts/deploy.sh` делает это автоматически при изменении `.tpl` между sha (см. блок про vault-template change). Вручную:

```bash
docker compose <args> restart vault-agent
docker compose <args> up -d --no-deps --force-recreate <consumer>
```

### Ротация

Источник истины — Vault KV на корп-стороне:

```
# на корп-VPS (stit/infra)
vault kv patch kv/projects/<p>/db password=<new>
```

Vault-agent на проектном VPS заметит изменение и перерендерит `.runtime/secrets/<svc>.env`. **Но consumer уже прочитал env_file при создании контейнера** — нужен force-recreate, не restart:

```bash
make restart SVC=backend     # ❌ контейнер не пересоздан, env_file не перечитан
docker compose <args> up -d --no-deps --force-recreate backend  # ✅
```

Не редактируй `.runtime/secrets/*.env` руками — vault-agent перетрёт.

## Что нельзя коммитить (cross-check)

`git diff --cached` перед коммитом — убедись что нет:
- `.env` или `.env.local` / `.env.production`
- `.runtime/` любого уровня
- `*.pem`, `*.key`
- Inline-секретов в `compose/*.yml` (значения вида `password: actual_secret` — должно быть `${VAR}` или прямо через vault-agent)

Hook `permissions.deny` страхует, но привычка проверять — золото.

## Чек перед коммитом

- В `.env.example` нет реальных значений (только placeholder / пусто)?
- Любой новый `${VAR}` в compose/configs — добавлен в `.env.example` (если bootstrap) или в vault-agent template + `agent.hcl.tpl` (если runtime)?
- `scripts/agent-tools/validate.sh` зелёный (он ловит missing vars в `.env.example`)?
