# Phase A — детерминированная механика и Phase B

5 шагов Phase A (A.1..A.5), каждый — отдельный reviewable diff. После
A — Phase B (печать cross-repo next-steps).

Каждое удаление чего-либо в A.2/A.3 идёт **после показа каскада** (см.
`gate-and-cascades.md`).

## A.1. Вывести `COMPOSE_PROFILES` из `stack § Service map`

### Маппинг (канон — `docs/project/README.md`)

| service-doc | subtype | hosting | профиль |
|---|---|---|---|
| postgres | `datastore` | `here` | `postgres` |
| minio | `datastore` | `here` | `storage` |
| backend | `backend` | `here` | `backend` |
| landing | `frontend` | `here` | — (always-on) |
| frontend | `frontend` | `external` | — (cross-repo next-step) |
| backend-external | `backend` | `external` | — (cross-repo next-step) |
| `infra` | `infra` | `here` | обычно always-on (см. service-doc) |

### Шаги

1. Прочитать `stack.md § Service map`.
2. Для каждой строки с `hosting: here` → определить профиль по таблице.
3. Собрать множество профилей в детерминированном порядке (алфавит:
   `backend,postgres,storage`).
4. Найти в `.env.example` строку `COMPOSE_PROFILES=...`:
   - если есть и значение совпадает — пропустить (идемпотентность);
   - если есть с другим значением — Edit на новое значение;
   - если нет — Write строки сразу после `# COMPOSE_PROFILES`-комментария.
5. Напомнить в чате:

   ```
   Дефолт записан в .env.example: COMPOSE_PROFILES=<набор>.
   В рантайме на VPS — выставь тот же набор в .env после bootstrap
   (профили активируются только после seed'а их KV).
   ```

### Anti-patterns

- Записать всё подряд (`backend,postgres,storage` всегда) — без оглядки
  на карту. Маппинг определяется картой, не «дефолтом шаблона».
- Записать `latest`-варианты, лишние профили `traefik`/`crowdsec` (это
  always-on, без профиля).

## A.2. Прунить неиспользуемые `compose/*.yml`

### Always-on (никогда не прунятся)

- `traefik.yml`
- `crowdsec.yml`
- `node-exporter.yml`
- `cadvisor.yml`
- `landing.yml`

### Profiled — таблица прунинга

| `compose/<name>.yml` | сохранить если |
|---|---|
| `postgres.yml` | в карте есть `datastore` postgres |
| `minio.yml` | в карте есть `datastore` minio |
| `backup.yml` | в карте есть `datastore` minio (storage профиль) |
| `backend.yml` | в карте есть `backend` с `hosting: here` |

### Шаги

1. Прочитать список `compose/*.yml`.
2. Из карты определить, какие profiled-фрагменты нужны.
3. Собрать список «к удалению»: profiled, которых нет в карте.
4. **Показать каскад** через `AskUserQuestion`:
   ```
   Удалю:
   - compose/minio.yml
   - compose/backup.yml
   В репо нет других ссылок на эти файлы:
     - Makefile глобит compose/*.yml через wildcard — само исключит;
     - scripts/render-configs.sh не упоминает по имени;
     - docs/ — упоминают как «опциональный профиль storage», не
       блокируют.
   Подтверждаешь?
   ```
5. По «Да» — `git rm compose/<name>.yml ...`.
6. Записать в `state/de-template.md § Применённые шаги`: «A.2 done».

### Anti-patterns

- Удалить always-on (`compose/traefik.yml` etc.).
- Удалить файл без проверки ссылок (вдруг в `Makefile` хардкод на
  старый набор).
- Удалить файлы без каскада.

## A.3. Прунить неиспользуемые секции `.env.example`

### Сохраняются всегда

Identity (`PROJECT_NAME`/`ENV`/`DOMAIN`), `ACME_*`,
`CROWDSEC_BOUNCER_API_KEY`, `HOST_ROLE`, `REGISTRY_HOST`.

### Per profile — таблица прунинга

| секция `.env.example` | сохранить если |
|---|---|
| `profile postgres` (`POSTGRES_*`) | профиль `postgres` |
| `profile storage` (`MINIO_*`, `*_S3_*`, `RESTIC_*`, `BACKUP_AWS_*`) | профиль `storage` |
| `profile backend` (`OIDC_*`, `JWT_SECRET`, `BACKEND_TAG`) | профиль `backend` |

### Шаги

1. Из A.1 определить активный набор профилей.
2. Собрать список секций «к удалению».
3. Дополнительная проверка: `grep` по compose/configs — `${VAR}` из
   удаляемых секций не должны остаться (их compose-фрагменты уже
   удалены в A.2).
4. **Показать каскад**:
   ```
   Удалю секции .env.example:
   - profile storage (MINIO_*, *_S3_*, RESTIC_*, BACKUP_AWS_*)
   ${VAR} этих секций в compose/configs не осталось (A.2 удалил
   minio.yml/backup.yml). Подтверждаешь?
   ```
5. По «Да» — Edit.
6. Записать в state «A.3 done». `make validate` § .env coverage
   подтвердит, что не удалено лишнего.

### Anti-patterns

- Удалить identity/ACME (фундамент).
- Удалить секцию, чей `${VAR}` ещё используется в compose/configs
  (`make validate` упадёт).

## A.4. Кастомить идентичность

### Файлы и правки

| файл | что меняется | что НЕ трогать |
|---|---|---|
| `CLAUDE.md` | шапка/стек под имя проекта; убрать «шаблон stit», «копируется в `<client-org>/infra`», секцию «Что менять при копировании» | Карта где-что, rules, корп-контракт, форвард-only |
| `README.md` (корневой) | проектная шапка вместо «шаблон проектной инфры»; убрать «форкни»; короткое описание из продуктового `<org>/strategy/.../vision.md § Problem` (cross-repo) | reference-ссылки |
| `docs/reference/*` | НЕ трогать (общие reference-доки) | всё |
| `docs/contributing.md` | НЕ трогать | всё |

### Шаги

1. Прочитать продуктовый контекст cross-repo из `<org>/strategy`
   (резолв пути — `docs/reference/ecosystem.md`; дефолт `../strategy`):
   `docs/projects/<slug>/vision.md § Problem` (одна-две фразы — основа
   шапки) + `surface.md` (контекст). Sibling-репо нет — спросить имя/
   описание проекта у оператора через `AskUserQuestion`.
2. Прочитать текущий `CLAUDE.md` — найти и заменить шаблонные блоки на
   проектные. Маркеры шаблона:
   - «Шаблон проектной инфры stit»;
   - «Копируется в `<client-org>/infra`»;
   - «Что менять при копировании в `<org>/infra`».
3. Прочитать `README.md` — заменить «шаблон проектной инфры» на
   проектное описание; убрать инструкцию «форкни»; оставить «Где
   живёт» и команды.
4. Дифф через Edit — каждый файл отдельно (reviewable).
5. Записать в state «A.4 done».

### Anti-patterns

- Удалить секцию «Стек» / «Команды» / «Корп-контракт» — это рабочий
  справочник, не шаблонный нарратив.
- Перевести «правила Git» и «Auto-memory» на проектные — они общие.
- Переписать `docs/reference/*` (это общий справочник архитектуры,
  одинаков по форкам).

## A.5. Strip scaffolding

### Действия

1. **Удалить** `docs/getting-started.md` — [META] «как форкнуть
   шаблон»; форку не нужен. `git rm`.
2. **Сбросить** `.claude/plans/roadmap.md` к пустому fork-start:
   - оставить шапку (формат, форвард-only);
   - `## Active` пуст;
   - `## Backlog` пуст;
   - удалить любые секции, унаследованные от шаблона.
3. **Оставить** `docs/project/{services/*, stack}.md` — это инфра-доки
   проекта (карта + cross-cutting). Продуктовые доки — в `<org>/strategy`.
4. **Оставить** `docs/project/_templates/` — система наследуется
   (`/add-service` использует).
5. **Оставить** deep-dive/init-project скилы (`.claude/skills/`) —
   тоже наследуются.

### Шаги

1. Через `AskUserQuestion`: «удалить `docs/getting-started.md` и
   сбросить `.claude/plans/roadmap.md`? Оба относятся к шаблонному
   scaffolding'у». Опции «Да» / «Только getting-started» / «Только
   roadmap» / «Отмена».
2. По «Да»:
   - `git rm docs/getting-started.md`;
   - Edit `.claude/plans/roadmap.md` — обнулить тело.
3. Записать в state «A.5 done».

## Phase B — cross-repo next-steps

Печатать в чат. **НЕ выполнять**.

### Источники накопления

1. `state/journey.md § ## Cross-repo next-steps` (если /init-project
   запускал → передал контекст).
2. State'ы deep-dive скиллов (`state/services/*.md`,
   `state/stack.md` — секция `## Что копать дальше`).
3. Анализ артефактов `de-template`-ом:
   - в карте есть `hosting: external` → форкнуть соответствующий
     `<org>/<repo>`;
   - в карте есть `backend` → tag живёт в `.env` (`BACKEND_TAG`), деплой — `make bump`;
   - в `services/*/Secrets` упоминаются переменные, не заполненные в
     `.env` на VPS → `/request-secret`;
   - в `stack/Edge` упомянут source-IP whitelist → `/corp-handoff`;
   - в `stack/Domains` — сабдомены, нужны A-записи под LE-HTTP-01.

### Формат чеклиста в чат

```
## Cross-repo next-steps (де-темплейт завершён)

### 1. Внешние сервисы
- [ ] Форкнуть `<org>/backend` из `go-backend-template`,
      собрать образ `git.stit.tech/<org>/backend:<tag>`.
- [ ] Форкнуть `<org>/frontend` (если есть external).

### 2. Секреты профилей в .env на VPS (через /request-secret)
- [ ] `POSTGRES_*` — для postgres профиля.
- [ ] `MINIO_*` / `*_S3_*` / `RESTIC_*` / `BACKUP_AWS_*` — для
      storage профиля.
- [ ] `OIDC_*` / `JWT_SECRET` — для backend профиля.

### 3. Edge (через /corp-handoff)
- [ ] Egress IP VPS в crowdsec-whitelist (получить IP после
      /bootstrap-vps).
- [ ] LE-HTTP-01 A-записи для сабдоменов:
      api.<DOMAIN>, minio.<DOMAIN>, s3.<DOMAIN>.

### 4. Выставить tag backend в .env
- [ ] После сборки backend-образа: `make bump SVC=backend TAG=<sha>`
      (правит `BACKEND_TAG` в `.env` на VPS + force-recreate).
```

### После печати

- Записать в `state/de-template.md § Применённые шаги`: «phase-b done».
- Перейти к Verify.

## После Verify

1. `make validate` зелёный.
2. `make check` зелёный.
3. Удалить `state/de-template.md` (онбординг закрыт).
4. Сообщить оператору: онбординг закрыт; следующий шаг —
   `/bootstrap-vps`.
