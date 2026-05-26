# project-infra-template-compose — гайд для агентов

Шаблон проектной инфры stit.tech: docker-compose стек одного VPS на клиентский
проект. Edge (Traefik v3 + CrowdSec) + Postgres + Minio + backend + vault-agent +
otel-agent + backup. Копируется в `<client-org>/infra`, адаптируется под домен/стек.

Этот файл — **ядро (always-on) + роутер**. Детали — в `docs/`, контекстные правила —
в `.claude/rules/` (path-scoped, грузятся когда matching-файл в контексте), процедуры —
в `.claude/skills/`. Human-обзор — `README.md`.

## Точка входа

- **`/smartdev`** — cockpit сессии: за один проход `make status`, поднимает активный план
  и **сам переключает** в нужный режим (triage / corp-handoff / plan / add-service /
  request-secret / dr-restore / bootstrap-vps). Запускай в начале / после `/clear`.
- **Planning-first.** Любое содержательное изменение идёт через план — секцию в едином
  `.claude/plans/roadmap.md` (skill `/plan`). Прямая правка — только truly-atomic и багфиксы
  (skill `triage`, RED-first). План переживает `/clear`.
- **Дефолтная петля любой правки — RED→GREEN:** `make validate` / `make doctor` красный →
  fix → зелёный. Все действия — через `make <verb>` (`make help`); скрипты за make не дёргаем.

## Где это запускается

Репо живёт на **рабочей станции оператора** — authoring / validate / plan / ship. Живого
стека локально нет: приложения и контейнеры — на удалённом VPS (один VPS = одна среда).
`make ship` пушит и триггерит remote `deploy.sh` по SSH. Ops на VPS (`ps`/`logs`/`deploy`/
`restart`) — через `scripts/tools/ssh.sh` (хост из `ansible/inventory.ini`). Локальный SKIP
authoring-проверок без `.env`/docker — норма, не падение.

## Где это в экосистеме

**Роль:** шаблон проектной VPS. Один форк (`<client-org>/infra`) — один проект, один VPS на
env (dev/staging/prod).
**Зависит от:** `stit-infra/infra` — выдаёт AppRole `projects-<p>-<env>` + KV
`kv/projects/<p>/<env>/*` (через `onboard-project.sh`), принимает OTLP на `otel.stit.tech`,
хостит registry `git.stit.tech`.
**Обслуживает:** `<client-org>/backend` (форк `go-backend-template`) — runtime для его образа;
deploy через `vault kv patch kv/projects/<p>/<env>/meta backend_tag=<tag>` + `make ship`.

Карта 4 репо и канонические контракты — `stit-infra/infra/docs/ecosystem.md`.

## Стек

| Слой | Что | Где |
|---|---|---|
| Edge | Traefik v3 + CrowdSec | `compose/traefik.yml`, `compose/crowdsec.yml` |
| DB | Postgres 17 | `compose/postgres.yml` |
| App | Backend (`git.stit.tech/<client-org>/backend`) | `compose/backend.yml` |
| Secrets | vault-agent sidecar | `compose/vault-agent.yml` |
| Telemetry | otel-agent → `otel.stit.tech` (OTLP + Prom-scrape host-метрик) | `compose/otel-agent.yml` |
| Host metrics | cadvisor + node-exporter | `compose/cadvisor.yml`, `compose/node-exporter.yml` |
| Storage | Minio (S3 + Console) на `s3.${DOMAIN}` / `minio.${DOMAIN}` | `compose/minio.yml` |
| Backup | restic + pg_dumpall + crond в alpine, пишет в `$RESTIC_REPOSITORY` | `compose/backup.yml`, `containers/backup/` |

Always-on (traefik / vault-agent / crowdsec / otel-agent / node-exporter / cadvisor / landing)
поднимается на минимальном seed'е (`meta` + `otel` от корпа при онбординге). `postgres` /
`storage` (minio + backup) / `backend` — opt-in через `COMPOSE_PROFILES`, активируются после
seed'а соответствующих KV. Сети: `proxy` (наружу), `backend-net` (internal). См.
`.claude/rules/multi-env.md` + `docs/reference/architecture.md`.

## Команды

Единый словарь `make <verb>`, сгруппирован в `make help`. Concise-by-default; `FORMAT=detailed` —
полный разбор. Канонический gate перед claim «готово» / push — **`make check`** (validate + doctor + plan-check + project-check).

| Группа | Верб | Что |
|---|---|---|
| LOOP | `validate` / `doctor` / `check` | syntax+tpl+.env coverage / live preflight / validate+doctor+plan-check+project-check |
| SHIP | `ship MSG="..."` | commit + check + push + (на main) ssh-deploy. Канон |
| | `deploy` / `render` | server-side: git pull → render → compose up --wait / envsubst+agent.hcl |
| OPS | `ps` / `logs SVC=` / `restart SVC=` | статус / логи / рестарт сервиса |
| | `backup` / `restore-pg SNAPSHOT=` | one-shot backup / restore postgres из restic |
| INTEL | `status` / `search Q= [P=]` | cockpit-сводка / поиск по compose+configs+scripts+docs |
| PROVISION | `new-env` | bootstrap `.env` на чистом VPS |
| SETUP | `setup` | поставить git-хуки (commit-msg) |
| META | `plan-check` / `project-check` | структура планов / продуктовый слой `docs/project/` |

## Карта: где что

| Тема | Где |
|---|---|
| Архитектура, сети, профили, non-goals | `docs/reference/architecture.md` |
| KV-layout, AppRole, multi-env, lazy-seed | `.claude/rules/multi-env.md` |
| Compose-инварианты сервиса | `.claude/rules/compose-and-services.md` |
| Секреты и `.env` | `.claude/rules/secrets-and-env.md` |
| Корп-handoff (когда тронул corp-поверхность) | `.claude/rules/corp-handoff.md` + skill `/corp-handoff` |
| Онбординг / путь потребителя | `docs/getting-started.md` |
| Runbook / инциденты | `docs/reference/runbook.md` |
| Экосистема 4 репо, контракты | `docs/reference/ecosystem.md` (→ канон `stit-infra/infra/docs/ecosystem.md`) |

## Корп-контракт

Проект должен быть онбоарден на корп-стороне для каждой среды (один VPS = одна среда):

```bash
# stit-infra/infra (корп-VPS), оператор с root-токеном Vault.
VAULT_TOKEN=<root> bash scripts/onboard-project.sh --name <p> --envs dev,prod
```

Per env создаёт: AppRole `projects-<p>-<env>` (flat) + policy read-only на
`kv/data/projects/<p>/<env>/*`; `kv/.../otel` (token + accountID); `kv/.../meta`
(`backend_tag`, `acme_email`, `acme_caserver`). Возвращает per-env блок `PROJECT_NAME` /
`ENV` / `VAULT_ROLE_ID` / `VAULT_SECRET_ID` для проектного `.env`.

Доп. KV (`db`, `oidc`, `jwt`, `minio`, `backup`, project-specific) — оператор запрашивает по
мере подключения сервисов через skill `/request-secret` и отдаёт блок `vault kv put` корп-админу
out-of-band. AppRole строго read-only на свой `<p>/<env>`. Подробности — `.claude/rules/multi-env.md`.

## Стиль

- **make-first.** Все операции — через `make <verb>` (`make help`); скрипты за таргетами напрямую
  не дёргаем. Raw-`docker` — только legit-исключения (restic/cscli/mc/ls через `docker exec`,
  throwaway в DR, explanatory deploy.sh-внутренности). Канон и список исключений — rule `.claude/rules/make-first.md`.
- **YAML 2-space indent**, без табов.
- **Image закреплён конкретной версией.** `:latest` запрещён — конвенция, ловится `make validate`.
- **Каждый сервис имеет** `restart`, `healthcheck`, `container_name`, явный `networks`.
- **Public сервисы** в `proxy` сети + Traefik labels с `crowdsec@file` middleware.
- **Comments — только когда WHY неочевидно.** Не пересказывай YAML.
- **Любой `${VAR}`** в compose/configs обязан быть в `.env.example` с комментарием как сгенерировать.

## Git workflow

- **Conventional Commits** — git-хук `commit-msg` блокирует невалидные. Типы: `feat`, `fix`,
  `refactor`, `docs`, `test`, `chore`, `meta`.
- Линейная история, push в main напрямую (solo-flow) — или в ветку → PR в Gitea → merge.
- `make ship MSG="..."` — единственный канон: commit + `make check` (красный → пуш отменён) +
  push + (на main) ssh-deploy. На чистом дереве MSG необязателен.
- Хуки ставятся `make setup`.

## Границы

### Делать всегда
- Перед claim «готово» — `make check` (validate + doctor + plan-check + project-check); после деплоя — `make ps`.
- **Изменение — через план** (planning-first; skill `/plan`). Отклонение — осознанное, проговаривается.
- Тронул corp-поверхность (`configs/vault-agent/`, `compose/*.yml` профили, `.env.example`,
  `configs/crowdsec/whitelists.yaml`, `ansible/`) — оформи **CORP-HANDOFF**-блок до claim «готово»
  (skill `/corp-handoff`; `make status → == Infra-touch ==` это ловит).
- Любая новая `${VAR}` в compose/configs — в `.env.example` сразу.
- Bumps версий образов — отдельным коммитом после явного OK.

### Сначала спросить
- `compose/traefik.yml` static config — глобальные изменения требуют рестарта Traefik.
- `compose/vault-agent.yml` / `configs/vault-agent/` — security-sensitive.
- `containers/backup/` или `compose/backup.yml` — риск потери restore-points.

### Не делать никогда
- `--no-verify` / `--no-gpg-sign`, `git push --force`, `docker volume rm` / `down -v` —
  блокирует `permissions.deny` в `.claude/settings.json`.
- Commit `.env*`, `.runtime/`, `*.pem`, `*.key`. Image-теги `:latest`.
- Хранить секреты в `.env` или `configs/` — всё через vault-agent.
- Писать в auto-memory — отключено (см. ниже).

## Что менять при копировании в `<org>/infra`

1. `.env` — `bash scripts/new-env.sh` (PROJECT_NAME, ENV, DOMAIN, VAULT_ROLE_ID, VAULT_SECRET_ID).
2. `docker-compose.yml` — проверить network names (conflict-free на shared VPS).
3. `compose/backend.yml` — `image:` под клиентский org, healthcheck path под backend API.
4. `configs/vault-agent/templates/backend.env.tpl` — project-specific env, если backend читает сверх контракта.
5. `configs/traefik/dynamic/` — клиент-специфичные routers/middlewares (опц.).

Полный путь потребителя — `docs/getting-started.md`.

## Auto-memory

В этом проекте автопамять Claude **отключена**. Всё, что должно пережить сессию, фиксируется в
репо под git — видно команде, ревьюится, воспроизводимо.

| Что | Куда |
|---|---|
| Постоянные правила/предпочтения для агента | `CLAUDE.md` или `.claude/rules/<topic>.md` |
| Архитектурные решения / «почему» | `docs/reference/architecture.md` (inline, present-state) |
| Активные задачи / план работ | `.claude/plans/roadmap.md` (single-file) |
| Reference на внешние системы | `docs/reference/{architecture,ecosystem,runbook}.md`, `docs/getting-started.md` |
| Креды и где используются | вне репо (Vaultwarden, оператор-only заметка) |

Технически: `autoMemoryEnabled: false` + `permissions.deny` на `Write`/`Edit`/`MultiEdit`/
`NotebookEdit` по `**/.claude/projects/**/memory/**` в `.claude/settings.json`. Если правила
«забываются» между сессиями — значит недо-зафиксированы в репо; перенеси в `CLAUDE.md` / `.claude/rules/`.

## Forward-only

Любой текст в репо описывает **только текущее состояние / намерение** — не «было/стало».
История — в `git log` + Conventional Commits. Полное правило — `.claude/rules/forward-only.md`.
</content>
</invoke>
