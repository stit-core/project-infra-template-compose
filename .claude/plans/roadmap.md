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

**Current focus:** Phase 8 завершена (A25-A32). Дальше — Phase 6 (env-local), затем 7 (ssh-wrapper), A8 в самом конце (rules последними). Следующую фазу прорабатываем перед стартом.

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
- [x] **A3:** Порт `scripts/tools/validate-plan.sh` под single-file
  - Что делаем: валидатор сканирует `### <slug>` под `## Active`; на секцию — `**Создан:**`,
    `**Статус:**` ∈ {planning,in-progress,blocked} (blocked → `blocked by`), подсекции
    `Контекст`/`Не входит в скоуп`/`Атомы`/`Чекпоинты`, ≥1 атом с `Verify:`+`Зависит от:`,
    ссылки `Зависит от: A<N>` — внутри секции. Без лимита 15 (один сквозной план). Corp impact
    НЕ требуется (зеркалит эталон; опциональна). Default-таргет — `roadmap.md`; `A=<file>` override.
    Help-текст таргета `plan-check` обновить под single-file.
  - Verify: `make plan-check` → `OK (1 plan checked)` на этом roadmap · Зависит от: —
  - Ref: `stit-infra/go-backend-template/scripts/tools/validate-plan.sh`
  - **Done:** `validate-plan.sh` переписан под single-file (default `roadmap.md`). `make plan-check` → `OK (1 plan(s) checked)`. Робастнее эталона: метадата `**Создан:**`/`**Статус:**` якорится к `^**` (само-ссылочная проза атомов не ломает парс); починен dep-integrity (эталон проверял `kk[2]` вместо `kk[3]` — занесено в Corp impact). Help-текст `plan-check` обновлён. Negative-тесты: missing subsection + dangling dep ловятся.
- [x] **A4:** Переписать `.claude/skills/plan/SKILL.md` под single-file
  - Что делаем: писать inline-секцию в `roadmap.md` (не отдельные файлы планов); lifecycle done=секция
    удаляется; bold-лейблы подсекций, `####` фазы; восстановление после /clear из roadmap.
  - Verify: `make validate` → OK; в SKILL.md нет литерала `<slug>.md` как операт. модели (упоминания только как запрет — перефразированы) · Зависит от: A3
  - Ref: `stit-infra/go-backend-template/.claude/skills/plan/SKILL.md`
  - **Done:** SKILL.md переписан зеркалом эталона под single-file (`### <slug>` под `## Active`, bold-подсекции, `####` фазы, `**Corp impact.**`, lifecycle done=секция удаляется, восстановление из roadmap). Инфра-адаптации: `triage`/`corp-handoff`/`make ship`, инфра-вопросы инлайн. `make validate` → OK; литерал `<slug>.md` убран (запреты перефразированы в «per-plan файлы»). Находка: `ship.sh` агрегация corp-impact мертва в single-file (см. A6).
- [x] **A5:** Детект планов в `scripts/tools/status.sh`
  - Что делаем: `== Plan ==` парсит `### <slug>` под `## Active` + `**Статус:**`.
  - Verify: `make status` → `== Plan ==` показывает активную секцию · Зависит от: A3
  - Ref: `stit-infra/go-backend-template/.claude/plans/roadmap.md`
  - **Done:** Plan-блок `status.sh` зеркалит эталон (focus + `slug: статус | next: <первый открытый атом>`), статус якорится к `^**`. `make status` → `focus: ... | gold-standard-alignment: in-progress | next: A4`.
- [x] **A6:** Зачистить хвосты старой модели + wiring + ship.sh corp-impact
  - Что делаем: (1) `forward-only.md` §«Планы» под single-file (секция удаляется, не файл).
    (2) **Механический sweep ВСЕХ plan-model `<slug>.md`** по `.claude`/`CLAUDE.md` →
    single-file roadmap: `smartdev`, `corp-handoff` skill+rule, `reviewer.md` (plan skill уже чист после A4).
    Phase 3 (A9/A11) делает только структурную нормализацию секций, не plan-model.
    (3) plan-check в `make check` (пред-ship gate). (4) Новый git-хук `scripts/git-hooks/pre-commit`
    (на change `roadmap.md` → plan-check), `make setup` его ставит.
    (5) **Фикс `ship.sh` corp-impact агрегации** (находка A4): сейчас грепает `## Corp impact` (h2)
    в per-slug файлах и ЯВНО скипает `roadmap.md` (строки 45-51) → в single-file агрегация мертва.
    Переписать: читать `**Corp impact.**` bold-лейбл из `### <slug>`-секций под `## Active` в roadmap.md.
  - Verify: `make validate` → OK; `make check` гоняет plan-check; `grep -rn '<slug>\.md' .claude CLAUDE.md | grep -v '\.claude/plans/'` → пусто; pre-commit установлен; `ship.sh` агрегирует `**Corp impact.**` из roadmap (smoke-тест на текущем roadmap → печатает Corp impact) · Зависит от: A4, A5
  - Ref: `stit-infra/go-backend-template/scripts/git-hooks/pre-commit`
  - **Done:** (1) forward-only §«Планы» + `## Активные`→`## Active` под single-file. (2) sweep `<slug>.md`→roadmap в smartdev/corp-handoff skill+rule (+ `## Corp impact`→`**Corp impact.**`). (3) plan-check в `make check` → `OK (1 plan(s) checked)`. (4) `scripts/git-hooks/pre-commit` (валидирует roadmap на change), `make setup` ставит. (5) `ship.sh` corp-impact переписан на single-file: читает `**Corp impact.**` из `### `-секций под `## Active` (был мёртв — грепал `## Corp impact` в per-slug, скипал roadmap). Smoke → 3 айтема. Все 5 verify зелёные.

#### Phase 3 — make-first + порядок скилов/правил
- [x] **A7:** Rule `.claude/rules/make-first.md`
  - Что делаем: канон `make <verb>` (словарь из `Makefile`), список raw-docker исключений
    (`docker exec` под `restic`/`cscli`/`mc`/`ls`), local-vs-remote split (ops → ssh-wrapper).
  - Verify: `make validate` → OK; `grep -c '^name:' .claude/rules/make-first.md` → 1 · Зависит от: —
  - Ref: `stit-infra/go-backend-template/.claude/rules/` (стиль path-scoped rule)
  - **Done:** `.claude/rules/make-first.md` создан (frontmatter `name`+`description`+`paths`: Makefile/scripts/skills). Словарь вербов из `make help`, raw-docker исключения (restic/cscli/mc/ls через `docker exec`, `docker compose config`, throwaway `docker run` в DR, explanatory deploy.sh-внутренности), local-vs-remote split (ops на VPS; ssh-обёртка вербов = «реализация-план» Phase 7/A23, снимет A24), запреты через permissions.deny. `make validate` → OK; `grep -c '^name:'` → 1.
- [x] **A8:** Frontmatter-контракт всех правил `.claude/rules/*.md` (rules последними, по решению юзера; skill-authoring.md отменён как лишний)
  - Что делаем: дописать `name:` во ВСЕ `.claude/rules/*.md` (аудит: сейчас `name:` нет ни в одном).
    **Находка:** `multi-env.md` вообще без frontmatter (нет `description`/`paths`) → не
    автоподгружается как path-scoped правило — дописать полный frontmatter (paths: `.env*`,
    `configs/vault-agent/**`, `compose/*.yml`, ansible onboard — по содержимому правила).
  - Verify: `make validate` → OK; во всех `.claude/rules/*.md` есть `name:`+`description:`+`paths:` · Зависит от: —
  - Ref: —
  - **Done:** `name:` дописан в 6 правил (ansible-style/compose-and-services/corp-handoff/forward-only/
    secrets-and-env/traefik-routing; make-first уже имел). `multi-env.md` получил полный frontmatter
    (name+description+paths: `.env*`/`configs/vault-agent/**`/`compose/*.yml`/`ansible/roles/stit-onboard/**`)
    — был без frontmatter вовсе, не автоподгружался. Все 8 правил: name=1 desc=1 paths=1; `make validate` → OK.
- [x] **A9:** Нормализовать `smartdev` + `triage`
  - Что делаем: секции под де-факто канон (`Когда применять`/`Когда НЕ применять`/`Шаги`/`Anti-patterns`);
    `docker logs` → `make logs SVC=`; внутренности `deploy.sh` пометить explanatory; local/remote из make-first.
  - Verify: `make validate` → OK; raw docker — только explanatory · Зависит от: A7
  - Ref: `stit-infra/go-backend-template/.claude/skills/smartdev/SKILL.md`
  - **Done:** smartdev — local/remote split делегирован в rule `make-first` (line 37), секция «Что делает deploy.sh» получила explanatory-маркер (не команды для ручного запуска). triage — исправлен устаревший «deny-хук»→`permissions.deny` (Claude-хук снесён), `docker compose config` помечен как make-first debug-исключение. `make validate` → OK; оставшийся raw-docker — explanatory (deploy.sh-внутренности) + anti-pattern-пример.
- [x] **A10:** Нормализовать `bootstrap-vps` + `dr-restore`
  - Что делаем: raw `docker exec` под restic/cscli/mc — legit со ссылкой на make-first; остальное через make; секции под де-факто канон.
  - Verify: `make validate` → OK · Зависит от: A7
  - Ref: `stit-infra/go-backend-template/.claude/skills/triage-failure/SKILL.md`
  - **Done:** dr-restore — `docker logs`→`make logs SVC=` (диагностика, acme-проверка); restic-exec + throwaway-pg помечены make-first исключениями. bootstrap-vps — verify `docker logs`→`make logs SVC=`; cscli/mc/ls exec помечены исключениями; destructive `docker volume rm traefik-acme` помечен (deny-blocked для агента, ручной operator-шаг с явным OK). `make validate` → OK; оставшийся raw-docker — blessed-exec/throwaway/explanatory/destructive-manual.
- [x] **A11:** Нормализовать `add-service` + `corp-handoff` + `request-secret`
  - Что делаем: порядок секций под де-факто канон, ссылки на make-first; контент по сути не менять.
  - Verify: `make validate` → OK · Зависит от: A7
  - Ref: `stit-infra/go-backend-template/.claude/skills/scaffold/SKILL.md`
  - **Done:** add-service / corp-handoff уже канон-совместимы (секции `Когда применять`/`НЕ применять`/`Шаги`/`Anti-patterns`, команды через make, raw-docker только в explanatory YAML-комментарии) — правок не потребовали. request-secret — убран стейл «без хука» (отсылал к снесённым Claude-хукам) → «plain-текст для copy-paste». `make validate` → OK.
- [x] **A12:** Замок: сверка `grep docker` + `CLAUDE.md` §Стиль
  - Что делаем: каждый raw-docker — explanatory или в исключениях make-first; в `CLAUDE.md`
    §Стиль ссылка на `make-first`.
  - Verify: `make validate` → OK; `make plan-check` → OK · Зависит от: A9, A10, A11
  - Ref: `stit-infra/go-backend-template/CLAUDE.md`
  - **Done:** CLAUDE.md §Стиль получил make-first-буллет (канон + raw-docker исключения → rule). Сверка скилов: весь raw-docker несёт explanatory/make-first маркер в прилегающей прозе (smartdev deploy-internals, dr-restore restic/throwaway, bootstrap-vps exec/destructive-manual/corp-side). `make validate` + `make plan-check` → OK. Прим.: raw-docker в ПРАВИЛАХ (secrets-and-env, traefik-routing, compose-and-services) — отложен к rules-работе (A8/конец, «пусть живут»); там вызовы explanatory/blessed-style, аннотирую при финальном касании правил.

#### Phase 4 — docs: переразложить, снести adrs
**Решения проработки (2026-05-26).** ecosystem.md — тонкий локальный (роль репо + контракты +
указатель на корп-канон, зеркалит эталон). onboarding.md операционка — расписывается ЦЕЛИКОМ в
getting-started.md (полный Day-0/Day-1, не лёгкий design-first). /init-project — forward-ссылка
уже сейчас (journey описывает путь, не наличие; снять пометку в Phase 8/A32). ADR-«почему»
(compose-only, env-centralized) — НЕ мигрируем нигде, очевидно из present-state доков.
- [x] **A13:** `docs/README.md` (роутер) + `docs/getting-started.md` (потребитель)
  - Что делаем: роутер на 3 аудитории + reference + design-source (Phase 8). getting-started `[META]` —
    полный путь потребителя: fork → bootstrap-vps (Day-0 corp-онбординг + Day-1 ansible/deploy-key/
    registry/.env) → первый деплой → активация профилей → /init-project (forward-ссылка) → own infra.
    Впитывает операционку `onboarding.md` целиком (onboarding.md удаляется в A15 при переезде).
  - Verify: `make validate` → OK; `test -e docs/README.md && test -e docs/getting-started.md` · Зависит от: A2
  - Ref: `stit-infra/go-backend-template/docs/{README,getting-started}.md`
  - **Done:** `docs/README.md` (роутер на 3 аудитории + reference + design-source-плейсхолдер Phase 8),
    `docs/getting-started.md` `[META]` (полный путь 0-8: форк → Day-0 corp-онбординг → Day-1 ansible/
    deploy-key/registry → .env → первый деплой → активация профилей → /init-project forward-ссылка →
    /de-template → own infra; впитал операционку onboarding.md). `make validate` → OK; оба файла есть.
    Прим.: README ссылается на `reference/*` — создаются в A15 (один фазовый юнит, ссылки резолвятся до ship).
- [x] **A14:** `docs/contributing.md` (как устроен `.claude`-слой)
  - Что делаем: матрица слоёв (rules/skills/agents/settings, где/когда грузятся/enforce), цикл, troubleshooting.
  - Verify: `make validate` → OK · Зависит от: A2
  - Ref: `stit-infra/go-backend-template/docs/contributing.md`
  - **Done:** `docs/contributing.md` зеркалит эталон под факт-раскладку репо: матрица слоёв, 8 rules/
    8 skills/2 agents, цикл задачи (ship вместо CI), «кто enforce'ит» (commit-msg + pre-commit на
    roadmap + `make check`-gate в ship.sh; нет Claude-хуков, нет pre-push), course-correction,
    «осознанно не делаем» (CI/Claude-хуки/per-plan-файлы/ADR-папка/bloat), troubleshooting под
    make validate/doctor/plan-check. `make validate` → OK.
- [x] **A15:** Проработать `docs/reference/{architecture,ecosystem,runbook}.md`
  - Что делаем: architecture ← `docs/architecture.md` (present-state, без ADR-«почему»; §«Что НЕ в
    шаблоне» сохраняем). ecosystem ← тонкий локальный: роль проектной VPS + контракты с корпом +
    указатель на канон `stit-infra/infra/docs/ecosystem.md`. runbook ← `docs/runbook.md`. Удалить
    старые `docs/{architecture,onboarding,runbook}.md`. Sweep ссылок `docs/architecture.md`/
    `docs/onboarding.md`/`docs/runbook.md` → новые пути в `CLAUDE.md` + `.claude/**`.
  - Verify: `make validate` → OK; `test -e docs/reference/architecture.md -a -e docs/reference/ecosystem.md -a -e docs/reference/runbook.md`; `test ! -e docs/architecture.md -a ! -e docs/onboarding.md -a ! -e docs/runbook.md`; `grep -rn 'docs/\(architecture\|onboarding\|runbook\)\.md' CLAUDE.md .claude --include='*.md' | grep -v '\.claude/plans/'` → пусто · Зависит от: A13
  - Ref: `stit-infra/go-backend-template/docs/reference/{architecture,ecosystem}.md`
  - **Done:** `git mv` architecture/runbook → `docs/reference/`; `docs/onboarding.md` снесён (операционка
    в getting-started, A13). `docs/reference/ecosystem.md` создан тонким (роль проектной VPS + контракты
    с корпом + указатель на канон `stit-infra/infra/docs/ecosystem.md`). Sweep путей в CLAUDE.md (карта +
    auto-memory + Стек §), корневом README.md (×3), WORKFLOW.md (×4, удаляется в A19), dr-restore SKILL.md
    (×3). ADR-«почему» НЕ мигрировал (решено). Все 4 verify зелёные; grep-gate CLEAN.
- [x] **A16:** Удалить `docs/adrs/**` + почистить ADR-следы
  - Что делаем: снести `docs/adrs/` целиком (0001/0002/template — «почему» НЕ мигрируем, решено);
    `forward-only.md` убрать секцию «Единственное исключение — ADR» + упоминания ADR в §«Чего не
    пишем»/§«Граница»; `.claude/agents/reviewer.md` убрать ADR-чек.
  - Verify: `test ! -e docs/adrs`; `grep -rn 'ADR\|adrs/' .claude docs CLAUDE.md | grep -v '/\.git/'` → нет стейл; `make validate` → OK · Зависит от: A15
  - Ref: `stit-infra/go-backend-template/docs/` (нет adrs/ — зеркалим отсутствие)
  - **Done:** `docs/adrs/` снесён целиком (0001/0002/template). forward-only.md — убрана секция
    «Единственное исключение — ADR», ADR-примеры в §«Чего не пишем»/§«Как вместо этого»/§«Граница»
    перефразированы на present-state (§Решения/Non-goals в reference-доке). reviewer.md — ADR-чек →
    forward-only-чек. `docs/adrs` нет; `make validate` → OK. Остаточные «ADR» — present-state
    утверждения об ОТСУТСТВИИ ADR (forward-only.md §34, contributing §71), не стейл-ссылки.
- [x] **A17:** Вшить env-framing в доки
  - Что делаем: workstation-не-app-host + ssh-wrapper модель в getting-started + contributing.
  - Verify: `make validate` → OK · Зависит от: A13, A14
  - Ref: `stit-infra/go-backend-template/docs/reference/ecosystem.md`
  - **Done:** getting-started — блок «Где ты работаешь» (workstation = authoring/validate/plan/ship,
    живого стека нет, make ship → remote deploy.sh, ops через ssh.sh, local SKIP норма). contributing —
    блок «Где это запускается» (validate без стека / doctor SKIP без `.env` / ops оборачивают SSH).
    `make validate` + `make plan-check` → OK.

#### Phase 5 — Раззнести и удалить WORKFLOW.md
- [x] **A18:** Раззнести `.claude/WORKFLOW.md` по homes
  - Что делаем: §цикл/course-correction → `smartdev`; §«что лежит где» → `CLAUDE.md` карта;
    §«осознанно не делаем» → `CLAUDE.md` границы; §«кто что enforces» → `docs/contributing.md`;
    §«когда сломалось» → `triage`; сценарии (VPS/сервис/bump/ротация/DR) уже в скилах — срезать.
  - Verify: `make validate` → OK; контент присутствует в homes · Зависит от: A1, A9, A14
  - Ref: `stit-infra/go-backend-template/` (нет WORKFLOW.md — цикл в CLAUDE.md+smartdev)
  - **Done:** verify-pass (контент front-load'ен раньше, нового порта не требовалось — решение проработки
    Phase 5). Покрытие: §1/§2/§4/§5 → `docs/contributing.md` (A14); §2 cockpit + §4 чейнинг → smartdev;
    §3 сценарии → скилы bootstrap-vps/add-service/dr-restore + rules multi-env/secrets-and-env; §6 trade-offs →
    vault-isolation `secrets-and-env.md:23`, single-VPS `architecture.md:3`, no-CI-deploy `contributing.md`,
    HA = очевидно (не фиксируем); §7 → triage «Категории падений» + `reference/runbook.md`. Ничего не теряется.
- [x] **A19:** `rm .claude/WORKFLOW.md` + sweep ссылок
  - Verify: `test ! -e .claude/WORKFLOW.md`; `grep -rn 'WORKFLOW\.md' . --include='*.md' | grep -v '/\.git/' | grep -v '\.claude/plans/'` → пусто (plans/ обсуждает миграцию легитимно); `make validate` → OK · Зависит от: A18
  - Ref: —
  - **Done:** `git rm .claude/WORKFLOW.md`; убран `.claude/WORKFLOW.md` из `paths:` frontmatter правила
    `forward-only.md` (был его триггером). Файла нет; grep WORKFLOW.md (excl plans) → CLEAN; `make validate` → OK.

#### Phase 6 — Креды: .env.local (workstation connection + tool-only)
**Решения проработки (2026-05-27).** Факты разошлись с исходным текстом атомов: `ssh.sh` уже
существует, SSH к VPS **key-based** (ключ на машине), deploy-key регистрируется руками,
`ROLE_ID/SECRET_ID` идут в `.env` через `new-env.sh`. Реальная роль `.env.local` в этом репо:
**workstation-файл с connection к VPS** (`SSH_HOST`/`SSH_PORT`/`SSH_USER`/`PROJECT_NAME` или
`HOST=user@ip`) + любые токены, которые юзер кидает в чат. **Host берётся из `.env.local`, не
хардкодится.** `.env` живёт только на сервере (workstation без `.env` — норма). Phase 6+7
сливаются в одну фичу: workstation→server ops через `.env.local`-driven `ssh.sh`.
- [x] **A20:** Rule `.claude/rules/env-local.md` + `.env.local.example`
  - Что делаем: `env-local.md` — `.env.local` (workstation, gitignored) хранит connection (SSH_*/
    PROJECT_NAME/HOST) + токены; SSH-ключ на машине; `.env` — серверный runtime. Инвариант: **токен
    из чата → агент пишет в `.env.local`, значение НЕ эхоит**; доступ к значению — tool-only (grep в
    bash), не `Read`/`cat`/echo. `.env.local.example` документирует ключи. `.gitignore` уже покрывает
    (`.env.*` + `*.local`).
  - Verify: `make validate` → OK; `.env.local` под gitignore; `.env.local.example` есть · Зависит от: A8
  - Ref: `stit-infra/go-backend-template/.claude/rules/env-local.md` + `.env.local.example`
  - **Done:** `.claude/rules/env-local.md` (workstation `.env.local` = connection+токены; `.env`
    серверный; поведение «токен из чата→.env.local, не эхоить»; security-инвариант tool-only;
    известные ключи) + `.env.local.example` (SSH_HOST/PORT/USER/PROJECT_NAME/HOST + плейсхолдер токена).
    `git check-ignore .env.local` → ignored; `make validate` → OK.
- [x] **A21:** `ssh.sh` читает connection из `.env.local` (tool-only)
  - Что делаем: `scripts/tools/ssh.sh` берёт `SSH_HOST`/`SSH_PORT`/`SSH_USER`/`PROJECT_NAME`/`HOST` из
    `.env.local` (grep `KEY=` внутри bash, значение не в stdout); приоритет env > `.env.local` >
    `inventory.ini` (fallback для bootstrap). Не эхоит connection-значения.
  - Verify: `make validate` → OK; `ssh.sh` читает `.env.local`, не светит значения · Зависит от: A20
  - Ref: `stit-infra/go-backend-template/scripts/tools/logs.sh`
  - **Done:** `ssh.sh` — `read_local KEY FILE` (grep, `|| true` чтобы pipefail+set -e не убивал при
    отсутствии ключа), приоритет env > `.env.local` > inventory. Тест: temp `.env.local` → невалидный
    subcommand печатает usage (exit 2), значение `10.20.30.40` НЕ в stdout (no leak); без источников →
    внятная ошибка про SSH_HOST. `make validate` → OK.
- [x] **A22:** Врезка в `bootstrap-vps` + `request-secret`
  - Что делаем: ссылка на `env-local`; SECRET_ID/pubkey/токены — tool-only, без переспрашивания/эха
    значения в чат; connection в `.env.local`.
  - Verify: `make validate` → OK · Зависит от: A20
  - Ref: `stit-infra/go-backend-template/.claude/skills/query-logs/SKILL.md`
  - **Done:** bootstrap-vps — Guard'рейл «Креды tool-only» (SECRET_ID/ROLE_ID/deploy-key/токены не
    эхоить; connection→`.env.local`). request-secret — anti-pattern, разводящий намеренный
    `vault kv put` hand-off от tool-only кредов оператора (токен→`.env.local`). `make validate` → OK.

#### Phase 7 — local-ssh-wrapper для ops-вербов
- [x] **A23:** Ops-вербы оборачивают ssh + `make ssh`
  - Что делаем: `Makefile` ops-вербы (`ps`/`logs`/`restart`/`backup`/`restore-pg`) — на workstation
    (нет `.env`) проксируют через `ssh.sh exec "make <verb> …"` на VPS; на VPS (есть `.env`) —
    локальный docker (sentinel = наличие `.env`). Новый верб **`make ssh CMD="…"`** = `ssh.sh exec`.
    Host/connection — из `.env.local` (A21), ничего не хардкодим. `ssh.sh` дописать под backup/restore-pg
    (через `exec make …`, не нужен отдельный subcommand).
  - Verify: `make validate` → OK; `make ps` с workstation идёт по ssh; `make ssh CMD=…` работает · Зависит от: A21
  - Ref: —
  - **Done:** Makefile OPS — все 5 вербов обёрнуты `if [ -f .env ] then docker… else ssh.sh exec make
    <verb>` (sentinel `.env`); новый `ssh` верб (`make ssh CMD="…"`), `.PHONY` дополнен. Тест: `make ps`
    без `.env` уходит в ssh.sh (ошибка SSH_HOST, НЕ локальный docker); `make ssh` без CMD → usage; `ssh`
    в `make help`. `make validate` → OK. backup/restore-pg идут через `exec make …`, отдельный subcommand
    в ssh.sh не понадобился.
- [x] **A24:** Отразить wrapper в make-first + smartdev
  - Что делаем: убрать «реализация — план» в `make-first.md` (ops-вербы теперь реально оборачивают ssh);
    добавить `make ssh` в словарь; smartdev точнее про local vs remote (sentinel `.env`).
  - Verify: `make validate` → OK · Зависит от: A23
  - Ref: `stit-infra/go-backend-template/.claude/rules/` (стиль)
  - **Done:** make-first — словарь OPS дополнен `ssh CMD=`; §Local-vs-remote переписан на present-state
    (sentinel `.env`, auto-proxy через ssh.sh, connection из `.env.local`, без «реализация-план»).
    smartdev §1 — серверные проверки описаны через auto-proxy + `.env.local`. `make validate` → OK.

#### Phase 8 — Продуктовый слой /init-project
**Решения проработки (2026-05-27).** Слой `docs/project/` = продуктовый уровень ВЫШЕ go-backend
(там code-слой одного сервиса). 3 kind'а: `vision` (singleton `vision.md`), `service` (per
hosted-service, `services/<name>.md`), `stack` (singleton `stack.md`). Frontmatter `id: project.<name>`
/ `kind` / `name`==basename / `status: draft→stable`; service дополнительно `subtype:
backend|frontend|datastore|infra` + `hosting: here|external`.
- **service-схема единая** (не per-subtype): H2 `Hosting`/`Identity`/`Secrets`/`Route`/`Generates`
  для всех subtype'ов; subtype — frontmatter-поле, per-subtype нюансы — в прозе/Generates.
- **services/ = только compose-хостируемое** (postgres, minio, backend-контейнер, landing). Внешний
  frontend-SPA / backend-код-репо — перечислены в vision `Service map` как контекст, без service-doc;
  для них de-template печатает cross-repo next-steps.
- **de-template выводит `COMPOSE_PROFILES` из service-map** (datastore→postgres/storage, backend→
  backend), НЕ из явного prune-list. `stack.md` несёт только cross-cutting.
- Required H2: vision — `Problem`/`Users`/`Service map`/`Boundaries`/`Environments`; service —
  `Hosting`/`Identity`/`Secrets`/`Route`/`Generates`; stack — `Domains`/`Edge`/`Networks`/`Backup`/
  `Observability`/`Generates`. Пустые → явный `N/A`/`_нет_` (зеркалит domain-дисциплину).
- de-template — **skill-only** движок (зеркалит эталон), reviewable edits, guard «не на каноническом
  шаблоне» (origin == `stit-infra/project-infra-template-compose` И не tmp-копия → СТОП).
- Исполнение: автономно до зелёного `make check`, commit по phase-юнитам, push/ship — отдельным OK.
- [x] **A25:** Слой `docs/project/`: `README.md` + `_templates/{vision,service,stack}.md`
  - Что делаем: создать `docs/project/README.md` (3 kind'а, frontmatter-контракт `project.<name>` +
    `subtype`/`hosting` для service, required-H2 таблица, workflow vision→services→stack→de-template,
    gate stable+validator, anti-patterns) + три `_templates/{vision,service,stack}.md` с обязательными
    H2 и `<...>`-плейсхолдерами. `services/` создаётся deep-dive'ами по карте, в шаблон не коммитим.
  - Verify: `make validate` → OK; `test -e docs/project/README.md -a -e docs/project/_templates/vision.md -a -e docs/project/_templates/service.md -a -e docs/project/_templates/stack.md` · Зависит от: A15
  - Ref: `stit-infra/go-backend-template/docs/{domains,stack}/README.md` + `_templates/`
  - **Done:** `docs/project/README.md` (продуктовый слой ВЫШЕ go-backend code-уровня; 3 kind'а
    vision/service/stack, frontmatter `project.<name>`+service `subtype`/`hosting`, required-H2,
    `Generates→инфра`-таблица «subtype→профиль», workflow, gate, anti-patterns) + три `_templates/`.
    `make validate` → OK; file-existence → PASS.
- [x] **A26:** `scripts/tools/validate-project-doc.sh`
  - Что делаем: зеркало `validate-stack-doc.sh` под 3 kind'а. Frontmatter (id/kind/name/status;
    service → ещё subtype∈{backend,frontend,datastore,infra}+hosting∈{here,external}); `basename==name`,
    `id=="project.<name>"`; required H2 per kind; при `status: stable` — секции непусты. `_templates/`+
    `README.md` скипаются.
  - Verify: валидатор зелёный (no .md под `docs/project` кроме templates → `OK (0 ...)`); negative-тест на битом frontmatter ловится · Зависит от: A25
  - Ref: `stit-infra/go-backend-template/scripts/tools/validate-{domain,stack}-doc.sh`
  - **Done:** `validate-project-doc.sh` зеркалит stack-валидатор под 3 kind'а; service-kind проверяет
    `subtype`/`hosting` enum'ы. Empty-run → `OK (0 file(s) checked)`; positive (stable service) → OK;
    negative (битый id + плохой subtype + пустая stable-секция) → 3 ошибки, exit 1.
- [x] **A27:** Вшить project-doc валидатор в `make check` + pre-commit
  - Что делаем: `make check` гоняет `validate-project-doc.sh docs/project`; `scripts/git-hooks/pre-commit`
    на change `docs/project/**.md` → валидатор (рядом с roadmap-валидацией). Новый таргет `project-check`
    в Makefile (зеркалит `plan-check`).
  - Verify: `make check` гоняет project-doc валидацию; pre-commit на change `docs/project/**`; `make validate`→OK · Зависит от: A26
  - Ref: `stit-infra/go-backend-template/scripts/git-hooks/pre-commit`
  - **Done:** Makefile — таргет `project-check` (+ `.PHONY`), вшит в `check` (после `plan-check`).
    pre-commit — блок на change `docs/project/**.md` → `validate-project-doc.sh`. `make check` → `✓ check
    clean` (гоняет project-check); `make project-check` → OK.
- [x] **A28:** Skill `service-deep-dive`
  - Что делаем: интервью-волнами (AskUserQuestion ≤4) заполняет `docs/project/services/<name>.md` до
    `status: stable`; пишет в md сразу; опирается на текущую compose-инфру как образец. По одному
    service-doc на hosted-сервис из vision `Service map`.
  - Verify: `make validate` → OK; frontmatter skill `name:`==1 · Зависит от: A25
  - Ref: `stit-infra/go-backend-template/.claude/skills/domain-deep-dive/SKILL.md`
  - **Done:** `.claude/skills/service-deep-dive/SKILL.md` (зеркало domain-deep-dive под единую
    service-схему: волны Hosting→Identity→Secrets→Route→Generates, `make project-check A=<file>`,
    skip `hosting: external`, опора на compose/vault-agent-инфру). `name:`==1; `make validate` → OK.
- [x] **A29:** Skill `stack-deep-dive`
  - Что делаем: интервью → `docs/project/stack.md` (domains/edge/networks/backup/observability +
    Generates) до `stable`. Cross-cutting инфра-стека VPS, профили НЕ дублирует (их выводит de-template).
  - Verify: `make validate` → OK; frontmatter skill `name:`==1 · Зависит от: A25
  - Ref: `stit-infra/go-backend-template/.claude/skills/stack-deep-dive/SKILL.md`
  - **Done:** `.claude/skills/stack-deep-dive/SKILL.md` (волны Domains→Edge→Networks→Backup→
    Observability→Generates; явно НЕ задаёт `COMPOSE_PROFILES` — anti-pattern; опора на traefik/
    crowdsec/backup-инфру). `name:`==1; `make validate` → OK.
- [x] **A30:** Skill `de-template`
  - Что делаем: skill-only движок. Gate (не канонический шаблон + артефакты stable+валидатор зелён).
    Читает stable `docs/project/{vision,services/*,stack}`: (1) **выводит `COMPOSE_PROFILES`** из service-map;
    (2) прунит неиспользуемые `compose/*.yml` + `vault-agent/agent.hcl.parts/`/`templates/` по hosted-набору;
    (3) кастомит `CLAUDE.md`/`README.md` под идентичность проекта, срезает scaffolding (getting-started META,
    сброс roadmap); (4) cross-repo (форки backend/frontend, seed секретов) — печатает next-steps, не выполняет.
  - Verify: `make validate` → OK; guard «не на каноническом шаблоне» присутствует · Зависит от: A25
  - Ref: `stit-infra/go-backend-template/.claude/skills/de-template/SKILL.md`
  - **Done:** `.claude/skills/de-template/SKILL.md` (Gate: `git remote get-url origin`==template → СТОП +
    `make project-check`; Phase A механика — вывод профилей из карты, прунинг `compose/*.yml` через
    `git rm` (wildcard в Makefile сам исключает) + vault-agent parts/templates per profile, кастом
    идентичности, strip scaffolding; cross-repo — только next-steps). `name:`==1; guard присутствует;
    `make validate` → OK.
- [x] **A31:** Skill `init-project` (оркестратор)
  - Что делаем: vision (заполнить `vision.md`+Service map) → чейн `service-deep-dive` per hosted-service →
    `stack-deep-dive` → `de-template`; сам не проектирует/не де-темплейтит. Gate перед de-template: всё stable.
  - Verify: `make validate` → OK; frontmatter skill `name:`==1 · Зависит от: A28, A29, A30
  - Ref: `stit-infra/go-backend-template/.claude/skills/init-service/SKILL.md`
  - **Done:** `.claude/skills/init-project/SKILL.md` (зеркало init-service уровнем выше: этапы vision →
    service-deep-dive per hosted → stack-deep-dive → de-template, gate перед de-template, cross-repo
    только next-steps; «НЕ делает» + anti-patterns). `name:`==1; `make validate` → OK.
- [x] **A32:** Чейн из `smartdev` на «проект не инициализирован»
  - Что делаем: детект (нет `docs/project/vision.md` со `status: stable`) → чейн `/init-project` первым делом.
  - Verify: `make validate` → OK; `make plan-check` → OK · Зависит от: A31, A9
  - Ref: `stit-infra/go-backend-template/.claude/skills/smartdev/SKILL.md` (uninitialized detection)
  - **Done:** smartdev — детект инициализации в §2 (`git remote get-url origin` + grep `status: stable`
    в vision.md); строка чейна в таблице §3 (после triage, перед corp-handoff, «первым делом»);
    `init-project` добавлен в mode-список frontmatter. `make validate` + `make plan-check` → OK.

**Corp impact.**
- **ecosystem.md entry-point.** WHAT: `stit-infra/infra/docs/ecosystem.md` зовёт entry-point репо как «AGENTS.md». WHY: переход на `CLAUDE.md`. ACTION: заменить в строке про `project-infra-template-compose`. WHO: corp. DECIDE: следующий corp-PR. RISK: косметика.
- **ecosystem.md skill index.** WHAT: индекс скилов репо не содержит `/init-project`, `/service-deep-dive`, `/stack-deep-dive`, `/de-template`. WHY: новые скилы. ACTION: дописать строки. WHO: corp. DECIDE: после Phase 8. RISK: нет, документация.
- **upstream validate-plan.sh dep-check bug.** WHAT: эталонный `go-backend-template/scripts/tools/validate-plan.sh` имеет мёртвую проверку dep-integrity — проверяет `kk[2]` (cur, всегда валиден) вместо `kk[3]` (dep). Здесь пофикшено при порте (A3). WHY: иначе dangling `Зависит от: A<N>` не ловится. ACTION: бэкпортнуть фикс в go-backend. WHO: corp. DECIDE: при следующем касании go-backend. RISK: низкий (latent, не триггерится без битых deps).

**Чекпоинты.** —
