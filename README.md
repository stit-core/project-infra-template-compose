# project-infra-template-compose

> IaC-шаблон проектной инфры — docker-compose стек одного VPS на клиентский
> проект. Форк → `<client-org>/infra`, адаптация под домен и стек, разворот за день.

Edge (Traefik v3 + CrowdSec) · Postgres · Minio · backend · vault-agent · otel-agent · backup —
декларативно, секреты из Vault, телеметрия в корп. Один VPS = одна среда.

## Экосистема

```
corp-infra-template          corp control plane — Vault · otel.sftbmb.ru · git.sftbmb.ru
      │  onboard-project.sh → AppRole projects-<p>-<env> + KV seed
      ▼
project-infra-template-compose   ← вы здесь   (форк → <client-org>/infra, один VPS на env)
      │  runtime для образа backend
      ▼
<client-org>/backend          форк go-backend-template ──► sftbmb-core/golibinfra
```

Канон контрактов — [`corp-infra-template/docs/ecosystem.md`](https://git.sftbmb.ru/sftbmb-core/corp-infra-template/src/branch/main/docs/ecosystem.md).

## Два пути: managed или self-hosted

Вендор-лока на инфре sftbmb нет — control-plane может быть наш или ваш:

- **Managed (sftbmb).** Наводите эндпоинты на наш контур (`vault.sftbmb.ru`, `otel.sftbmb.ru`,
  `git.sftbmb.ru`); мы онбордим проект (`onboard-project.sh`) и держим uptime. Меньше всего возни.
- **Self-hosted.** Поднимаете **свой** control-plane из
  [`corp-infra-template`](https://git.sftbmb.ru/sftbmb-core/corp-infra-template) (свой Vault,
  OTLP/Grafana, registry, онбординг) и наводите эти же эндпоинты на него — ни от кого не зависите.

Технически меняется только хост Vault / OTLP / registry — он в `.env` и KV, не зашит. Стек и
контракты одинаковы в обоих путях.

## Что внутри

| Слой | Что | Активация |
|---|---|---|
| **Edge** | Traefik v3 + CrowdSec — HTTP-01 LE, WAF, IP-bans | always-on |
| **Secrets** | vault-agent sidecar — рендерит секреты из Vault на VPS | always-on |
| **Telemetry** | otel-agent → `otel.sftbmb.ru` (OTLP + Bearer из Vault) · cadvisor · node-exporter | always-on |
| **Landing** | заглушка корня `${DOMAIN}` под LE-cert | always-on |
| **DB** | Postgres 17 | profile `postgres` |
| **Storage** | Minio (S3 + Console) | profile `storage` |
| **Backup** | restic + pg_dumpall + crond (alpine), daily → restic-репо | profile `storage` |
| **App** | backend, образ `git.sftbmb.ru/<client-org>/backend` | profile `backend` |

Always-on поднимается на минимальном seed'е (`meta` + `otel`); остальное — opt-in через
`COMPOSE_PROFILES`, по мере seed'а их KV. Детали слоёв — [`docs/reference/architecture.md`](docs/reference/architecture.md).

## Быстрый старт

Полный путь (corp Day-0 → bootstrap VPS → активация профилей → `/init-project` → своя инфра) —
**[`docs/getting-started.md`](docs/getting-started.md)**. Коротко, три шага:

**1. Корп-онбординг** (один раз на env, на корп control-plane `corp-infra-template`):
```bash
VAULT_TOKEN=<root> bash scripts/onboard-project.sh --name acme --envs dev,prod
```
Создаёт per-env AppRole + сеет `kv/projects/acme/<env>/{meta,otel}`; возвращает
`PROJECT_NAME / ENV / VAULT_ROLE_ID / VAULT_SECRET_ID` на каждый env.

**2. Форк + bootstrap VPS** (один VPS на env): **Use this template** → `<client-org>/infra`,
клон, затем поднять чистый VPS и завести identity:
```bash
cp ansible/inventory.example.ini ansible/inventory.ini   # заполни host/IP (gitignored)
ansible-playbook -i ansible/inventory.ini ansible/bootstrap.yml
ssh root@<vps>; cd /opt/<p>-infra
PROJECT_NAME=acme ENV=prod DOMAIN=acme.com VAULT_ROLE_ID=<id> VAULT_SECRET_ID=<id> \
  make new-env                   # .env (chmod 600), 5 переменных — остальное из Vault
```

**3. Первый деплой** (с рабочей станции оператора):
```bash
make ship        # check + push + (на main) ssh-deploy. На чистом дереве MSG не нужен.
```
Минимальный стек (traefik / vault-agent / crowdsec / otel / metrics / landing) живёт сразу.
Дальше — активация профилей: `/request-secret` → блок `vault kv put` корп-админу → `COMPOSE_PROFILES` + `make ship`.

## Принципы

- **Конфиг → код.** Всё декларативно в `compose/*.yml` и `configs/`. Нет «только на сервере».
- **Максимум в Vault.** `.env` минимален (identity + AppRole-bootstrap). Image-теги, ACME,
  restic endpoint, OTEL token, runtime-секреты — в `kv/projects/<p>/<env>/*`, ротируются корпом.
- **Multi-env через KV-dimension.** Один шаблон, N VPS, у каждого свой `ENV` и scope в Vault.
- **Lazy stack.** Минимальный стек на meta+otel seed'е; profiled-сервисы — по мере seed'ов.
- **Локальный CI.** Backend-образ собирает разработчик; `make ship` пушит код + ssh-деплоит.
  Никаких gitea-runner'ов / webhook'ов на сервере.

## Навигация

| Куда | Зачем |
|---|---|
| [`docs/getting-started.md`](docs/getting-started.md) | путь от форка до работающей VPS (Day-0 → де-템플ейт) |
| [`docs/reference/`](docs/reference/) | архитектура · экосистема · runbook/DR |
| `CLAUDE.md` | точка входа для агента (ядро + роутер); дневной флоу — skill `/smartdev` |
| `make help` | полный словарь команд |
| `.claude/rules/` · `.claude/skills/` | инварианты (path-scoped) и процедуры |

## Контракт с корпом

- **`vault.sftbmb.ru`** — secrets backend; AppRole per `(project, env)` от `onboard-project.sh`.
- **`otel.sftbmb.ru`** — observability ingest; tenant по `service.namespace=<project>-<env>` + Bearer из KV.
- **`git.sftbmb.ru`** — registry для backend/worker/frontend образов.

KV-layout, onboarding-флоу и multi-env — [`.claude/rules/multi-env.md`](.claude/rules/multi-env.md).
Restore из backup'а — `make restore-pg SNAPSHOT=latest` ([`docs/reference/runbook.md`](docs/reference/runbook.md)).

## Лицензия

Apache-2.0 — см. [`LICENSE`](LICENSE).
