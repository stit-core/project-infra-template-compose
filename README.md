<div align="center">

# project-infra-template-compose

### Проектная VPS-инфра одним docker-compose стеком

IaC-шаблон проектной инфры: один форк = один проект = один VPS на среду. Edge,
Postgres, MinIO, backend, индексируемый сайт, backup — декларативно,
секреты в `.env` на VPS. Форк → `<org>/infra`, разворот за день.

[![License](https://img.shields.io/badge/license-Apache--2.0-2563eb)](LICENSE)
[![Часть stit](https://img.shields.io/badge/stit-открытые_шаблоны-6366f1)](https://git.stit.tech/stit-core/stit-public)
[![Stack](https://img.shields.io/badge/stack-Docker_Compose-0ea5e9)](#что-внутри)
[![Edge](https://img.shields.io/badge/edge-Traefik_v3_%2B_CrowdSec-22c55e)](#что-внутри)
[![Secrets](https://img.shields.io/badge/secrets-plain_.env-000000)](#принципы)

</div>

---

## Место в экосистеме

```
<org>/strategy                      design-time SoT: бизнес, продукт, домены, UX
      │  читается cross-repo (vision, surface)
      ▼
<org>/infra   ← вы здесь            операционный хаб: общий план, агенты в сиблингах,
      │                             выкатка тегов (make bump); один VPS на среду
      ▼
<org>/{backend,frontend,site,<bot>} образ в registry своим /release → выкатка отсюда
<org>/mobile                        задачи отсюда; релиз — в магазины
```

Форки одной орги лежат рядом sibling-checkout'ами; продукт проектируется первым — в
`<org>/strategy` (форк
[`business-strategy-template`](https://git.stit.tech/stit-core/business-strategy-template)).
Карта всех репо, операционный флоу и контракты —
[`docs/reference/ecosystem.md`](docs/reference/ecosystem.md).

## Что внутри

| Слой | Что | Активация |
|---|---|---|
| **Edge** | Traefik v3 + CrowdSec — HTTP-01 LE, WAF, IP-bans, журнал доступа, allowlist поисковых и ИИ-ботов | always-on |
| **Landing** | заглушка корня `${DOMAIN}` под LE-cert до первого деплоя сайта | always-on |
| **DB** | Postgres 17 | profile `postgres` |
| **Storage** | MinIO (S3 + Console) | profile `storage` |
| **Backup** | restic + pg_dumpall + crond (alpine), daily → restic-репо | profile `storage` |
| **App** | backend, образ из registry (`REGISTRY_HOST`, дефолт `git.stit.tech`) | profile `backend` |
| **Site** | индексируемый сайт `<org>/site` на корне `${DOMAIN}` (`www` → корень) — `compose/site.yml`; приёмка — `make accept SVC=site` | profile `site` |

Always-on поднимается на identity + ACME из `.env`; остальное — opt-in через
`COMPOSE_PROFILES`, по мере заполнения их секций секретов в `.env`. Дефолт — single-host;
Postgres / MinIO можно вынести на отдельные хосты (split) — см.
[`docs/reference/architecture.md`](docs/reference/architecture.md).

## Быстрый старт

Полный путь (доступ к registry → bootstrap VPS → профили → `/init-project`) —
**[`docs/getting-started.md`](docs/getting-started.md)**. Коротко, три шага:

**1. Форк и доступ к registry** (один раз на проект): `Use this template` → `<org>/infra`,
клон; Gitea-аккаунт с PAT, которым VPS будет пуллить образы сервисов.

**2. Bootstrap VPS** (один VPS на среду): поднять чистый VPS и завести identity:
```bash
cp ansible/inventory.example.ini ansible/inventory.ini   # host/IP (gitignored)
ansible-galaxy collection install -r ansible/requirements.yml
ansible-playbook -i ansible/inventory.ini ansible/bootstrap.yml
# на VPS, в /opt/<p>-infra:
PROJECT_NAME=acme ENV=prod DOMAIN=acme.com ACME_EMAIL=ops@acme.com \
  make new-env                   # .env (chmod 600) — единственный источник секретов
```

**3. Первый деплой** (с рабочей станции оператора):
```bash
make ship        # check + push + (на main) ssh-deploy. На чистом дереве MSG не нужен.
```
Минимальный стек (traefik / crowdsec / landing)
живёт сразу. Дальше — активация профилей: допиши переменные профиля (см.
`.env.example`) в `.env` на VPS → `COMPOSE_PROFILES` + `make ship`. Сайт выкатывается тегом:
`make bump SVC=site TAG=vX.Y.Z`, затем `make accept SVC=site` (первый релиз —
[`docs/reference/ecosystem.md`](docs/reference/ecosystem.md)).

## Принципы

- **Конфиг → код.** Всё декларативно в `compose/*.yml` и `configs/`. Нет «только на сервере».
- **Всё в .env.** Один файл на VPS (chmod 600, gitignored) — identity, ACME,
  image-теги, секреты профилей. Оператор заполняет и ротирует руками.
- **Multi-env физически.** Один шаблон, N VPS, у каждого свой `ENV` и свой `.env`.
- **Lazy stack.** Минимальный стек без секретов профилей; profiled-сервисы — по мере заполнения `.env`.
- **Локальный CI.** Образы сервисов собирает и пушит их репо (`/release`); `make ship` пушит код инфры + ssh-деплоит, `make bump` выкатывает тег.

## Контракты

- **Registry** — образы сервисов тянутся из `REGISTRY_HOST` (дефолт `git.stit.tech`); тег —
  `<SVC>_TAG` в `.env`, выкатка — `make bump SVC=<svc> TAG=<tag>`.
- **`.env`-контракт и multi-env** — [`.claude/rules/multi-env.md`](.claude/rules/multi-env.md).
- **Restore из backup'а** — `make restore-pg SNAPSHOT=latest`
  ([`docs/reference/runbook.md`](docs/reference/runbook.md)).

## Навигация

| Куда | Зачем |
|---|---|
| [`docs/getting-started.md`](docs/getting-started.md) | путь от форка до работающей VPS |
| [`docs/reference/`](docs/reference/) | архитектура · экосистема · runbook/DR |
| [`CLAUDE.md`](CLAUDE.md) | точка входа для агента (ядро + роутер); дневной флоу — `/smartdev` |
| `make help` | полный словарь команд |

## Часть экосистемы stit

Это один из открытых шаблонов stit (Apache-2.0) — фундамент «-1 уровня»,
берите бесплатно и владейте. Карта всех шаблонов и точка входа —
**[витрина stit](https://git.stit.tech/stit-core/stit-public)**. Нужна
команда, стандарт или поддержка — **[наш подход и контакты (vision)](https://git.stit.tech/stit/vision)**.

## Лицензия

**Apache-2.0** — см. [`LICENSE`](LICENSE).
