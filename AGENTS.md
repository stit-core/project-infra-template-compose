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
| Telemetry | otel-agent → `otel.stit.tech` (OTLP от backend + Prom-scrape host-метрик) | `compose/otel-agent.yml` |
| Host metrics | cadvisor + node-exporter (скрейпятся локальным otel-agent) | `compose/cadvisor.yml`, `compose/node-exporter.yml` |
| Storage | Minio (S3 API + Console) на `s3.${DOMAIN}` / `minio.${DOMAIN}`, профиль `minio` | `compose/minio.yml` |
| Backup | self-contained контейнер (alpine + restic + pg_dumpall + crond), пишет в `$RESTIC_REPOSITORY` (дефолт — `s3:http://minio:9000/backups`) | `compose/backup.yml`, `containers/backup/` |
| CI | gitea-runner, профиль `ci` | `compose/runner.yml` |

`backend`, `minio`, `backup`, `runner` — opt-in через `COMPOSE_PROFILES=...`. По дефолту стартует только всё, что в core (traefik/postgres/vault-agent/otel-agent/crowdsec/cadvisor/node-exporter).

Сети: `proxy` (наружу), `backend-net` (internal). Подробно — `docs/architecture.md`.

## 2. Команды

```
make deploy           # на VPS: git pull → render-configs → compose up -d --wait
make remote-deploy    # с laptop'а: ssh → VPS → deploy.sh (читает ansible/inventory.ini)
make ship             # push текущей ветки; если main — авто-remote-deploy
make render           # рендер .tpl-конфигов через envsubst
make validate         # compose syntax + .env.example coverage
make ps / logs        # статус / логи
make restart SVC=...  # рестарт одного сервиса
make backup           # one-shot backup внутри backup-контейнера
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
- Линейная история, push в main напрямую (solo-flow) — или в ветку → PR в Gitea → merge.
- `make ship` для push + (если main) auto-remote-deploy. Или `git push` + `make remote-deploy` отдельно.
- Хуки ставятся `make hooks-install`.

## 6. Границы

### Делать всегда

- Перед claim "готово" — `validate.sh` локально, после деплоя — `make ps` для healthchecks.
- Любая новая `${VAR}` в compose/configs — в `.env.example` сразу.
- Bumps версий — отдельным коммитом после явного OK от пользователя.

### Сначала спросить

- `compose/traefik.yml` static config — глобальные изменения требуют рестарта Traefik.
- `compose/vault-agent.yml` / `configs/vault-agent/` — security-sensitive.
- `containers/backup/` или `compose/backup.yml` — изменение backup-стратегии может потерять restore-points.

### Не делать никогда

- `--no-verify` / `--no-gpg-sign` без явной просьбы.
- `git push --force` без явной просьбы.
- `docker volume rm` или `docker compose down -v` — теряет данные.
- Commit `.env*`, `.runtime/`, `*.pem`, `*.key`.
- Image-теги вида `:latest`.
- Хранить секреты в `.env` или `configs/`. Всё через vault-agent.
- **Писать в auto-memory** (`~/.claude/projects/**/memory/**`) — отключено. Pre-write хук блокирует. См. §8.

## 7. Что менять при копировании в `<org>/infra`

Минимальный set:

1. `.env` — `bash scripts/new-env.sh` (env-driven: PROJECT_NAME, DOMAIN, VAULT_ROLE_ID, VAULT_SECRET_ID; остальное зашито в дефолты).
2. `docker-compose.yml` — проверить network names (если нужен conflict-free на shared VPS).
3. `compose/backend.yml` (и опционально frontend/worker) — `image:` под клиентский org, healthcheck path под backend API.
4. `configs/vault-agent/templates/backend.env.tpl` — добавить project-specific env-переменные если backend читает что-то сверх стандартного контракта.
5. `configs/traefik/dynamic/` — клиент-специфичные routers/middlewares (опционально).

См. `docs/onboarding.md` для полного чек-листа.

## 8. Auto-memory

В этом проекте автопамять Claude **отключена**. Всё, что должно пережить сессию, фиксируется в репо под git — это видно команде, ревьюится, воспроизводимо.

Куда что писать:

| Что | Куда |
|---|---|
| Постоянные правила/предпочтения для агента | `AGENTS.md` или `.claude/rules/<topic>.md` |
| Архитектурные решения | `docs/adrs/NNNN-<slug>.md` |
| Активные задачи / план работ | `.claude/plans/<slug>.md` |
| Reference на внешние системы | `docs/architecture.md`, `docs/onboarding.md`, `docs/runbook.md` |
| Креды и где они используются | вне репо (Vaultwarden, оператор-only заметка) |

Технически:
- `permissions.deny` в `.claude/settings.json` блокирует Write/Edit/MultiEdit/NotebookEdit к memory-директории Claude Code (`~/.claude/projects/**/memory/**`).
- `scripts/claude-hooks/pre-write-no-memory.sh` (PreToolUse) — страховка с понятным сообщением.
- Если правила «забываются» между сессиями — значит они недо-зафиксированы в репо. Перенеси в `AGENTS.md` / `.claude/rules/`.
