# Дневной флоу проектной инфры с Claude Code

Этот документ — для человека. Описывает как работать с шаблоном `<client-org>/infra` через Claude Code.

Контекст: `CLAUDE.md` (постоянный), `README.md` (human-обзор), `docs/reference/architecture.md`, `docs/getting-started.md`, `docs/reference/runbook.md`.

## 1. Что лежит где

| Слой | Где | Когда грузится | Сила |
|---|---|---|---|
| Корневые правила | `CLAUDE.md` | Всегда | Advisory |
| Path-scoped правила | `.claude/rules/*.md` с `paths:` frontmatter | Когда matching-файл в контексте | Advisory |
| Skills | `.claude/skills/<name>/SKILL.md` | По description-match или явному `/<name>` | Procedural |
| Subagents | `.claude/agents/*.md` | При делегировании | Role-specific |
| Permissions | `.claude/settings.json` `permissions.deny` | Всегда | **Детерминированно** |

## 2. Цикл одной задачи

```
[твой prompt]
     ↓
GATHER  ─── make status — cockpit-сводка (Critical / Infra-touch / Plan)
            Read compose/configs (path-scoped правила автогрузятся)
            explorer subagent / make search Q= — широкий поиск
     ↓
COCKPIT ─── /smartdev ведёт: парс сигналов → САМ чейнит в режим
            (triage / corp-handoff / plan / add-service / …). Skip-able
            для тривиальной правки — иди сразу в RED→GREEN.
     ↓
ACT     ─── Edit/Write (после правки compose — `make validate`)
     ↓
VERIFY  ─── make validate (→ make check перед ship: validate + doctor)
            == Infra-touch == ≠ none → corp-handoff ДО claim «готово»
            git diff — нет ли .env / .runtime/ утечек
     ↓
COMMIT  ─── conventional prefix (commit-msg хук валидирует)
            push в main напрямую (solo-flow) — или в ветку → PR в Gitea → merge
     ↓
DEPLOY  ─── `make ship MSG="..."` локально: commit + check + push + (на main) ssh-deploy.
            На чистом дереве — `make ship` без MSG (check + push + deploy).
            Debug: на VPS `make deploy` (видишь пошаговый stdout).
            Verify: `make ps` + healthchecks.
```

## 3. Сценарии

### А. Первый запуск нового VPS

Триггер: «подними клиентский VPS», «новый сервер».

1. Skill `bootstrap-vps` ведёт чек-листом.
2. На корп-стороне (`stit-infra/infra`) оператор уже выполнил `bash scripts/onboard-project.sh --name <p> --envs dev,prod --source-ip <env>=<vps-egress-ip>` — получил per-env блок с `PROJECT_NAME`, `ENV`, `VAULT_ROLE_ID`, `VAULT_SECRET_ID`. Один VPS = одна среда. `--source-ip` пишет IP проектной VPS в CrowdSec whitelist (otel-collector UA иначе банится).
3. Локально: `ansible-playbook -i inventory.ini bootstrap.yml` → подготовка хоста.
4. После того как playbook отдал deploy-key — оператор регистрирует его в Gitea (Settings → Deploy keys).
5. `ansible-playbook ... --tags onboard` — клонирование репо.
6. На VPS: `PROJECT_NAME=… ENV=… DOMAIN=… VAULT_ROLE_ID=… VAULT_SECRET_ID=… bash scripts/new-env.sh` (или интерактивный запуск без env-vars). Корп-инфра (VAULT_ADDR/OTEL) зашита в скрипт.
7. С laptop'а: `make ship` → SSH-deploy → vault-agent поднимается → рендерит `.runtime/secrets/*.env`. Backend в profile, стартует отдельно (`COMPOSE_PROFILES=backend make ship` когда image готов).

### Б. Новый сервис

Триггер: «добавь Pyroscope / worker / cache».

1. Skill `add-service` — чек-лист: `compose/<svc>.yml` (pinned image, healthcheck, networks), traefik labels с `crowdsec@file`, при необходимости `configs/vault-agent/templates/<svc>.env.tpl` + блок в `configs/vault-agent/agent.hcl.parts/<profile>.hcl` (или `head.hcl` если always-on).
2. `${VAR}` в `.env.example`.
3. `make check` зелёный → `feat(<svc>): add <Service>` → ship. Если задело corp-поверхность (vault-agent template / новый KV) — `corp-handoff` блок до claim «готово».

### В. Bump образа

Триггер: «подними backend до 1.2.3».

1. Показать diff + release notes, получить явный OK (image-bump — не молча).
2. Edit на `image:` строке; тег закреплён конкретной версией, не `:latest`.
3. Отдельный коммит `chore(<svc>): bump <name> to <ver>`.
4. Push → deploy → verify healthcheck.

### Г. Ротация секрета

Триггер: «смени DB-пароль / OIDC client_secret».

1. На корп-стороне: `vault kv patch kv/projects/<p>/<env>/db password=<new>`.
2. На проектной: `make ship` (без MSG, на чистом дереве). `scripts/deploy.sh` детектит изменения в `configs/vault-agent/templates/` или смену `COMPOSE_PROFILES` между prev/new sha и сам делает `docker compose up -d --no-deps --force-recreate <consumer>` — `env_file` фиксируется при container CREATE, простой `restart` старый ENV не пересоздаст.
3. Проверить логи backend: коннект к БД ОК.

Подробности и schema — `.claude/rules/multi-env.md` + `.claude/rules/secrets-and-env.md`.

### Д. Disaster recovery

Триггер: «postgres упал», «volume потерян», «host crashed».

1. Skill `dr-restore` ведёт через runbook (`docs/reference/runbook.md`).
2. Каждый destructive шаг — явный OK.
3. После — записать в `docs/incidents/YYYY-MM-DD-<short>.md`.

## 4. Кто что enforces

| Механизм | Где | Сила |
|---|---|---|
| `permissions.deny` | `.claude/settings.json` | **Детерминированно** |
| git-хуки | `scripts/git-hooks/*` (commit-msg) | **Детерминированно** (на commit) |
| Skills | `.claude/skills/<name>/SKILL.md` | Procedure |
| Path-scoped rules | `.claude/rules/*.md` | Контекстная подсказка |
| CLAUDE.md | repo root | Always-on advisory |
| Subagent prompts | `.claude/agents/*.md` | Role-specific |

Жёсткие запреты (no `--no-verify`, no `git push --force`, no `docker volume rm` / `down -v`, no запись в auto-memory) — `permissions.deny` в `.claude/settings.json`. Conventional Commits — git-хук `commit-msg`. Стиль и conventions (включая no `:latest`, image-bump только с OK) — advisory в CLAUDE.md и rules, проверяются `make validate`.

**Cockpit-чейнинг:** `/smartdev` парсит `make status`-сигналы и сам переключает в `triage` (Critical ≠ none / багфикс), `corp-handoff` (Infra-touch ≠ none), `plan` (крупная задача), `add-service`/`request-secret`/`dr-restore`/`bootstrap-vps` (по задаче). **CORP-HANDOFF** — soft-механизм (`.claude/rules/corp-handoff.md` + skill, не хук): единственная гарантия — что агент его исполняет; тронул corp-поверхность → блок до claim «готово».

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
- Per-service runbook'и сверх `docs/reference/runbook.md` — `docs/reference/runbook.md` единый; отдельный per-service runbook заводится только под конкретный повторяющийся инцидент.
- Vault как primary store с прямым SDK — backend не ходит в Vault, читает только `.runtime/secrets/*.env`. Это сознательно: vault-agent изолирует auth.
- Multi-host / HA — single-VPS осознанный trade-off для проектного шаблона.

## 7. Куда смотреть когда сломалось

| Симптом | Куда |
|---|---|
| `permissions.deny` блокирует не по делу | `.claude/settings.json` `permissions` (или `.claude/settings.local.json` для локальных override) |
| Skill не активируется | `description` в frontmatter — переписать конкретнее |
| Path-rule не подгружается | `paths:` glob в frontmatter |
| Коммит reject'нут | `scripts/git-hooks/commit-msg` — type ∈ {feat, fix, refactor, docs, test, chore, meta} |
| `make validate` / `make check` красный | Первая `FAIL`-проверка обычно главная; `FORMAT=detailed` — разбор |
| `make doctor` FAIL | Строка `FAIL: <чек>` называет проверку; `A=--full` — captured detail |
| `make deploy` падает | `docker compose logs <svc>` на сервере; skill `triage` ведёт разбор |
| vault-agent не healthy | `docker logs vault-agent` — обычно AppRole expired или Vault unreachable |
| backend в `.env` не видит секреты | `ls -la .runtime/secrets/` — должны быть `*.env` файлы; если нет — vault-agent ещё не отрендерил |
| LE certs не renew | HTTP-01 challenge: `docker logs traefik | grep acme` |
| Backup не идёт | `tail /var/log/<project>-backup.log`, `crontab -l`, restic env-vars в `.env` |
