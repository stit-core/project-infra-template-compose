# AGENTS.md

Шаблон проектной инфры stit.tech: docker-compose стек одного VPS на клиентский проект. Копируется в `<client-org>/infra`, адаптируется под домен/стек.

Этот файл — постоянный гайд для агента. Контекстные правила в `.claude/rules/`, процедуры в `.claude/skills/`. Для обзорного human-описания — `README.md`.

**Точка входа — ведущий cockpit `/smartdev`:** за один проход гонит `make status`, поднимает активный план и **сам переключает** в нужный режим (triage / corp-handoff / plan / add-service / request-secret / dr-restore / bootstrap-vps). Дефолтная петля любой правки — RED→GREEN (`make validate`/`make doctor` красный → fix → зелёный). Все действия — через `make <verb>` (полный список — `make help`); скрипты за make напрямую не дёргаем.

## Где это в экосистеме

**Роль:** шаблон проектной VPS. Один форк (`<client-org>/infra`) — один проект, один VPS на env (dev/staging/prod). Хост: backend + postgres + minio + vault-agent + otel-agent + traefik + crowdsec + backup.
**Зависит от:** `stit-infra/infra` — выдаёт AppRole `projects-<p>-<env>` + KV `kv/projects/<p>/<env>/*` (через `scripts/onboard-project.sh`), принимает OTLP на `otel.stit.tech`, хостит registry `git.stit.tech`.
**Используется:** `<client-org>/backend` (форк `stit-infra/go-backend-template`) — runtime для его образа; через `vault kv patch kv/projects/<p>/<env>/meta backend_tag=<tag>` + `make ship` происходит deploy.

Карта 4 репо и канонические контракты — `stit-infra/infra/docs/ecosystem.md`. Локально: `.claude/rules/multi-env.md` (KV-layout, AppRole, lazy-seed) и `docs/architecture.md`.

**Принцип:** forward-only документация. Любой текст (docs, skills, rules, plans, этот файл, README) описывает **только текущее состояние/намерение** — без «было X, стало Y, потому что». История живёт в `git log`. Единственное исключение — `docs/adrs/**` (ADR by design фиксируют датированное обоснование решения). Детали и примеры — `.claude/rules/forward-only.md`.

## 1. Стек

| Слой | Что | Где |
|---|---|---|
| Edge | Traefik v3 + CrowdSec | `compose/traefik.yml`, `compose/crowdsec.yml` |
| DB | Postgres 17 | `compose/postgres.yml` |
| App | Backend (image `git.stit.tech/<client-org>/backend`) | `compose/backend.yml` |
| Secrets | vault-agent sidecar | `compose/vault-agent.yml` |
| Telemetry | otel-agent → `otel.stit.tech` (OTLP от backend + Prom-scrape host-метрик) | `compose/otel-agent.yml` |
| Host metrics | cadvisor + node-exporter (скрейпятся локальным otel-agent) | `compose/cadvisor.yml`, `compose/node-exporter.yml` |
| Storage | Minio (S3 API + Console) на `s3.${DOMAIN}` / `minio.${DOMAIN}` | `compose/minio.yml` |
| Backup | self-contained контейнер (alpine + restic + pg_dumpall + crond), пишет в `$RESTIC_REPOSITORY` из `kv/projects/<p>/<env>/backup.repository` (рендерится vault-agent'ом в `.runtime/secrets/backup.env`) | `compose/backup.yml`, `containers/backup/` |

Always-on (traefik / vault-agent / crowdsec / otel-agent / node-exporter / cadvisor / landing) поднимается на минимальном seed'е (`meta` + `otel` от корпа при онбординге). `postgres` / `storage` (minio + backup) / `backend` — opt-in через `COMPOSE_PROFILES`, активируются после seed'а соответствующих KV-объектов. См. `.claude/rules/multi-env.md`.

Сети: `proxy` (наружу), `backend-net` (internal). Подробно — `docs/architecture.md`.

## 2. Команды

Единый словарь `make <verb>`, сгруппирован в `make help`. Concise-by-default;
`FORMAT=detailed` — полный разбор (validate).

| Группа | Верб | Что |
|---|---|---|
| LOOP | `validate` | compose syntax + yamllint + .tpl + .env coverage (`FORMAT=detailed`) |
| | `doctor` | live fail-fast preflight: compose/vault-agent/dns/vault/env (`A=--full`) |
| | `check` | каноничный pre-ship gate = validate + doctor |
| SHIP | `ship MSG="..."` | с laptop'а: commit + check + push + (если main) ssh-deploy. Канон |
| | `deploy` | на VPS: git pull → render → compose up --wait. Server-side |
| | `render` | envsubst для .tpl + сборка agent.hcl из parts |
| OPS | `ps` / `logs SVC=` | статус / логи |
| | `restart SVC=` | рестарт одного сервиса |
| | `backup` | one-shot backup внутри backup-контейнера |
| | `restore-pg SNAPSHOT=` | restore postgres из restic-снапшота |
| INTEL | `status` | cockpit-сводка с сигналами Critical/Infra-touch/Plan |
| | `search Q= [P=]` | поиск по compose/configs/scripts/docs |
| PROVISION | `new-env` | bootstrap `.env` на чистом VPS (interactive / env-driven) |
| SETUP | `setup` | поставить git-хуки (commit-msg и пр.) |
| META | `plan-check` | валидатор структуры планов `.claude/plans/*.md` |

## 3. Корп-контракт

Этот шаблон требует, чтобы проект был онбоарден на корп-стороне для каждой среды (`dev`, `prod`, ...). Один VPS = одна среда.

```bash
# stit-infra/infra (корп-VPS), оператор с root-токеном Vault.
VAULT_TOKEN=<root> bash scripts/onboard-project.sh --name <p> --envs dev,prod
```

Per env создаёт:
- AppRole `projects-<p>-<env>` (flat — Vault не принимает слеши в `auth/approle/role/<name>`) + policy `projects-<p>-<env>-read` read-only на `kv/data/projects/<p>/<env>/*` и `kv/metadata/projects/<p>/<env>/*`.
- `kv/projects/<p>/<env>/otel` (OTEL token + accountID).
- `kv/projects/<p>/<env>/meta` (`backend_tag`, `acme_email`, `acme_caserver` — дефолты, ротируются `vault kv patch`).
- Возвращает per-env блок: `PROJECT_NAME`, `ENV`, `VAULT_ROLE_ID`, `VAULT_SECRET_ID` для проектного `.env`.

Дополнительные KV-объекты (`db`, `oidc`, `jwt`, `minio`, `backup`, project-specific) — оператор запрашивает по мере подключения сервисов через skill `/request-secret`: получает stdout-блок `vault kv put kv/projects/<p>/<env>/<name>` и отдаёт корп-админу out-of-band.

AppRole policy строго `kv/data/projects/<p>/<env>/*`. Невозможность залогиниться с чужим ENV = валидация. Подробности — `.claude/rules/multi-env.md`.

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
- `make ship MSG="..."` — единственный канон: commit + `make check` (красный → пуш отменён) + push + (на main) ssh-deploy. На чистом дереве MSG необязателен — просто check + push + deploy.
- Хуки ставятся `make setup`.

## 6. Границы

### Делать всегда

- Перед claim "готово" — `make check` локально (validate + doctor), после деплоя — `make ps` для healthchecks.
- Тронул corp-поверхность (`configs/vault-agent/`, `compose/*.yml` профили, `.env.example`, `configs/crowdsec/whitelists.yaml`, `ansible/`) — оформи `CORP-HANDOFF`-блок до claim «готово» (skill `corp-handoff`; `make status → == Infra-touch ==` это ловит).
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

1. `.env` — `bash scripts/new-env.sh` (env-driven: PROJECT_NAME, ENV, DOMAIN, VAULT_ROLE_ID, VAULT_SECRET_ID; остальное зашито в дефолты или приходит из Vault).
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

Технически (defense-in-depth):
- `autoMemoryEnabled: false` в `.claude/settings.json` — авторитетный переключатель: харнесс не читает и не пишет авто-память для этого проекта.
- `permissions.deny` в `.claude/settings.json` блокирует Write/Edit/MultiEdit/NotebookEdit по `**/.claude/projects/**/memory/**` (любой home, любая глубина).
- `scripts/claude-hooks/pre-write-no-memory.sh` (PreToolUse) — страховка с понятным сообщением.
- Если правила «забываются» между сессиями — значит они недо-зафиксированы в репо. Перенеси в `AGENTS.md` / `.claude/rules/`.
