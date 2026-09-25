---
name: stack-deep-dive
description: Углублённая проработка cross-cutting инфры VPS в singleton `docs/project/stack.md` (Service map · Domains · Edge · Networks · Backup · Observability · Environments · Generates). Ведёт сессию через структурированные вопросы (AskUserQuestion), фиксирует рабочее состояние в `state/stack.md`, не выдумывает решения сам. Использовать всегда, когда речь о `docs/project/stack.md`, заполнении 8 артефактных секций, проектировании cross-cutting (домены/edge/сети/бэкап/логи и метрики/среды), владении картой сервисов (Service map — драйвер COMPOSE_PROFILES), переходе `status draft → stable`, или копании связей с продуктовыми surfaces в соседнем `<org>/strategy` и service-doc'ами. Единственная точка входа в `docs/project/stack.md`. Профили `COMPOSE_PROFILES` явным списком не перечисляет — их выводит `/de-template` из `stack § Service map`.
---

# stack-deep-dive

Проектирование cross-cutting одного VPS под проект: доводит singleton
`docs/project/stack.md` до `status: stable`. Где `/service-deep-dive`
отвечает «как хостится конкретный сервис», этот скилл — «что общее для
всего стека» **плюс владение картой сервисов**: `Service map` (инвентарь),
домены и сабдомены, edge (Traefik+CrowdSec), сети, бэкап, логи и метрики,
среды, контракт `Generates` для `/de-template`.

`stack.md` — единственный инфра-singleton. **Продуктовый контекст**
(проблема, пользователи, поверхности) живёт в соседнем `<org>/strategy`
(`business-strategy-template`) и читается **cross-repo** — здесь не дублируется.
Резолв пути к sibling-репо — `docs/reference/ecosystem.md`.

Канон секций — `docs/project/README.md`. Скилл ведёт сеанс через
структурированные вопросы, фиксирует контекст в `state/`, не выдумывает
инфра-выбор.

**`Service map` авторится ЗДЕСЬ** — это авторитетный инвентарь частей
продукта на стороне инфры (строка = `name`/`subtype`/`hosting`/repo/
назначение). **Профили `COMPOSE_PROFILES` явным списком НЕ задаются** —
их выводит `/de-template` из `stack § Service map` (datastore→postgres/
storage, backend→backend). `stack § Generates` несёт только cross-cutting:
traefik dynamic routes, `DOMAIN`, ACME-настройки.

Использовать как **единственную точку входа** в `docs/project/stack.md`:
заведение, углубление, переход `draft → stable`.

## Точки входа

| вызов | поведение |
|---|---|
| `/stack-deep-dive` | сводка состояния + предложение копать самую дырявую секцию (режим A или C автоматически) |
| `/stack-deep-dive <section>` | углубить конкретную секцию (`service-map`/`domains`/`edge`/`networks`/`backup`/`observability`/`environments`/`generates`) |
| `/stack-deep-dive <свободный текст>` | сырьё → разбор → план заполнения (режим B) |

stack — singleton, режим B используется реже (типичный сценарий —
архитектор описывает stack целиком прозой; скилл раскладывает по
секциям).

## Что делать сразу при запуске

1. Прочитать `docs/project/README.md` — освежить контракт kinds.
2. Прочитать **продуктовый контекст cross-repo** из `<org>/strategy`
   (резолв пути — `ecosystem.md`; дефолт `../strategy`): `docs/projects/<slug>/
   surface.md` — какие поверхности продукта public (кандидаты на сабдомены
   и edge-роуты), `vision.md § Problem` — общий контекст. Если sibling-репо
   не склонирован — не падать, отметить next-step «склонируй `<org>/strategy`».
3. Прочитать `docs/project/stack.md`, если есть. Если нет — `cp
   _templates/stack.md stack.md`, заполнить frontmatter. `Service map`
   авторится здесь — сверить с продуктовыми surfaces (public-поверхность
   обычно = `frontend`/`backend`-строка карты), но datastore/infra-строки
   surface не имеют.
4. Если args пустые — сделать сводку (см. ниже) и через
   `AskUserQuestion` предложить выбор какую секцию копать.
5. Если args указывают на секцию — применить маршрут из
   `references/workflow-patterns.md`.

## Сводка состояния (без args)

1. Прочитать `stack.md` целиком.
2. Прочитать `state/stack.md`, если есть.
3. По каждой из 8 секций (Service map/Domains/Edge/Networks/Backup/
   Observability/Environments/Generates) — определить:
   - **заполнена** (есть содержимое, не placeholder `<...>`);
   - **полу-заполнена** (часть строк есть, часть placeholder);
   - **пустая** (только placeholder).
4. Запустить `make project-check A=docs/project/stack.md` — если
   красный, показать ошибки.
5. Вывести компактную карту состояния:

   ```
   ## Состояние stack.md (status=<…>)

   | секция         | заполнено | дыра |
   |---|---|---|
   | Service map    | да  | — |
   | Domains        | да  | — |
   | Edge           | нет | набор middleware на public-роутах не определён |
   | Networks       | да  | — |
   | Backup         | да  | retention TBD |
   | Observability  | да  | — |
   | Environments   | да  | — |
   | Generates      | нет | контракт для de-template пуст |
   ```

6. Через `AskUserQuestion` предложить выбор: какую секцию копать
   первой (опции — секции в порядке приоритета: фундамент → производное,
   с пометкой `(blocker)` если из state).

## Три режима

См. `references/workflow-patterns.md` — детали сценариев и примеры
вопросов.

- **A. Новый stack**. Файла нет или он целиком placeholder.
  `cp _templates/stack.md stack.md`, заполнить frontmatter
  (id/kind=stack/name=stack/status=draft). Волны по 8 секциям
  inside-out: Service map (инвентарь — фундамент) → Domains → Edge →
  Networks → Backup → Observability → Environments → Generates
  (фундамент → производное). Service map сверяется с продуктовыми
  surfaces из `<org>/strategy`.
- **B. Сырьё**. Args = свободный текст / описание инфры. Извлечь
  кандидатов по секциям, показать план, по подтверждению заполнить
  stub'ы и зайти в C-режим по каждой.
- **C. Углубление секции**. Args = `<section>` или выбор из сводки.
  Точечные вопросы по дырам/подозрениям; чек-лист `draft → stable`
  после каждой правки секции.

## Интерактив — через `AskUserQuestion`

**Любое взаимодействие с архитектором — через `AskUserQuestion`**: решения
по инфре принимает архитектор, а структурированный выбор фиксирует их
однозначно. Сводки в чат — только как **преамбула** перед
`AskUserQuestion`-раундом, коротко и по делу.

Принципы:

- Каждый «выбор» — `AskUserQuestion` с опциями (≤4 за tool-call).
- Свободная форма — через **Other**, не в чат.
- «Какую секцию копать?», «Готов к stable?», «Удалить stack.md?» —
  всё `AskUserQuestion`, не chat-prompt.

## Стиль вопросов

См. `references/workflow-patterns.md`.

- **Всегда через `AskUserQuestion`**, до 4 вопросов в одном раунде.
- **Опции** только для:
  - enum (`backup-engine`: restic / pgBackRest / N/A; `traefik
    middleware`: `crowdsec@file` / без / другие);
  - anti-patterns (бинарное «это похоже на X — согласен?»);
  - тест-критерия секции (✅/❌ из `field-checklists.md`);
  - выбора существующего соседа (сабдомен в карте сервисов, существующее
    имя сети из `compose/`).
- **Свободная форма** (через Other) — для **значения**: корневой
  `DOMAIN`, конкретные сабдомены, `RESTIC_REPOSITORY` URI, retention
  политика, имя сети если кастомное.
- Конкретные домены/имена от себя не подсказывай — это решения проекта,
  которые знает только архитектор. Anti-patterns — да, сами значения — нет.

## Память `state/stack.md` — коммитится

Заметка лежит **рядом со скиллом**:

```
.claude/skills/stack-deep-dive/state/stack.md
```

stack — singleton, поэтому один state-файл (без подкаталога `services/`).

State — **коммитбл артефакт**, не приватная память агента:

- В `.gitignore` НЕ попадает; коммитится в репо как часть PR'а вместе
  с `stack.md`.
- Это **shared контекст** команды архитекторов: ревьюится в Pull Request,
  виден всем, не привязан к конкретной сессии Claude.
- Переживает `/clear` именно за счёт коммита.
- **Не содержит секретов** — только имена переменных `.env` и описания
  доменных решений.

См. `references/state-format.md`. Кратко:

- Файл существует, пока есть хоть одна непустая секция.
- Три возможные секции: `## Открытые вопросы` (с опц. `**blocker**`),
  `## Доменные решения`, `## Что копать дальше`.
- Если все три пусты — заметку удалить (`git rm`).
- Forward-only, без истории.

## Зеркало карты с service-doc'ами и продуктом

`Service map` — авторитетный инвентарь, **живёт здесь**. Остальные секции
stack согласуются с ним и с service-doc'ами:

- **Service map ↔ service-doc** (двусторонний инвариант): каждая строка с
  `hosting: here` обязана иметь `services/<name>.md`; каждый service-doc
  обязан иметь строку в карте с тем же `subtype`/`hosting`. При правке
  карты (новая `hosting: here` строка) — напомнить оператору завести
  service-doc через `/service-deep-dive <name>`. external-строки
  service-doc НЕ имеют (только контекст для cross-repo next-step).
- **Service map ↔ продуктовые surfaces** (`<org>/strategy`, cross-repo):
  public-поверхность продукта (`surface.md` type `web`/`api`/`admin`)
  обычно соответствует `frontend`/`backend`-строке карты. datastore/infra
  surface не имеют. Рассинхрон (surface без сервиса или наоборот) — не
  ошибка, но повод уточнить через `AskUserQuestion`.
- **Domains** ↔ public-сервисы (`Route` в service-doc упоминает
  `<sub>.${DOMAIN}` — этот сабдомен обязан быть в `stack § Domains`).
  При правке Domains — пересчитать список сабдоменов из всех
  `services/*.md § Route`.
- **Backup** ↔ карта `datastore`-сервисов. Если в карте нет storage и
  нет postgres-volume — `Backup: N/A`. Если есть — описать restic-репо
  и расписание.
- **Networks** ↔ service-doc'и: какая сеть упомянута в `Identity`
  сервисов; кастомные имена сетей (`<project>-proxy`) — здесь.
- **Топология хостов** (single-host vs split): дефолт — single-host (всё на
  одном VPS). Split (Postgres/MinIO на отдельных хостах, `HOST_ROLE`) спрашивается
  в `§ Networks`, фиксируется в `state/stack.md § Host layout`; эндпоинты — в `.env`
  (`PG_HOST`/`PG_PORT`, `RESTIC_REPOSITORY`), не в карте. Швы и граница (репликация/HA —
  дело потребителя) — `references/multi-host.md`.
- **Generates** ↔ `/de-template`: traefik dynamic routes выводятся из
  service-doc, но `DOMAIN`/ACME — отсюда.

Скилл правит **свою** `Service map`, но **не правит** service-doc'и из
stack-сессии. Если видит рассинхрон (Route сабдомен не в Domains, или
`hosting: here` строка без service-doc) — открытый вопрос в
`state/stack.md` и напоминание оператору в конце.

## Контракт `draft → stable`

См. `references/draft-stable.md`. Чек-лист:

1. Frontmatter валиден: `id == "project.stack"`, `kind == "stack"`,
   `name == "stack"`, `status` ∈ {`draft`,`stable`}.
2. Все 8 H2 (Service map/Domains/Edge/Networks/Backup/Observability/
   Environments/Generates) присутствуют и непусты (placeholder `<...>` не
   считается). `N/A` явной строкой — допустимо (`Backup: N/A`,
   `Environments: N/A` если среда одна).
3. Все ссылки валидны:
   - `Service map` непуста; каждая `hosting: here` строка имеет
     `services/<name>.md` (или stub-next-step в state);
   - сабдомены в `Domains` упомянуты в `Service map` public-сервисов (или
     stub-next-step с записью в state);
   - имена сетей в `Networks` соответствуют тому, что есть в `compose/`
     (или явный rename-план);
   - `Backup: N/A` ↔ в карте нет datastore-сервисов;
   - `Generates` упоминает реальные пути (`configs/traefik/dynamic/*`,
     `.env.example`).
4. `Generates` непуст и содержит хотя бы один из:
   `configs/traefik/dynamic/*`, `DOMAIN` в `.env.example`, ACME next-step
   (`ACME_EMAIL`/`ACME_CASERVER` в `.env` на VPS).
5. Тест-критерий из `field-checklists.md` явно подтверждён архитектором
   (раунд `AskUserQuestion` ✅/❌).
6. В `state/stack.md` нет `**blocker**`-вопросов.
7. `make project-check A=docs/project/stack.md` зелёный.

Если все ✅ — предложить через `AskUserQuestion`: «Готов к stable,
повышаем?». По подтверждению — изменить `status: draft → stable`.
**Скилл не повышает сам.**

Понижение `stable → draft` — только архитектор.

## Stub-цепочки

Если копаемая секция ссылается на ещё несуществующую сущность:

- **Сабдомен не в карте**: открытый вопрос в state «допилить
  service-doc для `<name>`» (не blocker, если сервис ещё проектируется).
- **`Backup` упоминается, но в карте нет datastore-профиля**:
  `**blocker**` — нужно либо `Backup: N/A`, либо завести
  storage-сервис.

После заведения stub продолжаем копание.

## Удаление stack.md

`stack.md` — singleton, удаление = откат проекта к pre-init.
Каскад:

1. Прочитать service-doc'и — что зависит от stack (карта сервисов в
   stack.md, поэтому удаление сносит и инвентарь).
2. Показать каскад: «после удаления stack.md `/de-template` не сможет
   вывести `COMPOSE_PROFILES` (карта сервисов исчезнет), развернуть
   traefik dynamic routes и ACME-настройки — это откат проекта
   к pre-init».
3. Через `AskUserQuestion` подтвердить: «Это точно? Опции: "Да, откат" /
   "Нет, отмена" / "Сбросить к шаблону (`cp _templates/stack.md`)"».
4. По подтверждению — выполнить.
5. Удалить `state/stack.md`.

## Завершение сессии

В конце короткая сводка в чат — что изменено, что осталось — и сразу
`AskUserQuestion` «куда дальше?» с опциями:

- «Копать следующую секцию» (если есть `draft`-секции с дырами);
- «Перейти к `/de-template`» (если stack `stable` и все service-doc'и
  `stable`);
- «Вернуться к `/service-deep-dive <name>`» (если обнаружен рассинхрон
  service ↔ stack);
- «Зафиксировать остановку, выйти»;
- Other — свой следующий шаг.

Накопленные cross-doc/cross-repo next-steps идут **в state**, не в чат.

## Запреты

- Не редактировать stack.md вслепую — всегда сначала `Read`.
- Не выдумывать значения: домены, retention, имена сетей.
- Не дублировать `COMPOSE_PROFILES` явным списком в `stack.md` — их
  выводит `/de-template` из `stack § Service map` (subtype+hosting), не из
  захардкоженного списка.
- Не редактировать продуктовые артефакты в `<org>/strategy` из stack-сессии —
  они read-only отсюда; рассинхрон surface↔карта фикси через
  `AskUserQuestion`/state, а не правкой соседнего репо.
- Не описывать always-on сервисы (traefik/crowdsec/landing) как
  «отдельный сервис» — это фундамент шаблона; в stack описывается
  их конфигурация (middleware, rate-limit), не их «наличие».
- Не оставлять `Generates` пустым.
- Не повышать `draft → stable` без явного подтверждения архитектора и
  зелёного `make project-check`.
- Не понижать `stable → draft` сам.
- Не аккумулировать историю в `state/` — forward-only.
- Не править service-doc'и из stack-сессии — записывай в state как
  open-question, фикси оператор через `/service-deep-dive`.
