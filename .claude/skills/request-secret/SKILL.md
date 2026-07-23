---
name: request-secret
description: Сформировать блок переменных для .env проектной VPS — секреты нового профиля/сервиса с генерацией паролей. Активируй на "/request-secret", "выпиши креды", "нужны креды для X", "секреты для профиля", "блок для .env".
---

# Skill: request-secret

Сформировать stdout-блок `VAR=value` для `.env` на проектной VPS: когда оператору нужны секреты нового профиля (postgres, storage, backend) или project-specific переменные (stripe-key, sendgrid-creds — что угодно).

Skill не действует за оператора — он печатает готовый блок, который оператор дописывает в `.env` на VPS (файл живёт только там, chmod 600, gitignored). После — обновить `COMPOSE_PROFILES` и `make ship`/`make deploy`. Корп-сторона в секретах не участвует.

Для **project-specific** переменной дополнительно нужны правки в репо: `${VAR}` в compose/`configs/*.tpl` + декларация в `.env.example` (см. `.claude/rules/secrets-and-env.md` § Новый секрет) — этот skill делает их сам (это не corp-поверхность).

## Когда применять

- "Выпиши креды для postgres / minio / stripe / ..."
- "Нужен блок секретов для профиля storage"
- "/request-secret"
- Когда активация профиля требует незаполненных переменных из `.env.example`.

## Когда НЕ применять

- Юзер хочет ротировать существующее значение — это правка одной строки в `.env` на VPS + `make deploy` (упомяни, не центрируй).
- Юзер хочет добавить новый сервис в стек — это `/add-service`. Этот skill активируется когда сервис уже добавлен и пора заполнить его секреты.
- Registry-доступ / CrowdSec-whitelist / DNS — это corp-поверхность, skill `corp-handoff`.

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

Поля identity (`PROJECT_NAME`/`ENV`) — не секреты, `grep`/`awk` по ним легитимен. Сами
**значения** секретов из `.env.local` (токены) так не вытаскивай — security-инвариант
`env-local.md` (доступ к кредам только через tools, без эха в чат) остаётся в силе.

### 2. Определи набор переменных

Стандартные наборы (контракт — `.env.example`, секции `profile <name>`):

| Профиль | Переменные | Генерится / задаётся |
|---|---|---|
| `postgres` | `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB` | user/db — слова; password — генерится |
| `backend` | `OIDC_CLIENT_ID`, `OIDC_CLIENT_SECRET`, `JWT_SECRET` | OIDC — выдаёт IDP оператора; JWT — генерится |
| `storage` | `MINIO_ROOT_USER`, `MINIO_ROOT_PASSWORD`, `APP_S3_ACCESS_KEY`, `APP_S3_SECRET_KEY`, `BACKUP_S3_ACCESS_KEY`, `BACKUP_S3_SECRET_KEY`, `MINIO_BUCKETS` (опц), `RESTIC_REPOSITORY`, `RESTIC_PASSWORD`, `BACKUP_AWS_ACCESS_KEY_ID`, `BACKUP_AWS_SECRET_ACCESS_KEY` | пароли/ключи — генерятся; `RESTIC_REPOSITORY` — задаёт оператор (external endpoint!) |

**Project-specific** — что угодно (`STRIPE_KEY`, `SENDGRID_API_KEY`). Для них перед блоком сделай правки в репо: `${VAR}` в `environment:` consumer'а + декларация в `.env.example` с комментарием — иначе значение до сервиса не доедет.

### 3. Спроси / выясни значения

Для случайных значений (пароли, signing keys) — генерируй локально:
```bash
openssl rand -hex 32    # password / JWT_SECRET / RESTIC_PASSWORD
openssl rand -hex 8     # 16-char hex — S3 access_key (короткий: minio SA access_key 3-20 chars)
openssl rand -hex 16    # 32-char hex — S3 secret_key
```

Не печатай эти команды в выводе — генери значения сам и подставляй в блок. Оператор не должен делать дополнительных шагов. Внешние значения (OIDC-креды от IDP, `RESTIC_REPOSITORY`, ключи third-party API) — спроси или оставь placeholder с пояснением.

### 4. Печатай блок

Формат — один stdout-блок (plain-текст, чтобы оператор мог copy-paste целиком в `.env` на VPS):

```
================================================================================
ДОПИШИ В .env НА VPS (/opt/<p>-infra/.env, chmod 600). Секция: profile <name>.
--------------------------------------------------------------------------------
POSTGRES_USER=app
POSTGRES_PASSWORD=<generated>
POSTGRES_DB=app
--------------------------------------------------------------------------------
После: добавь профиль в COMPOSE_PROFILES и `make ship` (или `make deploy` на VPS).
Ротация: правка значения в .env + `make deploy`.
================================================================================
```

Если значения чувствительные (`RESTIC_PASSWORD`, generated keys) — напомни оператору продублировать offsite. Без `RESTIC_PASSWORD` restore из снапшотов невозможен **даже** при сохранённом репозитории.

### 5. Поясни next steps

После дописывания блока оператору обычно нужно:
1. Обновить `COMPOSE_PROFILES` в `.env` (если набор связан с профилем — postgres / storage / backend).
2. `make ship` (или `make deploy` на VPS) — compose поднимет/пересоздаст сервисы с новым env.

Скажи юзеру что именно нужно делать дальше — не оставляй его гадать.

## Несколько кредов одного "типа"

Иногда нужно >1 user'а для postgres, >1 OIDC-клиента и т.п. Путь один: дополнительные переменные (`POSTGRES_READONLY_USER`, `POSTGRES_READONLY_PASSWORD`) + декларация в `.env.example` + расширение consumer'а (`environment:` в compose, init.sql / migrations, чтобы создавал доп. юзеров). Согласуй имена с оператором.

## Anti-patterns

- **Печатать литералы значений без генерации.** Если поле должно быть случайным (`password`, `JWT_SECRET`, S3 keys) — генери `openssl rand` САМ, не оставляй `<value>` placeholder. Только для внешне-задаваемых полей (`OIDC_CLIENT_ID` от IDP, `RESTIC_REPOSITORY`, third-party ключи) — placeholder с пояснением.

- **Класть значения секретов в репо.** Блок — только для `.env` на VPS. В `.env.example` — пустые декларации с комментарием, в compose — `${VAR}`. Никогда не коммить реальное значение.

- **Префиксы env'а в имени.** Не `POSTGRES_PASSWORD_PROD` — env-разделение уже физическое (один VPS = один env = один `.env`). Имя описывает _что_, не _где_.

- **Путать секрет-блок с tool-only кредами.** Печатаемый блок — намеренный hand-off оператору
  (значения в нём — для copy-paste в серверный `.env`). А вот креды, которые **присылает
  оператор** (готовый токен, connection к VPS), — НЕ эхо-ить: токен → агент пишет в
  `.env.local`, значение не цитирует (`.claude/rules/env-local.md`).
