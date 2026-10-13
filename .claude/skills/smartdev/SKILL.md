---
name: smartdev
description: Ведущий cockpit проектной инфры (<org>/infra — операционный хаб проекта). За один проход собирает состояние (make status), поднимает контекст (активный план, инициализирован ли проект, есть ли соседний <org>/strategy) и сам переключает в нужный режим — init-project / triage / plan / add-service / dr-restore / bootstrap-vps или задача агенту в сиблинг-репо, — ведя RED→GREEN по дефолту. Запускай в начале сессии, после /clear, когда непонятно, с чего начать или в каком репо живёт задача, когда спрашивают о состоянии репо или стека, и когда «вроде сломалось».
---

# Skill: smartdev

Каноничный entry-point. Задача — не показать сводку и замолчать, а **вести**: за один проход
собрать состояние, поднять контекст и самому переключить в правильный режим. Дефолтная петля для
любой правки — RED→GREEN (`validate`/`doctor` красный → fix → зелёный), не «опиши и спроси».

## Когда применять

- Начало сессии, возврат к репо после паузы или `/clear`.
- Юзер сформулировал задачу, но непонятно, насколько она большая и в каком репо живёт.
- Что-то «вроде сломалось» и нужна ориентация.

Юзер уже дал чёткую узкую задачу — иди прямо в работу (RED→GREEN). Идёт активная сессия с
известным контекстом — briefing не повторяй.

## 1. Собрать состояние

```bash
make status
```

Секции детерминированы — на них держится чейнинг:
- `== Critical ==` — `ATTENTION:`-строки git/deploy-drift (upstream behind) или `none`. Это
  pure-local (`status.sh`): docker тут не дёргается.
- `== Server ==` — серверный смок VPS (host-витали load/RAM/swap/disk/OOM + здоровье
  контейнеров unhealthy/exited/restart-loop + edge: журнал доступа, его чтение CrowdSec, allowlist и
  баны ботов + сайт: liveness, `/` по среде, `robots.txt`, `sitemap.xml`). Собирает таргет `make status`
  через смок (`smoke-run.sh` на VPS / `ssh.sh smoke` с workstation). Свои `ATTENTION:`-строки — чейнить
  как Critical (→ triage); что значит каждая — `docs/reference/runbook.md`. `SKIP` — нет `.env.local`
  (connection не задан) или VPS недоступен; это норма, не падение.
- `== Plan ==` — активные планы (статус, прогресс, следующий шаг) и число пунктов бэклога, или `none`.
- `== Branch ==` / `== Working tree ==` / `== Compose ==` / `== Recent commits ==` — фон.

Смок VPS — на входе сессии. Дальше точечно: `make ps` / `make logs SVC=<svc>` /
`bash scripts/tools/ssh.sh exec '…'` (exec-канон и `.env.local` — rules `make-first`/`env-local`).
`make doctor` без `.env` локально → SKIP, норма.

## 2. Поднять контекст

- `== Plan ==` ≠ none → прочитай активный план `.claude/plans/<slug>.md` целиком, начиная с «Где мы
  сейчас»; у программы — ещё статусы фаз. Сверься с `git log` с момента последней правки плана.
- **Инициализирован ли проект** — свежий форк шаблона ещё не развёрнут под свой продукт:
  ```bash
  git remote get-url origin           # ещё …project-infra-template-compose… ?
  test -f docs/project/stack.md && grep -q '^status: stable' docs/project/stack.md
  ```
  Origin ещё template ИЛИ нет `stack.md` со `status: stable` → проект не инициализирован (см. чейн).
- **Продуктовый контекст** живёт в соседнем `<org>/strategy` (резолв пути —
  `docs/reference/ecosystem.md`, дефолт `../strategy`). Глянь, есть ли он и что в
  `docs/projects/<slug>/{vision,surface}.md` — это scope для инфры. Соседа нет → не падай, отметь
  next-step «склонируй `<org>/strategy` рядом».
- Автопамять в проекте отключена (`CLAUDE.md § Auto-memory`) — весь переживающий
  сессию контекст в репо: планы, state-файлы скиллов, docs.

## 3. Чейнить

За один проход переключись в режим. Сверху вниз — первый сработавший выигрывает:

| Сигнал из `make status` / задачи | Действие — чейн |
|---|---|
| `== Critical ==` ≠ none (upstream behind-drift) | → skill `triage` |
| `== Server ==` ATTENTION (host-pressure: disk/RAM/load/OOM, unhealthy/exited/restart на VPS, edge, сайт) | → skill `triage` |
| Багфикс / «сломалось» / «не поднимается» / трейс | → skill `triage` (не `plan`) |
| Проект не инициализирован (origin ещё template ИЛИ нет stable `docs/project/stack.md`) | → skill `init-project` (первым делом) |
| `== Plan ==` активный `in-progress` | продолжи со следующего открытого шага («Где мы сейчас») |
| Задача целиком про один сиблинг: фича бэка / фронта / сайта / бота, задача мобильному приложению, правка дизайна продукта | → агент в `../<repo>` работает его обвязкой (`CLAUDE.md § Оркестрация`); выкатка тега — вернись сюда, шаги handoff-блока релиза (`docs/reference/ecosystem.md`): `make bump`, у сайта — ещё `make accept SVC=site` (у mobile и strategy выкатки отсюда нет) |
| Задача сквозная (несколько репо) | → skill `plan`: фаза на репо → агенты в сиблингах → выкатка здесь |
| Задача = новый сервис в стек | → skill `add-service` |
| Задача = restore / потеря данных / host crashed | → skill `dr-restore` |
| Задача = новый VPS / клиент / первый запуск | → skill `bootstrap-vps` |
| Задача содержательная (не truly-atomic: топология, env-контракт, security-sensitive, несколько файлов) | → skill `plan` (planning-first) |
| Задача truly-atomic (опечатка, один очевидный файл, одна `${VAR}`) | делай сразу, RED→GREEN |
| Задачи нет, working tree чистый, план none | спроси юзера: какую задачу решаем |

Security-sensitive (план + явный OK до правки): `.env.example`-контракт,
`configs/traefik/traefik.yml.tpl` (static-конфиг Traefik рендерится из него в
`configs/traefik/traefik.yml`; правка → рестарт Traefik = downtime),
`containers/backup/` + `compose/backup.yml` (риск потери restore-points).

## 4. Дефолтная петля — RED→GREEN

Любая правка compose/configs/scripts:

1. Правишь.
2. `make validate` (синтаксис/tpl/.env-coverage) — зелёный.
3. `make doctor`, если задело live-поверхность (.env/rendered configs) — зелёный или осознанный WARN.
4. Коммит (Conventional Commits). Деплой — `make ship MSG="..."` (см. ниже), только когда юзер этого хочет.

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

1. Форма строк `.env` и identity — до первого чтения ключа (`ENV-ERR` — отказ до compose).
2. `git pull --ff-only origin main` (его отказ деплой не останавливает); `deploy.sh`, обновлённый этим pull,
   продолжает новой версией.
3. `scripts/render-configs.sh` — preflight `.env` и envsubst для `.tpl`.
4. preflight DNS — только warnings.
5. **crowdsec early** (ждёт healthy) — bouncer auto-register если `CROWDSEC_BOUNCER_API_KEY=` пуст.
6. `docker compose up -d --remove-orphans --wait --wait-timeout 180` (смена .env-значений → compose пересоздаёт сам).
7. Diff от `refs/deploy/ok` (ревизия, конфиги которой сервисы уже подхватили): `configs/{traefik,crowdsec,postgres}/**`
   (кроме заданий `configs/crowdsec/*.sh` и `ai-bots.sources`) → restart их и ожидание healthy.
8. При профиле `site` — allowlist ботов: недостающие и не обновлявшиеся шесть дней списки.

### Hot-fix прямо на VPS

При инциденте допустимо, но строго временно: `/opt/<p>-infra/` — рабочая копия
git-репо. Следующий `make ship`/`make deploy` сделает `git pull --ff-only` и
**затрёт правки**. Hot-fix = обязательный backport в git в тот же день. Если
оператор упомянул правку на хосте — флажь `⚠ on-server drift, нужен backport`
(в `triage`). Исключение — gitignored (`.env`, rendered-конфиги) правятся на VPS легально.

Debug на VPS: `bash scripts/tools/ssh.sh exec 'make deploy'` (пошаговый stdout вместо
`--wait`-таймаутов `make ship`).

## Что cockpit не делает

- Развёрнутый диагноз сам не ставит — чейнит в `triage` (там петля разбора).
- `make ship`/`deploy`/`backup` без явной воли юзера не запускает.
- `git pull`/`fetch` без явной просьбы не делает.
- Чужой in-progress план не перепланирует — продолжает его.

## Anti-patterns

- Дамп всего `make status` в чат: сводка — только то, что влияет на выбор режима, дальше — действие.
- Пере-смок VPS (`make status` / `ssh.sh smoke`) на каждый микро-вопрос: смок — на входе сессии, дальше точечно `make ps`/`make logs`.
- Длинный briefing и остановка «жду команды» вместо чейна.
- Прыжок в `add-service` минуя оценку — если задача = один Edit, делай Edit (RED→GREEN).
- Багфикс через `plan`: баг → `triage`.
