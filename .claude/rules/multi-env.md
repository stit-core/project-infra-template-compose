---
name: multi-env
description: Проектная сторона multi-env контракта — per-env .env (единственный источник секретов/конфига), profile-based opt-in, ротация правкой .env + deploy. Один env = отдельный VPS со своим ENV и своим .env. Грузится при работе с .env, compose-профилями, ansible-онбордингом.
paths:
  - ".env*"
  - "compose/*.yml"
  - "ansible/roles/stit-onboard/**"
---

# Multi-environment

Один проект может иметь несколько сред (`dev`, `prod`, опционально `staging`/etc). Каждая среда — **отдельный VPS** с одним и тем же compose-шаблоном, но со своим `ENV` и своим `.env`. Шаблон агностичен к именам env'ов — это произвольные слаги.

Этот документ описывает контракт per-env `.env`: что где живёт, как активируются профили, как ротируются значения. Механика секретов (имена, рендер, что нельзя коммитить) — `.claude/rules/secrets-and-env.md`.

## Принцип: всё в .env

`.env` на VPS — единственный источник конфига и секретов среды. Оператор заполняет и ротирует руками; compose интерполирует значения в `environment:` сервисов, render-configs.sh — в `.tpl`-конфиги. Никаких внешних secret-backend'ов у шаблона нет.

### Что где живёт

| Категория | Где | Примеры |
|---|---|---|
| Identity | `.env` | `PROJECT_NAME`, `ENV`, `DOMAIN` |
| ACME | `.env` | `ACME_EMAIL`, `ACME_CASERVER` |
| Локально-сгенерированные | `.env` (auto после первого deploy) | `CROWDSEC_BOUNCER_API_KEY` |
| Оператор-управление | `.env` | `COMPOSE_PROFILES`, `HOST_ROLE` |
| Image-теги | `.env` (**строго**; бамп — `make bump SVC= TAG=`) | `BACKEND_TAG`, `SITE_TAG` (конвенция `<SVC>_TAG`) |
| Среда сайта | `.env` (`ROBOTS_POLICY` ставит `make new-env` по `ENV`, замок — оператор) | `ROBOTS_POLICY` (`index` — прод, `noindex` — любая другая), замок `STAGING_BASIC_AUTH_USERS` |
| Registry образов | `.env` (дефолт `git.stit.tech` в compose; другой registry — override) | `REGISTRY_HOST=git.stit.tech` |
| Секреты профилей | `.env` (секции в `.env.example`) | `POSTGRES_*`, `OIDC_*`, `JWT_SECRET`, `MINIO_*`, `RESTIC_*`, `SITE_SMTP_URL` |

Полный контракт переменных с комментариями как сгенерировать — `.env.example`. Env'ы физически изолированы: разные VPS, разные `.env`, утечка значения одной среды не задевает другую.

## Operator flow — bootstrap нового VPS

На каждом VPS отдельный bootstrap (по одному на env):

```bash
make new-env             # prompt: PROJECT_NAME, ENV, DOMAIN, ACME_EMAIL
make ship                # минимальный стек: traefik + crowdsec + landing
```

Минимальному стеку секретов сверх ACME не нужно. Postgres/minio/backup/backend — в `compose.profiles`, не стартуют пока оператор их явно не включит.

## Operator flow — добавить секреты для нового профиля

Когда стек дозрел до `postgres`/`storage`/`backend` — оператор:
- берёт набор переменных профиля из `.env.example` (контракт с комментариями, как сгенерировать каждое);
- генерирует случайные пароли (`openssl rand`), внешние значения (OIDC-креды, external S3) подставляет свои;
- дописывает блок `VAR=value` в `.env` на VPS (в git секреты не уезжают — `.env` gitignored).

После:

```bash
$EDITOR .env   # дописать блок + добавить профиль в COMPOSE_PROFILES
make ship      # compose поднимет новые сервисы
```

Project-specific переменные (например `STRIPE_KEY`) — тот же флоу + декларация в `.env.example` и `${VAR}` в compose (см. `secrets-and-env.md` § Новый секрет).

Сайт (`site`) включается не `make ship`, а тегом: секция `profile site`, на не-прод — замок и `make deploy`, затем
профиль и сразу `make bump SVC=site TAG=…`, затем `make accept SVC=site` — `docs/reference/ecosystem.md`
(«Первый релиз сайта на среде»).

## Ротация

Источник правды — `.env` на VPS. Любая ротация:

```bash
$EDITOR .env             # заменить значение
make deploy              # compose пересоздаёт сервисы с изменённым environment
```

Compose сравнивает интерполированный конфиг сам — точечный `make recreate SVC=` нужен только вне deploy-флоу. Image-теги под ротацию НЕ попадают: rollout нового тега — `make bump SVC=backend TAG=<tag>` (правит `BACKEND_TAG` в `.env` + force-recreate).

## Profile-based opt-in

Default-стек поднимается **без** секретов профилей. Сервисы с runtime-секретами сидят за `compose.profiles`:

| Сервис | Profile | Требует в .env |
|---|---|---|
| `traefik`, `crowdsec`, `landing` | **always-on** | identity + `ACME_*` |
| `postgres` | `postgres` | `POSTGRES_*` |
| `minio` | `storage` | `MINIO_*`, `APP_S3_*`, `BACKUP_S3_*` |
| `backup` | `storage` | `RESTIC_*`, `BACKUP_AWS_*`, `POSTGRES_*` |
| `backend` | `backend` | `OIDC_*`, `JWT_SECRET`, `POSTGRES_*`, `BACKEND_TAG` |
| `site` | `site` | `SITE_TAG`, `ROBOTS_POLICY`, канал формы (`SITE_FORM_*`, `SITE_SMTP_URL`); на не-прод — `ROBOTS_POLICY=noindex` и замок `STAGING_BASIC_AUTH_USERS` |

Включить postgres + backend = `COMPOSE_PROFILES=postgres,backend` в `.env` на VPS + `make ship` (их секции в `.env` должны быть заполнены). `storage` требует одновременного `postgres` (backup делает pg_dumpall) — `deploy.sh` валидирует на single-host.

Каждая среда — отдельный VPS с собственным `ENV` и `.env`. Среда не конвертируется in-place: добавление env'а проекту = bootstrap нового VPS под этот env (skill `bootstrap-vps`).
