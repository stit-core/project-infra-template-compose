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
| Оператор | bootstrap: `VAULT_ROLE_ID`, `VAULT_SECRET_ID`, `RESTIC_PASSWORD`, `AWS_*`, image tags, `DOMAIN` | `.env` (gitignored, на VPS) | оператор через `scripts/new-env.sh` |
| Runtime | DB-пароль, OIDC client_secret, JWT key, OTEL_TOKEN | `.runtime/secrets/*.env` (gitignored, рендерится vault-agent'ом) | vault-agent из `kv/projects/<p>/*` |

Backend / postgres / other consumer-сервисы читают **только** `.runtime/secrets/*.env` через `env_file:`. Они не знают про Vault напрямую.

## Что куда

| Файл | В репо? | Зачем |
|---|---|---|
| `.env.example` | да | Список всех bootstrap-переменных, как сгенерировать |
| `.env` | **нет** (gitignored, permissions.deny) | Реальные оператор-секреты на VPS |
| `.runtime/secrets/*.env` | **нет** (gitignored, .runtime/ полностью) | Vault-agent output |
| `.runtime/secrets-bootstrap/{role-id,secret-id}` | **нет** | Trampoline-файлы для AppRole login |
| `configs/vault-agent/templates/*.env.tpl` | да | Vault-agent шаблоны (`{{ with secret "kv/projects/.../db" }}...{{ end }}`) |
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

### vault-agent шаблоны

`configs/vault-agent/templates/<svc>.env.tpl`:

```
{{ with secret "kv/projects/${PROJECT_NAME}/db" -}}
PG_DSN=postgres://{{ .Data.data.user }}:{{ .Data.data.password }}@postgres:5432/{{ .Data.data.dbname }}
{{- end }}
```

Каждый новый рендер-таргет требует двух правок:
1. Создать `.tpl` в `configs/vault-agent/templates/`.
2. Добавить `template { source = ...; destination = "/secrets/<svc>.env"; perms = 0400 }` блок в `agent.hcl.tpl`.

После — рестарт vault-agent: `make restart SVC=vault-agent`. Consumer (backend и т.д.) поднимется когда `.ready` marker появится (depends_on: service_healthy).

### Ротация

Источник истины — Vault KV на корп-стороне:

```
# на корп-VPS (stit/infra)
vault kv patch kv/projects/<p>/db password=<new>
# на проектной — vault-agent заметит изменение, перерендерит .env
# но consumer уже прочитал env_file при старте — нужен рестарт
make restart SVC=backend
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
