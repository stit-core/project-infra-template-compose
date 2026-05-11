# Дневной флоу проектной инфры с Claude Code

Этот документ — для человека. Описывает как работать с шаблоном `<client-org>/infra` через Claude Code.

Контекст: `AGENTS.md` (постоянный), `README.md` (human-обзор), `docs/architecture.md`, `docs/onboarding.md`, `docs/runbook.md`.

## 1. Что лежит где

| Слой | Где | Когда грузится | Сила |
|---|---|---|---|
| Корневые правила | `AGENTS.md` (CLAUDE.md → AGENTS.md) | Всегда | Advisory |
| Path-scoped правила | `.claude/rules/*.md` с `paths:` frontmatter | Когда matching-файл в контексте | Advisory |
| Skills | `.claude/skills/<name>/SKILL.md` | По description-match или явному `/<name>` | Procedural |
| Subagents | `.claude/agents/*.md` | При делегировании | Role-specific |
| Hooks | `.claude/settings.json` + `scripts/claude-hooks/*.sh` | На события (PreToolUse/PostToolUse) | **Детерминированно** |

## 2. Цикл одной задачи

```
[твой prompt]
     ↓
GATHER  ─── Read compose/configs (path-scoped правила автогрузятся)
            explorer subagent — для широкого поиска
            scripts/agent-tools/status.sh — сводка репо
     ↓
PLAN    ─── smartdev → решает: edit / план / переключение в skill
            Skip-able для тривиальных правок
     ↓
ACT     ─── Edit/Write
            PostToolUse: docker compose config -q после правки compose
            PreToolUse: блок image-bump'ов без SKIP_IMAGE_HOOK=1
     ↓
VERIFY  ─── scripts/agent-tools/validate.sh
            git diff — нет ли .env / .runtime/ утечек
     ↓
COMMIT  ─── conventional prefix (commit-msg хук валидирует)
            push в main напрямую (solo-flow) — или в ветку → PR в Gitea → merge
     ↓
DEPLOY  ─── `make ship MSG="..."` локально: commit + push + (на main) ssh-deploy.
            На чистом дереве — `make ship` без MSG (push + deploy).
            Debug: на VPS `make deploy` (видишь пошаговый stdout).
            Verify: `make ps` + healthchecks.
```

## 3. Сценарии

### А. Первый запуск нового VPS

Триггер: «подними клиентский VPS», «новый сервер».

1. Skill `bootstrap-vps` ведёт чек-листом.
2. На корп-стороне (`stit/infra`) оператор уже выполнил `bash scripts/onboard-project.sh <project>` — получил блок с `VAULT_ROLE_ID`, `VAULT_SECRET_ID`, `OTEL_*`.
3. Локально: `ansible-playbook -i inventory.ini bootstrap.yml` → подготовка хоста.
4. После того как playbook отдал deploy-key — оператор регистрирует его в Gitea (Settings → Deploy keys).
5. `ansible-playbook ... --tags onboard` — клонирование репо.
6. На VPS: `PROJECT_NAME=… DOMAIN=… VAULT_ROLE_ID=… VAULT_SECRET_ID=… bash scripts/new-env.sh` (или интерактивный запуск без env-vars). Корп-инфра (VAULT_ADDR/OTEL) зашита в скрипт.
7. С laptop'а: `make ship` → SSH-deploy → vault-agent поднимается → рендерит `.runtime/secrets/*.env`. Backend в profile, стартует отдельно (`COMPOSE_PROFILES=backend make ship` когда image готов).

### Б. Новый сервис

Триггер: «добавь Pyroscope / worker / cache».

1. Skill `add-service` — чек-лист: `compose/<svc>.yml` (pinned image, healthcheck, networks), traefik labels с `crowdsec@file`, при необходимости `configs/vault-agent/templates/<svc>.env.tpl` + блок в `agent.hcl.tpl`.
2. `${VAR}` в `.env.example`.
3. `validate.sh` зелёный → `feat(<svc>): add <Service>` → push → deploy.

### В. Bump образа

Триггер: «подними backend до 1.2.3».

1. Edit на `image:` строке блокируется PreToolUse-хуком.
2. Показать diff + release notes, получить OK.
3. `SKIP_IMAGE_HOOK=1` в окружении Edit.
4. Отдельный коммит `chore(<svc>): bump <name> to <ver>`.
5. Push → deploy → verify healthcheck.

### Г. Ротация секрета

Триггер: «смени DB-пароль / OIDC client_secret».

1. На корп-стороне: `vault kv patch kv/projects/<p>/db password=<new>`.
2. На проектной: `make restart SVC=backend` (vault-agent сам перерендерит при template-change, но рестарт consumer-а гарантирует подхват `env_file`).
3. Проверить логи backend: коннект к БД ОК.

Подробности и schema — `stit/infra/docs/project-secrets.md`.

### Д. Disaster recovery

Триггер: «postgres упал», «volume потерян», «host crashed».

1. Skill `dr-restore` ведёт через runbook (`docs/runbook.md`).
2. Каждый destructive шаг — явный OK.
3. После — записать в `docs/incidents/YYYY-MM-DD-<short>.md`.

## 4. Кто что enforces

| Механизм | Где | Сила |
|---|---|---|
| Hooks | `.claude/settings.json` + `scripts/claude-hooks/*.sh` | **Детерминированно** |
| Skills | `.claude/skills/<name>/SKILL.md` | Procedure |
| Path-scoped rules | `.claude/rules/*.md` | Контекстная подсказка |
| AGENTS.md | repo root | Always-on advisory |
| Subagent prompts | `.claude/agents/*.md` | Role-specific |

Критичные инварианты (no `--no-verify`, no image-bumps без OK, no `:latest`) — в хуках. Стиль и conventions — в AGENTS.md и rules.

## 5. Course correction

| Что | Как |
|---|---|
| Прервать | `Esc` |
| Plan mode | `Shift+Tab` или `/plan` |
| Заблокировать путь локально | `.claude/settings.local.json` → `permissions.deny` |
| После 2 неудачных попыток | `/clear` |
| Разовый контекст | `@path/to/file` |
| Откат | `git restore <file>` |

## 6. Что осознанно не делаем

- Auto-deploy через Gitea Actions для прод-веток — solo-flow, ручной шаг = sanity check. CI используется только для билда/тестов backend образа.
- Per-service runbook'и сверх `docs/runbook.md` — сделаем когда боль появится.
- Vault как primary store с прямым SDK — backend не ходит в Vault, читает только `.runtime/secrets/*.env`. Это сознательно: vault-agent изолирует auth.
- Multi-host / HA — single-VPS осознанный trade-off для проектного шаблона.

## 7. Куда смотреть когда сломалось

| Симптом | Куда |
|---|---|
| Хук блокирует не по делу | `scripts/claude-hooks/*.sh` + `.claude/settings.json` `hooks` |
| Skill не активируется | `description` в frontmatter — переписать конкретнее |
| Path-rule не подгружается | `paths:` glob в frontmatter |
| Коммит reject'нут | `scripts/git-hooks/commit-msg` — type ∈ {feat, fix, refactor, docs, test, chore, meta} |
| `validate.sh` падает | Первая красная секция обычно главная |
| `make deploy` падает | `docker compose logs <svc>` на сервере |
| vault-agent не healthy | `docker logs vault-agent` — обычно AppRole expired или Vault unreachable |
| backend в `.env` не видит секреты | `ls -la .runtime/secrets/` — должны быть `*.env` файлы; если нет — vault-agent ещё не отрендерил |
| LE certs не renew | HTTP-01 challenge: `docker logs traefik | grep acme` |
| Backup не идёт | `tail /var/log/<project>-backup.log`, `crontab -l`, restic env-vars в `.env` |
