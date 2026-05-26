---
name: service-deep-dive
description: Спроектировать один hosted-сервис продукта — довести docs/project/services/<name>.md от драфта до status=stable через волны вопросов (Hosting→Identity→Secrets→Route→Generates). Артефакт — source of truth и вход для de-template (секция Generates — что родится/изменится в инфре). Активируй когда юзер проектирует сервис, говорит "спроектируем сервис X", "добьём service-doc", "/service-deep-dive <name>", или когда init-project дошёл до шага сервисов. Решения не выдумывай — интервьюируй.
---

# Skill: service-deep-dive

Проектирование одного **hosted**-сервиса проекта: доводит `docs/project/services/<name>.md` до
`status: stable`. Где `/init-project` отвечает «из чего состоит продукт» (vision § Service map),
этот скилл — «как именно этот сервис хостится на VPS»: хостинг/профиль, идентичность образа или
движка, какой Vault KV нужен, как роутится, что из него родит `de-template`.

Это **source of truth и вход для `de-template`**: секция `Generates` описывает, что из артефакта
изменится в инфре (профиль, vault-agent part/template, traefik route). Работает через
AskUserQuestion в режиме интервьюера — **не выдумывает** решения сам.

В онбординг-флоу `/init-project` чейнит сюда по одному разу на каждый hosted-сервис из карты,
затем — `/stack-deep-dive` → `/de-template`.

## Когда применять

- "Спроектируем сервис `db`" / "Добьём `services/backend.md`"
- "/service-deep-dive backend"
- `/init-project` дошёл до проектирования сервиса из карты
- service-doc в `draft` — нужно довести до `stable`

## Когда НЕ применять

- Артефакта ещё нет — сначала `cp docs/project/_templates/service.md docs/project/services/<name>.md`,
  заполни frontmatter (subtype/hosting/name).
- Сервис `hosting: external` (frontend-SPA/CDN, backend-код-репо) — он живёт только в vision
  `Service map`, своего service-doc не получает (см. `docs/project/README.md`).
- Артефакт уже `stable` — запусти валидатор, не интервьюй заново.
- Правка одной готовой секции (поменялся образ) — точечная правка, не deep-dive.

## Шаги

### 1. Сканируй контекст

```bash
ls docs/project/services/
make project-check A=docs/project/services/<name>.md
```

Зелёный и `stable` → выходи: «сервис спроектирован, делать нечего». Иначе прочитай frontmatter
(`subtype`/`hosting`/`status`) и H2-заголовки, вычисли заполненность по обязательным секциям
(`docs/project/README.md`).

### 2. Покажи карту состояния

Сжато, ≤8 строк:

```
## Состояние services/<name>.md (subtype=<…>, hosting=<…>)

| секция | заполнено | дыра |
|---|---|---|
| Hosting   | да  | — |
| Secrets   | нет | Vault KV не определён |
| Generates | нет | контракт для de-template пуст |
```

### 3. Веди волны

Порядок — фундамент → производное (запоминай, у пользователя не спрашивай):

1. **Hosting** — `here`/`external`, какой профиль `COMPOSE_PROFILES` активирует, source-репо (для
   backend: код внешний, контейнер here).
2. **Identity** — образ (`git.stit.tech/<org>/<name>:<tag>`, pinned) или движок (postgres 17 / minio);
   container_name, healthcheck, сети (`proxy`/`backend-net`).
3. **Secrets** — какой `kv/projects/<p>/<env>/<kind>` нужен + поля; какой vault-agent template
   рендерит env. Нет секретов → `N/A`.
4. **Route** — public (сабдомен `<name>.${DOMAIN}` + traefik + `crowdsec@file`) или internal → `_internal_`.
5. **Generates** — явно: что `de-template` родит/изменит (профиль, `agent.hcl.parts/<part>.hcl` +
   `templates/<kind>.env.tpl`, traefik labels, для external — cross-repo next-step). Без `Generates`
   артефакт бесполезен движку.

Для текущей секции: 3–5 предметных вопросов через `AskUserQuestion` (≤4 за tool-call). После
ответов **сразу** пиши в md через Edit/Write — не копи «запишу в конце» (теряется при /clear).
Кратко покажи, что добавилось, переходи дальше.

### 4. Правила вопросов

- **Конкретные, falsifiable.** Плохо: «как с секретами?». Хорошо: «`db` читает
  `kv/projects/<p>/<env>/db` поля user/password/database, или ещё `sslmode`?».
- **Bounded.** Опции AskUserQuestion взаимоисключающие (или `multiSelect=true`).
- **Не выдумывай.** «Не знаю» → пиши `TBD` явно, вернись позже.
- **Опирайся на инфру как образец.** `compose/<name>.yml`, `configs/vault-agent/templates/<kind>.env.tpl`,
  `.claude/rules/compose-and-services.md` — живой пример: «healthcheck сейчас `pg_isready` — оставляем?».

### 5. Промоушн status

После всех волн:

```bash
make project-check A=docs/project/services/<name>.md
```

Зелёный → правь frontmatter `status: draft → stable`, запусти валидатор ещё раз (теперь проверит
non-empty bodies). Красный → вернись к проблемным секциям, не маркируй stable.

### 6. Финал

Сводка: сервис `stable`. Следующий шаг:
- **Онбординг** (из `/init-project`): остались сервисы из карты → следующий `/service-deep-dive`;
  все hosted готовы → `/stack-deep-dive`.
- **Отдельно**: артефакт — актуальный source of truth; правь при изменении сервиса.

## Anti-patterns

- ❌ >4 вопросов одним AskUserQuestion (инструмент режет до 4).
- ❌ Копить ответы в RAM, писать в конце — теряется при /clear.
- ❌ Заводить service-doc для `hosting: external` — он только в vision `Service map`.
- ❌ Оставить `Generates` пустым — движку `de-template` не из чего разворачивать.
- ❌ Дублировать `COMPOSE_PROFILES` целиком — профиль сервиса родит de-template из карты; здесь только
  какой профиль активирует ЭТОТ сервис.
- ❌ Промоутить `stable` при красном валидаторе.

## Что делает валидатор (для справки)

- Frontmatter: `id`/`kind`/`name`/`status` + (service) `subtype`∈{backend,frontend,datastore,infra},
  `hosting`∈{here,external}.
- `basename == name`; `id == "project.<name>"`.
- Все обязательные H2 (Hosting/Identity/Secrets/Route/Generates) присутствуют; при `stable` — непусты.

См. `scripts/tools/validate-project-doc.sh` и `docs/project/README.md`.
