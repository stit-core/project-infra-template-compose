# Этапы онбординга — детальные триггеры и выходы

5 этапов. Для каждого — **вход** (что должно быть), **что делает** (на
уровне оркестратора), **выход** (признак done), **что в state**.

Скилл сам не интервьюирует и не проектирует; он подсказывает оператору
правильный slash-command и проверяет gate. Продуктовый слой (vision,
surfaces) живёт в соседнем `<org>/strategy` и **читается** cross-repo —
здесь не авторится.

## Этап 1. Продуктовый контекст (cross-repo, read-only)

### Вход

- Pre-flight пройден (форк, git-хуки, не канонический шаблон).

### Что делает

1. Резолвить путь к `<org>/strategy` — `STRATEGY_REPO_PATH` из `.env.local` или
   дефолт `../strategy` (см. `docs/reference/ecosystem.md`).
2. Прочитать `<org>/strategy/docs/projects/<slug>/{vision,surface}.md`:
   - `vision.md § Problem` — задача продукта (контекст для CLAUDE.md-меты
     на этапе 4);
   - `surface.md` — какие поверхности продукта (`web`/`api`/`admin`/…) —
     кандидаты на `frontend`/`backend`-строки карты сервисов.
3. Зафиксировать scope в state (`## Доменные решения` — короткой строкой).
4. **Ничего не авторить** — продуктовые доки read-only отсюда.

### Выход (done)

- Продуктовый контекст прочитан, scope зафиксирован в state.
- ЛИБО (sibling-репо нет) — записан next-step «склонируй/заполни
  `<org>/strategy`», этап не блокирует (стек ведётся по словам оператора).

### state на конец этапа

- В `## Текущий этап` записать «2».
- Если `<org>/strategy` недоступен — next-step «склонировать `<org>/strategy`» в
  `## Cross-repo next-steps`.

---

## Этап 2. Стек + карта сервисов → `/stack-deep-dive`

### Вход

- Этап 1 done (scope понятен или зафиксирован пробел).
- `docs/project/stack.md` отсутствует ИЛИ существует и `status: draft`.

### Что делает

1. Если файла нет:
   ```bash
   cp docs/project/_templates/stack.md docs/project/stack.md
   ```
2. Сообщить оператору: «следующий шаг — `/stack-deep-dive`». Он авторит
   `Service map` (инвентарь — из продуктовых surfaces + ответов оператора),
   cross-cutting (Domains/Edge/Networks/Backup/Observability) и Environments.
3. После возврата — проверить:
   - `stack § Service map` непуст и содержит хотя бы один `hosting: here`;
   - `stack.md status=stable` (допустимы stub-next-step'ы в Domains на
     ещё-не-заведённые service-Routes);
   - `make project-check A=docs/project/stack.md` зелёный.

### Выход (done)

- `stack.md status=stable`, `Service map` непуст.
- `make project-check A=docs/project/stack.md` зелёный.

### state на конец этапа

- В `## Текущий этап` записать «3».
- Если `Service map` содержит `hosting: external` — добавить в
  `## Cross-repo next-steps` строки «форкнуть `<repo>` для `<name>`».
- Слить cross-repo next-steps из stack-сессии (A-записи сабдоменов,
  `ACME_EMAIL`/`ACME_CASERVER` в `.env` на VPS).

---

## Этап 3. Hosted-сервисы → `/service-deep-dive`

### Вход

- Этап 2 done.
- В `stack § Service map` есть хотя бы один сервис с `hosting: here`.

### Что делает

1. Извлечь из `stack § Service map` список `hosting: here` сервисов.
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
5. Если `stack § Domains` несли stub на service-Routes — после заведения
   сервисов вернуть оператора в `/stack-deep-dive` финализировать
   сабдомены.

### Выход (done)

- Все `hosting: here` сервисы из карты → `status=stable`.
- `stack.md` остаётся `stable` (Domains сверены с Routes).
- `make project-check` зелёный по всему `docs/project/`.
- Расхождений между картой и `services/*.md` нет (зеркало консистентно).

### state на конец этапа

- В `## Текущий этап` записать «4».
- Накопленные cross-repo next-steps от каждого `/service-deep-dive`
  (секреты в `.env`, форки) — слить в `## Cross-repo next-steps`.

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
   - в `.claude/plans/` нет планов шаблона, `backlog.md` — `_пусто_`.
4. Если что-то не сделано — указать оператору вернуться в
   `/de-template` или зафиксировать `**blocker**` в state.

### Выход (done)

- `make validate` зелёный.
- Шаблонная мета убрана.
- COMPOSE_PROFILES выведен и зафиксирован.

### state на конец этапа

- В `## Текущий этап` записать «5».

---

## Этап 5. Финал

### Вход

- Этапы 1–4 done.

### Что делает

1. Прогнать `make check` — зелёный → готово.
2. Перечислить накопленные cross-repo next-steps из state; работу в
   сиблингах предложить вести общим планом (`/plan`, фаза на репо).
3. Сообщить оператору: онбординг закрыт.
4. Подсказать следующий шаг: VPS среды ещё нет → `/bootstrap-vps`; уже
   поднят → `make ship`.
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
| 3 | в `stack § Service map` нет сервиса, на который ссылается deep-dive | → 2 (допилить карту через `/stack-deep-dive`) |
| 3 | в карте `hosting: here` строка без service-doc | завести через `/service-deep-dive <name>` |
| 4 | de-template обнаружил рассинхрон карты и services | → 2 или 3 |
| 4 | de-template gate красный | → 2 или 3 (по какой артефакт красный) |
| 5 | `make check` красный | → к источнику ошибки |

Возврат фиксируется в `## Текущий этап` state с пометкой причины.

## Gate'ы — компактно

| между | gate |
|---|---|
| 1 → 2 | продуктовый контекст прочитан (или next-step зафиксирован, если `<org>/strategy` нет) |
| 2 → 3 | `stack.md stable` + `make project-check A=docs/project/stack.md` зелёный + `Service map` непуст |
| 3 → 4 | все `hosting: here` сервисы `stable` + `stack.md stable` + `make project-check` зелёный по всему `docs/project/` |
| 4 → 5 | `make validate` зелёный + origin ≠ template + scaffolding убран |
| финал | `make check` зелёный |

Скилл **не пропускает** gate'ы. Не пройден → инструкция оператору
вернуться/допилить.
