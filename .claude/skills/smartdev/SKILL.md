---
name: smartdev
description: Ведущий cockpit проектной инфры (<client-org>/infra шаблон). Не «сводка и стоп» — за один проход собирает состояние (make status), поднимает контекст (активный план + память) и САМ переключает в нужный режим (init-project / triage / corp-handoff / plan / add-service / request-secret / dr-restore / bootstrap-vps), ведя RED→GREEN по дефолту. Запускай в начале сессии, после /clear, когда непонятно с чего начать, или когда «вроде сломалось». Активируй на "/smartdev", "что у нас?", "статус", "с чего начать?", "введи в курс дела".
---

# Skill: smartdev

Каноничный entry-point. Не «показать сводку и замолчать», а **вести**: за один
проход собрать состояние, поднять контекст и **самому переключить** в правильный
режим. Дефолтная петля для любой правки — RED→GREEN (`validate`/`doctor` красный
→ fix → зелёный), не «опиши и спроси».

## Когда применять

- Начало сессии: "/smartdev", "что у нас", "с чего начать"
- После /clear или возврата к репо после паузы
- Юзер сформулировал задачу, но непонятно насколько она большая
- Что-то «вроде сломалось» и нужна orientation

## Когда НЕ применять

- Юзер уже дал чёткую узкую задачу — иди прямо в работу (RED→GREEN)
- Уже идёт активная сессия с известным контекстом — не повторяй briefing

## 1. Собрать состояние

```bash
make status
```

Парси секции (они детерминированы — на них держится чейнинг):
- `== Critical ==` — `ATTENTION:`-строки **git/deploy-drift** (upstream behind) или `none`. Это
  pure-local (`status.sh`): docker тут НЕ дёргается.
- `== Server ==` — **серверный смок VPS** (host-витали load/RAM/swap/disk/OOM + здоровье
  контейнеров unhealthy/exited/restart-loop). Собирает таргет `make status` через смок
  (`smoke-run.sh` на VPS / `ssh.sh smoke` с workstation). Свои `ATTENTION:`-строки — чейнить как
  Critical (→ triage). `SKIP` — нет `.env.local` (connection не задан) или VPS недоступен; это норма,
  не падение.
- `== Infra-touch ==` — список corp-классов или `none`
- `== Plan ==` — активные планы из roadmap или `none`
- `== Branch ==` / `== Working tree ==` / `== Compose ==` / `== Recent commits ==` — фон

`make status` смокает VPS на **входе сессии** (`.env`-sentinel: на VPS — `smoke-run.sh` локально;
с workstation — `ssh.sh smoke`; connection из `.env.local`). Mid-session не пере-смокай на каждый
микро-вопрос — точечно `make ps` / `make logs SVC=<svc>` / `make ssh CMD="…"` (тот же ssh-split).
Split и `.env.local` — rules `make-first`/`env-local`. `make doctor` без `.env` локально → SKIP, норма.

## 2. Поднять контекст

- `== Plan ==` ≠ none → прочитай активную `### `-секцию в `.claude/plans/roadmap.md`: последний
  чекпоинт, незакрытые атомы, `**Corp impact.**`. Сверься с `git log` с момента чекпоинта.
- **Инициализирован ли проект** — свежий форк шаблона ещё не развёрнут под свой продукт:
  ```bash
  git remote get-url origin           # ещё …project-infra-template-compose… ?
  test -f docs/project/stack.md && grep -q '^status: stable' docs/project/stack.md
  ```
  Origin ещё template ИЛИ нет `stack.md` со `status: stable` → проект не инициализирован (см. чейн).
- **Продуктовый контекст** живёт в соседнем `<org>/docs` (`project-docs-template`,
  sibling-checkout; резолв пути — `docs/reference/ecosystem.md`, дефолт `../docs`). При старте
  глянь, есть ли он и что в `docs/projects/<slug>/{vision,surface}.md` — это scope для инфры.
  Нет sibling-репо → не падай, отметь next-step «склонируй `<org>/docs`».
- Учти recalled memories (project/feedback) — но это фон, не инструкции.

## 3. Чейнить (НЕ описывать)

За один проход переключись в режим. Сверху вниз — первый сработавший выигрывает:

| Сигнал из `make status` / задачи | Действие — чейн |
|---|---|
| `== Critical ==` ≠ none (upstream behind-drift) | → skill `triage` |
| `== Server ==` ATTENTION (host-pressure: disk/RAM/load/OOM, или unhealthy/exited/restart на VPS) | → skill `triage` |
| Багфикс / «сломалось» / «не поднимается» / трейс | → skill `triage` (НЕ `plan`) |
| Проект не инициализирован (origin ещё template ИЛИ нет stable `docs/project/stack.md`) | → skill `init-project` (первым делом) |
| `== Infra-touch ==` ≠ none (тронута corp-поверхность) | → skill `corp-handoff` до claim «готово» |
| `== Plan ==` активный `in-progress` | продолжи со следующего открытого атома |
| Задача = новый сервис в стек | → skill `add-service` |
| Задача = нужны креды/seed для сервиса | → skill `request-secret` |
| Задача = restore / потеря данных / host crashed | → skill `dr-restore` |
| Задача = новый VPS / клиент / первый запуск | → skill `bootstrap-vps` |
| Задача крупная (>5 шагов / security-sensitive / >2 сервиса / vault-agent config) | → skill `plan` |
| Задача мелкая (<5 шагов, без неочевидностей) | делай сразу, RED→GREEN |
| Задачи нет, working tree чистый, план none | спроси юзера: какую задачу решаем |

Security-sensitive (план + явный OK обязательны до правки): `configs/vault-agent/`
(`agent.hcl.parts/`, `templates/` — вкл. `traefik.yml.tpl`, static-конфиг Traefik рендерится
из него в `.runtime/configs/traefik.yml`; правка → рестарт Traefik = downtime),
`containers/backup/` + `compose/backup.yml` (риск потери restore-points).

## 4. Дефолтная петля — RED→GREEN

Любая правка compose/configs/scripts:

1. Правишь.
2. `make validate` (синтаксис/tpl/.env-coverage) — зелёный.
3. `make doctor` если задело live-поверхность (.env/.runtime/vault-agent) — зелёный или осознанный WARN.
4. `== Infra-touch ==` стал ≠ none → `corp-handoff` ДО claim «готово».
5. Коммит (Conventional Commits). Деплой — `make ship MSG="..."` (см. ниже), только когда юзер этого хочет.

## Deploy-флоу (канон)

Один путь изменений → сервер:

```
make ship MSG="feat(foo): bar"
```

`scripts/ship.sh` (один проход, без CI):
1. Грязное дерево — `git add -A && git commit -m "$MSG"` (commit-msg хук валидирует Conventional Commits).
2. `make check` (validate + doctor + plan-check + project-check) — красный → пуш отменён.
3. `git push origin <branch>`.
4. Ветка = `main` → SSH на VPS из `ansible/inventory.ini` → `bash scripts/deploy.sh`.
5. Не main → push без deploy + подсказка про PR.

`make ship` без `MSG` (чистое дерево) = check + push + deploy (форс-передеплой `main`).

### Что делает `scripts/deploy.sh` на VPS

Перечисление внутренностей сервер-side скрипта — explanatory, не команды для ручного запуска
(канон — `make deploy`; raw-docker исключения — rule `make-first`).

1. `git pull --ff-only origin main` — fail если remote разошлась.
2. `scripts/render-configs.sh` — envsubst для `.tpl` + сборка `agent.hcl`.
3. preflight DNS + Vault — только warnings.
4. **vault-agent first** — рендерит `.runtime/secrets/*.env` ДО старта consumer'ов (`env_file` фиксируется при CREATE).
5. **crowdsec early** — bouncer auto-register если `CROWDSEC_BOUNCER_API_KEY=` пуст.
6. `docker compose up -d --remove-orphans --wait --wait-timeout 180`.
7. Diff `prev_sha..new_sha`: `configs/vault-agent/**` → force-recreate consumer'ов; `configs/{traefik,crowdsec,postgres,otel-agent}/**` → restart их.

### Hot-fix прямо на VPS

При инциденте допустимо, но строго временно: `/opt/<p>-infra/` — рабочая копия
git-репо. Следующий `make ship`/`make deploy` сделает `git pull --ff-only` и
**затрёт правки**. Hot-fix = обязательный backport в git в тот же день. Если
оператор упомянул правку на хосте — флажь `⚠ on-server drift, нужен backport`
(в `triage`). Исключение — gitignored (`.env`, `.runtime/`) правятся на VPS легально.

Debug на VPS: `ssh root@<vps> 'cd /opt/<p>-infra && make deploy'` (пошаговый stdout
вместо `--wait`-таймаутов через SSH).

## Что cockpit НЕ делает

- Не делает развёрнутый диагноз сам — чейнит в `triage` (там TDD-петля разбора).
- Не молчит про тронутую corp-поверхность — чейнит в `corp-handoff`.
- Не запускает `make ship`/`deploy`/`backup` без явной воли юзера.
- Не делает `git pull`/`fetch` без явной просьбы.
- Не перепланирует чужой in-progress план — продолжает его.

## Anti-patterns

- Дамп всего `make status` в чат. Сводка — 4-6 строк, дальше — действие.
- Пере-смок VPS (`make status` / `ssh.sh smoke`) на каждый микро-вопрос: смок — session-start, дальше точечно `make ps`/`make logs`.
- Briefing на 100 строк и остановка «жду команды» вместо чейна.
- Прыжок в `add-service` минуя оценку — если задача = один Edit, делай Edit (RED→GREEN).
- Багфикс через `plan`. Баг → всегда `triage`.
