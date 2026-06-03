# Чек-листы секций service-doc

`docs/project/services/<name>.md` несёт 5 обязательных H2: Hosting /
Identity / Secrets / Route / Generates. По разделу на каждую секция:

- **Что фиксируем** — поля, которые должны попасть в текст.
- **Опции опрашиваются как** — enum / anti-pattern / Other.
- **Что НЕ** — anti-patterns с примерами.
- **Тест-критерий** — ✅/❌ образцы.
- **Порядок копания** — последовательность вопросов в режиме A/C.

Полный канон — `docs/project/README.md`. Здесь — выжимка для скилла.

---

## Hosting

**Что фиксируем**:

- `hosting`: `here` (контейнер в этом репо) / `external` (свой репо/CDN —
  service-doc НЕ заводим).
- Какой `COMPOSE_PROFILES`-профиль активирует этот сервис:
  - `backend` → `backend`,
  - `datastore` postgres → `postgres`,
  - `datastore` minio → `storage`,
  - `frontend` landing → `—` (always-on `landing`),
  - `infra` → обычно always-on, не профильное.
- Источник: для `backend` — внешний source-репо `<org>/backend`, но
  контейнер `here`; для движков (postgres/minio) — official image; для
  кастомного образа — `git.stit.tech/<org>/<name>`.

**Опции опрашиваются как**:

- `hosting`: enum (`here`/`external`) — 2 опции.
- Профиль: enum существующих профилей.
- Источник: 2 опции «свой образ» / «public engine», далее Other.

**Что НЕ**:

- Не дублировать весь `COMPOSE_PROFILES` целиком — здесь только какой
  профиль активирует ЭТОТ сервис.
- Не путать `here` с «образ собирается в этом репо» — backend хостится
  here, но source-репо внешний (это разные оси).

**Тест-критерий**:

- ✅ «Сервис `here`, профиль `postgres`, образ движок `postgres:17.X`».
- ✅ «Сервис `here`, профиль `backend`, образ `git.stit.tech/<org>/backend:<sha>`».
- ❌ «Сервис `external` с service-doc» (это рассинхрон, такого быть не должно).
- ❌ «Дублирован полный набор `COMPOSE_PROFILES=postgres,storage,backend`».

**Порядок копания**:

1. `hosting` (если ещё не во frontmatter).
2. Какой профиль активирует (из карты subtype).
3. Источник (свой образ или engine).

---

## Identity

**Что фиксируем**:

- Образ: `<registry>/<image>:<tag>` **pinned** (semver / sha-prefix /
  date-tag — НЕ `:latest`).
- `container_name` (обычно `<name>`, иногда суффикс).
- `healthcheck`: команда или path. Для postgres — `pg_isready`, для
  HTTP-API — `wget`/`curl` + `/healthz`, для minio — `mc ready`.
- Сети: `proxy` (наружу — если public) и/или `backend-net` (internal).

**Опции опрашиваются как**:

- Образ: Other (конкретный tag — архитектор называет).
- `container_name`: 2 опции «дефолт == name» / «другой» (Other).
- Сети: multiSelect (`proxy` / `backend-net` / «обе»).
- Healthcheck: 3 опции «команда внутри контейнера» / «HTTP path через
  wget/curl» / «нет (TBD)», далее Other для конкретики.

**Что НЕ**:

- `image: <registry>/<image>:latest` — anti-pattern (ловится
  `make validate`).
- Контейнер в `proxy`-сети, но без traefik labels — лишняя поверхность.
- Контейнер public, но не в `proxy` — traefik не достучится.
- `healthcheck` отсутствует — обязательная конвенция шаблона.
- `container_name` совпадает с другим сервисом на shared VPS — конфликт.

**Тест-критерий**:

- ✅ «`image: postgres:17.4`, `container_name: db`, healthcheck
  `pg_isready -U postgres`, сеть `backend-net`».
- ✅ «`image: git.stit.tech/acme/backend:abc1234`, healthcheck
  `wget -qO- http://localhost:8080/healthz`, сети `proxy + backend-net`».
- ❌ «`image: minio/minio:latest`» — pinned обязательно.
- ❌ «public сервис без сети `proxy`».

**Порядок копания**:

1. Образ + tag (Other).
2. `container_name` (Other если не дефолт).
3. Healthcheck (Other).
4. Сети (multiSelect).
5. Anti-patterns: «`:latest`?» / «healthcheck есть?» / «сеть `proxy` при
   public?».

---

## Secrets

**Что фиксируем**:

- Какой Vault KV нужен: `kv/projects/<p>/<env>/<kind>` — `kind` ∈
  {`db`, `minio`, `backup`, `backend`, `jwt`, `oidc`, project-specific}.
- Поля KV (`user`/`password`/`database` для db; `root_user`/
  `root_password`/`access_key`/`secret_key` для minio; project-specific
  для backend).
- Какой vault-agent template рендерит env-файл — обычно
  `configs/vault-agent/templates/<kind>.env.tpl` → итог
  `.runtime/<kind>.env`, подключается `env_file:`.
- Если секретов нет — `N/A` явной строкой.

**Опции опрашиваются как**:

- KV-kind: enum существующих + «нужен новый» (Other → /request-secret
  next-step).
- Поля: Other (свободный список — архитектор называет).
- Template: 2 опции «существующий `<kind>.env.tpl`» / «нужен новый»
  (Other → cross-repo next-step).

**Что НЕ**:

- Хранить секрет в `.env` или `configs/` — всё через vault-agent.
- Прямое чтение `$VAULT_TOKEN` или `/run/secrets/` из приложения —
  anti-pattern (только env_file через vault-agent).
- KV-путь без `<p>/<env>` префикса — корп-AppRole не пропустит.
- Хардкодить креды в образ — никогда.

**Тест-критерий**:

- ✅ «`kv/projects/acme/dev/db` поля `user/password/database`,
  template `db.env.tpl` → `.runtime/db.env`, backend через
  `env_file:`».
- ✅ «`N/A` — сервис не читает секретов».
- ❌ «postgres-пароль в `.env` напрямую» — не через vault.
- ❌ «KV `kv/db` без env-префикса».

**Порядок копания**:

1. Есть ли вообще секреты? (если нет — `N/A`, секция готова).
2. KV-kind (enum + Other).
3. Поля (Other).
4. Template (enum + Other).
5. Anti-patterns: «через vault-agent?» / «env-префикс есть?».

---

## Route

**Что фиксируем**:

- Public или internal:
  - Public → сабдомен (`<sub>.${DOMAIN}` или корень `${DOMAIN}`),
    traefik router, обязательный middleware `crowdsec@file`, порт
    контейнера, путь LE-сертификата.
  - Internal → `_internal_` явной строкой (доступ только из
    `backend-net`).
- Если public: какой именно сабдомен.

**Опции опрашиваются как**:

- Public/internal: 2 опции.
- Сабдомен: Other (архитектор называет — это стратегия проекта).
- Middleware: 2 опции «`crowdsec@file` (дефолт)» / «без middleware»
  (anti-pattern, спросить почему).

**Что НЕ**:

- Public сервис без `crowdsec@file` middleware — anti-pattern на
  публичной поверхности.
- `_internal_`, но в сети `proxy` — лишняя поверхность.
- Сабдомен, не упомянутый в `stack § Domains`, — рассинхрон (stub).
- Сабдомен корневой `${DOMAIN}` для не-landing — конфликт с landing.

**Тест-критерий**:

- ✅ «public, `api.${DOMAIN}`, traefik router + `crowdsec@file`, порт
  8080, LE через `acme_email/caserver` meta».
- ✅ «`_internal_` — backend-net only».
- ❌ «`api.example.com` без middleware» — публичная поверхность без
  щита.
- ❌ «`${DOMAIN}` для backend» — landing занимает корень.

**Порядок копания**:

1. Public или internal?
2. Если public: сабдомен (Other) + порт.
3. Middleware (дефолт).
4. Сверить с `stack § Domains` — если нет, stub-next-step.
5. Anti-patterns: «без middleware?» / «лишняя сеть?».

---

## Generates

**Что фиксируем** — контракт для `/de-template`:

- `COMPOSE_PROFILES += <profile>` (или «always-on» для landing/infra).
- `compose/<name>.yml` — keep (при `hosting: here`).
- `configs/vault-agent/agent.hcl.parts/<part>.hcl` — keep (если секреты).
- `configs/vault-agent/templates/<kind>.env.tpl` — keep (если секреты).
- traefik labels или dynamic route (если public).
- Для `hosting: external` — cross-repo next-step («форкни `<repo>`,
  запиши tag в `kv/.../meta.backend_tag`»).

**Опции опрашиваются как** — обычно Other (имена parts/templates —
архитектор называет по реальным файлам), enum только для да/нет «нужен
этот pull-up».

**Что НЕ**:

- Пустой `Generates` — движку `/de-template` не из чего разворачивать.
- Дублировать полный `COMPOSE_PROFILES` — здесь только `+=` для **этого**
  сервиса.
- Описывать always-on сервисы (traefik/crowdsec/vault-agent/...) — они
  фундамент шаблона, не из service-doc.

**Тест-критерий**:

- ✅ «`COMPOSE_PROFILES += postgres`; `compose/postgres.yml` keep;
  `agent.hcl.parts/postgres.hcl` + `templates/db.env.tpl` keep».
- ✅ «`COMPOSE_PROFILES` — нет (always-on landing); `compose/landing.yml`
  keep; traefik labels для `${DOMAIN}`».
- ✅ «external; cross-repo next-step: форкни `<org>/frontend`,
  деплой на CDN».
- ❌ «`Generates` пуст».
- ❌ «`COMPOSE_PROFILES=postgres,storage,backend`» — целый набор не отсюда.

**Порядок копания**:

1. Какой профиль `+=` (или always-on)?
2. Compose-фрагмент keep?
3. Vault-agent parts/templates keep (если есть Secrets)?
4. Traefik labels / dynamic route (если public)?
5. Для external — cross-repo next-step текстом.

---

## Глобальные Anti-patterns kind=service

Кросс-секционные ошибки, ловятся в режиме C прохода:

| anti-pattern | где смотреть | вопрос |
|---|---|---|
| `:latest` тег | Identity | «образ pinned (semver/sha) — или `:latest`?» |
| Public без middleware | Route | «`crowdsec@file` есть?» |
| Секрет в `.env` напрямую | Secrets | «всё через vault-agent?» |
| service-doc для `external` | frontmatter + Hosting | «`hosting: external` → файл вообще должен быть?» (нет → каскад) |
| Пустой `Generates` | Generates | «что родит de-template?» |
| Сабдомен не в `stack § Domains` | Route | «допилить stack — или это уже в нём?» |
| Дублирован `COMPOSE_PROFILES` | Hosting / Generates | «только профиль этого сервиса — да?» |

## Глобальный Тест-критерий kind=service

Через `AskUserQuestion` 1 раунд, 2 опции:

- ✅ «Этот файл описывает один hosted-сервис целиком: хостинг,
  идентичность, секреты, роут и контракт для движка — без пропусков и
  без дублирования соседних артефактов».
- ❌ «Это часть описания (некоторые секции пусты или `<...>`), или
  пересекается со `stack` (cross-cutting/карта), или описывает несколько
  сервисов в одном файле».

При ❌ — выйти в C-режим по конкретной дыре. При ✅ — пункт 5
чек-листа `draft-stable.md` пройден.
