---
name: stack-deep-dive
description: Спроектировать cross-cutting инфры VPS — довести docs/project/stack.md от драфта до status=stable через волны вопросов (Domains→Edge→Networks→Backup→Observability→Generates). Профили COMPOSE_PROFILES НЕ описывает — их выводит de-template из карты сервисов. Секция Generates — вход для de-template (traefik dynamic, DOMAIN, crowdsec source-IP). Активируй когда юзер проектирует инфра-стек, говорит "спроектируем стек", "добьём stack.md", "/stack-deep-dive", или когда init-project дошёл до шага стека. Решения не выдумывай — интервьюируй.
---

# Skill: stack-deep-dive

Проектирование cross-cutting одного VPS под проект: доводит singleton `docs/project/stack.md` до
`status: stable`. Где `service-deep-dive` отвечает «как хостится конкретный сервис», этот скилл —
«что общее для всего стека»: домены и сабдомены, edge (Traefik+CrowdSec), сети, бэкап, телеметрия.

**Профили `COMPOSE_PROFILES` тут НЕ задаются** — их выводит `de-template` из vision `Service map`
(datastore→postgres/storage, backend→backend). `stack.md § Generates` несёт только cross-cutting:
traefik dynamic routes, `DOMAIN`, crowdsec source-IP next-step, acme-настройки.

В онбординг-флоу `/init-project` чейнит сюда после всех `service-deep-dive`, затем — `/de-template`.

## Когда применять

- "Спроектируем инфра-стек" / "Добьём `stack.md`"
- "/stack-deep-dive"
- `/init-project` дошёл до шага стека (все hosted-сервисы спроектированы)
- `stack.md` в `draft` — нужно довести до `stable`

## Когда НЕ применять

- Артефакта ещё нет — сначала `cp docs/project/_templates/stack.md docs/project/stack.md`.
- Уже `stable` — запусти валидатор, не интервьюй заново.
- Правка одной секции (добавился сабдомен) — точечная правка, не deep-dive.

## Шаги

### 1. Сканируй контекст

```bash
make project-check A=docs/project/stack.md
```

Зелёный и `stable` → выходи. Иначе прочитай H2-заголовки, вычисли заполненность по обязательным
секциям (`docs/project/README.md`).

### 2. Покажи карту состояния

Сжато, ≤8 строк, по секции на строку (Domains/Edge/Networks/Backup/Observability/Generates):
`| секция | заполнено | дыра |`.

### 3. Веди волны

Порядок — фундамент → производное (запоминай, не спрашивай):

1. **Domains** — корневой `DOMAIN`, какие сервисы публичны и под какими сабдоменами
   (`api.`/`s3.`/`minio.`), acme_email/caserver (из meta KV).
2. **Edge** — Traefik+CrowdSec: middleware на public-роутах, нужен ли source-IP whitelist (egress
   IP VPS — corp-side), rate-limit.
3. **Networks** — `proxy` (наружу) / `backend-net` (internal), кастомные имена для conflict-free
   на shared VPS, кто в какой сети.
4. **Backup** — restic-репо (`RESTIC_REPOSITORY`), что бэкапится, расписание, retention. Нет
   storage-профиля → `N/A`.
5. **Observability** — otel-agent → `otel.stit.tech`, resource attrs, accountID/token (kv otel),
   cadvisor+node-exporter (always-on).
6. **Generates** — явно: что `de-template` родит/изменит (`configs/traefik/dynamic/*`, `DOMAIN` в
   `.env.example`, crowdsec source-IP next-step, acme meta next-step). `COMPOSE_PROFILES` тут НЕ
   задаётся.

Для текущей секции: 3–5 предметных вопросов через `AskUserQuestion` (≤4 за tool-call). После
ответов **сразу** пиши в md — не копи «запишу в конце».

### 4. Правила вопросов

- **Конкретные, falsifiable.** Плохо: «как с доменами?». Хорошо: «backend под `api.${DOMAIN}` или
  на корне `${DOMAIN}`? minio Console под `minio.${DOMAIN}` нужен публично?».
- **Bounded / multiSelect** где уместно.
- **Не выдумывай.** «Не знаю» → `TBD`.
- **Опирайся на инфру.** `compose/traefik.yml`, `configs/traefik/`, `configs/crowdsec/`,
  `compose/backup.yml`, `.claude/rules/multi-env.md` — живой образец.

### 5. Промоушн status

```bash
make project-check A=docs/project/stack.md
```

Зелёный → `status: draft → stable`, прогони валидатор ещё раз. Красный → вернись к секциям.

### 6. Финал

Сводка: `stack.md` stable. Следующий шаг:
- **Онбординг** (из `/init-project`): стек спроектирован → `/de-template` развернёт инфру по
  карте сервисов + `stack § Generates`.
- **Отдельно**: артефакт — актуальный source of truth инфры; правь при изменениях.

## Anti-patterns

- ❌ >4 вопросов одним AskUserQuestion.
- ❌ Копить ответы в RAM, писать в конце — теряется при /clear.
- ❌ Прописывать `COMPOSE_PROFILES` в `stack.md` — профили выводит de-template из карты сервисов.
- ❌ Оставить `Generates` пустым.
- ❌ Промоутить `stable` при красном валидаторе.

## Что делает валидатор (для справки)

- Frontmatter: `id`==`project.stack`, `kind`==stack, `name`==stack, `status`.
- Обязательные H2 (Domains/Edge/Networks/Backup/Observability/Generates) присутствуют; при `stable` — непусты.

См. `scripts/tools/validate-project-doc.sh` и `docs/project/README.md`.
