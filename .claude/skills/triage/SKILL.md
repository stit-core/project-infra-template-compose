---
name: triage
description: Red-арм cockpit'а — структурированный разбор инфра-падения — compose не стартует / сервис unhealthy / cert не выписан / render fail / deploy.sh упал / on-server drift. Найти корневую причину, не замазать симптом. smartdev чейнит сюда на `== Critical ==` ≠ none или когда юзер пишет «сломалось», «не поднимается», «упало», «почему unhealthy», «cert не выписался», «деплой красный», кидает лог/трейс. Багфикс идёт сюда, НЕ в plan.
---

# Skill: triage

Дисциплинированный разбор инфра-падения. Цель — **корневая причина**, не
«рестартни и авось пройдёт».

**Red-арм cockpit'а:** `smartdev` переключает сюда, когда `make status` дал
`== Critical ==` ≠ none (unhealthy / exited / upstream-drift) или задача =
«сломалось». Это **никогда не идёт в `plan`** — план для багфикса анти-паттерн.
Исключение — research-spike, когда причина неясна после ≥2 попыток.

## Когда применять

- `make status` / `make ps` → unhealthy / restarting / exited
- `make ship`/`make deploy` упал
- сервис стартует с пустыми секретами; cert не выписывается; landing/сайт не открывается
- Юзер кидает лог / трейс / «почему X не работает»

## Когда НЕ применять

- Новая фича / новый сервис — это `add-service` или `plan`, не triage
- Опечатка которую видно с первой строки — просто чини

## Категории падений

| Тип | Признаки | Где смотреть |
|---|---|---|
| **compose не стартует** | `docker compose up` error, сервис не создаётся | `make validate` → `make doctor` → `docker compose config` (raw — debug-исключение make-first) |
| **healthcheck red** | `make ps` unhealthy / restarting | `make logs SVC=<svc>` — последние строки перед рестартом |
| **пустые секреты** | сервис падает на auth/DSN; env-значения пустые | `make doctor` (.env identity/coverage) — переменные профиля не заполнены в `.env` (`/request-secret`) |
| **cert не выписан** | HTTPS не открывается, traefik спамит acme | `make logs SVC=traefik` + `grep -i acme` — DNS NXDOMAIN / LE rate-limit / HTTP-01 |
| **render fail** | `make render`/deploy падает на envsubst / agent.hcl | `scripts/render-configs.sh` — отсутствующий `${VAR}` в `.env`, .tpl-синтаксис, профиль |
| **deploy.sh fail** | `make ship`/`make deploy` non-zero | где упал: `git pull --ff-only` (drift) / render-configs / compose `--wait` timeout |
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
- Причина на корп-стороне (registry-доступ / DNS / crowdsec whitelist)
  → это **не чинится здесь**: оформи `CORP-HANDOFF` (skill `corp-handoff`),
  передай корп-админу. Не workaround'ь обходом политики.

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

`fix(<scope>): <одна строка>`. Если задело corp-поверхность — `CORP-HANDOFF`
блок до claim «готово».

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
- ❌ Workaround'ить отсутствующий KV / политику вместо `corp-handoff`.
- ❌ «while we're at it» — расширение скоупа в багфиксе. Фикс = маленький коммит; большое — `plan`.
