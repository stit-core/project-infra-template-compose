<div align="center">

# project-infra-template-compose

### Проектная VPS-инфра одним docker-compose стеком

IaC-шаблон проектной инфры: один форк = один проект = один VPS на среду. Edge,
Postgres, MinIO, backend, backup — декларативно,
секреты в `.env` на VPS. Форк → `<org>/infra`, разворот за день.

[![License](https://img.shields.io/badge/license-Apache--2.0-2563eb)](LICENSE)
[![Часть stit](https://img.shields.io/badge/stit-открытые_шаблоны-6366f1)](https://git.stit.tech/stit-core/stit-public)
[![Stack](https://img.shields.io/badge/stack-Docker_Compose-0ea5e9)](#что-внутри)
[![Edge](https://img.shields.io/badge/edge-Traefik_v3_%2B_CrowdSec-22c55e)](#что-внутри)
[![Secrets](https://img.shields.io/badge/secrets-plain_.env-000000)](#контракт-с-control-plane)
[![Open core](https://img.shields.io/badge/open_core-no_vendor_lock-8b5cf6)](#два-пути-managed-или-self-hosted)

</div>

---

## Место в экосистеме

```
corp-infra-template          control plane — registry · CrowdSec
      │  registry-pull + whitelist egress-IP
      ▼
project-infra-template-compose   ← вы здесь   (форк → <org>/infra, один VPS на среду)
      │  runtime для образа backend
      ▼
<org>/backend                форк go-backend-template ──► stit-core/golibinfra
```

Продуктовый контекст (vision, surfaces) — в соседнем `<org>/strategy` (форк
[`business-strategy-template`](https://git.stit.tech/stit-core/business-strategy-template)),
читается cross-repo. Канон контрактов —
[`corp-infra-template/docs/ecosystem.md`](https://git.stit.tech/stit-core/corp-infra-template/src/branch/main/docs/ecosystem.md).

## Два пути: managed или self-hosted

Вендор-лока нет — control-plane может быть наш или ваш:

- **Managed (stit).** Наводите registry на наш контур (`git.stit.tech`);
  мы держим uptime. Меньше всего возни.
- **Self-hosted.** Поднимаете **свой** control-plane из
  [`corp-infra-template`](https://git.stit.tech/stit-core/corp-infra-template)
  (свой registry) и наводите registry-эндпоинт на него — ни от кого не
  зависите.

Технически меняется только хост registry — он в `.env`, не зашит. Стек и
контракты одинаковы в обоих путях.

## Что внутри

| Слой | Что | Активация |
|---|---|---|
| **Edge** | Traefik v3 + CrowdSec — HTTP-01 LE, WAF, IP-bans | always-on |
| **Host metrics** | cadvisor · node-exporter — локальные метрики хоста/контейнеров | always-on |
| **Landing** | заглушка корня `${DOMAIN}` под LE-cert | always-on |
| **DB** | Postgres 17 | profile `postgres` |
| **Storage** | MinIO (S3 + Console) | profile `storage` |
| **Backup** | restic + pg_dumpall + crond (alpine), daily → restic-репо | profile `storage` |
| **App** | backend, образ из вашего registry | profile `backend` |

Always-on поднимается на минимальном seed'е (`meta`); остальное — opt-in
через `COMPOSE_PROFILES`, по мере seed'а их KV. Дефолт — single-host; Postgres /
MinIO можно вынести на отдельные хосты (split) — см.
[`docs/reference/architecture.md`](docs/reference/architecture.md).

## Быстрый старт

Полный путь (corp Day-0 → bootstrap VPS → профили → `/init-project`) —
**[`docs/getting-started.md`](docs/getting-started.md)**. Коротко, три шага:

**1. Корп-handoff** (один раз на среду): egress-IP будущей VPS — в корп
CrowdSec-whitelist; доступ к registry `git.stit.tech` для pull/push образов.

**2. Форк + bootstrap VPS** (один VPS на среду): `Use this template` →
`<org>/infra`, клон, поднять чистый VPS и завести identity:
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
Минимальный стек (traefik / crowdsec / metrics / landing)
живёт сразу. Дальше — активация профилей: `/request-secret` → блок `VAR=value`
в `.env` на VPS → `COMPOSE_PROFILES` + `make ship`.

## Принципы

- **Конфиг → код.** Всё декларативно в `compose/*.yml` и `configs/`. Нет «только на сервере».
- **Всё в .env.** Один файл на VPS (chmod 600, gitignored) — identity, ACME,
  image-теги, секреты профилей. Оператор заполняет и ротирует руками.
- **Multi-env физически.** Один шаблон, N VPS, у каждого свой `ENV` и свой `.env`.
- **Lazy stack.** Минимальный стек без секретов профилей; profiled-сервисы — по мере заполнения `.env`.
- **Локальный CI.** Backend-образ собирает разработчик; `make ship` пушит код + ssh-деплоит.

## Контракт с control-plane

- **Registry** `git.stit.tech` — образы backend / worker / frontend.
- **CrowdSec whitelist** — egress-IP проектной VPS.

`.env`-контракт и multi-env — [`.claude/rules/multi-env.md`](.claude/rules/multi-env.md).
Restore из backup'а — `make restore-pg SNAPSHOT=latest`
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
