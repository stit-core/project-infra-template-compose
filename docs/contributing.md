# Contributing — работа с шаблоном через Claude Code

**[META]** Для контрибьютора *самого шаблона*: как устроена `.claude`-система, что
enforce'ится детерминированно, как вмешаться. (Потребителю шаблона — `getting-started.md`.)

**Где это запускается.** Репо живёт на рабочей станции оператора — authoring-поверхность
(validate / plan / ship). Живого стека локально нет: он на удалённом VPS (один VPS = одна среда).
`make validate` гоняет синтаксис/tpl/`.env`-coverage и работает без живого стека; `make doctor`
бьёт по live-поверхности (`.env`/rendered-конфиги) и без `.env` многое SKIP'ает — это норма.
Ops-вербы (`ps`/`logs`/`restart`) оборачивают SSH на VPS через `scripts/tools/ssh.sh`.

## Что где лежит и когда грузится

| Слой | Где | Когда грузится | Сила |
|---|---|---|---|
| Ядро + роутер | `CLAUDE.md` (реальный файл) | всегда, каждый запуск | advisory |
| Path-scoped правила | `.claude/rules/*.md` с `paths:` | когда matching-файл в контексте | advisory |
| Skills (процедуры) | `.claude/skills/<name>/SKILL.md` | по `description` или `/<name>` | procedural |
| Subagent'ы | `.claude/agents/*.md` | когда основной агент делегирует | role-specific |
| Settings / permissions | `.claude/settings.json` | старт сессии | детерминированно (deny) |

Progressive disclosure: на холодном старте — только имена+описания; тела skills/rules грузятся
по необходимости.

**Важно про `paths:`** — нативный ключ path-scoping в Claude Code именно `paths:` (не `globs:`).
Правило без `paths:` грузится всегда. Проверь, что новое правило path-scoped.

Правила: `make-first`, `multi-env`, `compose-and-services`, `secrets-and-env`,
`traefik-routing`, `ansible-style`, `env-local`, `forward-only`. Skills:
`smartdev` (cockpit), `plan`, `triage`, `add-service`,
`dr-restore`, `bootstrap-vps`, `init-project`, `stack-deep-dive`, `service-deep-dive`, `de-template`.
Subagent'ы: `explorer` (read-many), `reviewer` (severity-graded review) — оба read-only,
`model: inherit` (модель основной сессии).

## Цикл одной задачи

```
prompt → /smartdev (cockpit: make status, читает активные планы, чейнит режим)
       → plan (planning-first: изменение идёт через план в .claude/plans/; сквозная задача — программа)
       → act (RED→GREEN: make validate/doctor; работа в сервис-репо — агентами в сиблингах, CLAUDE.md § Оркестрация)
       → verify (claim «готово» → make check = validate + doctor + plan-check + project-check)
       → ship (make ship MSG="…": commit + check + push + на main ssh-deploy)
```

Планирование — **дефолт** (skill `plan`). Прямая правка — только truly-atomic и багфиксы
(→ skill `triage`, RED-first). Планы — файлы `.claude/plans/<slug>.md`, бэклог —
`.claude/plans/backlog.md`; закрытый план удаляется (история в git).

## Кто что enforce'ит

| Механизм | Где | Сила |
|---|---|---|
| git-хуки | `scripts/git-hooks/` (ставятся `make setup`): commit-msg (Conventional Commits), pre-commit (`.claude/plans/` → `validate-plan.sh`; `docs/project/**.md` → `validate-project-doc.sh`) | **детерминированно** |
| permissions.deny | `.claude/settings.json` | **детерминированно** (блок `--no-verify`, force-push, `reset --hard`, `docker volume rm`, `down -v`, запись в auto-memory) |
| `make check` (gate) | `scripts/ship.sh` зовёт перед push — красный отменяет пуш | **детерминированно** (на ship) |
| Path-scoped rules | `.claude/rules/*.md` | контекстная подсказка |
| CLAUDE.md | repo root | always-on advisory |

Claude Code хуков (PreToolUse/PostToolUse/Stop) в шаблоне **нет** — критичные инварианты держат
git-хуки + `permissions.deny`; soft-guidance — CLAUDE.md и rules. Pre-push хука тоже нет: gate
перед сервером — `make ship → make check`. Push в `main` разрешён (прямой solo-flow или PR в Gitea).

## Course correction

| Хочется | Как |
|---|---|
| Прервать работу | `Esc` |
| План на одно сообщение | `/plan` |
| Заблокировать путь | `.claude/settings.local.json` → `permissions.deny` |
| После 2 неудачных попыток | `/clear` + переписать запрос |
| Разовый контекст | `@path/to/file` |
| Откатить | `git restore` / `git revert` (snapshots не нужны — git) |

## Что осознанно не делаем

- **CI/runner'ы/push-trigger** — деплой это `make ship` → ssh → `deploy.sh`. Никакого Gitea-CI.
- **Claude Code хуки** — инварианты на git-хуках + `permissions.deny`, не на PreToolUse/Stop.
- **Архив планов** — закрытый план удаляется целиком, история — в `git log` (forward-only).
- **ADR-папка** — «почему» живёт present-state inline в reference-доках, без датированных ADR.
- **Bloated CLAUDE.md** — bloat снижает adherence; держим router-стиль, детали в docs/rules/skills.

Triage / DR / bootstrap делаем скиллами, не прозой в CLAUDE.md.

## Troubleshooting

| Симптом | Куда смотреть |
|---|---|
| Skill не активируется | `description` в frontmatter — переписать конкретнее, «pushy» |
| Path-scoped rule не грузится | frontmatter `paths:` (не `globs:`!) — проверить glob |
| Subagent ушёл надолго | `tools` в frontmatter — урезать до read-only |
| CLAUDE.md игнорируется | длина / конфликт инструкций между секциями |
| Коммит reject'нут | `scripts/git-hooks/commit-msg` — type ∈ {feat,fix,refactor,docs,test,chore,meta,perf} |
| `make validate` падает | compose-синтаксис / `:latest` / `${VAR}` не в `.env.example` / `.tpl` не рендерится |
| `make doctor` падает | live-поверхность: `.env`/rendered-конфиги (локально без `.env` многое SKIP — норма) |
| `make plan-check` падает | формат плана или бэклога в `.claude/plans/` — см. skill `plan` |
