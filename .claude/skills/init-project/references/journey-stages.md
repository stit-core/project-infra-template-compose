# Этапы онбординга — детальные триггеры и выходы

5 этапов. Для каждого — **вход** (что должно быть), **что делает** (на
уровне оркестратора), **выход** (признак done), **что в state**.

Скилл сам не интервьюирует и не проектирует; он подсказывает оператору
правильный slash-command и проверяет gate.

## Этап 1. Vision + карта сервисов

### Вход

- Pre-flight пройден (форк, git-хуки, не канонический шаблон).
- `docs/project/vision.md` отсутствует ИЛИ существует и `status: draft`.

### Что делает

1. Если файла нет:
   ```bash
   cp docs/project/_templates/vision.md docs/project/vision.md
   ```
2. Прочитать `vision.md`. Определить, какие H2 заполнены, какие
   placeholder `<...>`.
3. **vision не имеет своего deep-dive скилла** — это singleton с
   относительно простой структурой. Скилл `init-project` ведёт
   заполнение **сам**, через AskUserQuestion.
4. Волны вопросов inside-out (фундамент → производное):
   - **Problem** (Other) — одно-два предложения о задаче клиента.
   - **Users** (Other) — кто пользователи / акторы + нагрузка.
   - **Service map** (волна на каждую строку):
     - перечислить кандидатов через AskUserQuestion (multiSelect:
       backend / frontend / datastore-postgres / datastore-minio /
       другое (Other));
     - для каждого: `subtype` (enum 4 опции), `hosting` (enum: `here` /
       `external`), `repo / source` (Other), `назначение` (Other).
   - **Boundaries** (Other) — что в скоупе, что non-goal.
   - **Environments** (Other) — какие среды, чем отличаются.
5. Edit'ом писать в md по мере ответов (не копить).
6. После заполнения — `make project-check A=docs/project/vision.md`.
7. Если зелёный — раунд AskUserQuestion: «Готов к stable?», по «Да»
   — `status: draft → stable`.

### Выход (done)

- `vision.md status=stable`.
- `make project-check A=docs/project/vision.md` зелёный.
- `Service map` непуст и содержит хотя бы один `hosting: here`.

### state на конец этапа

- Из `## Текущий этап` удалить «1»; записать «2».
- Если `Service map` содержит `hosting: external` — добавить в
  `## Cross-repo next-steps` строки «форкнуть `<repo>` для `<name>`».

---

## Этап 2. Hosted-сервисы → `/service-deep-dive`

### Вход

- Этап 1 done.
- В `Service map` есть хотя бы один сервис с `hosting: here`.

### Что делает

1. Извлечь из `Service map` список `hosting: here` сервисов.
2. Для каждого проверить наличие `docs/project/services/<name>.md`:
   - **файла нет** → инструкция оператору: «`/service-deep-dive <name>`
     заведёт через A-режим».
   - **файл `draft`** → инструкция: «`/service-deep-dive <name>`
     продолжит C-режим».
   - **файл `stable`** → проверить `make project-check`; зелёный →
     пометить done; красный → инструкция «`/service-deep-dive <name>`
     добьёт».
3. Через AskUserQuestion (если несколько кандидатов): «какой сервис
   копать первым?» (опции — кандидаты).
4. **Сам не вызывает** `/service-deep-dive` — сообщает оператору,
   ждёт возврата.
5. После возврата (оператор пишет `/init-project`) — пересчитать
   состояние, идти по следующему сервису.

### Выход (done)

- Все `hosting: here` сервисы из карты → `status=stable`.
- `make project-check` зелёный по `docs/project/services/`.
- Расхождений между картой и `services/*.md` нет (зеркало консистентно).

### state на конец этапа

- Из `## Текущий этап` обновить «3».
- Накопленные cross-repo next-steps от каждого `/service-deep-dive`
  (seed KV, форки) — слить в `## Cross-repo next-steps`.

---

## Этап 3. Инфра-стек → `/stack-deep-dive`

### Вход

- Этап 2 done.

### Что делает

1. Если `docs/project/stack.md` нет:
   ```bash
   cp docs/project/_templates/stack.md docs/project/stack.md
   ```
2. Сообщить оператору: «следующий шаг — `/stack-deep-dive`».
3. После возврата — проверить:
   - `stack.md status=stable`;
   - `make project-check` зелёный по всему `docs/project/`.

### Выход (done)

- `stack.md status=stable`.
- `make project-check` зелёный.
- Расхождений между stack и картой/service-doc'ами нет.

### state на конец этапа

- Из `## Текущий этап` обновить «4».
- Слить cross-repo next-steps из stack-сессии (corp-handoff для
  crowdsec, acme через meta, otel через корп).

---

## Этап 4. Развернуть инфру → `/de-template`

### Вход

- Этапы 1–3 done.
- `make project-check` зелёный по всему `docs/project/`.

### Что делает

1. Прогнать gate ещё раз (`make project-check`) — guard перед чейном.
2. Сообщить оператору: «следующий шаг — `/de-template`».
3. После возврата проверить:
   - `make validate` зелёный (compose-фрагменты после прунинга
     консистентны);
   - origin ≠ канонический шаблон;
   - `.env.example` содержит `COMPOSE_PROFILES=<набор>`;
   - `CLAUDE.md` / `README.md` без «шаблон»-нарратива;
   - `docs/getting-started.md` ([META]) удалён;
   - `.claude/plans/roadmap.md` сброшен.
4. Если что-то не сделано — указать оператору вернуться в
   `/de-template` или зафиксировать `**blocker**` в state.

### Выход (done)

- `make validate` зелёный.
- Шаблонная мета убрана.
- COMPOSE_PROFILES выведен и зафиксирован.

### state на конец этапа

- Из `## Текущий этап` обновить «5».

---

## Этап 5. Финал

### Вход

- Этапы 1–4 done.

### Что делает

1. Прогнать `make check` — зелёный → готово.
2. Перечислить накопленные cross-repo next-steps из state.
3. Сообщить оператору: онбординг закрыт.
4. Подсказать `/bootstrap-vps` (поднять VPS под env).
5. Через AskUserQuestion: «удалить `state/journey.md`?» (опции «Да» /
   «Оставить — допилить cross-repo next-steps»).

### Выход (done)

- `make check` зелёный.
- Cross-repo next-steps переданы оператору (в чате или в state).

### state после финала

- Опционально удалён (или оставлен с next-steps до закрытия).

---

## Когда возвращаться назад

Скилл может **обнаружить** на этапе N, что нужно вернуться на меньший:

| на этапе | признак | возврат |
|---|---|---|
| 2 | в карте нет сервиса, на который ссылается deep-dive | → 1 (допилить карту) |
| 3 | stack ссылается на сабдомен сервиса, который ещё `draft` | → 2 (добить сервис) |
| 4 | de-template обнаружил рассинхрон карты и services | → 1 или 2 |
| 4 | de-template gate красный | → 2 или 3 (по какой артефакт красный) |
| 5 | `make check` красный | → к источнику ошибки |

Возврат фиксируется в `## Текущий этап` state с пометкой причины.

## Gate'ы — компактно

| между | gate |
|---|---|
| 1 → 2 | `vision.md stable` + `make project-check A=docs/project/vision.md` зелёный + `Service map` непуст |
| 2 → 3 | все `hosting: here` сервисы `stable` + `make project-check` зелёный по `services/` |
| 3 → 4 | `stack.md stable` + `make project-check` зелёный по всему `docs/project/` |
| 4 → 5 | `make validate` зелёный + origin ≠ template + scaffolding убран |
| финал | `make check` зелёный |

Скилл **не пропускает** gate'ы. Не пройден → инструкция оператору
вернуться/допилить.
