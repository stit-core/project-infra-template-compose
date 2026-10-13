---
name: de-template
description: Развернуть форк `project-infra-template-compose` в самостоятельную проектную инфру по stable-артефактам `docs/project` — вывести `COMPOSE_PROFILES` из `stack § Service map`, прунить неиспользуемые `compose/*.yml` + секции `.env.example`, кастомить `CLAUDE.md`/`README.md` под проект (продуктовый контекст читает cross-repo из `<org>/strategy`), печатать cross-repo next-steps. Вызывай, когда юзер хочет убрать шаблонную мету из своего форка, или когда `/init-project` дошёл до развёртывания (стек + сервисы stable). Движок skill-only — reviewable edits по фазам с показом каскадов перед прунингом. На каноническом репо шаблона не запускается.
---

# de-template — движок развёртывания инфры

Превращает форк `project-infra-template-compose` в проектную инфру,
которая ничего не помнит про шаблон. Читает **stable** инфра-артефакты
`docs/project/{services/*, stack}` (+ продуктовый контекст cross-repo из
`<org>/strategy` для кастомизации идентичности) и:

1. Выводит `COMPOSE_PROFILES` из `stack § Service map`.
2. Прунит неиспользуемые compose-фрагменты + env-секции (с показом
   каскада — что исчезнет — до удаления).
3. Кастомит идентичность (`CLAUDE.md`/`README.md` под проект).
4. Сбрасывает scaffolding (`getting-started.md`, `.claude/plans/`).
5. Печатает cross-repo next-steps.

Движок **skill-only**: нет committed-скрипта — детерминированная
механика идёт как **reviewable edits под этой процедурой**, каждый шаг
— отдельный diff с явным подтверждением каскада через
`AskUserQuestion`.

Запускается **один раз** на форке. Финал — зелёный `make validate` /
`make check` и репо без следов «шаблона».

## Точки входа

| вызов | поведение |
|---|---|
| `/de-template` | полный путь: Gate → Phase A → Phase B → Verify |
| `/de-template status` | сводка состояния (gate, что уже сделано, что осталось) |
| `/de-template phase=<a1..a5>` | одна фаза (для возобновления после блокера) |

`a1..a5` — шаги Phase A (см. `references/phase-a-mechanics.md`):
`a1`=profiles, `a2`=prune-compose, `a3`=prune-env,
`a4`=identity, `a5`=strip-scaffolding.

## Интерактив — через `AskUserQuestion`

**Любое подтверждение / выбор — через `AskUserQuestion`**, потому что
движок необратимо меняет репо: каждое такое действие (`git rm` в
A.2/A.3, сброс планов в A.5, удаление getting-started) идёт через
явный `AskUserQuestion` после показа каскада, а не «удалю по
умолчанию» / «сделаю и покажу diff».

Принципы:

- Gate-провалы → не plain «выход с ошибкой», а `AskUserQuestion` с
  опциями «вернуться в `/service-deep-dive`», «вернуться в
  `/init-project`», «выход».
- Каскад в A.2/A.3 → `AskUserQuestion` «удалить X, Y, Z?» (Да / Нет /
  Показать diff подробнее / Other).
- Идемпотентность (Gate.3) → `AskUserQuestion` «продолжить с фазы X /
  прогнать заново / выход».
- Сводки в чат — коротко, только то, что нужно для выбора, и сразу `AskUserQuestion`.

## Что делать сразу при запуске

1. Прочитать `state/de-template.md`, если есть (что уже сделано).
2. Прогнать **Gate** (см. ниже).
3. Прочитать stable-артефакты: `docs/project/stack.md` (§ Service map +
   § Generates) + все `services/*.md`. Для A.4 — продуктовый
   `<org>/strategy/.../vision.md § Problem` (cross-repo; резолв пути —
   `docs/reference/ecosystem.md`).
4. Если args = `status` — только сводка + `AskUserQuestion` «что
   делать?» (продолжить / пропустить фазу X / выход).
5. Если args = `phase=<x>` — после Gate `AskUserQuestion` «прогнать
   только фазу X?».
6. Иначе — `AskUserQuestion` «полный проход / выбрать фазу / выход»,
   далее по фазам с каскадным `AskUserQuestion` на каждом шаге.

## Gate (проверить ДО любых правок)

См. `references/gate-and-cascades.md § Gate`. Кратко — 3 проверки:

1. **Не канонический шаблон.**
   ```bash
   git remote get-url origin
   ```
   Если origin == `…stit-core/project-infra-template-compose…` И
   каталог не временная тест-копия → СТОП. Запуск на каноне сносит
   шаблонные фрагменты. Через `AskUserQuestion` явно подтвердить: «это
   форк `<client-org>/infra` или throwaway-копия?». При «нет» — выйти.

2. **Артефакты stable.**
   ```bash
   make project-check
   ```
   Зелёный И `stack` + все `services/*` — `status: stable`, секции
   `Generates` непусты, `stack § Service map` непуст. Иначе СТОП →
   инструкция оператору: `/stack-deep-dive`/`/service-deep-dive` добить.

3. **Идемпотентность.** Прочитать состояние:
   - `.env.example` содержит ли уже `COMPOSE_PROFILES=...`?
   - `compose/` прунены?
   - `CLAUDE.md` помнит про шаблон?

   Если что-то частично сделано — показать сводку, через
   `AskUserQuestion`: «продолжить с фазы X» / «прогнать заново» /
   «выход».

## Phase A — детерминированная механика

См. `references/phase-a-mechanics.md` — пошаговая механика A.1..A.5
с подсказками по каскадам.

Каждый шаг — отдельный reviewable дифф. Перед удалением чего-либо —
**через `AskUserQuestion` показать каскад** (см. `gate-and-cascades.md
§ Каскады прунинга`): «удалим X, Y, Z; никаких других ссылок на них в
репо нет — подтверждаешь?».

### A.1. Вывести `COMPOSE_PROFILES` из `stack § Service map`

- Из `stack § Service map` + `services/*.md` (subtype + hosting)
  собрать активный набор по таблице маппинга (см.
  `phase-a-mechanics.md`).
- Записать дефолт в `.env.example` (`COMPOSE_PROFILES=<набор>`).
- Напомнить оператору: тот же набор выставить в `.env` после bootstrap
  (профили активируются после заполнения их секций секретов в `.env` —
  `.claude/rules/multi-env.md`).

### A.2. Прунить неиспользуемые `compose/*.yml`

- Always-on (никогда не прунятся): `traefik`, `crowdsec`; `landing` — пока
  корень `${DOMAIN}` не занят сайтом.
- Сайт на корне (строка карты `<org>/site`, `hosting: here` → `compose/site.yml`,
  профиль `site`) — заглушка `compose/landing.yml` прунится вместе с
  `configs/landing/` и строкой `configs/landing/index.html` в `.gitignore`: её
  роутер сайт перебивает, а пока она в стеке, на адресах сайта без его роутеров
  отвечает её страница с кодом 200. Сертификат корня выпускается с первым
  `make bump SVC=site`.
- Profiled — каскад: показать список `compose/<x>.yml` для удаления +
  все ссылки на эти файлы (Makefile, скрипты, доки) → через
  `AskUserQuestion` подтвердить.
- Удалить через `git rm`.
- `COMPOSE_ARGS` в Makefile глобит `compose/*.yml` через
  `$(wildcard …)` — Makefile править не надо; `ROLE_FILES` в
  `scripts/deploy.sh` (роли multi-host) называет фрагменты по имени —
  строку роли правят тем же шагом.

### A.3. Прунить неиспользуемые секции `.env.example`

- Сохраняются всегда: identity, ACME, `CROWDSEC_BOUNCER_API_KEY`,
  `HOST_ROLE`, registry.
- Per profile (см. `phase-a-mechanics.md`) — каскад прунинга: показать
  секции переменных отключённых профилей + проверить, что их `${VAR}`
  не остались в compose/configs → через `AskUserQuestion` подтвердить.
- Удалить Edit'ом (`make validate` § .env coverage подтвердит чистоту).

### A.4. Кастомить идентичность

- `CLAUDE.md` — шапка/стек под имя проекта из продуктового
  `<org>/strategy/.../vision.md § Problem` (cross-repo read); убрать
  «шаблон stit», «копируется в `<client-org>/infra`», секцию «Что
  менять при копировании». Карта где-что и rules остаются.
- `README.md` (корневой) — проектная шапка вместо «шаблон проектной
  инфры»; убрать «форкни».
- Reference-доки (`docs/reference/*`, `docs/contributing.md`) — общие,
  остаются ссылками.

Эти правки — **не каскад**: точечное переписывание, не удаление.

### A.5. Strip scaffolding

- `docs/getting-started.md` ([META] «как форкнуть шаблон») — удалить.
- `.claude/plans/` — сбросить к fork-start (планы шаблона ≠ планы форка): удалить файлы
  планов, `backlog.md` — `_пусто_`.
- `docs/project/{services/*, stack}.md` — **оставить**: это инфра-доки
  проекта (карта сервисов + cross-cutting). Продуктовые доки — в `<org>/strategy`.
- `docs/project/_templates/` и deep-dive/init-project скилы — тоже
  остаются (система наследуется).

## Phase B — cross-repo next-steps (печатать, не выполнять)

См. `references/phase-a-mechanics.md § Phase B`.

de-template **не делает** cross-repo действий — печатает чеклист
оператору, склеивая накопленное:

- из `state/journey.md § ## Cross-repo next-steps` (если приходит из
  `/init-project`);
- из state'ов deep-dive скиллов (`state/services/*.md`,
  `state/stack.md` через `## Что копать дальше`);
- из дополнительной логики самого `/de-template`.

Категории чеклиста:

- **Сервисы из сиблинг-репо** (`hosting: external` и сервисы с образом
  сервис-репо): форк соответствующего шаблона (`<org>/backend`,
  `<org>/frontend`, `<org>/site`, …) — дальше его ведёт агент в сиблинге
  обвязкой того репо по плану здесь (`CLAUDE.md § Оркестрация`); образ
  пушит `/release` сервис-репо в `REGISTRY_HOST`, тег → `<SVC>_TAG` в
  `.env` (`make bump SVC=<svc> TAG=…`).
- **Секреты активных профилей**: оператор дописывает блок `VAR=value`
  в `.env` на VPS по `.env.example` (комментарии там объясняют, как
  сгенерировать каждое значение).
- **DNS и ACME** из `stack § Domains` / `§ Generates`: A-записи сабдоменов под LE HTTP-01;
  `ACME_EMAIL`/`ACME_CASERVER` — в `.env` на VPS.

## Verify

```bash
make validate    # фрагменты после прунинга консистентны
make check       # перед claim «готово»
```

Зелёный `make validate` на развёрнутом форке + отсутствие
«шаблон»-нарратива в `CLAUDE.md`/`README.md` — критерий движка.

## Память `state/de-template.md` — коммитится

Скилл-однократный, но **может прерваться** на блокере (например, gate
красный после A.3 и нужно вернуться к deep-dive). state позволяет
возобновиться без полного прохода.

State — **коммитбл артефакт**, не приватная память агента:

- В `.gitignore` НЕ попадает; коммитится между фазами (`A.1 done` →
  commit, `A.2 done` → commit), чтобы прерывание не теряло прогресс.
- Это **shared контекст** для архитекторов: видно в PR, ревьюится.
- Переживает `/clear`, переход между машинами оператора.
- **Не содержит секретов** — только метаданные о ходе развёртывания.
- После Verify (зелёный `make validate/check`) — `state/de-template.md`
  удаляется (`git rm`); онбординг закрыт.

См. `references/state-format.md`. Кратко:

- Файл существует, пока de-template не закрыт.
- Секции:
  - `## Текущая фаза` (a1..a5 или phase-b);
  - `## Открытые вопросы` (`**blocker**` для блокирующих, обычно =
    `make project-check` красный → возврат к deep-dive);
  - `## Применённые шаги` — короткий список «a1 done, a2 done».

## Запреты

- **Не запускать на каноническом шаблоне.** Gate первая защита.
- **Не стартовать до `stable`-артефактов** — gate вторая защита.
- **Не прунить always-on фундамент** (`traefik`/`crowdsec`) —
  это фиксированная база шаблона; `landing` прунится только при сайте
  на корне.
- **Не удалять без каскада.** Каждое `git rm` идёт после показа
  каскада + явного подтверждения через `AskUserQuestion`.
- **Не выполнять cross-repo (форки, заполнение `.env` на VPS) самому** —
  только печатать next-steps: это действия в чужих репо и на сервере.
- **Не `docker volume rm`/`down -v` при прунинге** — не нужно и
  deny-blocked в `.claude/settings.json`; удаляем только файлы
  фрагментов.
- **Не удалять `docs/project/*`-артефакты** — это инфра-доки проекта
  (карта сервисов + cross-cutting + service-doc'и), не scaffolding.
- **Не удалять `docs/project/_templates/`** — система наследуется.
- **Не аккумулировать журнал** в state — forward-only.

## См. также

- `docs/project/README.md` — контракт артефактов + таблица «subtype →
  профиль».
- `.claude/skills/init-project/SKILL.md` — оркестратор, чейнит сюда
  последним шагом.
- `.claude/rules/multi-env.md` — profile-based opt-in, секреты в `.env`.
