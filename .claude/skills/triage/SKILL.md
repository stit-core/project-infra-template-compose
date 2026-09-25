---
name: triage
description: Red-арм cockpit'а — структурированный разбор инфра-падения (compose не стартует, сервис unhealthy / exited / в restart-loop, cert не выписан, render fail, deploy.sh упал, образ не пуллится, on-server drift). Найти корневую причину, не замазать симптом. smartdev чейнит сюда на `== Critical ==` ≠ none или ATTENTION в `== Server ==`; вызывай и когда юзер сообщает о поломке или присылает лог/трейс. Багфикс ведётся здесь, а не через plan.
---

# Skill: triage

Дисциплинированный разбор инфра-падения. Цель — **корневая причина**, не
«рестартни и авось пройдёт».

**Red-арм cockpit'а:** `smartdev` переключает сюда, когда `make status` дал
`== Critical ==` ≠ none (upstream-drift) или ATTENTION в `== Server ==` (unhealthy / exited /
restart-loop / host-pressure), либо задача = «сломалось». Багфикс ведётся здесь, а не через
`plan`: у фикса своя короткая RED→GREEN петля, план её только замедляет. Исключение —
research-spike, когда причина неясна после ≥2 попыток.

## Когда применять

- `make status` / `make ps` → unhealthy / restarting / exited
- `make ship`/`make deploy` упал
- сервис стартует с пустыми секретами; cert не выписывается; landing/сайт не открывается
- Юзер кидает лог / трейс / «почему X не работает»

## Когда не применять

- Новая фича / новый сервис — это `add-service` или `plan`, не triage
- Опечатка которую видно с первой строки — просто чини

## Категории падений

| Тип | Признаки | Где смотреть |
|---|---|---|
| **compose не стартует** | `docker compose up` error, сервис не создаётся | `make validate` → `make doctor` → `docker compose config` (raw — debug-исключение make-first) |
| **healthcheck red** | `make ps` unhealthy / restarting | `make logs SVC=<svc>` — последние строки перед рестартом |
| **пустые секреты** | сервис падает на auth/DSN; env-значения пустые | `make doctor` (.env identity/coverage) — переменные профиля не заполнены в `.env` (оператор дописывает по `.env.example`) |
| **cert не выписан** | HTTPS не открывается, traefik спамит acme | `make logs SVC=traefik` + `grep -i acme` — DNS NXDOMAIN / LE rate-limit / HTTP-01 |
| **render fail** | `make render`/deploy падает на envsubst | `scripts/render-configs.sh` — отсутствующий `${VAR}` в `.env`, .tpl-синтаксис, профиль |
| **deploy.sh fail** | `make ship`/`make deploy` non-zero | где упал: `git pull --ff-only` (drift) / render-configs / compose `--wait` timeout |
| **pull образа** | `compose up` / `make bump` падает на pull (`manifest unknown`, `unauthorized`) | тег есть в registry? VPS залогинен в `REGISTRY_HOST`? путь `${REGISTRY_HOST}/${PROJECT_NAME}/<svc>` совпадает с тем, куда пушит `/release` сервис-репо? |
| **on-server drift** | оператор правил на хосте, следующий deploy затрёт | backport в git **в тот же день** |

## Шаги

### 1. Воспроизвести минимально

- Что именно красное? `make ps`, `make doctor`, `make logs SVC=<svc>`.
- Когда последний раз работало? `git log --oneline -10` — что изменил последний deploy (`prev_sha..HEAD`)?
- Локально или только на VPS? (cert/healthcheck/.env — обычно VPS-only.)

Не гоняй весь стек — точечно тот сервис, что упал.

### 2. Прочитать сообщение целиком

Не первую строку — **целиком**. В compose/traefik выводе главное
часто в середине (после длинного wait-стека или списка ретраев). Читай до конца.

### 3. Сформулировать гипотезу

Одно проверяемое предложение: «X падает потому что Y».
- «postgres в restart-loop потому что `POSTGRES_PASSWORD` пуст в `.env` при активном `COMPOSE_PROFILES=postgres`»
- «backend unhealthy потому что контейнер создан до заполнения `.env` — нужен `make recreate SVC=backend`»
- «cert не выписан потому что `s3.$DOMAIN` → NXDOMAIN, HTTP-01 не проходит»

Несколько гипотез — выбирай самую дешёвую в проверке (`make doctor` секции часто сразу указывают).

### 4. Фикс (минимальный, корневой)

Инфра ≠ TDD (нет unit-тестов). Но:
- Баг в скрипте (`deploy.sh`/`render-configs.sh`/`scripts/tools/*`) → добавь
  guard/проверку, чтобы не повторилось молча; верификация — `make check`.
- Баг в compose/configs → правь декларативно, не хот-фиксь на хосте.
- Причина вне этого репо → здесь она не чинится, назови её и владельца: нет образа/тега в
  registry — `/release` в сервис-репо (агентом в сиблинге); VPS не залогинен в registry
  (`docker login` с PAT) или DNS-запись не указывает на VPS — оператор. Обходы (подмена тега,
  `:latest`) не делаем — они прячут причину до следующего деплоя.

### 5. Re-verify зелёный

```
make validate            # синтаксис/tpl/.env
make doctor              # live preflight (compose/render/dns/env)
make ps                  # healthchecks (на VPS / через ssh.sh)
make logs SVC=<svc>      # подтверди, что ретраи прекратились
```
Для cert — дай время на retry-цикл, смотри логи до зелёного, не «один раз глянул».

### 6. on-server drift

Оператор упомянул правку на хосте (`/opt/<p>-infra/`)? Следующий
`make ship`/`deploy` сделает `git pull --ff-only` и **затрёт**. Backport
правки в git коммитом **в тот же день**. Исключение — gitignored
(`.env`, rendered-конфиги), они на VPS легальны.

### 7. Коммит

`fix(<scope>): <одна строка>`.

### 8. Когда застрял (2+ попытки)

1. Откатись к чистому состоянию (`git stash` / зафиксируй текущий red).
2. Сформулируй вслух юзеру: «думаю X, но проверка Y даёт Z, не хватает Q».
3. Делегируй subagent `explorer`: «найди где задаётся/читается <X>».
4. Если всё равно — `plan` skill: research-spike (план именно на разведку, не на фикс).

## Anti-patterns

- ❌ Рестарт «чтобы прошло» без понимания причины — вернётся.
- ❌ Правка на хосте без backport в git в тот же день.
- ❌ `docker compose down -v` / `docker volume rm` — теряет данные (блокирует `permissions.deny`, и правильно).
- ❌ Раздуть healthcheck-timeout вместо фикса причины unhealthy.
- ❌ «while we're at it» — расширение скоупа в багфиксе. Фикс = маленький коммит; большое — `plan`.
