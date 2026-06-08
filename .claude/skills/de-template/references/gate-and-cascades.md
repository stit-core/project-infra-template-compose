# Gate и каскады прунинга

de-template — однократный движок, который меняет структуру репо. Две
группы защит:

- **Gate** — проверки ДО любых правок, гарантируют, что запуск
  правомерен.
- **Каскады** — показ что исчезнет, прежде чем удалить.

Оба механизма прогоняются через `AskUserQuestion`, чтобы оператор мог
остановить процесс.

## Gate

### 1. Не канонический шаблон

Запуск `/de-template` на каноне `…stit-core/project-infra-template-compose`
сносит его шаблонные фрагменты. Защита:

```bash
git remote get-url origin
```

| origin | действие |
|---|---|
| содержит `stit-core/project-infra-template-compose` | СТОП. Через `AskUserQuestion`: «это форк `<client-org>/infra` или throwaway-копия?» (опции «Да, форк» / «Да, throwaway тест-копия» / «Нет, канон» / Other). При «Нет» — выйти, объяснить почему. |
| любое другое (включая `git.stit.tech/<org>/infra`) | OK, идти дальше |
| origin не настроен (`origin: no upstream`) | через `AskUserQuestion`: «нет origin — это локальный throwaway?» (опции «Да» / «Нет, настроить origin сначала») |

### 2. Артефакты stable

`/de-template` читает stable-артефакты `docs/project/`. Если хотя бы
один в `draft` или валидатор красный — движку не из чего выводить.

```bash
make project-check
```

Проверки:

- `make project-check` → зелёный;
- `stack.md → status: stable` (вкл. непустой `Service map`);
- все `services/*.md → status: stable` (для `hosting: here`);
- `Generates` секции непусты в `service` и `stack`.

| результат | действие |
|---|---|
| всё зелёное и stable | OK |
| `stack draft` | СТОП → «оператор → `/stack-deep-dive`» |
| `services/*` draft | СТОП → «оператор → `/service-deep-dive <name>`» |
| `make project-check` красный | СТОП → показать ошибки валидатора, инструкция куда копать |

### 3. Идемпотентность

`/de-template` запускается один раз, но может прерваться. Проверка
«частично применённого» состояния:

| артефакт | признак «уже сделано» |
|---|---|
| A.1 — `COMPOSE_PROFILES` | `.env.example` содержит непустой `COMPOSE_PROFILES=...` строкой |
| A.2 — прунинг compose | в `compose/` нет `<name>.yml` для профилей, которых нет в карте |
| A.3 — прунинг vault-agent | в `configs/vault-agent/agent.hcl.parts/` и `templates/` нет «лишних» имён |
| A.4 — идентичность | `CLAUDE.md` не содержит «Шаблон проектной инфры stit» / `README.md` не «шаблон проектной инфры» |
| A.5 — scaffolding | `docs/getting-started.md` нет; `.claude/plans/roadmap.md` пуст |

Прочитать `state/de-template.md`, если есть — он отражает применённые
шаги.

| результат | действие |
|---|---|
| ничего не сделано | OK → полный путь |
| всё сделано (но `state` ещё есть) | СТОП → «онбординг уже закрыт, удалить state и выйти?» |
| частично | через `AskUserQuestion` показать сводку «применено: A.1, A.2; не применено: A.3, A.4, A.5» → опции «продолжить с A.3» / «прогнать заново всё» / «выход» |

## Каскады прунинга

Перед каждым `git rm` — **показ каскада** через `AskUserQuestion`. Цель:
оператор видит, **что именно** исчезнет и **на что** это влияет, до
необратимого действия.

### Структура каскада

```
Удалю:
- <list файлов>

В репо ссылки на них:
- <Makefile / scripts / configs / docs> — статус (само исключит / не
  ссылается / нужно править)

Подтверждаешь?
[ Да / Нет / Показать diff подробнее ]
```

### Каскад A.2 — прунинг compose

Пример:

```
Удалю compose/minio.yml + compose/backup.yml (профиль storage не в
карте).

Ссылки в репо:
- Makefile (COMPOSE_ARGS) — wildcard $(wildcard compose/*.yml),
  само исключит. Править не надо.
- scripts/deploy.sh — wildcard через docker compose, само исключит.
- docs/reference/architecture.md — упоминает storage как
  «опциональный профиль», не блокирует. Останется forward-only
  описание возможности.
- docs/project/* — нет ссылок (профиль не в карте по построению).

Подтверждаешь?
```

Проверки перед показом:

1. `grep -r "compose/<name>.yml" Makefile scripts/ docs/ .claude/ configs/`
   — все хиты.
2. Если есть hard-coded ссылка не через wildcard — пометить «нужно
   править вручную перед прунингом», предложить через
   `AskUserQuestion` опцию «исправить ссылку сначала» / «всё равно
   удалить» / «выход».

### Каскад A.3 — прунинг vault-agent

Пример:

```
Удалю:
- configs/vault-agent/agent.hcl.parts/storage.hcl
- configs/vault-agent/templates/minio.env.tpl
- configs/vault-agent/templates/backup.env.tpl

Ссылки в репо:
- scripts/render-configs.sh — собирает agent.hcl из parts по имени
  профиля из $COMPOSE_PROFILES. Профиля storage в наборе нет —
  лишних включений не будет.
- compose/minio.yml + compose/backup.yml — уже удалены в A.2.
- docs/ — упоминания общие, не блокируют.

Подтверждаешь?
```

Проверки перед показом:

1. `grep -r "<part-name>" scripts/ configs/ docs/ compose/`
   — все хиты.
2. Если template упомянут в существующем `compose/<name>.yml` через
   `env_file: .runtime/<name>.env` — это **рассинхрон**:
   `compose/<name>.yml` сохранился (профиль в карте есть), а template
   удаляется (?). Через `AskUserQuestion` показать конфликт, остановить.

### Каскад A.5 — strip scaffolding

Особый случай: `docs/getting-started.md` и `.claude/plans/roadmap.md`
— документация / план. Каскад минимален, но всё равно через
`AskUserQuestion`:

```
Удалю docs/getting-started.md ([META]-шаблон) и обнулю
.claude/plans/roadmap.md (reset к fork-start).

Ссылки в репо:
- README.md ссылается на docs/getting-started.md в секции
  «Развёртывание» — заменю на «см. stack.md / docs/project/ / <org>/docs».
- CLAUDE.md ссылается на docs/getting-started.md в «Корп-контракт» —
  заменю на «см. corp-handoff и init-project».

Подтверждаешь?
```

После «Да» — Edit ссылок до удаления файлов.

## Обработка «Нет» в каскадах

Если оператор отвечает «Нет» — НЕ удалять. Записать в
`state/de-template.md § Открытые вопросы`:

```markdown
## Открытые вопросы
- A.2 заблокирован оператором: уточнить судьбу `compose/minio.yml` —
  возможно вернуть `datastore` minio в карту. (**blocker**)
```

И **выйти** из текущего прохода. Возобновление — через
`/de-template phase=a2` после устранения причины.

## Обработка прерывания

Если процесс прервался посередине (ctrl-c, /clear, ошибка):

1. При следующем `/de-template` — Gate.3 (Идемпотентность) детектирует
   частичное состояние из `state/de-template.md`.
2. Через `AskUserQuestion` — продолжить с не-сделанной фазы.

state на полупустом репо — **не теряется** при `/clear` (он в
`.claude/skills/de-template/state/`, переживает /clear).

## После Verify

state-файл удаляется. Если есть остающиеся `**blocker**`-вопросы (что-то
не закрыли) — не удалять, оставить до решения.
