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

- Заводить строку для always-on фундамента (traefik/crowdsec/vault-agent/
  otel-agent/cadvisor/node-exporter/landing) — это не «часть продукта».
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
- LE-сертификаты: `acme_email` / `acme_caserver` (значения через `meta`
  KV; в stack — указание «значения через meta next-step»).
- Wildcard или per-host: обычно per-host через HTTP-01 challenge.

**Опции опрашиваются как**:

- `acme_caserver`: 2 опции (`prod` / `staging`).
- Сабдомен на сервис: enum существующих сервисов из карты, для каждого
  — Other (имя сабдомена).
- Сертификаты: 2 опции (`per-host HTTP-01` / `wildcard DNS-01`).

**Что НЕ**:

- Описывать сабдомены, которых нет в карте public-сервисов.
- Хардкодить `acme_email` в `stack.md` — это значение в `meta` KV.
- Класть два разных сервиса на один сабдомен.
- Корневой `${DOMAIN}` не на landing.

**Тест-критерий**:

- ✅ «`DOMAIN=acme.dev`; `api.acme.dev` → backend, `minio.acme.dev` →
  minio Console, `s3.acme.dev` → minio S3, корень → landing;
  `acme_caserver=prod`, `acme_email` через meta».
- ❌ «`DOMAIN` без указания сабдоменов» — public-сервисы есть, а
  схемы нет.
- ❌ «два сервиса на одном сабдомене» — конфликт роутов.

**Порядок копания**:

1. Корневой `DOMAIN` (Other).
2. Перечислить public-сервисы из карты — для каждого сабдомен (Other).
3. `acme_caserver` (enum), `acme_email` (next-step через meta).
4. Anti-patterns.

---

## Edge

**Что фиксируем**:

- Traefik middleware на public-роутах:
  - `crowdsec@file` (дефолт шаблона) — обязательный bouncer;
  - rate-limit (дефолт traefik или кастомный);
  - другие middleware (custom headers, redirect, etc.).
- CrowdSec source-IP whitelist: нужен ли (если CrowdSec central-LAPI на
  корп-стороне) — egress IP **этого** VPS в их whitelist. Это
  corp-handoff.
- Особые роуты (sticky, retry, custom resolver).

**Опции опрашиваются как**:

- Дефолтный middleware: 2 опции «`crowdsec@file` на всех public» /
  «исключения есть» (Other).
- Source-IP whitelist: 2 опции «нужен → /corp-handoff next-step» / «не
  нужен».
- Rate-limit: 2 опции «дефолт» / «кастомный» (Other).

**Что НЕ**:

- Public-роут без `crowdsec@file` — anti-pattern шаблона.
- Описывать сами правила CrowdSec (это `configs/crowdsec/`).
- Описывать рекомендации Traefik «вообще» — фиксируем конкретный
  middleware-набор стека.

**Тест-критерий**:

- ✅ «`crowdsec@file` на всех public-роутах; source-IP whitelist
  нужен — next-step через /corp-handoff (egress IP VPS в whitelist);
  rate-limit дефолтный».
- ✅ «`crowdsec@file` на всех public; whitelist не нужен (no central
  LAPI)».
- ❌ «Public-роут без middleware».
- ❌ «Описание правил CrowdSec» — это в `configs/`, не в stack.

**Порядок копания**:

1. Middleware-набор (enum + Other).
2. Source-IP whitelist (да/нет).
3. Rate-limit / прочее (Other если нужно).
4. Anti-patterns.

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
  достаёт PG через `db.host`/`db.port` из KV (vault-agent рендерит PG_DSN),
  restic — через `backup.repository` из KV; cross-host сеть/TLS — дело
  потребителя. См. `references/multi-host.md`.

**Опции опрашиваются как**:

- Дефолтные/кастомные имена: 2 опции «дефолт `proxy`/`backend-net`» /
  «кастом» (Other → имена).
- Сетевая раскладка: enum по subtype (`backend`, `datastore`, и т.д.).
- Топология: 2 опции «single-host (co-located, дефолт)» / «split (postgres/
  minio на отдельных хостах)». При split — `host` в Service map + KV host/port.

**Что НЕ**:

- Описывать сети, которых нет в `compose/` (или явный rename-план).
- Класть datastore в `proxy` без public-роута — лишняя поверхность.
- Описывать `compose`-внутренности сети (driver, subnet) — это
  `docker-compose.yml`.

**Тест-критерий**:

- ✅ «`acme-proxy` / `acme-backend`; backend в обеих, postgres в
  `acme-backend`, minio в обеих (Console + S3), вспомогательные
  (cadvisor/node-exporter) — `acme-backend`».
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
- `RESTIC_REPOSITORY` URI (через KV `backup.repository`). Restic endpoint:
  managed S3 (дефолт) или **MinIO на отдельном хосте** при split (`HOST_ROLE`
  storage) — URI наводится на storage-хост. См. `references/multi-host.md`.
- Что бэкапится: pg_dumpall (всегда при postgres), volume'ы (minio data,
  vault rendered configs, etc.). При split backup делает pg_dumpall к PG на
  db-хосте по сети — cross-host доступ обеспечивает потребитель.
- Расписание crond (`0 3 * * *` — 03:00 daily).
- Retention: `keep-daily 7 keep-weekly 4 keep-monthly 3` (дефолт
  `containers/backup/backup-now`) или другое.
- `N/A` если в карте нет datastore и нет важных volume'ов.

**Опции опрашиваются как**:

- Движок: enum (`restic` / `pgBackRest` / `N/A`).
- Что бэкапится: multiSelect (`postgres` / `minio-volume` / `vault-rendered`
  / `other` Other).
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

- otel-agent → endpoint (поле `OTEL_EXPORTER_OTLP_ENDPOINT`): корп-default
  (managed `otel.stit.tech:443`) или свой коллектор (self-hosted форк
  corp-infra-template / project-specific). Managed-дефолт в `.env.example`/
  compose, self-hosted переопределяет в `.env`. См. `references/multi-host.md`.
- Resource attributes: `service.namespace=<project>` / `deployment.env`
  / `host.name`.
- KV otel: token + accountID (через `kv/.../otel`, корп-онбординг).
- Host metrics: `cadvisor` + `node-exporter` (always-on фундамент).
- Логи: уходят через otel-agent или local-only.

**Опции опрашиваются как**:

- otel endpoint: 2 опции (`otel.stit.tech` (default корп) / другой
  Other).
- Resource attrs: Other (свободная форма).
- Логи: 2 опции («через otel-agent» / «local-only»).

**Что НЕ**:

- Описывать always-on (`cadvisor`/`node-exporter` есть в фундаменте) —
  фиксируем только их конфигурацию, если она кастомная.
- Захардкодить otel-токен — он в KV `otel`.
- Дублировать `Generates` поля sub-сервисов.

**Тест-критерий**:

- ✅ «`otel.stit.tech`; resource attrs `service.namespace=acme,
  deployment.env=${ENV}`; KV otel (через корп-онбординг); cadvisor +
  node-exporter (дефолт)».
- ❌ «Без resource attrs» — телеметрия безымянная.
- ❌ «Без указания KV otel» — токен теряется.

**Порядок копания**:

1. Endpoint (enum + Other).
2. Resource attrs (Other).
3. KV otel (next-step через корп-онбординг).
4. Логи (enum).
5. Anti-patterns.

---

## Environments

**Что фиксируем**:

- Какие среды у проекта (`dev` / `staging` / `prod` / произвольные слаги).
- Каждая среда = **отдельный VPS** с одним `ENV` в `.env` и своей
  AppRole-парой (канон — `.claude/rules/multi-env.md`).
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
- Хардкодить `VAULT_ROLE_ID`/`SECRET_ID` per env — они в `.env` на VPS.
- Описывать корп-онбординг AppRole/KV — это `multi-env.md` + корп-сторона.

**Тест-критерий**:

- ✅ «`dev` (`dev.acme.dev`, 2GB, профили postgres+backend) и `prod`
  (`acme.dev`, 4GB, postgres+storage+backend) — каждая отдельный VPS».
- ✅ «`N/A` — проект single-env (только prod)».
- ❌ «Перечислены среды без указания, чем отличаются» — пустая карта сред.
- ❌ «Секреты/role_id в Environments» — их место в `.env` на VPS.

**Порядок копания**:

1. Список сред (Other) или `N/A`.
2. Per среда: домен (Other), масштаб, профили (multiSelect).
3. Anti-patterns.

---

## Generates

**Что фиксируем** — контракт для `/de-template`:

- `configs/traefik/dynamic/*` — клиент-специфичные routers/middlewares.
- `DOMAIN` в `.env.example` (либо дефолт).
- crowdsec source-IP next-step (corp-handoff: egress IP в whitelist).
- acme `meta` next-step (`acme_email`/`acme_caserver` через
  `vault kv put kv/projects/<p>/<env>/meta`).
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
  `DOMAIN=acme.dev` в `.env.example`, crowdsec next-step через
  /corp-handoff, acme `meta` next-step (через /request-secret)».
- ❌ «`Generates` пуст».
- ❌ «`COMPOSE_PROFILES=postgres,storage,backend` в stack».

**Порядок копания**:

1. traefik dynamic (если есть кастомизация).
2. `DOMAIN` default.
3. crowdsec next-step (если whitelist нужен).
4. acme next-step.
5. Anti-patterns.

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
| acme значения хардкодом | Domains | «через `meta` KV — да?» |

## Глобальный Тест-критерий kind=stack

Через `AskUserQuestion` 1 раунд, 2 опции:

- ✅ «Этот файл описывает инфру VPS целиком: карту сервисов, домены, edge,
  сети, бэкап, телеметрию, среды, контракт для `/de-template` — карта
  сервисов живёт здесь, но `COMPOSE_PROFILES` явным списком не дублируется;
  отдельные сервисы детально не расписаны (это service-doc)».
- ❌ «Это часть описания (некоторые секции `<...>`), или детально
  пересекается с service-doc'ами, или содержит `COMPOSE_PROFILES` списком».

При ❌ — выйти в C-режим по конкретной дыре. При ✅ — пункт 5
чек-листа `draft-stable.md` пройден.
