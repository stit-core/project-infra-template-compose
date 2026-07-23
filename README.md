<div align="center">

# project-infra-template-compose

### Проектная VPS-инфра одним docker-compose стеком

IaC-шаблон проектной инфры: один форк = один проект = один VPS на среду. Edge,
Postgres, MinIO, backend, vault-agent, backup — декларативно,
секреты из Vault. Форк → `<org>/infra`, разворот за день.

[![License](https://img.shields.io/badge/license-Apache--2.0-2563eb)](LICENSE)
[![Часть stit](https://img.shields.io/badge/stit-открытые_шаблоны-6366f1)](https://git.stit.tech/stit-core/stit-public)
[![Stack](https://img.shields.io/badge/stack-Docker_Compose-0ea5e9)](#что-внутри)
[![Edge](https://img.shields.io/badge/edge-Traefik_v3_%2B_CrowdSec-22c55e)](#что-внутри)
[![Secrets](https://img.shields.io/badge/secrets-vault--agent-000000)](#контракт-с-control-plane)
[![Open core](https://img.shields.io/badge/open_core-no_vendor_lock-8b5cf6)](#два-пути-managed-или-self-hosted)

</div>

---

## Место в экосистеме

```
corp-infra-template          control plane — Vault · registry
      │  onboard-project.sh → AppRole projects-<p>-<env> + KV seed
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

- **Managed (stit).** Наводите эндпоинты на наш контур (`vault.stit.tech`,
  `git.stit.tech`); мы онбордим проект (`onboard-project.sh`) и
  держим uptime. Меньше всего возни.
- **Self-hosted.** Поднимаете **свой** control-plane из
  [`corp-infra-template`](https://git.stit.tech/stit-core/corp-infra-template)
  (свой Vault, registry, онбординг) и наводите эти же эндпоинты на
  него — ни от кого не зависите.

Технически меняется только хост Vault / registry — он в `.env` и KV, не
зашит. Стек и контракты одинаковы в обоих путях.

## Что внутри

| Слой | Что | Активация |
|---|---|---|
| **Edge** | Traefik v3 + CrowdSec — HTTP-01 LE, WAF, IP-bans | always-on |
| **Secrets** | vault-agent sidecar — рендерит секреты из Vault на VPS | always-on |
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

**1. Корп-онбординг** (один раз на среду, на control-plane):
```bash
VAULT_TOKEN=<root> make onboard NAME=acme ENVS=dev,prod
```
Создаёт per-env AppRole + сеет `kv/projects/acme/<env>/meta`; возвращает
`PROJECT_NAME / ENV / VAULT_ROLE_ID / VAULT_SECRET_ID` на каждую среду.

**2. Форк + bootstrap VPS** (один VPS на среду): `Use this template` →
`<org>/infra`, клон, поднять чистый VPS и завести identity:
```bash
cp ansible/inventory.example.ini ansible/inventory.ini   # host/IP (gitignored)
ansible-galaxy collection install -r ansible/requirements.yml
ansible-playbook -i ansible/inventory.ini ansible/bootstrap.yml
# на VPS, в /opt/<p>-infra:
PROJECT_NAME=acme ENV=prod DOMAIN=acme.com VAULT_ROLE_ID=<id> VAULT_SECRET_ID=<id> \
  make new-env                   # .env (chmod 600), 5 переменных — остальное из Vault
```

**3. Первый деплой** (с рабочей станции оператора):
```bash
make ship        # check + push + (на main) ssh-deploy. На чистом дереве MSG не нужен.
```
Минимальный стек (traefik / vault-agent / crowdsec / metrics / landing)
живёт сразу. Дальше — активация профилей: `/request-secret` → блок `vault kv put`
корп-админу → `COMPOSE_PROFILES` + `make ship`.

## Принципы

- **Конфиг → код.** Всё декларативно в `compose/*.yml` и `configs/`. Нет «только на сервере».
- **Максимум в Vault.** `.env` минимален (identity + AppRole-bootstrap). Image-теги,
  ACME, restic endpoint, runtime-секреты — в `kv/projects/<p>/<env>/*`,
  ротируются централизованно.
- **Multi-env через KV-dimension.** Один шаблон, N VPS, у каждого свой `ENV` и scope в Vault.
- **Lazy stack.** Минимальный стек на meta seed'е; profiled-сервисы — по мере seed'ов.
- **Локальный CI.** Backend-образ собирает разработчик; `make ship` пушит код + ssh-деплоит.

## Контракт с control-plane

- **Vault** — secrets backend; AppRole per `(project, env)` от `onboard-project.sh`.
- **Registry** — образы backend / worker / frontend.

KV-layout, onboarding-флоу и multi-env — [`.claude/rules/multi-env.md`](.claude/rules/multi-env.md).
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
