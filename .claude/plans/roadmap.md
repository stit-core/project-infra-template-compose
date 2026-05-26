# Roadmap

Единственный артефакт планирования шаблона — этот файл. Подпапок, `<slug>.md`,
архивов и changelog'ов нет: они расходятся с правдой и мешают.

Это **единый сквозной план** приведения репо к gold standard `go-backend-template`
плюс продуктовый слой `/init-project`. Агент идёт по фазам **сверху вниз**, отмечает
атомы `[x]` + под-буллет `**Done:**` (evidence: коммит-хеш / `make <verb>` → результат).
Каждый атом несёт `Ref:` — файл-образец в соседнем `go-backend-template`, который
зеркалим. По завершении всего плана `### `-секция удаляется — история в `git log`.

**Planning-first.** Прямая правка без плана — только truly-atomic (опечатка) и багфиксы
(→ skill `triage`, RED-first). Отклонение от плана — осознанное, проговаривается с юзером.

**Где это запускается.** Репо живёт на машине оператора — authoring / validate / plan /
ship-поверхность. Приложения и живого стека локально нет: они на удалённом VPS.
`make ship` пушит и триггерит remote `deploy.sh` по ssh; live-ops (`ps`/`logs`/`restart`/
`backup`/`restore-pg`) прозрачно оборачивают ssh на VPS (local-ssh-wrapper, Phase 7).
Локальный SKIP в authoring-проверках без `.env`/docker — норма, не падение.

**Current focus:** Phase 2 · A3

## Active

### gold-standard-alignment — Привести `.claude`/docs к эталону go-backend + слой /init-project
**Создан:** 2026-05-26 · **Статус:** in-progress

**Контекст.** `go-backend-template` прошёл полный рефактор доков/скилов/правил и принят
за gold standard. Этот репо подтягиваем к тем же конвенциям (единый `CLAUDE.md`,
single-file планирование, make-first, причёсанные docs без ADR) и достраиваем продуктовым
слоем `/init-project` (vision → карта сервисов → стек → de-template), который стоит на
уровень выше `/init-service` бэкенда. Граница продуктового слоя — только этот репо.

**Не входит в скоуп.** Cross-repo действия `/init-project` (создание форков backend/frontend,
seed секретов) — только печать next-steps, не выполнение. Изменение корп-стороны (Vault,
AppRole) — через `corp-handoff`. Продуктовые инфра-фичи (DOMAIN→Vault, CrowdSec auto-register,
vault-agent webhook) — вне этого плана.

**Открытые вопросы.** (все закрыты в ходе проектирования)
- [x] Q1: AGENTS.md или CLAUDE.md? → только CLAUDE.md.
- [x] Q2: WORKFLOW.md? → раззнести по homes (Phase 5), не дамп в CLAUDE.md.
- [x] Q3: модель планов? → single-file (эталон), без `<slug>.md`.
- [x] Q4: docs? → README+getting-started+contributing+reference, `adrs/` снести, «почему» inline без ADR-номеров.
- [x] Q5: remote-ops? → local-ssh-wrapper (Phase 7).
- [x] Q6: docs/project granularity? → файл-на-сервис, отдельный stack.md.
- [x] Q7: /init-project поведение? → design-first (deep-dive'ы), `de-template` мутирует репо in-repo.

**Референсы.** Зеркалим из `stit-infra/go-backend-template`: `CLAUDE.md`,
`docs/{README,getting-started,contributing}.md`, `docs/reference/{architecture,ecosystem}.md`,
`scripts/tools/validate-plan.sh`, `.claude/skills/plan/SKILL.md`, `.claude/plans/roadmap.md`,
`.claude/rules/env-local.md`, `.claude/skills/{init-service,domain-deep-dive,stack-deep-dive,de-template}/SKILL.md`,
`docs/{domains,stack}/README.md` + их `_templates/`, `scripts/tools/validate-{domain,stack}-doc.sh`.

**Атомы.**

#### Phase 1 — Единый CLAUDE.md (без AGENTS.md)
- [x] **A1:** `AGENTS.md` → `CLAUDE.md` (router-стиль)
  - Что делаем: собрать `CLAUDE.md` в router-стиле эталона (one-liner+стек, meta-layout,
    точка входа `/smartdev`, planning-first, команды `make`, карта где-что, стиль, git,
    границы, env-framing workstation+ssh-wrapper). Удалить `AGENTS.md`. `WORKFLOW.md` пока остаётся.
  - Verify: `make validate` → OK; `test ! -e AGENTS.md && test -e CLAUDE.md` · Зависит от: —
  - Ref: `stit-infra/go-backend-template/CLAUDE.md`
  - **Done:** CLAUDE.md (182 стр.) написан, AGENTS.md удалён. `make validate` → OK; `test ! -e AGENTS.md && test -e CLAUDE.md` → PASS. Решения: ADR убран сразу (зеркалит эталон; §forward-only → указатель на правило, auto-memory «архитектура» → docs/architecture.md), env-framing — честный present-state (workstation без живого стека, ops через ssh.sh как инструмент), без hook-ссылок.
- [x] **A2:** Sweep ссылок `AGENTS.md` → `CLAUDE.md`
  - Что делаем: заменить во всех живых файлах — `scripts/tools/search.sh` (список dirs),
    `.claude/rules/forward-only.md` (frontmatter `description`+glob), `.claude/WORKFLOW.md` (удаляется в A19 — но держим grep чистым),
    `docs/adrs/0002-*.md` (×1, удаляется в A16). Прим.: `scripts/claude-hooks/` снесён вместе с Claude-хуками вне плана.
  - Verify: `grep -rn 'AGENTS\.md' . --include='*.md' --include='*.sh' --include='*.json' | grep -v '/\.git/' | grep -v '\.claude/plans/'` → пусто (исключаем plans/: текст плана легитимно обсуждает миграцию, секция удаляется при закрытии плана); `make validate` → OK · Зависит от: A1
  - Ref: `stit-infra/go-backend-template/CLAUDE.md`
  - **Done:** заменено в `search.sh`, `forward-only.md` (description+glob), `WORKFLOW.md` (×3), `docs/adrs/0002`. Сужённый grep → пусто; `make validate` → OK.

#### Phase 2 — Single-file планирование
- [ ] **A3:** Порт `scripts/tools/validate-plan.sh` под single-file
  - Что делаем: валидатор сканирует `### <slug>` под `## Active`; на секцию — `**Создан:**`,
    `**Статус:**` ∈ {planning,in-progress,blocked} (blocked → `blocked by`), подсекции
    `Контекст`/`Не входит в скоуп`/`Атомы`/`Чекпоинты`, ≥1 атом с `Verify:`+`Зависит от:`,
    ссылки `Зависит от: A<N>` — внутри секции. Без лимита 15 (один сквозной план).
  - Verify: `make plan-check` → `OK (1 plan checked)` на этом roadmap · Зависит от: —
  - Ref: `stit-infra/go-backend-template/scripts/tools/validate-plan.sh`
- [ ] **A4:** Переписать `.claude/skills/plan/SKILL.md` под single-file
  - Что делаем: писать inline-секцию в `roadmap.md` (не `<slug>.md`); lifecycle done=секция
    удаляется; bold-лейблы подсекций, `####` фазы; восстановление после /clear из roadmap.
  - Verify: `make validate` → OK; в SKILL.md нет `<slug>.md`/подпапок · Зависит от: A3
  - Ref: `stit-infra/go-backend-template/.claude/skills/plan/SKILL.md`
- [ ] **A5:** Детект планов в `scripts/tools/status.sh`
  - Что делаем: `== Plan ==` парсит `### <slug>` под `## Active` + `**Статус:**`.
  - Verify: `make status` → `== Plan ==` показывает активную секцию · Зависит от: A3
  - Ref: `stit-infra/go-backend-template/.claude/plans/roadmap.md`
- [ ] **A6:** Зачистить хвосты старой модели
  - Что делаем: `forward-only.md` секция «Планы» под single-file; pre-commit wiring
    (валидировать на change `roadmap.md`); `reviewer.md`/`CLAUDE.md` если ссылаются на `<slug>.md`.
  - Verify: `make validate` → OK; `grep -rn '<slug>\.md\|plans/.*\.md' .claude CLAUDE.md` → нет стейл · Зависит от: A4, A5
  - Ref: `stit-infra/go-backend-template/scripts/git-hooks/pre-commit`

#### Phase 3 — make-first + порядок скилов/правил
- [ ] **A7:** Rule `.claude/rules/make-first.md`
  - Что делаем: канон `make <verb>` (словарь из `Makefile`), список raw-docker исключений
    (`docker exec` под `restic`/`cscli`/`mc`/`ls`), local-vs-remote split (ops → ssh-wrapper).
  - Verify: `make validate` → OK; `grep -c '^name:' .claude/rules/make-first.md` → 1 · Зависит от: —
  - Ref: `stit-infra/go-backend-template/.claude/rules/` (стиль path-scoped rule)
- [ ] **A8:** Rule `.claude/rules/skill-authoring.md` + `name:` во всех правилах
  - Что делаем: канонический скелет SKILL.md (секции) + frontmatter-контракт правил; дописать
    `name:` в `secrets-and-env.md`.
  - Verify: `make validate` → OK; во всех `.claude/rules/*.md` есть `name:` · Зависит от: —
  - Ref: `stit-infra/go-backend-template/docs/contributing.md`
- [ ] **A9:** Нормализовать `smartdev` + `triage`
  - Что делаем: секции под скелет; `docker logs` → `make logs SVC=`; внутренности `deploy.sh`
    пометить explanatory; local/remote из make-first.
  - Verify: `make validate` → OK; raw docker — только explanatory · Зависит от: A7, A8
  - Ref: `stit-infra/go-backend-template/.claude/skills/smartdev/SKILL.md`
- [ ] **A10:** Нормализовать `bootstrap-vps` + `dr-restore`
  - Что делаем: raw `docker exec` под restic/cscli/mc — legit со ссылкой на make-first; остальное через make; секции под скелет.
  - Verify: `make validate` → OK · Зависит от: A7, A8
  - Ref: `stit-infra/go-backend-template/.claude/skills/triage-failure/SKILL.md`
- [ ] **A11:** Нормализовать `add-service` + `corp-handoff` + `request-secret`
  - Что делаем: порядок секций под скелет, ссылки на make-first; контент по сути не менять.
  - Verify: `make validate` → OK · Зависит от: A7, A8
  - Ref: `stit-infra/go-backend-template/.claude/skills/scaffold/SKILL.md`
- [ ] **A12:** Замок: сверка `grep docker` + `CLAUDE.md` §Стиль
  - Что делаем: каждый raw-docker — explanatory или в исключениях make-first; в `CLAUDE.md`
    §Стиль ссылки на `make-first` + `skill-authoring`.
  - Verify: `make validate` → OK; `make plan-check` → OK · Зависит от: A9, A10, A11
  - Ref: `stit-infra/go-backend-template/CLAUDE.md`

#### Phase 4 — docs: переразложить, снести adrs
- [ ] **A13:** `docs/README.md` (роутер) + `docs/getting-started.md` (потребитель)
  - Что делаем: роутер на 3 аудитории; getting-started — fork → bootstrap-vps → /init-project → own infra.
  - Verify: `make validate` → OK · Зависит от: A2
  - Ref: `stit-infra/go-backend-template/docs/{README,getting-started}.md`
- [ ] **A14:** `docs/contributing.md` (как устроен `.claude`-слой)
  - Что делаем: матрица слоёв (rules/skills/agents/settings, где/когда грузятся/enforce), цикл, troubleshooting.
  - Verify: `make validate` → OK · Зависит от: A2
  - Ref: `stit-infra/go-backend-template/docs/contributing.md`
- [ ] **A15:** Проработать `docs/reference/{architecture,ecosystem,runbook}.md`
  - Что делаем: качественные артефакты; «почему» (compose-only, env-centralized) — present-state
    inline (§Решения/Non-goals), БЕЗ ADR-номеров. Перенести суть из старых `architecture/onboarding/runbook`.
  - Verify: `make validate` → OK · Зависит от: A13
  - Ref: `stit-infra/go-backend-template/docs/reference/{architecture,ecosystem}.md`
- [ ] **A16:** Удалить `docs/adrs/**` + почистить ADR-следы
  - Что делаем: снести `docs/adrs/`; `forward-only.md` убрать секцию «исключение — ADR»;
    `reviewer.md` убрать ADR-чек.
  - Verify: `test ! -e docs/adrs`; `grep -rn 'ADR\|adrs/' .claude docs CLAUDE.md | grep -v '/\.git/'` → нет стейл; `make validate` → OK · Зависит от: A15
  - Ref: `stit-infra/go-backend-template/docs/` (нет adrs/ — зеркалим отсутствие)
- [ ] **A17:** Вшить env-framing в доки
  - Что делаем: workstation-не-app-host + ssh-wrapper модель в getting-started + contributing.
  - Verify: `make validate` → OK · Зависит от: A13, A14
  - Ref: `stit-infra/go-backend-template/docs/reference/ecosystem.md`

#### Phase 5 — Раззнести и удалить WORKFLOW.md
- [ ] **A18:** Раззнести `.claude/WORKFLOW.md` по homes
  - Что делаем: §цикл/course-correction → `smartdev`; §«что лежит где» → `CLAUDE.md` карта;
    §«осознанно не делаем» → `CLAUDE.md` границы; §«кто что enforces» → `docs/contributing.md`;
    §«когда сломалось» → `triage`; сценарии (VPS/сервис/bump/ротация/DR) уже в скилах — срезать.
  - Verify: `make validate` → OK; контент присутствует в homes · Зависит от: A1, A9, A14
  - Ref: `stit-infra/go-backend-template/` (нет WORKFLOW.md — цикл в CLAUDE.md+smartdev)
- [ ] **A19:** `rm .claude/WORKFLOW.md` + sweep ссылок
  - Verify: `test ! -e .claude/WORKFLOW.md`; `grep -rn 'WORKFLOW\.md' . | grep -v '/\.git/'` → пусто; `make validate` → OK · Зависит от: A18
  - Ref: —

#### Phase 6 — Креды: .env.local (ops-креды, tool-only)
- [ ] **A20:** Rule `.claude/rules/env-local.md` + `.env.local.example`
  - Что делаем: порт правила + расширение на ops-креды (SSH к VPS, git-PAT, свежие ROLE_ID/SECRET_ID);
    `.env.local` в `.gitignore` (уже под `.env.*`), committed только `.env.local.example`.
  - Verify: `make validate` → OK; `grep -q 'env.local' .gitignore`-эквивалент покрывает · Зависит от: A8
  - Ref: `stit-infra/go-backend-template/.claude/rules/env-local.md` + `.env.local.example`
- [ ] **A21:** Tool-only доступ к кредам
  - Что делаем: `scripts/tools/ssh.sh` (и др.) `grep`-ают `KEY=` внутри bash, значение не в stdout;
    инвариант «никогда `Read`/`cat`/echo креда» — в правиле.
  - Verify: `make validate` → OK; `ssh.sh` не эхоит значения · Зависит от: A20
  - Ref: `stit-infra/go-backend-template/scripts/tools/logs.sh`
- [ ] **A22:** Врезка в `bootstrap-vps` + `request-secret`
  - Что делаем: ссылка на `env-local`, забор кред через tools, без переспрашивания/эха.
  - Verify: `make validate` → OK · Зависит от: A20
  - Ref: `stit-infra/go-backend-template/.claude/skills/query-logs/SKILL.md`

#### Phase 7 — local-ssh-wrapper для ops-вербов
- [ ] **A23:** Ops-вербы оборачивают ssh
  - Что делаем: `Makefile` (`ps`/`logs`/`restart`/`backup`/`restore-pg`) + `scripts/tools/ssh.sh` —
    выполнять на VPS из рабочей станции; авто-хост из `ansible/inventory.ini`; fallback на локальный docker если уже на VPS.
  - Verify: `make validate` → OK; `make ps` с рабочей станции бьёт по VPS · Зависит от: A21
  - Ref: —
- [ ] **A24:** Отразить wrapper в make-first + smartdev
  - Что делаем: убрать «реализация — план» в `make-first.md`; smartdev точнее про local vs remote.
  - Verify: `make validate` → OK · Зависит от: A23
  - Ref: `stit-infra/go-backend-template/.claude/rules/` (стиль)

#### Phase 8 — Продуктовый слой /init-project
- [ ] **A25:** Слой `docs/project/`: `README.md` + `_templates/{vision,service,stack}.md`
  - Что делаем: kinds (vision/service[backend|frontend|datastore|infra]/stack), frontmatter
    `id/kind/status: draft→stable`, workflow; файл-на-сервис (`services/<name>.md`).
  - Verify: `make validate` → OK · Зависит от: A15
  - Ref: `stit-infra/go-backend-template/docs/{domains,stack}/README.md` + `_templates/`
- [ ] **A26:** `scripts/tools/validate-project-doc.sh`
  - Что делаем: frontmatter (id/kind/name/status) + required sections per kind + ref-integrity при stable.
  - Verify: валидатор зелёный на `_templates/` · Зависит от: A25
  - Ref: `stit-infra/go-backend-template/scripts/tools/validate-{domain,stack}-doc.sh`
- [ ] **A27:** Вшить project-doc валидатор в `make check` + pre-commit
  - Verify: `make check` гоняет project-doc валидацию; pre-commit на change `docs/project/**` · Зависит от: A26
  - Ref: `stit-infra/go-backend-template/scripts/git-hooks/pre-commit`
- [ ] **A28:** Skill `service-deep-dive`
  - Что делаем: интервью-волнами заполняет `docs/project/services/<name>.md` до `status: stable`.
  - Verify: `make validate` → OK · Зависит от: A25
  - Ref: `stit-infra/go-backend-template/.claude/skills/domain-deep-dive/SKILL.md`
- [ ] **A29:** Skill `stack-deep-dive`
  - Что делаем: интервью → `docs/project/stack.md` до `stable`.
  - Verify: `make validate` → OK · Зависит от: A25
  - Ref: `stit-infra/go-backend-template/.claude/skills/stack-deep-dive/SKILL.md`
- [ ] **A30:** Skill `de-template`
  - Что делаем: читает stable-артефакты, ACT in-repo: прунит неиспользуемые `compose/*.yml` +
    `vault-agent/agent.hcl.parts`/`templates`, ставит `COMPOSE_PROFILES`, кастомит `CLAUDE.md`/README
    под идентичность проекта, срезает scaffolding; cross-repo форки/секреты — печатает next-steps.
  - Verify: `make validate` → OK · Зависит от: A25
  - Ref: `stit-infra/go-backend-template/.claude/skills/de-template/SKILL.md`
- [ ] **A31:** Skill `init-project` (оркестратор)
  - Что делаем: vision → чейн `service-deep-dive` → `stack-deep-dive` → `de-template`; сам не проектирует.
  - Verify: `make validate` → OK · Зависит от: A28, A29, A30
  - Ref: `stit-infra/go-backend-template/.claude/skills/init-service/SKILL.md`
- [ ] **A32:** Чейн из `smartdev` на «проект не инициализирован»
  - Что делаем: детект (нет stable `docs/project/vision.md`) → чейн `/init-project` первым делом.
  - Verify: `make validate` → OK; `make plan-check` → OK · Зависит от: A31, A9
  - Ref: `stit-infra/go-backend-template/.claude/skills/smartdev/SKILL.md` (uninitialized detection)

**Corp impact.**
- **ecosystem.md entry-point.** WHAT: `stit-infra/infra/docs/ecosystem.md` зовёт entry-point репо как «AGENTS.md». WHY: переход на `CLAUDE.md`. ACTION: заменить в строке про `project-infra-template-compose`. WHO: corp. DECIDE: следующий corp-PR. RISK: косметика.
- **ecosystem.md skill index.** WHAT: индекс скилов репо не содержит `/init-project`, `/service-deep-dive`, `/stack-deep-dive`, `/de-template`. WHY: новые скилы. ACTION: дописать строки. WHO: corp. DECIDE: после Phase 8. RISK: нет, документация.

**Чекпоинты.** —
