# Phase A — детерминированная механика и Phase B

5 шагов Phase A (A.1..A.5), каждый — отдельный reviewable diff. После
A — Phase B (печать cross-repo next-steps).

Каждое удаление чего-либо в A.2/A.3 идёт **после показа каскада** (см.
`gate-and-cascades.md`).

## A.1. Вывести `COMPOSE_PROFILES` из карты сервисов

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

1. Прочитать `vision.md § Service map`.
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
- `vault-agent.yml`
- `otel-agent.yml`
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

## A.3. Прунить vault-agent parts/templates

### Сохраняются всегда

`configs/vault-agent/agent.hcl.parts/`:
- `head.hcl`
- `tail.hcl`

`configs/vault-agent/templates/`:
- `meta.env.tpl`
- `otel.env.tpl`
- `traefik.yml.tpl`

### Per profile — таблица прунинга

| фрагмент | сохранить если |
|---|---|
| `agent.hcl.parts/postgres.hcl` | профиль `postgres` |
| `templates/db.env.tpl` (или `postgres.env.tpl`) | профиль `postgres` |
| `agent.hcl.parts/storage.hcl` | профиль `storage` |
| `templates/minio.env.tpl` | профиль `storage` |
| `templates/backup.env.tpl` | профиль `storage` |
| `agent.hcl.parts/backend.hcl` | профиль `backend` |
| `templates/backend.env.tpl` | профиль `backend` |

### Шаги

1. Из A.1 определить активный набор профилей.
2. Собрать список «к удалению» из parts и templates.
3. Дополнительная проверка: прочитать `scripts/render-configs.sh` (он
   собирает `agent.hcl` из parts под `COMPOSE_PROFILES`) — убедиться,
   что нет хардкода на удаляемое имя.
4. **Показать каскад**:
   ```
   Удалю:
   - configs/vault-agent/agent.hcl.parts/storage.hcl
   - configs/vault-agent/templates/minio.env.tpl
   - configs/vault-agent/templates/backup.env.tpl
   render-configs.sh берёт parts по имени профиля из
   $COMPOSE_PROFILES — лишних включений не будет.
   Подтверждаешь?
   ```
5. По «Да» — `git rm`.
6. Записать в state «A.3 done».

### Anti-patterns

- Удалить `head.hcl`/`tail.hcl` (фундамент).
- Удалить `meta.env.tpl`/`otel.env.tpl` (от корп-онбординга, всегда
  нужны).
- Удалить template без проверки ссылок в `compose/<name>.yml`
  (`env_file: .runtime/<x>.env`).

## A.4. Кастомить идентичность

### Файлы и правки

| файл | что меняется | что НЕ трогать |
|---|---|---|
| `CLAUDE.md` | шапка/стек под имя проекта; убрать «шаблон stit.tech», «копируется в `<client-org>/infra`», секцию «Что менять при копировании» | Карта где-что, rules, корп-контракт, форвард-only |
| `README.md` (корневой) | проектная шапка вместо «шаблон проектной инфры»; убрать «форкни»; короткое описание из vision `Problem` | reference-ссылки |
| `docs/reference/*` | НЕ трогать (общие reference-доки) | всё |
| `docs/contributing.md` | НЕ трогать | всё |

### Шаги

1. Прочитать `vision.md § Problem` (одна-две фразы — основа шапки) и
   `vision.md § Users` (контекст).
2. Прочитать текущий `CLAUDE.md` — найти и заменить шаблонные блоки на
   проектные. Маркеры шаблона:
   - «Шаблон проектной инфры stit.tech»;
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
3. **Оставить** `docs/project/{vision, services/*, stack}.md` — это
   продуктовые доки проекта.
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
   - в карте есть `backend` → tag пушится в `meta.backend_tag`;
   - в `services/*/Secrets` упоминаются KV-kind, которых нет в Vault
     (требуют seed) → `/request-secret`;
   - в `stack/Edge` упомянут source-IP whitelist → `/corp-handoff`;
   - в `stack/Domains` — сабдомены, нужны A-записи под LE-HTTP-01;
   - корп-онбординг не сделан (нет `kv/.../meta`/`kv/.../otel`) →
     `onboard-project.sh`.

### Формат чеклиста в чат

```
## Cross-repo next-steps (де-темплейт завершён)

### 1. Внешние сервисы
- [ ] Форкнуть `<org>/backend` из `go-backend-template`,
      собрать образ `git.stit.tech/<org>/backend:<tag>`.
- [ ] Форкнуть `<org>/frontend` (если есть external).

### 2. Корп-онбординг (если ещё нет)
- [ ] На корп-VPS: `onboard-project.sh --name <p> --envs dev,prod`.

### 3. Seed вторичных KV (через /request-secret)
- [ ] `kv/projects/<p>/<env>/db` (user/password/database) — для
      postgres профиля.
- [ ] `kv/projects/<p>/<env>/minio` (root_user/root_password) —
      для storage профиля.
- [ ] `kv/projects/<p>/<env>/backup` (s3-creds) — для restic.

### 4. Edge (через /corp-handoff)
- [ ] Egress IP VPS в crowdsec-whitelist (получить IP после
      /bootstrap-vps).
- [ ] LE-HTTP-01 A-записи для сабдоменов:
      api.<DOMAIN>, minio.<DOMAIN>, s3.<DOMAIN>.

### 5. Записать tag backend в meta
- [ ] После сборки backend-образа: `vault kv patch
      kv/projects/<p>/<env>/meta backend_tag=<sha>`.
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
