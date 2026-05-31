# Три режима ведения сеанса — stack-deep-dive

`stack-deep-dive` поддерживает три сценария входа. stack — singleton,
поэтому режим A применяется один раз (создание), дальше — почти всегда
C по секциям. B — реже, для разбора сырья (описание инфры прозой).

## A. Новый stack

**Сигнал**: `docs/project/stack.md` не существует или весь — placeholder
`<...>` без заполненных строк.

### Шаги

1. Прочитать `docs/project/README.md`, `field-checklists.md`,
   `vision.md § Service map`.
2. `cp docs/project/_templates/stack.md docs/project/stack.md` через
   Read+Write. Заполнить frontmatter (id=project.stack / kind=stack /
   name=stack / status=draft).
3. Зайти на волны inside-out по 6 секциям (фундамент → производное):
   - **Domains** (фундамент: корневой `DOMAIN` и сабдомены) →
   - **Edge** (middleware, source-IP, rate-limit) →
   - **Networks** (имена `proxy`/`backend-net`) →
   - **Backup** (restic-репо, расписание, retention; `N/A` если нет
     storage в карте) →
   - **Observability** (otel endpoint, resource attrs) →
   - **Generates** (контракт для `/de-template`).
4. Для каждой секции — раунд 3–5 `AskUserQuestion` (≤4 за tool-call)
   по `field-checklists.md § <секция>`. После ответов **сразу** Edit'ом
   писать в md — не копить «запишу в конце».
5. По мере заполнения — если поле требует ссылку на ещё не
   существующую сущность, отработать stub (см. SKILL.md): отметить
   open-question в state, продолжить.
6. После всех секций — раунд `AskUserQuestion` по тест-критерию
   (см. `field-checklists.md § Глобальный Тест-критерий kind=stack`):
   ✅/❌ варианты как опции.
7. Применить чек-лист `draft-stable.md`. Если все 7 пунктов ✅ —
   предложить повышение в stable.
8. Записать `state/stack.md`, если есть открытые вопросы.

### Пример раунда (Edge, после Domains)

Корневой `DOMAIN` известен. Public-сервисы из карты: backend под `api.`,
minio Console под `minio.`. Скилл предлагает четыре вопроса разом:

- **crowdsec middleware** — две опции: «`crowdsec@file` на всех public
  роутах (дефолт шаблона)» / «исключения есть» (Other → какие).
- **source-IP whitelist** — две опции: «нужен — `Generates` next-step
  через /corp-handoff» / «не нужен (нет CrowdSec central-LAPI)».
- **rate-limit** — две опции: «дефолт traefik» / «кастомный
  middleware» (Other → подробнее).
- **acme провайдер** — две опции: «LE prod (acme_caserver=prod)» /
  «LE staging (тестовый)». Подсказка: «значение пойдёт в `meta` KV».

## B. Сырьё

**Сигнал**: args = свободный текст / описание инфры (например, «у нас
два VPS, dev и prod, dev пишет в `dev-restic`, prod в `prod-restic`,
oбa под `*.acme.dev`, public только backend и minio Console»).

### Шаги

1. Прочитать материал внимательно. Прочитать `vision.md § Service map`
   и `services/*.md` — что уже есть.
2. Разнести материал по 6 секциям. Фильтр — секции `Что НЕ` из
   `field-checklists.md`:
   - не относить к stack описание конкретного сервиса (это service-doc);
   - не относить always-on фундамент (траefik «есть» — не stack-факт;
     stack — какой middleware на нём);
   - не выдумывать секции, которых в материале нет.
3. Через чат показать план:
   ```
   Из материала разнесу:
   - Domains: DOMAIN=acme.dev; api.acme.dev, minio.acme.dev;
   - Edge: crowdsec@file (дефолт), source-IP — TBD;
   - Networks: дефолтные proxy/backend-net;
   - Backup: restic репо `s3://restic.acme.dev/<env>`, расписание TBD;
   - Observability: дефолтный otel.stit.tech (KV otel из корп-онбординга);
   - Generates: traefik dynamic для api/minio, DOMAIN в .env.example.
   ```
4. Раунд `AskUserQuestion` — подтвердить разнос / попросить корректировку
   через Other.
5. По подтверждению — `cp _templates/stack.md stack.md` (если нет) и
   заполнить секции стартовыми строками. Незаполненное — пометить
   open-question в `state/stack.md`.
6. Через `AskUserQuestion` — выбрать, какую секцию углубить первой.
7. Перейти в режим C по секциям. Повторить.

### Что НЕ делать в режиме B

- Не объявлять извлечённое «зафиксированным». Это кандидаты до
  подтверждения архитектора.
- Не угадывать retention / расписание / resource attrs — только то, что
  прямо в материале.
- Не повышать stable в B-режиме.

## C. Углубление секции

**Сигнал**: args = `<section>` (`domains`/`edge`/`networks`/`backup`/
`observability`/`generates`), либо выбор из сводки.

### Шаги

1. Прочитать `stack.md`.
2. Прочитать `state/stack.md`, если есть.
3. Прочитать соседей по теме:
   - **domains** → `vision § Service map` (какие сервисы public) +
     `services/*.md § Route` (какие сабдомены упомянуты).
   - **edge** → `compose/traefik.yml`, `compose/crowdsec.yml`,
     `configs/crowdsec/whitelists.yaml` (живой образец).
   - **networks** → `docker-compose.yml` + `compose/*.yml` (какие сети
     реально есть).
   - **backup** → `compose/backup.yml` (если уже есть),
     `containers/backup/` (cron + restic).
   - **observability** → `compose/otel-agent.yml`,
     `configs/otel-agent/`.
   - **generates** → `configs/traefik/dynamic/`, `.env.example`,
     `configs/crowdsec/whitelists.yaml`.
4. Применить `field-checklists.md § <секция>` к строкам. Найти:
   - пустые обязательные поля (placeholder `<...>`);
   - подозрения по anti-patterns (Backup без retention; public-сабдомен
     без middleware где-то в проекте; Networks без явного имени);
   - расхождения с картой/service-doc'ами.
5. Раунд `AskUserQuestion` (до 4 вопросов) — точечно по найденному:
   - дыры — заполняем через Other;
   - anti-pattern-подозрения — опции «да, anti-pattern» / «нет, вот
     почему» (Other);
   - битые ссылки — опции «исправить на <варианты>» / «оставить
     open-question» / «выкинуть упоминание».
6. Применить ответы: правка секции, обновление state-заметки.
7. После раунда — повторно прогнать чек-лист `draft-stable.md`.
   Если все 7 ✅ — предложить повышение в stable.
8. Если осталась дыра — следующий раунд.

### Когда переходить от C к завершению

- Все 7 пунктов чек-листа ✅ → предложить stable, по подтверждению
  поменять status.
- Остался `**blocker**`-вопрос, на который архитектор ответить не может
  → зафиксировать в state, оставить `status: draft`, выйти из секции;
  предложить другую или сводку.

## Стиль вопросов: правила

### Когда давать опции

| ситуация | формат |
|---|---|
| enum-выбор (`backup-engine`: restic / pgBackRest / `N/A`) | по опции на значение enum |
| anti-pattern из `Что stack НЕ` | две опции: «соответствует anti-pattern» / «нет» (Other) |
| тест-критерий из `field-checklists` | опции из примеров ✅/❌ |
| выбор существующего соседа (сабдомен из карты, сеть из compose) | по опции на каждый существующий + «нужен новый» (Other) |
| структурный выбор (`Backup: есть / N/A`, `source-IP whitelist: нужен / нет`) | две опции |

### Когда не давать опции, только Other

| поле | почему |
|---|---|
| корневой `DOMAIN` | значение проекта — архитектор называет |
| конкретный сабдомен (`api.<...>`, `minio.<...>`) | стратегия именования проекта |
| `RESTIC_REPOSITORY` URI | конкретный bucket — архитектор называет |
| retention политика (`keep-daily 7 keep-weekly 4 …`) | бизнес-решение |
| otel resource attrs | контекст проекта |
| имена кастомных сетей | стратегия conflict-free |

### Чего не делать

- Не предлагать «образцы» вроде «может, retention 30 дней?» — это
  выдумывание операционной политики.
- Не упоминать «дефолтные» значения как опции (они подсказка в Other).
- Не задавать больше 4 вопросов в одном `AskUserQuestion`.
- Не закрывать сессию без чек-листа `draft-stable.md`.
- Не править service-doc'и из stack-сессии — это open-question для
  оператора (он зайдёт в `/service-deep-dive`).
