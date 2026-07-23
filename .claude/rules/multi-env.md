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

Этот документ описывает контракт per-env `.env`: что где живёт, как активируются профили, как ротируются значения. Механика секретов (имена, рендер, что нельзя коммитить) — `.claude/rules/secrets-and-env.md`. Контракт с корпом (registry + CrowdSec) — `.claude/rules/corp-handoff.md`.

## Принцип: всё в .env

`.env` на VPS — единственный источник конфига и секретов среды. Оператор заполняет и ротирует руками; compose интерполирует значения в `environment:` сервисов, render-configs.sh — в `.tpl`-конфиги. Никаких внешних secret-backend'ов у шаблона нет.

### Что где живёт

| Категория | Где | Примеры |
|---|---|---|
| Identity | `.env` | `PROJECT_NAME`, `ENV`, `DOMAIN` |
| ACME | `.env` | `ACME_EMAIL`, `ACME_CASERVER` |
| Локально-сгенерированные | `.env` (auto после первого deploy) | `CROWDSEC_BOUNCER_API_KEY` |
| Оператор-управление | `.env` | `COMPOSE_PROFILES`, `HOST_ROLE` |
| Image-теги | `.env` (**строго**; бамп — `make bump SVC= TAG=`) | `BACKEND_TAG` (конвенция `<SVC>_TAG`) |
| Registry-эндпоинт | `.env` (managed-дефолт в коде; self-hosted override) | `REGISTRY_HOST=git.stit.tech` |
| Секреты профилей | `.env` (секции в `.env.example`) | `POSTGRES_*`, `OIDC_*`, `JWT_SECRET`, `MINIO_*`, `RESTIC_*` |

Полный контракт переменных с комментариями как сгенерировать — `.env.example`. Env'ы физически изолированы: разные VPS, разные `.env`, утечка значения одной среды не задевает другую.

## Operator flow — bootstrap нового VPS

На каждом VPS отдельный bootstrap (по одному на env):

```bash
make new-env             # prompt: PROJECT_NAME, ENV, DOMAIN, ACME_EMAIL
make ship                # минимальный стек: traefik + crowdsec + node-exporter + cadvisor + landing
```

Минимальному стеку секретов сверх ACME не нужно. Postgres/minio/backup/backend — в `compose.profiles`, не стартуют пока оператор их явно не включит.

## Operator flow — добавить секреты для нового профиля

Когда стек дозрел до `postgres`/`storage`/`backend` — зовёшь Claude skill `/request-secret` (`.claude/skills/request-secret/SKILL.md`). Skill:
- определяет по профилю/запросу нужный набор переменных (контракт — `.env.example`);
- генерит случайные пароли сам (`openssl rand`), внешние значения (OIDC-креды, external S3) спрашивает;
- печатает готовый блок `VAR=value` для дописывания в `.env` на VPS (без эха секретов в git).

После:

```bash
$EDITOR .env   # дописать блок + добавить профиль в COMPOSE_PROFILES
make ship      # compose поднимет новые сервисы
```

Project-specific переменные (например `STRIPE_KEY`) — тот же флоу + декларация в `.env.example` и `${VAR}` в compose (см. `secrets-and-env.md` § Новый секрет).

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
| `traefik`, `crowdsec`, `node-exporter`, `cadvisor`, `landing` | **always-on** | identity + `ACME_*` |
| `postgres` | `postgres` | `POSTGRES_*` |
| `minio` | `storage` | `MINIO_*`, `APP_S3_*`, `BACKUP_S3_*` |
| `backup` | `storage` | `RESTIC_*`, `BACKUP_AWS_*`, `POSTGRES_*` |
| `backend` | `backend` | `OIDC_*`, `JWT_SECRET`, `POSTGRES_*`, `BACKEND_TAG` |

`COMPOSE_PROFILES=postgres,backend make ship` = включить postgres + backend (их секции в `.env` должны быть заполнены). `storage` требует одновременного `postgres` (backup делает pg_dumpall) — `deploy.sh` валидирует на single-host.

## Контракт со `corp-infra-template` (что обязан гарантировать корп)

1. **Registry** `git.stit.tech` — pull образов `git.stit.tech/<p>/backend:<tag>` (плюс push-доступ разработчику backend-форка).
2. **CrowdSec whitelist** — egress-IP проектной VPS в корп-whitelist, иначе служебный трафик к корп-сервисам режется 403 (`corp-infra-template/.claude/rules/crowdsec-whitelist.md`).

Секреты корп не выдаёт и не хранит — они целиком на стороне проектной VPS.

Каждая среда — отдельный VPS с собственным `ENV` и `.env`. Среда не конвертируется in-place: добавление env'а проекту = bootstrap нового VPS под этот env (skill `bootstrap-vps`).
