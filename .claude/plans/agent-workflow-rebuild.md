# Ребилд agent-workflow по образцу go-backend-template df59179c40

**Slug:** `agent-workflow-rebuild`
**Создан:** 2026-05-18
**Статус:** in-progress
**Последний чекпоинт:** —

## Контекст

`stit-infra/go-backend-template` начиная с `df59179c40` («feat(workflow): make-first
vocabulary, cockpit smartdev, release-one-command») пересобрал agent-workflow:
единый `make <verb>` словарь, ведущий cockpit-`smartdev` (чейнит сам, не «сводка
и замолчать»), детерминированно-парсимые сигналы (`ATTENTION:`/`== Infra-touch ==`),
fail-fast `make doctor`/`check`, handoff-механизм с агрегацией.

Этот репо уже имеет тот же каркас (forward-only внедрён полностью — `rules/forward-only.md`,
forward-only `roadmap.md`, коммиты `d47d625`..`c54b99e`; path-scoped rules; hooks;
explorer/reviewer subagents; `ship.sh` как единый путь). Отстаёт именно постфевральная
шлифовка df59179. Переносим её, переводя на infra-реальность (нет TDD/compile-loop;
`release→image+STOP` здесь = `ship→deploy` т.к. репо и есть таргет деплоя; handoff-
направление развёрнуто на **корп**, а не на инфру).

Эталоны: `go-backend-template/Makefile`, `.claude/skills/{plan,triage-failure}/SKILL.md`,
`.claude/rules/infra-impact.md`.

## Не входит в скоуп

- Изменение compose/configs/ansible самой инфры — это workflow-ребилд, не инфра-правка.
- `make release VERSION=` — здесь нет промежуточного registry-хендоффа; роль
  «финальной команды» играет `ship`.
- pre-skill hook-gate (Q2 = не добавляем) — у инфры нет аналога draft-артефактов
  backend'а; `plan-check` остаётся soft-валидатором как backend.

## Открытые вопросы

- [x] Q1: переименовать `scripts/agent-tools/` → `scripts/tools/`? → **да, полный
  паритет с backend** (A1; blast radius промерян — 4 скрипта + 13 ссылок).
- [x] Q2: pre-skill hook-gate для `plan`/`triage`? → **нет** (см. «не в скоупе»).
- [x] Q3: `new-env` поднимаем make-верб'ом? → **да**; `bootstrap-vps` зовёт `make new-env`.

## Атомы

Стандарт: ровно 1 коммит-worth, `Verify:` обязателен (canonical make-верб + ожидаемый
результат), `Зависит от:` явно. Лимит ~15, группировка по фазам, чекпоинт на границе фазы.

### Phase 1 — Хребет (словарь + tooling + сигналы)

- [x] **A1:** Переименовать `scripts/agent-tools/` → `scripts/tools/` (фундамент)
  - Что делаем: `git mv scripts/agent-tools scripts/tools`; обновить все 13 ссылок:
    `Makefile`(×2), `.claude/settings.json`(×2 globs), `.claude/WORKFLOW.md`(×2),
    `.claude/agents/explorer.md`(×3), `.claude/agents/reviewer.md`(×1),
    `.claude/rules/secrets-and-env.md`(×1), `.claude/skills/add-service/SKILL.md`(×1),
    `.claude/skills/smartdev/SKILL.md`(×1), `scripts/claude-hooks/post-compose-validate.sh`(×1),
    self-ref в `scripts/tools/ssh.sh` + `status.sh`.
  - Файлы: см. выше (cohesive rename — одна логическая единица)
  - Verify: `grep -rn 'agent-tools' . --exclude-dir=.git` пусто; `make validate` зелёный
  - Зависит от: —
  - **Done:** `git mv` (R/RM — история сохранена) + sed по 11 файлам; ссылок `agent-tools` в коде/конфиге нет (остаток только в self-описании плана); `make validate` → `OK` exit 0; `settings.json` валиден.

- [x] **A2:** Makefile — grouped `##@` help + vocabulary-шапка + `.PHONY` sync
  - Что делаем: grouped `##@`-awk help (как backend Makefile:12-15); шапка-комментарий
    с правилом `make <verb>` + passthrough-конвенцией (A=/SVC=/SNAPSHOT=/Q=,P=/ENV=);
    rename `hooks-install`→`setup`; стаб-таргеты `doctor`/`check`/`search`/`new-env`/
    `plan-check` (guard «not yet implemented (AN)» по паттерну backend Makefile:121-122);
    `.PHONY` со всеми верб'ами. Группы: LOOP/SHIP/OPS/INTEL/PROVISION/SETUP/META.
  - Файлы: `Makefile`
  - Verify: `make help` → секции с заголовками; `make` без аргумента не падает
  - Зависит от: A1
  - **Done:** `make help` рендерит 7 групп (LOOP/SHIP/OPS/INTEL/PROVISION/SETUP/META); `make`→help exit 0; стабы doctor/check/search/new-env/plan-check печатают «not yet implemented (AN)»; `hooks-install`→`setup`. NB: `make hooks-install` в доках — чинит A9.

- [x] **A3:** `make doctor` — live fail-fast preflight
  - Что делаем: `scripts/tools/doctor.sh`: `docker compose config -q`, vault-agent
    unix-socket reachable, `.runtime/{secrets,env}` отрендерены, `preflight-dns.sh`,
    `preflight-vault.sh`, `.env`↔`.env.example` coverage. Каноничная строка
    `OK` / `FAIL: <reason>`. Wire `make doctor` (убрать стаб).
  - Файлы: `scripts/tools/doctor.sh`, `Makefile`
  - Verify: `make doctor` → `OK` на здоровом / `FAIL: <reason>` при сорванном preflight
  - Зависит от: A2
  - **Done:** `scripts/tools/doctor.sh` (+x) — 7 проверок с классификацией PASS/SKIP/WARN/FAIL; `set -e` намеренно снят (диагностич. оркестратор); docker-daemon-down → SKIP не FAIL. clean checkout → `OK` exit 0 (всё SKIP — `make check` зелёный на лаптопе); `.env` без identity → `FAIL: compose config .env identity` exit 1; `A=--full` печатает captured detail. Makefile: прямой `bash` вызов (как validate/status).

- [x] **A4:** `make check` — каноничный pre-ship gate + ship.sh hookup
  - Что делаем: `check = validate + doctor`; `scripts/ship.sh` гонит `make check`
    до push, abort на красном (fail-fast как backend `release-preflight`).
  - Файлы: `Makefile`, `scripts/ship.sh`
  - Verify: `make check` зелёный на чистом дереве; искусственный красный doctor → ship abort
  - Зависит от: A3
  - **Done:** Makefile `check` = `$(MAKE) -s validate` + `$(MAKE) -s doctor` + `✓ check clean` (fail-fast: stop на первом красном). ship.sh: `if ! make check` гейт между commit и `git push` (стр.34, push стр.41) — friendly-abort, коммит локально остаётся. clean → exit 0; broken .env → check exit≠0.

- [x] **A5:** `validate.sh` — concise-by-default + каноничная OK/FAIL + FORMAT=detailed
  - Что делаем: `scripts/tools/validate.sh` сжатый вывод + финальная
    `OK` / `FAIL: <reason>`; `FORMAT=detailed` — полный разбор (паттерн backend
    `scripts/tools/*.sh --format=detailed`).
  - Файлы: `scripts/tools/validate.sh`, `Makefile`
  - Verify: `make validate` → одна каноничная строка; `make validate FORMAT=detailed` — verbose
  - Зависит от: A1
  - **Done:** `validate.sh` переписан: `rec()` копит per-check статус; concise — строка на проверку + `OK`/`FAIL: <чеки>` exit 1; `--format=detailed` — полный per-item разбор. docker-daemon-down → SKIP (как doctor). `make check` остался зелёным.

- [x] **A6:** `status.sh` — детерминированные сигналы для cockpit-чейнинга
  - Что делаем: добавить `== Critical ==` (`ATTENTION:` из unhealthy `docker compose
    ps` / ff-drift / on-server-drift hint), `== Infra-touch ==` (working tree задел
    corp-поверхность — globs из corp-handoff: `configs/vault-agent/**`, `compose/*.yml`,
    `.env.example`, `configs/crowdsec/whitelists.yaml`, `ansible/**`; иначе `none`),
    `== Plan ==` (активный план из roadmap). Сохранить каноничный хвост.
  - Файлы: `scripts/tools/status.sh`
  - Verify: `make status` показывает 3 новые секции; на чистом → `Critical: none`, `Infra-touch: none`
  - Зависит от: A1
  - **Done:** `status.sh` + `== Critical ==` (behind-drift + docker unhealthy/exited → `ATTENTION:`), `== Infra-touch ==` (5 corp-классов из git porcelain → none/список), `== Plan ==` (активные из roadmap). `set -e` снят (паритет с doctor/validate). Позитив проверен (untracked compose → `compose-topology/profiles`); чистый → `none`/`none`; `OK` exit 0 сохранён.

- [x] **A7:** `make search` + `make new-env` верб'ами (Q3)
  - Что делаем: wire `scripts/tools/search.sh` как `make search Q= [P=]`;
    wire `scripts/new-env.sh` как `make new-env` (ENV-driven passthrough). Убрать стабы.
  - Файлы: `Makefile`
  - Verify: `make search Q=traefik` → хиты; `make new-env` (dry/prompt) не падает
  - Зависит от: A2
  - **Done:** `search` с Q=/P= + guard (usage exit 2 без Q) — хиты по traefik; `new-env` → `bash scripts/new-env.sh` (`make -n` подтвердил wiring, env-driven через инхеритнутый env). `make check` зелёный.

### Phase 2 — Cockpit + sync доков

- [x] **A8:** Переписать `smartdev` в ведущий cockpit
  - Что делаем: парс `status.sh`-сигналов → чейн-таблица: `Critical≠none`/unhealthy →
    `triage`; `Infra-touch≠none` → `corp-handoff`; активный план in-progress →
    продолжить со следующего атома; крупная задача → `plan`; новый сервис →
    `add-service`; креды → `request-secret`; restore/host-crash → `dr-restore`;
    новый VPS → `bootstrap-vps`. Дефолт RED→GREEN = `validate`/`doctor` красный →
    fix → зелёный. Убрать «сводка ≤25 строк и стоп» как терминальный режим.
  - Файлы: `.claude/skills/smartdev/SKILL.md`
  - Verify: skill описывает чейнинг + RED→GREEN; нет «не делает развёрнутого диагноза» как финала
  - Зависит от: A6
  - **Done:** smartdev переписан: §3 чейн-таблица (Critical→triage, Infra-touch→corp-handoff, Plan→continue, задачи→add-service/request-secret/dr-restore/bootstrap-vps/plan), §4 RED→GREEN дефолт через `make validate/doctor`. Терминальный «≤25 строк и стоп» убран. `make status`-верб (make-first). Forward-ссылки на triage/corp-handoff/plan (Phase 3) — ок mid-plan. Реестр скилов обновлён.

- [x] **A9:** Sync `AGENTS.md` + `.claude/WORKFLOW.md` + `README.md` под новый словарь
  - Что делаем: make-верб-таблица = фактический Makefile; cockpit как entry-point;
    цикл GATHER→PLAN→ACT→VERIFY→COMMIT→SHIP; corp-handoff в «что enforces».
    Forward-only (описываем NOW, без migration-прозы / «было/стало»).
  - Файлы: `AGENTS.md`, `.claude/WORKFLOW.md`, `README.md`
  - Verify: `rg -n 'hooks-install|agent-tools' AGENTS.md .claude/WORKFLOW.md README.md` пусто; каждый верб из `make help` есть в AGENTS.md
  - Зависит от: A2, A8
  - **Done:** AGENTS.md §intro cockpit-вход + §2 grouped verb-table (16 верб'ов), §5 `setup`/check, §6 corp-handoff. WORKFLOW.md цикл (GATHER/COCKPIT/VERIFY) + enforces (cockpit-чейнинг + soft CORP-HANDOFF) + troubleshooting. README Day-0 `make check`/`make help`/cockpit. Stale `hooks-install|agent-tools` = 0; все 16 верб'ов в AGENTS.md. Forward-only (без было/стало).

- [x] **A10:** Sync `.claude/settings.json`
  - Что делаем: убедиться `Bash(make *)` покрывает новые верб'ы; явный allow для
    новых скриптов (`scripts/tools/doctor.sh`, `validate-plan.sh`) если нужен;
    Q2 — pre-skill gate НЕ добавляем.
  - Файлы: `.claude/settings.json`
  - Verify: `python3 -m json.tool .claude/settings.json` валиден; `make doctor` не требует prompt
  - Зависит от: A3
  - **Done:** `Bash(make *)` + `Bash(bash scripts/tools/*)` (globы) уже покрывают 16 верб'ов + doctor.sh/validate-plan.sh — A1-rename достаточен. Убраны избыточные прямые `Bash(scripts/hooks-install.sh)`×2 (канон = `make setup`; ansible-путь не agent-gated) — консистентно с make-first. Q2: hook-gpre-skill НЕ добавлен. JSON валиден, регрессии нет.

### Phase 3 — Скилы plan / triage / corp-handoff

- [x] **A11:** Скил `plan` (тонкий, infra-flavored)
  - Что делаем: `.claude/skills/plan/SKILL.md` по образцу backend, но блоки вопросов
    переписаны под инфру (Скоуп / Env+секреты / Топология сервисов+networking /
    Vault-KV-зависимости / Rollout+downtime / Откат). Lifecycle PLANNING→IN-PROGRESS→
    CHECKPOINT→DONE; slug; шаблон `<slug>.md` с секцией `## Corp impact` (не Infra);
    регистрация в roadmap. Ссылка на `make plan-check`.
  - Файлы: `.claude/skills/plan/SKILL.md`
  - Verify: skill ссылается на `make plan-check` и `roadmap.md`; нет backend-специфики (sqlc/depguard)
  - Зависит от: —
  - **Done:** `.claude/skills/plan/SKILL.md` — lifecycle PLANNING→IN-PROGRESS→CHECKPOINT→DONE, infra-вопросы (Скоуп/Env+секреты/Топология/Vault-KV/Rollout/Откат), шаблон с `## Corp impact`, roadmap-формат репо (`## Активные`, `[planning]`). Багфикс→triage. backend-специфики 0. В реестре скилов.

- [x] **A12:** `make plan-check` — валидатор структуры планов
  - Что делаем: `scripts/tools/validate-plan.sh` — каждый атом имеет `Verify:`
    и `Зависит от:`, ≤15 атомов, фазы при >~8. Wire `make plan-check` (убрать стаб).
  - Файлы: `scripts/tools/validate-plan.sh`, `Makefile`
  - Verify: `make plan-check` на этом файле (`agent-workflow-rebuild.md`) → PASS
  - Зависит от: A2, A11
  - **Done:** `scripts/tools/validate-plan.sh` (+x, awk per-atom scan): обязательные секции/поля + Verify:/Зависит от: на атом + ≤15 + ADVISORY фазы>8. `make plan-check` direct-bash. Дог-фудинг: rebuild-план → `OK` exit 0; негатив (атом без Verify) → `FAIL` exit 1.

- [x] **A13:** Скил `triage` (тонкий, infra-failure)
  - Что делаем: `.claude/skills/triage/SKILL.md`. Таблица категорий: compose не
    стартует / healthcheck red / vault-agent retry-loop / cert не выписан / render
    fail / `deploy.sh` fail / on-server drift. Петля: воспроизвести минимально
    (`make ps`/`make logs SVC=`/`make doctor`) → прочитать целиком → гипотеза →
    fix → re-verify зелёный + backport если правил на хосте. Без TDD (нет unit-
    тестов) — verify через `make doctor`/`make ps` зелёный. Чейнится из smartdev.
  - Файлы: `.claude/skills/triage/SKILL.md`
  - Verify: skill present; категории покрывают vault-agent/cert/healthcheck; ссылка из smartdev (A8)
  - Зависит от: A8
  - **Done:** `.claude/skills/triage/SKILL.md` — 7 категорий (compose/healthcheck/vault-agent retry/cert/render/deploy.sh/on-server drift), петля воспроизвести→прочитать→гипотеза→fix→re-verify зелёный (`make doctor`/`ps`/`validate`, без TDD), corp-причина → corp-handoff, on-server → backport. Чейн из smartdev (стр.52-53). В реестре.

- [ ] **A14:** Rule + skill `corp-handoff`
  - Что делаем: `.claude/rules/corp-handoff.md` (globs: `configs/vault-agent/**`,
    `compose/*.yml`, `.env.example`, `configs/crowdsec/whitelists.yaml`,
    `ansible/roles/stit-onboard/**`) — железобетонное правило + классификация
    (Vault seed/patch · AppRole/onboarding · crowdsec whitelist/source-ip · DNS).
    `.claude/skills/corp-handoff/SKILL.md` — блок `CORP-HANDOFF` (WHAT/WHY/ACTION/
    WHO/DECIDE/RISK), агрегация в активный план `## Corp impact`. `request-secret`
    помечается как частный случай (кросс-ссылка в обе стороны).
  - Файлы: `.claude/rules/corp-handoff.md`, `.claude/skills/corp-handoff/SKILL.md`,
    `.claude/skills/request-secret/SKILL.md`
  - Verify: globs валидны; `rg -l corp-handoff .claude/skills/smartdev` непусто (чейн из A8)
  - Зависит от: A8

- [ ] **A15:** ship.sh агрегирует `## Corp impact` + закрытие плана
  - Что делаем: `scripts/ship.sh` перед push печатает агрегированный `## Corp impact`
    из активного плана; warn если corp-поверхность тронута, но handoff-блока нет.
    Обновить roadmap-строку; чекпоинт; при DONE — удалить этот план (forward-only).
  - Файлы: `scripts/ship.sh`, `.claude/plans/roadmap.md`
  - Verify: `make ship` (dry) с планом, где есть `## Corp impact`, печатает агрегат
  - Зависит от: A4, A14

## Corp impact

<Этот ребилд меняет только agent-workflow (Makefile/skills/rules/docs/scripts-tooling)
— не compose/configs/Vault-контракт. Ожидается пустым; если атом неожиданно заденет
corp-поверхность — записать CORP-HANDOFF-айтем сюда до закрытия плана.>

—

## Чекпоинты

### 2026-05-18 — Phase 1 завершена (граница фазы)
- Закрыто: A1-A7 ✓ (хребет — словарь + tooling + сигналы). 7/15.
- Коммиты: `050834b`(A1) `c006e24`(A2) `d150d12`(A3) `efda2c9`(A4) `77c765f`(A5) `d48041c`(A6) + A7.
- Решения по развилкам исполнены: scripts/tools rename (Q1), без hook-gate (Q2), new-env верб (Q3).
- Обнаружено: `set -e` несовместим с диагностич.-оркестраторами (doctor/validate/status гоняют ожидаемо-падающие команды) → во всех трёх снят, статус копится в `$fail`. Зафиксировано как паттерн для будущих tool-скриптов.
- Не переоценивал: зависимости Phase 2/3 в силе. A8 (cockpit smartdev) зависит от A6-сигналов — готовы.
- Следующий шаг: Phase 2 A8 — переписать smartdev в ведущий cockpit.

### 2026-05-18 — Phase 2 завершена (граница фазы)
- Закрыто: A8-A10 ✓ (cockpit + sync доков). 10/15. Коммиты `bf9a59f`(A8) `b4656c8`(A9) + A10.
- smartdev = ведущий cockpit; AGENTS/WORKFLOW/README/settings.json под единый словарь, forward-only.
- Обнаружено: settings.json уже был синхронен через globы (A1-rename сделал основную работу) — A10 свёлся к консистентной чистке + верификации, не к расширению allow.
- Не переоценивал: Phase 3 (A11-A15) — скилы plan/triage/corp-handoff + plan-check + ship-агрегация. A11 без зависимостей, можно начинать.
- Следующий шаг: Phase 3 A11 — скил `plan` (тонкий, infra-flavored).
