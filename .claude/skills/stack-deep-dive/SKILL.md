---
name: stack-deep-dive
description: Углублённая проработка cross-cutting инфры VPS в singleton `docs/project/stack.md` (Domains · Edge · Networks · Backup · Observability · Generates). Ведёт сессию через структурированные вопросы (AskUserQuestion), фиксирует рабочее состояние в `state/stack.md`, не выдумывает решения сам. Использовать всегда, когда речь о `docs/project/stack.md`, заполнении 6 артефактных секций, проектировании cross-cutting (домены/edge/сети/бэкап/телеметрия), переходе `status draft → stable`, или копании связей со `vision § Service map` и service-doc'ами. Также — единственная точка входа в `docs/project/stack.md`. Профили `COMPOSE_PROFILES` НЕ описывает — их выводит `/de-template` из карты сервисов.
---

# stack-deep-dive

Проектирование cross-cutting одного VPS под проект: доводит singleton
`docs/project/stack.md` до `status: stable`. Где `/service-deep-dive`
отвечает «как хостится конкретный сервис», этот скилл — «что общее для
всего стека»: домены и сабдомены, edge (Traefik+CrowdSec), сети, бэкап,
телеметрия, контракт `Generates` для `/de-template`.

Канон секций — `docs/project/README.md`. Скилл ведёт сеанс через
структурированные вопросы, фиксирует контекст в `state/`, не выдумывает
инфра-выбор.

**Профили `COMPOSE_PROFILES` тут НЕ задаются** — их выводит
`/de-template` из vision `Service map` (datastore→postgres/storage,
backend→backend). `stack § Generates` несёт только cross-cutting:
traefik dynamic routes, `DOMAIN`, crowdsec source-IP next-step,
acme-настройки.

Использовать как **единственную точку входа** в `docs/project/stack.md`:
заведение, углубление, переход `draft → stable`.

## Точки входа

| вызов | поведение |
|---|---|
| `/stack-deep-dive` | сводка состояния + предложение копать самую дырявую секцию (режим A или C автоматически) |
| `/stack-deep-dive <section>` | углубить конкретную секцию (`domains`/`edge`/`networks`/`backup`/`observability`/`generates`) |
| `/stack-deep-dive <свободный текст>` | сырьё → разбор → план заполнения (режим B) |

stack — singleton, режим B используется реже (типичный сценарий —
архитектор описывает stack целиком прозой; скилл раскладывает по
секциям).

## Что делать сразу при запуске

1. Прочитать `docs/project/README.md` — освежить контракт kinds.
2. Прочитать `docs/project/vision.md § Service map` — какие сервисы
   public (нужны сабдомены), какой профиль storage (Backup `N/A` или
   нет), есть ли что-то требующее cross-cutting Edge/Networks.
3. Прочитать `docs/project/stack.md`, если есть. Если нет — `cp
   _templates/stack.md stack.md`, заполнить frontmatter.
4. Если args пустые — сделать сводку (см. ниже) и через
   `AskUserQuestion` предложить выбор какую секцию копать.
5. Если args указывают на секцию — применить маршрут из
   `references/workflow-patterns.md`.

## Сводка состояния (без args)

1. Прочитать `stack.md` целиком.
2. Прочитать `state/stack.md`, если есть.
3. По каждой из 6 секций (Domains/Edge/Networks/Backup/Observability/
   Generates) — определить:
   - **заполнена** (есть содержимое, не placeholder `<...>`);
   - **полу-заполнена** (часть строк есть, часть placeholder);
   - **пустая** (только placeholder).
4. Запустить `make project-check A=docs/project/stack.md` — если
   красный, показать ошибки.
5. Вывести компактную карту состояния (≤8 строк):

   ```
   ## Состояние stack.md (status=<…>)

   | секция         | заполнено | дыра |
   |---|---|---|
   | Domains        | да  | — |
   | Edge           | нет | crowdsec source-IP whitelist неопределён |
   | Networks       | да  | — |
   | Backup         | да  | retention TBD |
   | Observability  | да  | — |
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
  (id/kind=stack/name=stack/status=draft). Волны по 6 секциям
  inside-out: Domains → Edge → Networks → Backup → Observability →
  Generates (фундамент → производное).
- **B. Сырьё**. Args = свободный текст / описание инфры. Извлечь
  кандидатов по секциям, показать план, по подтверждению заполнить
  stub'ы и зайти в C-режим по каждой.
- **C. Углубление секции**. Args = `<section>` или выбор из сводки.
  Точечные вопросы по дырам/подозрениям; чек-лист `draft → stable`
  после каждой правки секции.

## Интерактив — норма, plain-чат запрещён

**Любое взаимодействие с архитектором — через `AskUserQuestion`.** Не
«выведи таблицу и жди ответа в свободной форме», не «дай развёрнутый
рассказ и спроси что дальше». Сводки в чат — только как **преамбула**
перед `AskUserQuestion`-раундом.

Принципы:

- Каждый «выбор» — `AskUserQuestion` с опциями (≤4 за tool-call).
- Свободная форма — через **Other**, не в чат.
- «Какую секцию копать?», «Готов к stable?», «Удалить stack.md?» —
  всё `AskUserQuestion`, не chat-prompt.
- Длинные монологи скилла — anti-pattern. Сводки коротко (≤8 строк) и
  сразу `AskUserQuestion`.

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
  политика, имя сети если кастомное, otel resource attrs.
- **Никогда** не подсказывать конкретные домены/имена от себя.
  Anti-patterns — да. Сами значения — нет.

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
- **Не содержит секретов** — только ссылки на KV-пути и описания
  доменных решений.

См. `references/state-format.md`. Кратко:

- Файл существует, пока есть хоть одна непустая секция.
- Три возможные секции: `## Открытые вопросы` (с опц. `**blocker**`),
  `## Доменные решения`, `## Что копать дальше`.
- Если все три пусты — заметку удалить (`git rm`).
- Forward-only, без истории.

## Зеркало с картой и service-doc'ами

`stack.md` cross-cutting, но **читает** карту и service-doc'и:

- **Domains** ↔ public-сервисы (`Route` в service-doc упоминает
  `<sub>.${DOMAIN}` — этот сабдомен обязан быть в `stack § Domains`).
  При правке Domains — пересчитать список сабдоменов из всех
  `services/*.md § Route`.
- **Backup** ↔ карта `datastore`-сервисов. Если в карте нет storage и
  нет postgres-volume — `Backup: N/A`. Если есть — описать restic-репо
  и расписание.
- **Networks** ↔ service-doc'и: какая сеть упомянута в `Identity`
  сервисов; кастомные имена сетей (`<project>-proxy`) — здесь.
- **Generates** ↔ `/de-template`: traefik dynamic routes выводятся из
  service-doc, но `DOMAIN`/acme/crowdsec-whitelist — отсюда.

Скилл сам **не правит** service-doc'и из stack-сессии. Если видит
рассинхрон (Route сабдомен не в Domains, или Domains требует сабдомен
которого нет в карте) — открытый вопрос в `state/stack.md` и
напоминание оператору в конце.

## Контракт `draft → stable`

См. `references/draft-stable.md`. Чек-лист:

1. Frontmatter валиден: `id == "project.stack"`, `kind == "stack"`,
   `name == "stack"`, `status` ∈ {`draft`,`stable`}.
2. Все 6 H2 (Domains/Edge/Networks/Backup/Observability/Generates)
   присутствуют и непусты (placeholder `<...>` не считается). `N/A`
   явной строкой — допустимо (например, `Backup: N/A`).
3. Все ссылки валидны:
   - сабдомены в `Domains` упомянуты в карте public-сервисов (или
     stub-next-step с записью в state);
   - имена сетей в `Networks` соответствуют тому, что есть в `compose/`
     (или явный rename-план);
   - `Backup: N/A` ↔ в карте нет datastore-сервисов;
   - `Generates` упоминает реальные пути (`configs/traefik/dynamic/*`,
     `.env.example`).
4. `Generates` непуст и содержит хотя бы один из:
   `configs/traefik/dynamic/*`, `DOMAIN` в `.env.example`, crowdsec
   source-IP next-step, acme meta next-step.
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
- **crowdsec source-IP whitelist**: это corp-handoff (egress IP VPS
  знает только корп-сторона) — записать как cross-repo next-step в
  state, в `Generates` упомянуть как «next-step через /corp-handoff».

После заведения stub продолжаем копание.

## Удаление stack.md

`stack.md` — singleton, удаление = откат проекта к pre-init.
Каскад:

1. Прочитать service-doc'и + `vision.md` — что зависит от stack.
2. Показать каскад: «после удаления stack.md `/de-template` не сможет
   развернуть traefik dynamic routes, crowdsec whitelist, acme — это
   откат проекта к pre-init».
3. Через `AskUserQuestion` подтвердить: «Это точно? Опции: "Да, откат" /
   "Нет, отмена" / "Сбросить к шаблону (`cp _templates/stack.md`)"».
4. По подтверждению — выполнить.
5. Удалить `state/stack.md`.

## Завершение сессии

В конце короткая сводка в чат (≤10 строк) — что изменено, что осталось
— и сразу `AskUserQuestion` «куда дальше?» с опциями:

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
- Не выдумывать значения: домены, retention, otel resource attrs,
  имена сетей.
- Не дублировать `COMPOSE_PROFILES` целиком в `stack.md` — это вход
  `/de-template` из карты сервисов, не из stack.
- Не описывать always-on сервисы (traefik/crowdsec/vault-agent/
  otel-agent/cadvisor/node-exporter/landing) как «отдельный сервис» —
  это фундамент шаблона; в stack описывается их конфигурация
  (middleware, source-IP, otel endpoint), не их «наличие».
- Не оставлять `Generates` пустым.
- Не повышать `draft → stable` без явного подтверждения архитектора и
  зелёного `make project-check`.
- Не понижать `stable → draft` сам.
- Не аккумулировать историю в `state/` — forward-only.
- Не править service-doc'и из stack-сессии — записывай в state как
  open-question, фикси оператор через `/service-deep-dive`.
