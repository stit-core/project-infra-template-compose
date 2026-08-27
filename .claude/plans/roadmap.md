# Roadmap

Единственный артефакт планирования шаблона — этот файл. Подпапок, `<slug>.md`,
архивов и changelog'ов нет: они расходятся с правдой и мешают.

**Planning-first.** Изменение идёт через план — `### <slug>`-секцию под `## Active` ниже.
Прямая правка без плана допустима только для truly-atomic (опечатка, один очевидный файл)
и багфиксов (→ skill `triage`, RED-first). Отклонение от плана — осознанное, проговаривается
с юзером.

**Жизненный цикл.** `planning → in-progress → blocked? → done`. По `done` секция задачи
удаляется целиком — история остаётся в `git log`. Незакрытый follow-up переезжает в `## Backlog`
или новой `### `-секцией, а не хвостом в удаляемой.

**Где это запускается.** Репо живёт на машине оператора — authoring / validate / plan /
ship-поверхность. Приложения и живого стека локально нет: они на удалённом VPS. `make ship`
пушит и триггерит remote `deploy.sh` по ssh; live-ops (`ps`/`logs`/`restart`/`backup`/
`restore-pg`) прозрачно оборачивают ssh на VPS (connection из `.env.local`). Локальный SKIP
в authoring-проверках без `.env`/docker — норма, не падение.

**Current focus:** stitch-ecosystem-seams (in-progress)

## Active

### stitch-ecosystem-seams — сшивание обвязок экосистемы шаблонов
**Создан:** 2026-08-27 · **Статус:** in-progress

**Контекст.** Экосистема (canon: `corp-infra-template/docs/ecosystem.md`) имеет единый каркас
обвязки (CLAUDE.md ядро+роутер, /smartdev, planning-first, forward-only, draft→stable), но швы
порваны: канон не знает `telegram-bot-template`/`pylibinfra`; `spa-frontend-template` знает
соседей под старыми именами (`../docs`/`project-docs-template`, `stit-infra/infra`, ~30 мест);
agent-flow «strategy → infra-хаб → сервис-репо» нигде не описан; tag-конвенция расходится
(`make bump`/`<SVC>_TAG` vs `bot_tag`+`make ship`); `make ssh CMD=` ломает кавычки (3 слоя
разбора), родственный PATH-баг пойман в corp-roadmap. Решения юзера (AskUserQuestion):
FSD-проектирование переезжает из frontend в strategy полным слоем; `make ssh` удаляется в пользу
`scripts/tools/ssh.sh`; roadmap'ы всех шаблонов — под ноль; оркестрация — CLAUDE.md-guidance +
подсказка в /smartdev. Сквозной план на 6 репо — осознанное исключение из лимита ~15 атомов
(дробление на 6 мини-планов по репо дороже координации).

**Не входит в скоуп.** Код приложений и compose-стека (только обвязка: CLAUDE.md / rules /
skills / docs / Makefile-словари / scripts-tools). `compose/frontend.yml`|`bot.yml` в шаблон
infra (сервисы добавляются per-проект через /add-service). Скилл-оркестратор /dispatch (решение:
guidance-only). Шаблоны ai-gateway/amocrm-gateway, библиотеки golibinfra/pylibinfra/ui-lib —
только упоминания в каноне. Push в remotes — отдельное решение юзера (Q5).

**Открытые вопросы.**
- [x] Q1: куда переносить FSD-проектирование → полный слой в strategy
  (`projects/<slug>/fsd/<surface>/` + deep-dive по канону strategy); `Generates`/`src/`-пути
  остаются исполнителю (frontend /scaffold выводит сам)
- [x] Q2: судьба `make ssh` → удалить верб; канон произвольной команды —
  `scripts/tools/ssh.sh exec '…'`; PATH-баг remote-make чинится в обоих ssh.sh (infra + corp)
- [x] Q3: глубина чистки roadmap'ов → под ноль; мелкие живые пункты выполняются этой волной,
  крупные удаляются (история в git log)
- [x] Q4: оформление оркестрации → CLAUDE.md-guidance + подсказка режима в /smartdev; без /dispatch
- [ ] Q5: коммиты по-repo по ходу волн и push — подтвердить перед финальной сдачей (не блокирует
  правки; блокирует A16-сдачу)

**Атомы.**

#### Phase 1 — corp-infra-template (канон)
- [x] **A1:** canon `docs/ecosystem.md`: +`telegram-bot-template`+`pylibinfra` в семейство и
  Identity, frontend в диаграмму и skill-index, rollout-контракт → `make bump SVC= TAG=`
  (`<SVC>_TAG`), секция «Операционная модель агентов» (strategy = design SoT → `<org>/infra` =
  операционный хаб → сервис-репо = исполнители; sibling-checkout layout + резолв путей)
  - Verify: `grep -c "telegram-bot-template" docs/ecosystem.md` ≥ 2 · Зависит от: —
  - **Done:** canon переписан: диаграмма 3 сервис-шаблона + либы, семейство 9 репо, секция
    «Операционная модель агентов», rollout=`make bump`, skill-index актуализирован; grep=7
- [x] **A2:** corp `scripts/tools/ssh.sh`: self-route fix (`make` нет в PATH non-interactive
  ssh) — собственные сабкоманды / `bash -lc`; снимает пункт make-self-route-remote-make их roadmap
  - Verify: `bash -n scripts/tools/ssh.sh` (corp) → OK · Зависит от: —
  - **Done:** helper `run_dir` (bash -lc + printf %q), restart/exec переведены; bash -n OK
- [x] **A3:** corp roadmap под ноль: удалить offsite-backup (крупный, история в git log),
  make-self-route закрыт A2
  - Verify: corp `.claude/plans/roadmap.md` — Active+Backlog пустые · Зависит от: A2
  - **Done:** Active+Backlog `_(пусто)_`
#### Phase 2 — project-infra-template-compose (этот репо)
- [x] **A4:** `scripts/tools/ssh.sh` стабилизация: exec-контракт «команда = один аргумент,
  без перепарса кавычек», remote make-вызовы устойчивы к PATH (`bash -lc`), header-док
  - Verify: `bash -n scripts/tools/ssh.sh` → OK; `bash scripts/tools/ssh.sh` → usage · Зависит от: —
  - **Done:** rewrite: run/run_dir (printf %q + bash -lc), SSH_OPTS (BatchMode/ConnectTimeout),
    usage до резолва connection, logs без -f; bash -n OK, usage exit=2
- [x] **A5:** удалить верб `ssh` из Makefile (ops-вербы продолжают проксировать через ssh.sh);
  rule `make-first` + CLAUDE.md (§Команды, §Где это запускается) + `env-local.md`: канон
  произвольной команды — `scripts/tools/ssh.sh exec '…'` (задокументированное исключение make-first)
  - Verify: `make check` → OK; `grep -c "^ssh:" Makefile` = 0 · Зависит от: A4
  - **Done:** верб удалён (+.PHONY), make-first § SSH добавлена, CLAUDE.md §Команды + smartdev +
    env-local обновлены; make check ✓
- [x] **A6:** оркестрация: CLAUDE.md — секция «Оркестрация: агенты по репо» (карта сиблингов,
  постановка задач агентам в соседние репо их вербами/скиллами, границы) + «Обслуживает» →
  сервис-форки (backend из коробки; frontend/bot через /add-service); `docs/reference/ecosystem.md`
  — generalize sibling-резолв (`<REPO>_PATH` override, дефолт `../<name>`) + `env-local.md` ключи;
  /smartdev — подсказка «задача не про инфру → раскидай по сиблингам»
  - Verify: `make check` → OK · Зависит от: —
  - **Done:** секция + таблица сиблингов в CLAUDE.md, ecosystem.md generalize (`<NAME>_REPO_PATH`),
    smartdev: 2 chain-строки (сервис-задача → сиблинг; сквозная → план здесь); make check ✓
- [x] **A7:** roadmap этого репо: снять протухший пункт corp-canon (починен corp-side `94b1554`),
  удалить smoke-пороги (low-prio, история в git log); validate-plan backport выполняет A14
  - Verify: `make plan-check` → OK · Зависит от: —
  - **Done:** Backlog пуст; plan-check OK
#### Phase 3 — business-strategy-template (слой FSD)
- [x] **A8:** слой формы: `docs/projects/_template/fsd/` — README-канон (8 kinds, партиционирование
  по surface) + шаблоны артефактов; адаптация `docs/fsd/*` фронта под стиль strategy (карты
  слайсов + маппинги на interface/screens/domains; `Generates` с `src/`-путями не переезжает)
  - Verify: `ls docs/projects/_template/fsd/*.md | wc -l` ≥ 9 · Зависит от: —
  - **Done:** README-канон + 8 шаблонов в стиле interface-канона (per-record status,
    slug-таблицы, критерии/Что-НЕ/тест-критерий); ls = 9
- [x] **A9:** скилл `fsd-deep-dive` (+`fsd-audit`) по канону strategy (SKILL.md + references,
  AskUserQuestion, draft→stable), перенос/адаптация фронтового `/fsd-deep-dive` (~450 строк)
  - Verify: `ls .claude/skills/fsd-deep-dive/SKILL.md` (strategy) → есть · Зависит от: A8
  - **Done:** fsd-deep-dive (SKILL + workflow-patterns + draft-stable, state в дереве
    entrypoint) + fsd-audit (5 категорий проверок); зеркало widgets.pages ↔ pages.widgets
- [x] **A10:** сшивка strategy-доков: CLAUDE.md (слой в модель слоёв + зоны правок), `docs/README.md`
  handoff-таблица (frontend читает `fsd/<surface>/`); чистота screens/interface сохраняется
  (R-SEM-003 остаётся — FSD-имена живут только в своём слое)
  - Verify: `grep -c "fsd" CLAUDE.md` (strategy) ≥ 2 · Зависит от: A9
  - **Done:** CLAUDE.md (7 правок: преамбула, каноны, таблица слоёв, consumers, зоны),
    docs/README + README handoff, projects/README, interface/screens/project README'и,
    entrypoint (SKILL + routing + state-model); grep=12. Cross-audit сознательно не тронут
#### Phase 4 — spa-frontend-template
- [x] **A11:** осовременить имена: `../docs`→`../strategy` (резолв — поле в `docs/stack/service.md`
  как у go/tg), `project-docs-template`→`business-strategy-template`, `stit-infra/infra`→
  `corp-infra-template`, экосистема 4→6 шаблонов + 2 библиотеки
  - Verify: `grep -ri "project-docs\|stit-infra" --include="*.md" -l | wc -l` = 0 · Зависит от: —
  - **Done:** grep=0; ecosystem.md переписан (6+3, sibling-layout `~/git/<org>/`, орк-модель,
    make bump); CLAUDE.md/README/getting-started/docs-README/stack-README/service.md-шаблон
    (+поля project-slug/strategy-path/surface) обновлены
- [x] **A12:** FSD-переезд фронт-сторона: удалить skill `fsd-deep-dive` + `docs/fsd/`;
  `/scaffold`+`/de-template`+`/init-service` читают stable `fsd/<surface>/` из `../strategy`
  cross-repo; `src/`-пути выводит `/scaffold`
  - Verify: `ls docs/fsd` → нет; `grep -rl "fsd-deep-dive" .claude/skills | wc -l` = 0 · Зависит от: A9, A11
  - **Done:** каталоги удалены; scaffold/de-template/init-service/smartdev/stack-deep-dive/prune/
    shared-ui-rule перешиты на cross-repo чтение. Упоминания `/fsd-deep-dive` остались только как
    отсылки к скиллу strategy-репо (осознанное отклонение от буквы Verify — дух соблюдён:
    локального скилла нет)
- [x] **A13:** тонкий release/handoff-путь фронта по образцу tg-bot (skill `release`: build+push
  образа + INFRA-HANDOFF-блок; без обещаний CI — runner в экосистеме сознательно отсутствует);
  roadmap фронта под ноль
  - Verify: `ls .claude/skills/release/SKILL.md` (frontend) → есть · Зависит от: A11
  - **Done:** skill release создан (STOP на image-in-registry, handoff → make bump SVC=frontend);
    deployment.md § CI handoff → § Release handoff; roadmap фронта: Backlog пуст
#### Phase 5 — go-backend-template + telegram-bot-template
- [x] **A14:** go: `docs/reference/release.md` → канон `make bump SVC=backend TAG=` (`BACKEND_TAG`);
  ecosystem.md — упоминание оркестрации из `<org>/infra`; backport dep-check-фикса в
  `scripts/tools/validate-plan.sh` (`kk[2]`→`kk[3]`); roadmap под ноль
  - Verify: `make check` (go) → OK · Зависит от: —
  - **Done:** release.md/ecosystem.md → make bump + 6 шаблонов + 3 либы + орк-нота; backport
    не нужен — go validate-plan.sh уже несёт kk[3] (наш backlog-пункт протух); roadmap: 3 секции
    (2 blocked с code-done + 1 planning) и Backlog снесены под ноль, сохранена 1 строка —
    security-находка auth.Refresh/CanLogin (осознанное исключение); make check → ✓ clean (75.6%)
- [x] **A15:** tg: `docs/reference/release.md` → `BOT_TAG` + `make bump`; Makefile +`plan-check`
  +`doctor` (порт из go); ecosystem.md — оркестрация из `<org>/infra`; roadmap под ноль
  (заготовленный INFRA-HANDOFF из Backlog разобрать: сдать или удалить осознанно)
  - Verify: `make check` + `make plan-check` (tg) → OK · Зависит от: A14
  - **Done:** bot_tag→BOT_TAG+make bump (дока+release.sh+skill); plan-check (порт validate-plan)
    + doctor (адаптация go: uv/docker-auth/hooks/plan/drafts) в Makefile; INFRA-HANDOFF-знание
    зафиксировано forward-state: env-ручки Фазы 1 → `.env.example` (блок Deploy-ручки), BotFather
    Stars-замечание → release.md § Verify; ecosystem: services/-путь доменов + 3 либы + орк-нота;
    roadmap: Active+Backlog пусты; make check → ✓ clean (97 passed), plan-check OK, doctor OK
#### Phase 6 — финал
- [x] **A16:** сквозной свип консистентности: grep-проверка старых имён по 6 репо, гейты
  (`make check` здесь + go + tg; `pnpm typecheck && pnpm lint` фронт), Q5 (коммиты/push) закрыт
  с юзером, эта секция удаляется, Backlog здесь пуст
  - Verify: `make check` → OK · Зависит от: A5, A10, A12, A13, A15
  - **Done:** свип чист (project-docs/stit-infra/bot_tag/backend_tag/«N шаблонов»-дрейф = 0 вне
    этой план-секции); гейты: infra ✓ / go ✓ (75.6%) / tg ✓ (97 passed, plan-check, doctor) /
    frontend typecheck+lint ✓ (3 pre-existing biome warnings). Осталось закрыть Q5 с юзером →
    коммиты по-repo → удалить секцию

**Corp impact.** — (правки corp-side выполняются в этой же волне в sibling-checkout
`../corp-infra-template` — оператор корп-инфры и оператор проекта здесь одно лицо)

**Чекпоинты.**
- **2026-08-27 · Phase 1–2 закрыты.**
  - Закрыто: A1–A7 ✓ (канон + corp ssh/roadmap; infra ssh-канон + оркестрация + roadmap)
  - Обнаружено: corp-канон уже знал `<org>/strategy` (94b1554) — протухшим был наш backlog-пункт;
    у pylibinfra/ui-lib есть свои скиллы (add-kit|component + release) — отражено в skill-index
  - Следующий шаг: A8 (слой FSD в strategy)
- **2026-08-27 · Phase 3 закрыта (FSD-слой в strategy).**
  - Закрыто: A8–A10 ✓
  - Обнаружено: strategy-канон артефактов — per-record status без frontmatter (сильнее
    фронтового file-level draft/stable) — слой fsd переведён на него; state — единое дерево
    entrypoint, не skill-локальный state/ как во фронте
  - Осознанно не тронуто: `/cross-audit` (fsd-слой покрыт своим `/fsd-audit`; сквозные углы
    с fsd — расширение cross-audit при следующем касании strategy)
  - Следующий шаг: A11 (frontend осовременить имена)
- **2026-08-27 · Phase 4–6 закрыты, волна готова к сдаче.**
  - Закрыто: A11–A16 ✓ (frontend осовременен + FSD-переезд + release-путь; go/tg выровнены на
    make bump, tg получил plan-check/doctor; сквозной свип и все гейты зелёные)
  - Обнаружено: go-roadmap был не «мусорным», а с 3 план-секциями и живым Backlog — «под ноль»
    исполнен с двумя forward-фиксациями (env-ручки tg → `.env.example`, BotFather-замечание →
    release.md) и одним осознанным исключением (security-строка auth.Refresh в go)
  - Открыто: Q5 — коммиты по-repo + push (ответ юзера) → после него секция удаляется

## Backlog

_(пусто — закрытие волны stitch-ecosystem-seams оставляет Backlog чистым)_
