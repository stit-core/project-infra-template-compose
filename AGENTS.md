# AGENTS.md

Шаблон проектной инфры stit.tech: docker-compose стек одного VPS на клиентский проект. Копируется в `<client-org>/infra`, адаптируется под домен/стек.

Этот файл — постоянный гайд для агента. Контекстные правила в `.claude/rules/` (если появляются), процедуры в `.claude/skills/`. Для обзорного human-описания — `README.md`.

## 1. Стек

| Слой | Что | Где |
|---|---|---|
| Edge | Traefik v3 + CrowdSec | `compose/traefik.yml`, `compose/crowdsec.yml` |
| DB | Postgres 17 | `compose/postgres.yml` |
| App | Backend (image `git.stit.tech/<org>/backend`) | `compose/backend.yml` |
| Secrets | vault-agent sidecar | `compose/vault-agent.yml` |
| Telemetry | otel-agent → `otel.stit.tech` | `compose/otel-agent.yml` |
| Backup | restic-cron → corp Minio | `compose/backup.yml` |
| CI | gitea-runner | `compose/runner.yml` |

Сети: `proxy` (наружу), `backend-net` (internal). Подробно — `docs/architecture.md`.

## 2. Команды

```
make deploy           # git pull → render-configs → compose up -d --wait
make render           # рендер .tpl-конфигов через envsubst
make validate         # compose syntax + .env.example coverage
make ps / logs        # статус / логи
make restart SVC=...  # рестарт одного сервиса
make backup           # one-shot restic
make status           # сводка состояния репо для /smartdev
make hooks-install    # поставить commit-msg hook
```

## 3. Корп-контракт

Этот шаблон требует, чтобы проект был онбоарден на корп-стороне:

```bash
# stit/infra (корп-VPS), оператор с root-токеном Vault.
VAULT_TOKEN=<root> bash scripts/onboard-project.sh <project>
```

Это создаёт:
- `kv/observability/tenants/<p>` (OTEL_TOKEN + accountID)
- `kv/projects/<p>/{db,oidc,jwt}` со stub-значениями (db с random password)
- AppRole `project-<p>` с scoped policy
- Возвращает блок для проектного `.env`: PROJECT_NAME, VAULT_ROLE_ID/SECRET_ID, OTEL_*

Дополнительные секреты (реальный OIDC client_secret, 3rd-party API keys) — через `seed-project-secrets.sh` на корп-стороне.

См. `stit/infra/docs/project-secrets.md` для подробностей KV-схемы и rotation flow.

## 4. Стиль

- **YAML 2-space indent**, без табов.
- **Image закреплён конкретной версией.** `:latest` запрещён — pre-edit guard в `.claude/settings.json` блокирует.
- **Каждый сервис имеет** `restart`, `healthcheck`, `container_name`, явный `networks`.
- **Public сервисы** в `proxy` сети + Traefik labels с `crowdsec@file` middleware.
- **Comments — только когда WHY неочевидно.** Не пересказывай YAML.
- **Любой `${VAR}`** в compose/configs обязан быть в `.env.example` с комментарием как сгенерировать.

## 5. Git workflow

- **Conventional Commits** — `commit-msg` хук блокирует невалидные. Типы: `feat`, `fix`, `refactor`, `docs`, `test`, `chore`, `meta`.
- Линейная история, push в main напрямую (solo-flow на проектной стороне).
- Хуки ставятся `make hooks-install`.

## 6. Границы

### Делать всегда

- Перед claim "готово" — `validate.sh` локально, после деплоя — `make ps` для healthchecks.
- Любая новая `${VAR}` в compose/configs — в `.env.example` сразу.
- Bumps версий — отдельным коммитом после явного OK от пользователя.

### Сначала спросить

- `compose/traefik.yml` static config — глобальные изменения требуют рестарта Traefik.
- `compose/vault-agent.yml` / `configs/vault-agent/` — security-sensitive.
- `scripts/backup.sh` — изменение backup-стратегии может потерять restore-points.

### Не делать никогда

- `--no-verify` / `--no-gpg-sign` без явной просьбы.
- `git push --force` без явной просьбы.
- `docker volume rm` или `docker compose down -v` — теряет данные.
- Commit `.env*`, `.runtime/`, `*.pem`, `*.key`.
- Image-теги вида `:latest`.
- Хранить секреты в `.env` или `configs/`. Всё через vault-agent.

## 7. Что менять при копировании в `<org>/infra`

Минимальный set:

1. `.env` — заполнить блоком от `onboard-project.sh` + клиентским доменом + image tags.
2. `docker-compose.yml` — проверить network names (если нужен conflict-free на shared VPS).
3. `compose/backend.yml` (и опционально frontend/worker) — `image:` под клиентский org, healthcheck path под backend API.
4. `configs/vault-agent/templates/backend.env.tpl` — добавить project-specific env-переменные если backend читает что-то сверх стандартного контракта.
5. `configs/traefik/dynamic/` — клиент-специфичные routers/middlewares (опционально).

См. `docs/onboarding.md` для полного чек-листа.
