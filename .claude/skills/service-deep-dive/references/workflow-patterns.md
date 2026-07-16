# Три режима ведения сеанса — service-deep-dive

`service-deep-dive` поддерживает три явно различающихся сценария входа.
Скилл выбирает режим по виду args при запуске и далее ведёт сеанс,
комбинируя точечные шаги.

## A. Новая сущность

**Сигнал**: args = `<name>` (нет `docs/project/services/<name>.md`), или
`<name>:<subtype>:<hosting>` (явный subtype/hosting).

### Шаги

1. Прочитать `docs/project/README.md` (контракт), `stack.md § Service
   map` (карта), `field-checklists.md` (выжимка по kind=service).
2. Если subtype/hosting не указаны в args — раунд 1 `AskUserQuestion`:
   - **subtype** — 4 опции enum (`backend` / `frontend` / `datastore` /
     `infra`).
   - **hosting** — 2 опции enum (`here` / `external`). Если выбран
     `external` — СТОП, объяснить: «у external нет service-doc, добавь
     строку в `stack § Service map` и выходи». Через `AskUserQuestion`:
     «Дописать строку в карту? / Уже есть? / Отказаться».
3. Раунд 2 `AskUserQuestion` — идентичность:
   - **container_name** (Other) — обычно равен `<name>`, но иногда нужен
     суффикс (`<name>-app`). Подсказка: «дефолт == name; нужен другой?».
   - **образ vs движок** — две опции: «свой образ
     `git.stit.tech/<org>/<name>:<tag>`» / «public engine (postgres /
     minio / redis / …)». Через Other — тег/версия конкретно.
4. `cp docs/project/_templates/service.md docs/project/services/<name>.md`
   через Read+Write. Заполнить frontmatter (id/kind/subtype/hosting/
   name/status=draft) и пустые H2.
5. Если строки в `stack § Service map` нет — раунд `AskUserQuestion`:
   «Дописать строку (`name` / `subtype` / `hosting` / `repo` /
   `назначение`)?» — заполнить через Other.
6. Зайти на волны inside-out: Hosting → Identity → Secrets → Route →
   Generates. Для каждой секции — раунд 3–5 `AskUserQuestion`
   (≤4 за tool-call) по `field-checklists.md § <секция>`. После
   ответов **сразу** Edit'ом писать в md — не копить «запишу в конце».
7. По мере заполнения — если поле требует ссылку на ещё не существующую
   сущность, отработать **stub** (см. SKILL.md): создать stub-запись,
   записать state-заметку с открытым вопросом, продолжить.
8. После всех секций — раунд `AskUserQuestion` по тест-критерию
   (см. `field-checklists.md § Тест-критерий`): ✅/❌ варианты как опции.
9. Применить чек-лист `draft-stable.md`. Если все 6 пунктов ✅ —
   предложить повышение в stable.
10. Записать `state/services/<name>.md`, если есть открытые
    вопросы / доменные решения.

### Пример раунда (Secrets, после Identity)

Сервис = backend, subtype=backend, hosting=here. Скилл предлагает
четыре вопроса разом:

- **KV-kind** — опции из стандартных KV-kind (`db`/`minio`/`backup`/
  `jwt`/`oidc` — см. `.claude/rules/multi-env.md`) + «нужен новый KV»
  (Other → `/request-secret`-stub).
- **Поля KV** — Other (свободная форма; подсказка: «обычно
  user/password/database для db; root_user/root_password для minio»).
  НЕ предлагать опции — это архитектор называет.
- **vault-agent template** — две опции: «использовать существующий
  `<svc>.env.tpl` из `configs/vault-agent/templates/`» / «нужен новый
  template» (Other → stub + cross-repo next-step «после de-template
  завести template»).
- **secret-anti-pattern check** — две опции: «секреты только через
  vault-agent / env_file» / «есть прямое чтение
  `$VAULT_TOKEN`/`/run/secrets/`» (anti-pattern, обсудить).

## B. Сырьё

**Сигнал**: args = свободный текст (описание продукта / задачи), либо
пользователь приложил скрин чужого compose / README соседнего проекта /
транскрипт интервью.

### Шаги

1. Прочитать материал внимательно. Прочитать `stack.md § Service map`
   и существующие `services/*.md` — что уже есть.
2. Извлечь кандидатов на сервисы. Фильтр — секции `Что НЕ` из
   `field-checklists.md`:
   - не считать сервисом отдельный bin/cron-job, который живёт внутри
     контейнера другого сервиса (это деталь Identity, не сервис);
   - не плодить `infra`-сервисы под always-on (traefik/crowdsec/
     vault-agent/otel-agent/cadvisor/node-exporter — фундамент шаблона);
   - не выдумывать сервисы, которых в материале нет, «потому что обычно
     бывают».
3. Через чат показать план: «Из материала вижу:
   - 3 hosted-сервиса: `<name1>` (backend), `<name2>` (datastore-postgres),
     `<name3>` (datastore-minio);
   - 1 external: `<name4>` (frontend SPA);
   - не уверен про `<name5>` — это сервис или модуль внутри backend?
   Так?»
4. Раунд `AskUserQuestion` — подтвердить план / попросить корректировку
   через Other.
5. По подтверждению — для каждого hosted:
   - дописать строку в `stack § Service map` (если ещё нет);
   - завести stub `services/<name>.md` (frontmatter + пустые H2);
   - создать `state/services/<name>.md` с открытым вопросом «извлечено
     из сырья — уточнить <что>».
6. Для каждого external — только строка в карте + state-заметка для
   cross-repo next-step (форки, источник образа).
7. Через `AskUserQuestion` — выбрать, какой сервис углубить первой.
8. Перейти в режим C на выбранном. Повторить для остальных.

### Что НЕ делать в режиме B

- Не объявлять извлечённое «зафиксированным». Это кандидаты до
  подтверждения архитектора.
- Не угадывать `image:tag`, домены, KV-поля по сырью — только `name` /
  одна-две фразы под Identity max близко к языку оригинала.
- Не выдумывать кандидатов «потому что обычно бывают» (типичный пример:
  «обычно есть redis для кеша» — но в материале redis не упомянут).
- Не повышать stable в B-режиме. Только заведение stub'ов и план
  углубления.

## C. Углубление

**Сигнал**: args = `<name>` существующей записи, либо архитектор выбрал
из сводки.

### Шаги

1. Прочитать `docs/project/services/<name>.md`.
2. Прочитать `state/services/<name>.md`, если есть.
3. Прочитать соседей: `stack § Service map` (как описан в карте),
   `stack.md § Domains` (если public — есть ли сабдомен), компоненты
   инфры рядом (`compose/<name>.yml`, `configs/vault-agent/templates/`,
   `configs/vault-agent/agent.hcl.parts/`) — образец, если уже развёрнут.
4. Применить `field-checklists.md § <секция>` к строкам. Найти:
   - пустые обязательные слоты (placeholder `<...>` считается пустым);
   - подозрения по anti-patterns (`Identity` содержит `:latest`,
     `Route` указывает на корень `${DOMAIN}` без на то причины, `Secrets`
     обходит vault-agent);
   - расхождения с картой (subtype/hosting в frontmatter ≠ карта);
   - битые ссылки (KV-kind, которого нет в templates;
     сабдомен, который не упомянут в stack).
5. Раунд `AskUserQuestion` (до 4 вопросов) — точечно по найденному:
   - дыры — заполняем через Other;
   - anti-pattern-подозрения — опции «да, anti-pattern» / «нет, вот
     почему» (через Other);
   - битые ссылки — опции «исправить на <варианты>» / «оставить
     stub-next-step» / «выкинуть упоминание».
6. Применить ответы: правка строки, обновление state-заметки,
   пересчёт зеркала карты если нужно.
7. После раунда — повторно прогнать чек-лист `draft-stable.md`.
   Если все 6 ✅ — предложить повышение в stable.
8. Если осталась дыра или подозрение — следующий раунд.

### Когда переходить от C к завершению

- Все 6 пунктов чек-листа ✅ → предложить stable, по подтверждению
  поменять status.
- Остался `**blocker**`-вопрос, на который архитектор сейчас ответить не
  может → зафиксировать в state, оставить `status: draft`, выйти из
  углубления этой сущности; предложить другую или сводку.

## Стиль вопросов: правила

### Когда давать опции

| ситуация | формат |
|---|---|
| enum frontmatter (`subtype`, `hosting`) | по опции на каждое значение enum |
| anti-pattern из `Что service НЕ` | две опции: «соответствует anti-pattern» / «нет, вот почему» (Other) |
| тест-критерий из `field-checklists` | опции из примеров ✅/❌, архитектор соотносит свой случай |
| выбор существующего соседа (KV-kind в templates, профиль из карты, существующий compose-образец) | по опции на каждый существующий + «нужен новый» (Other) |
| структурный выбор (`entrypoint: true/false`, `public/internal`) | две опции |
| источник образа (свой `git.stit.tech/<org>/...` vs public engine) | две опции |

### Когда не давать опции, только Other

| поле | почему |
|---|---|
| `name` / `id` | имя — формулировка архитектора |
| `image:<tag>` | конкретный pinned-tag — архитектор называет |
| `container_name` (если не дефолт) | имя — выбор архитектора |
| `healthcheck` команда / path | специфика сервиса |
| KV-поля (user/password/database/...) | контракт сервиса с инфрой |
| `<sub>.${DOMAIN}` | домены — стратегия проекта |
| Generates конкретика (имена parts/templates) | следует из реальных файлов, но называет архитектор |

### Чего не делать

- Не предлагать «образцы» вроде «может быть, healthcheck такой?» — это
  выдумывание домена/архитектуры.
- Не упоминать «правильные» формулировки из README как опции в виде
  готовых текстов значений. Примеры в README — иллюстрация канона.
- Не задавать больше 4 вопросов в одном `AskUserQuestion`. Если нужно
  больше — следующий раунд.
- Не закрывать сессию без чек-листа `draft-stable.md` хотя бы по одной
  правленой сущности.
