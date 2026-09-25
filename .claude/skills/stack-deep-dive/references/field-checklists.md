# Чек-листы секций stack.md

`docs/project/stack.md` несёт 8 обязательных H2: Service map / Domains /
Edge / Networks / Backup / Observability / Environments / Generates. По
разделу на каждую секцию:

- **Что фиксируем** — поля.
- **Опции опрашиваются как** — enum / anti-pattern / Other.
- **Что НЕ** — anti-patterns.
- **Тест-критерий** — ✅/❌ образцы.
- **Порядок копания**.

Полный канон — `docs/project/README.md` и
`docs/reference/architecture.md`. Здесь — выжимка для скилла.

---

## Service map

**Что фиксируем** — авторитетный инвентарь частей продукта на стороне
инфры (одна строка = одна часть):

- `name` — слаг сервиса (`backend`, `db`, `storage`, `web`).
- `subtype` — `backend` / `frontend` / `datastore` / `infra`.
- `hosting` — `here` (контейнер в этом репо) / `external` (свой репо/CDN).
- `repo / source` — откуда (`<org>/backend`, «postgres в этом репо», CDN).
- `назначение` — одна фраза.
- `host` — **опционально, только при multi-host split**: на каком хосте живёт
  `hosting: here` строка (`HOST_ROLE`-роль `edge`/`db`/`storage`). Single-host
  (дефолт) — поле опускается (всё на одном VPS). См. `references/multi-host.md`.

Карта — **драйвер `COMPOSE_PROFILES`** (`/de-template` выводит профили из
неё: datastore→postgres/storage, backend→backend). Сверяется с
продуктовыми surfaces из `<org>/strategy` (cross-repo): public-surface обычно
= `frontend`/`backend`-строка; datastore/infra surface не имеют.

**Опции опрашиваются как**:

- `subtype`: enum (4 значения).
- `hosting`: 2 опции (`here` / `external`).
- name / repo / назначение: Other (значения проекта).

**Что НЕ**:

- Заводить строку для always-on фундамента (traefik/crowdsec/
  landing) — это не «часть продукта».
- Авторить здесь продуктовые surfaces — они в `<org>/strategy`, читаются
  cross-repo (карта — про инфра-инвентарь, не про UX-поверхности).
- `hosting: here` строка без последующего `services/<name>.md`.

**Тест-критерий**:

- ✅ «`backend` (backend/here/`<org>/backend`/API), `db` (datastore/here/
  postgres/Postgres 17), `storage` (datastore/here/minio/S3), `web`
  (frontend/external/CDN/SPA) — из карты выводятся профили backend,
  postgres, storage».
- ❌ «traefik строкой в карте» — это фундамент, не часть продукта.
- ❌ «`hosting: here` без service-doc» — нарушен инвариант зеркала.

**Порядок копания**:

1. Прочитать surfaces из `<org>/strategy` (cross-repo) — кандидаты public-частей.
2. Per часть продукта — `name`/`subtype` (enum)/`hosting` (2 опции)/repo/
   назначение (Other).
3. Каждой `hosting: here` строке — напомнить про `services/<name>.md`.
4. Anti-patterns.

---

## Domains

**Что фиксируем**:

- Корневой `DOMAIN` (например, `acme.dev`).
- Список сабдоменов: какой сервис → какой сабдомен (`backend → api.`,
  `minio → minio.`, `minio-s3 → s3.`, landing → корень).
- LE-сертификаты: `ACME_EMAIL` / `ACME_CASERVER` — значения живут в `.env`
  на VPS; в stack — указание «ACME next-step».
- Wildcard или per-host: обычно per-host через HTTP-01 challenge.

**Опции опрашиваются как**:

- `ACME_CASERVER`: 2 опции (`prod` / `staging`).
- Сабдомен на сервис: enum существующих сервисов из карты, для каждого
  — Other (имя сабдомена).
- Сертификаты: 2 опции (`per-host HTTP-01` / `wildcard DNS-01`).

**Что НЕ**:

- Описывать сабдомены, которых нет в карте public-сервисов.
- Хардкодить `ACME_EMAIL` в `stack.md` — это значение `.env` на VPS.
- Класть два разных сервиса на один сабдомен.
- Корневой `${DOMAIN}` не на landing.

**Тест-критерий**:

- ✅ «`DOMAIN=acme.dev`; `api.acme.dev` → backend, `minio.acme.dev` →
  minio Console, `s3.acme.dev` → minio S3, корень → landing;
  `ACME_CASERVER` — prod, `ACME_EMAIL` — next-step в `.env`».
- ❌ «`DOMAIN` без указания сабдоменов» — public-сервисы есть, а
  схемы нет.
- ❌ «два сервиса на одном сабдомене» — конфликт роутов.

**Порядок копания**:

1. Корневой `DOMAIN` (Other).
2. Перечислить public-сервисы из карты — для каждого сабдомен (Other).
3. `ACME_CASERVER` (enum), `ACME_EMAIL` (next-step: `.env` на VPS).
4. Anti-patterns.

---

## Edge

**Что фиксируем**:

- Traefik middleware на public-роутах (набор — `configs/traefik/dynamic/middlewares.yml.tpl`):
  - `crowdsec@file` (дефолт шаблона) — обязательный bouncer;
  - `secure-headers@file` — на HTTP-роутах сервисов (backend, landing);
  - rate-limit (дефолт `rate-limit@file` или кастомный);
  - другие middleware (custom headers, redirect, etc.).
- Особые роуты (sticky, retry, custom resolver).

**Опции опрашиваются как**:

- Дефолтный middleware: 2 опции «`crowdsec@file` на всех public» /
  «исключения есть» (Other).
- Rate-limit: 2 опции «дефолт» / «кастомный» (Other).

**Что НЕ**:

- Public-роут без `crowdsec@file` — anti-pattern шаблона.
- Описывать сами правила CrowdSec (это `configs/crowdsec/`).
- Описывать рекомендации Traefik «вообще» — фиксируем конкретный
  middleware-набор стека.

**Тест-критерий**:

- ✅ «`crowdsec@file` на всех public-роутах, `secure-headers@file` на
  backend и landing; rate-limit дефолтный».
- ✅ «`crowdsec@file` на всех public; для `api.` кастомный rate-limit
  (отдельный middleware в `configs/traefik/dynamic/`)».
- ❌ «Public-роут без middleware».
- ❌ «Описание правил CrowdSec» — это в `configs/`, не в stack.

**Порядок копания**:

1. Middleware-набор (enum + Other).
2. Rate-limit / прочее (Other если нужно).
3. Anti-patterns.

---

## Networks

**Что фиксируем**:

- Дефолтные `proxy` (наружу через traefik) / `backend-net` (internal).
- Кастомные имена для conflict-free на shared VPS
  (`<project>-proxy` / `<project>-backend`).
- Кто в какой сети — перечислить по subtype (`backend` → обе,
  `datastore postgres` → `backend-net`, `datastore minio` → обе для
  Console, инфра → `proxy`).
- **Топология хостов** (single-host vs split): Postgres / MinIO co-located на
  одном VPS (дефолт) или вынесены на отдельные хосты (`HOST_ROLE` db/storage).
  При split docker service-name DNS между хостами не работает — backend
  достаёт PG через `PG_HOST`/`PG_PORT` из `.env`, restic — через
  `RESTIC_REPOSITORY`; cross-host сеть/TLS — дело потребителя.
  См. `references/multi-host.md`.

**Опции опрашиваются как**:

- Дефолтные/кастомные имена: 2 опции «дефолт `proxy`/`backend-net`» /
  «кастом» (Other → имена).
- Сетевая раскладка: enum по subtype (`backend`, `datastore`, и т.д.).
- Топология: 2 опции «single-host (co-located, дефолт)» / «split (postgres/
  minio на отдельных хостах)». При split — `host` в Service map + `PG_HOST`/`PG_PORT` в `.env`.

**Что НЕ**:

- Описывать сети, которых нет в `compose/` (или явный rename-план).
- Класть datastore в `proxy` без public-роута — лишняя поверхность.
- Описывать `compose`-внутренности сети (driver, subnet) — это
  `docker-compose.yml`.

**Тест-критерий**:

- ✅ «`acme-proxy` / `acme-backend`; backend в обеих, postgres в
  `acme-backend`, minio в обеих (Console + S3)».
- ❌ «Без явных имён на shared VPS» — конфликт.
- ❌ «postgres в `proxy`» — лишняя поверхность.

**Порядок копания**:

1. Дефолтные или кастомные имена.
2. Раскладка по subtype (enum + multiSelect).
3. Anti-patterns.

---

## Backup

**Что фиксируем**:

- Backup-движок: restic (дефолт шаблона) / pgBackRest / `N/A`.
- `RESTIC_REPOSITORY` URI (в `.env`; local-default нет). Restic endpoint:
  внешний S3 (рекомендуемый) или **MinIO на отдельном хосте** при split (`HOST_ROLE`
  storage) — URI наводится на storage-хост. См. `references/multi-host.md`.
- Что бэкапится: pg_dumpall (всегда при postgres), volume'ы (minio data,
  etc.). При split backup делает pg_dumpall к PG на db-хосте по сети —
  cross-host доступ обеспечивает потребитель.
- Расписание crond (`0 3 * * *` — 03:00 daily).
- Retention: `keep-daily 7 keep-weekly 4 keep-monthly 3` (дефолт
  `containers/backup/backup-now`) или другое.
- `N/A` если в карте нет datastore и нет важных volume'ов.

**Опции опрашиваются как**:

- Движок: enum (`restic` / `pgBackRest` / `N/A`).
- Что бэкапится: multiSelect (`postgres` / `minio-volume` / `other` Other).
- Расписание: 4 опции (`daily 03:00` / `daily 02:00` / `every 6h` /
  Other).
- Retention: Other (бизнес-решение).

**Что НЕ**:

- `Backup: N/A`, если в карте есть datastore — рассинхрон.
- Backup без явного recipient (куда бэкапить).
- Описывать restic-внутренности (cron-script внутри контейнера) — это
  `containers/backup/`.

**Тест-критерий**:

- ✅ «restic → `s3:…/acme/dev`; pg_dumpall + minio-volume; daily 03:00;
  retention 7-4-3».
- ✅ «`N/A` — в карте только backend без datastore».
- ❌ «`N/A`, при этом в карте есть `datastore` postgres».
- ❌ «restic без `RESTIC_REPOSITORY`».

**Порядок копания**:

1. Движок (enum).
2. Если не `N/A`: `RESTIC_REPOSITORY` (Other), что бэкапится
   (multiSelect), расписание (enum + Other), retention (Other).
3. Anti-patterns.

---

## Observability

**Что фиксируем**:

- Метрики: none по дефолту (шаблон метрики не собирает) или свой сервис
  метрик проекта (project-specific строка в карте).
- Логи: local-only (`docker logs`) или свой стек проекта.

**Опции опрашиваются как**:

- Метрики: 2 опции («none (дефолт)» / «свой коллектор» Other).
- Логи: 2 опции («local-only» / «свой стек» Other).

**Что НЕ**:

- Дублировать `Generates` поля sub-сервисов.

**Тест-критерий**:

- ✅ «метрик нет (дефолт); логи local-only».
- ✅ «свой сервис метрик (строка в карте) + его экспортёры; логи local-only».
- ❌ «Просто \"есть мониторинг\"» — не сказано кто и что собирает.

**Порядок копания**:

1. Метрики (enum + Other).
2. Логи (enum).
3. Anti-patterns.

---

## Environments

**Что фиксируем**:

- Какие среды у проекта (`dev` / `staging` / `prod` / произвольные слаги).
- Каждая среда = **отдельный VPS** с одним `ENV` и своим `.env`
  (канон — `.claude/rules/multi-env.md`).
- Чем среды отличаются: домен (`dev.acme.dev` vs `acme.dev`), масштаб
  (RAM/CPU VPS), какой набор профилей включён.
- `N/A` — если среда одна (single-env проект).

**Опции опрашиваются как**:

- Список сред: Other (слаги проекта).
- Домен на среду: Other (стратегия именования).
- Профили на среду: multiSelect (`postgres`/`storage`/`backend`).

**Что НЕ**:

- Конвертировать среду in-place — добавление env = bootstrap нового VPS
  (это не stack-факт, а операция; `skill bootstrap-vps`).
- Дублировать значения секретов per env — они в `.env` на VPS.

**Тест-критерий**:

- ✅ «`dev` (`dev.acme.dev`, 2GB, профили postgres+backend) и `prod`
  (`acme.dev`, 4GB, postgres+storage+backend) — каждая отдельный VPS».
- ✅ «`N/A` — проект single-env (только prod)».
- ❌ «Перечислены среды без указания, чем отличаются» — пустая карта сред.
- ❌ «Секреты в Environments» — их место в `.env` на VPS.

**Порядок копания**:

1. Список сред (Other) или `N/A`.
2. Per среда: домен (Other), масштаб, профили (multiSelect).
3. Anti-patterns.

---

## Generates

**Что фиксируем** — контракт для `/de-template`:

- `configs/traefik/dynamic/*` — клиент-специфичные routers/middlewares.
- `DOMAIN` в `.env.example` (либо дефолт).
- ACME next-step (`ACME_EMAIL`/`ACME_CASERVER` в `.env` на VPS).
- Кастомные имена сетей (если не дефолт) — `.env.example`.

**Что НЕ**:

- `COMPOSE_PROFILES` явным списком — выводится из `Service map` (выше в
  этом же файле), не задаётся списком в Generates.
- Always-on (`compose/traefik.yml` etc.) — фундамент, не Generates.
- service-specific traefik labels — они в service-doc `Generates`.

**Опции опрашиваются как** — обычно Other (имена путей и values —
архитектор называет), enum только для да/нет.

**Тест-критерий**:

- ✅ «`configs/traefik/dynamic/middlewares.yml` (rate-limit override),
  `DOMAIN=acme.dev` в `.env.example`, acme next-step: `ACME_*` в `.env` на VPS».
- ❌ «`Generates` пуст».
- ❌ «`COMPOSE_PROFILES=postgres,storage,backend` в stack».

**Порядок копания**:

1. traefik dynamic (если есть кастомизация).
2. `DOMAIN` default.
3. acme next-step.
4. Anti-patterns.

---

## Глобальные Anti-patterns kind=stack

| anti-pattern | где | вопрос |
|---|---|---|
| `Backup: N/A` при datastore в карте | Backup | «в карте есть postgres — точно `N/A`?» |
| Public без `crowdsec@file` где-то в проекте | Edge | «все public роуты через middleware?» |
| Сабдомен не в карте | Domains | «сервис существует или это план?» |
| `hosting: here` строка без service-doc | Service map | «завести `services/<name>.md`?» |
| `COMPOSE_PROFILES` явным списком в Generates | Generates | «выводится из Service map — убрать список?» |
| Always-on в Generates | Generates | «это фундамент шаблона — он не Generates?» |
| Сети не описаны / без имён | Networks | «shared VPS — нужны кастомные имена?» |
| acme значения хардкодом | Domains | «значения — в `.env` на VPS, да?» |

## Глобальный Тест-критерий kind=stack

Через `AskUserQuestion` 1 раунд, 2 опции:

- ✅ «Этот файл описывает инфру VPS целиком: карту сервисов, домены, edge,
  сети, бэкап, логи и метрики, среды, контракт для `/de-template` — карта
  сервисов живёт здесь, но `COMPOSE_PROFILES` явным списком не дублируется;
  отдельные сервисы детально не расписаны (это service-doc)».
- ❌ «Это часть описания (некоторые секции `<...>`), или детально
  пересекается с service-doc'ами, или содержит `COMPOSE_PROFILES` списком».

При ❌ — выйти в C-режим по конкретной дыре. При ✅ — пункт 5
чек-листа `draft-stable.md` пройден.
