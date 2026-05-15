# multi-env

**Status:** done
**Slug:** multi-env

Перевод шаблона на multi-environment модель: один проект = N сред (`dev`, `prod`, ...) = N VPS, каждый со своим `ENV` в `.env`. Vault — единственный источник правды по конфигу и секретам проекта; `.env` сжимается до identity + bootstrap-auth.

## Направление

Максимально в Vault. Любое значение, которое (а) меняется реже чем раз в неделю и (б) должно быть централизованно ротируемым корп-стороной — переезжает в `kv/projects/<p>/<env>/*`. В `.env` остаётся только то, без чего AppRole-login невозможен или что инициализуется локально (`CROWDSEC_BOUNCER_API_KEY` — auto-register).

### Что где живёт (финал после миграции)

| Переменная | Где | Почему |
|---|---|---|
| `PROJECT_NAME`, `ENV`, `DOMAIN` | `.env` | identity, нужно ДО Vault-login. `DOMAIN` — кандидат на перенос в отдельной фазе, требует compose.env через vault-agent. |
| `VAULT_ROLE_ID`, `VAULT_SECRET_ID` | `.env` | secret-zero. |
| `VAULT_ADDR`, `OTEL_EXPORTER_OTLP_*` | hardcoded в шаблоне | корп-константы. |
| `BACKEND_TAG`, `ACME_EMAIL`, `ACME_CASERVER`, image tag'и других сервисов | **Vault** `kv/projects/<p>/<env>/meta` | централизованный rollout/ротация. |
| `RESTIC_REPOSITORY` | **Vault** `kv/projects/<p>/<env>/backup` | endpoint решает корп. |
| Runtime-секреты (db, oidc, jwt, minio, backup, otel) | **Vault** `kv/projects/<p>/<env>/{db,oidc,jwt,minio,backup,otel}` | как сейчас. |
| `CROWDSEC_BOUNCER_API_KEY` | `.env` (auto-register на первом deploy) | local-only артефакт. |
| `COMPOSE_PROFILES` | `.env` | оператор-only переключатель lazy stack. |

## KV layout

```
kv/projects/<p>/
  _meta                       # { env_<env>=1, ..., created: <ISO> }  ← корп пишет при онбординге
  <env>/
    meta                      # { backend_tag, acme_email, acme_caserver, ... }  ← non-secret конфиг
    otel                      # token                  ← засеивается при онбординге
    db                        # user/password/database
    oidc                      # client_id/client_secret
    jwt                       # signing_key
    minio                     # root_user/root_password + app/backup access/secret keys
    backup                    # restic password + AWS creds + repository
```

AppRole `projects-<p>-<env>` (flat — Vault не принимает слеши в `auth/approle/role/<name>`) имеет policy:
```hcl
path "kv/data/projects/<p>/<env>/*" { capabilities = ["read"] }
```

Невозможность залогиниться с чужим ENV = валидация. `_meta` читает только корп (для аудита/документации).

## Phases

### Phase 0: Контракт (этот PR + .claude/rules/multi-env.md)

- `.claude/plans/multi-env.md` ← здесь
- `.claude/plans/roadmap.md` ← добавить в Активные
- `.claude/rules/multi-env.md` ← контракт для проектной стороны И stit-infra/infra
  - KV layout
  - Onboard flow (`onboard-project --name <p> --envs dev,prod`)
  - Request-secret flow (оператор → корп-админ)
  - Profile-based opt-in flow
  - Что обязан сделать `stit-infra/infra` (контракт)

### Phase 1: ENV dimension

- `.env.example` + `scripts/new-env.sh`: prompt `ENV`, валидация (a-z+digits), `RESTIC_REPOSITORY` auto-convention (`s3://.../<p>-<env>-backups` если оператор не override'ит, но фактически он живёт в Vault — `.env` его не содержит).
- `compose/vault-agent.yml`: прокинуть `ENV` в environment.
- `configs/vault-agent/templates/*.tpl`: path `kv/data/projects/%s/%s/...` через `(env "PROJECT_NAME")` + `(env "ENV")`.
- Слить `kv/observability/tenants/<p>` → `kv/projects/<p>/<env>/otel`. Поправить `backend.env.tpl`.
- Удалить `RESTIC_REPOSITORY` из `.env` / `compose/vault-agent.yml` environment / `scripts/deploy.sh` грязный grep — теперь приходит из `backup.env` (через vault-agent).
- Добавить рендер `kv/projects/<p>/<env>/meta` в новый `.runtime/env/compose.env` (через vault-agent template), переключить compose на `--env-file .env --env-file .runtime/env/compose.env` (через Makefile).
- `BACKEND_TAG`, `ACME_EMAIL`, `ACME_CASERVER` — переезжают в `meta` KV-объект.

Блокер: требует синхронной правки `stit-infra/infra/onboard-project.sh` (новые KV paths + meta-объект). Не катить пока корп-сторона не подравняется.

### Phase 2: Lazy stack (profiles + blocks)

- Разрезать `configs/vault-agent/agent.hcl.tpl` на `head.tpl` / `tail.tpl` / `blocks/<name>.tpl`.
- `scripts/render-configs.sh`: собирает `agent.hcl` из head + always-on (otel, meta) + per-profile-blocks + tail.
- `compose/postgres.yml` → `profiles: [postgres]`. `compose/minio.yml`, `compose/backup.yml` → `profiles: [storage]`. (Backend уже под `[backend]`.)
- `scripts/deploy.sh`: детектит смену активных profile'ов (по `.runtime/.profiles-prev` snapshot) → trigger force-recreate vault-agent.
- Vault-agent healthcheck: оставить blocker-check на `backend.env` / `postgres.env` УСЛОВНЫМ от активных profile'ов (рендерится `health.sh` с нужным набором).

### Phase 3: new-env.sh cleanup

- Убрать генерацию `.onboard-creds` (minio/restic creds теперь корп-side).
- Убрать `scripts/show-onboard-creds.sh` (не нужен).
- `new-env.sh` оставляет только prompt 4 значений (PROJECT_NAME, ENV, DOMAIN, VAULT_ROLE_ID, VAULT_SECRET_ID) + `.env`.
- Удалить `.onboard-creds` из `.gitignore` если он там как explicit entry (gitignored через `.env*`).

### Phase 4: skill `.claude/skills/request-secret/`

- Вместо shell-скрипта — Claude skill (`.claude/skills/request-secret/SKILL.md`).
- Оператор зовёт `/request-secret`; Claude спрашивает имя (произвольный slug), поля, генерит случайные значения через `openssl rand`, печатает блок `vault kv put kv/projects/<p>/<env>/<name>` для копи-паста.
- Стандартные имена (`db`/`minio`/`backup`/`oidc`/`jwt`/`meta`/`otel`) задокументированы в SKILL.md как cookbook; project-specific (`stripe-key`, etc.) — по факту.

### Phase 5: Docs

- `.claude/rules/secrets-and-env.md` rewrite под multi-env (path с `<env>`, новый seed-флоу, profile-based opt-in).
- `.env.example` комменты.
- `README.md` — короткое обновление флоу (если есть).

## Контракт со stit-infra/infra (что должен сделать корп)

1. `onboard-project.sh --name <p> --envs dev,prod` создаёт:
   - `kv/projects/<p>/_meta` с `{env_<env>=1, ..., created=<ISO>}`
   - Per env: AppRole `projects-<p>-<env>` (flat) + policy на `kv/data/projects/<p>/<env>/*`
   - Per env: `kv/projects/<p>/<env>/otel` (token)
   - Per env: `kv/projects/<p>/<env>/meta` с дефолтами `backend_tag=latest`, `acme_email=ops@<domain-placeholder>`, `acme_caserver=https://acme-v02.api.letsencrypt.org/directory`
   - Возвращает оператору per-env блок: `PROJECT_NAME / ENV / VAULT_ROLE_ID / VAULT_SECRET_ID`.

2. `seed-secret.sh --project <p> --env <env> --kind <kind>` (или эквивалент) — admin tool для seed'а `db/oidc/jwt/minio/backup` по запросу оператора.

3. Все ротации — через `vault kv patch kv/projects/<p>/<env>/<kind>`. Vault-agent на VPS перерендерит, `scripts/deploy.sh` force-recreate-нёт consumer'ов на следующем deploy (или через MQTT-event/webhook, если когда-нибудь добавим).

## Open questions (на потом)

- `DOMAIN` в Vault — требует `compose.env` через vault-agent + перестройка порядка в `deploy.sh`. Phase 6, если будет нужно.
- `CROWDSEC_BOUNCER_API_KEY` — auto-register с post-seed в Vault (требует write-token у оператора). Не делаем пока нет ощутимой пользы.
- Webhook от Vault-агента при KV-change → авто-deploy без манального `make ship`. Корп-side, future.
