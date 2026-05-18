---
name: smartdev
description: Entry-point для проектной инфры (<client-org>/infra шаблон). Запускай в начале сессии или когда непонятно с чего начать. Даёт сводку (ветка, working tree, compose-фрагменты, последние коммиты) и предлагает следующее действие. Активируй на "/smartdev", "что у нас?", "статус", "с чего начать?", "введи в курс дела".
---

# Skill: smartdev

Каноничный entry-point для работы с проектным репо. Цель — дать картину "что сейчас происходит" и переключить в правильный режим: edit / план / специализированный skill.

## Когда применять

- В начале сессии: "/smartdev", "что у нас", "с чего начать"
- После /clear или возврата к репо после паузы
- Когда юзер сформулировал задачу, но непонятно насколько она большая
- Когда что-то "вроде сломалось" и нужна orientation

## Когда НЕ применять

- Юзер уже дал чёткую узкую задачу — иди прямо в работу
- Уже идёт активная сессия с известным контекстом — не повторяй briefing

## Deploy-флоу (канон)

Один путь изменений → сервер:

```
make ship MSG="feat(foo): bar"
```

`scripts/ship.sh` делает (один проход, без CI / runner'ов):

1. Если working tree грязный — `git add -A && git commit -m "$MSG"` (commit-msg хук валидирует Conventional Commits).
2. `git push origin <branch>`.
3. **Если ветка = `main`** — SSH на VPS из `ansible/inventory.ini` → `bash scripts/deploy.sh`.
4. Если не main — push без deploy'я + подсказка про PR.

`make ship` без `MSG` (на чистом дереве) = push + deploy. Используется когда нужно форс-передеплоить `main` без новых изменений.

### Что делает `scripts/deploy.sh` на VPS

1. `git pull --ff-only origin main` — fail если remote разошлась.
2. `scripts/render-configs.sh` — envsubst для `.tpl`.
3. preflight DNS + Vault — только warnings.
4. **vault-agent first** — рендерит `.runtime/secrets/*.env` ДО старта consumer'ов (`env_file` фиксируется при CREATE контейнера).
5. **crowdsec early** — для bouncer auto-register если `CROWDSEC_BOUNCER_API_KEY=` пустой.
6. `docker compose up -d --remove-orphans --wait --wait-timeout 180`.
7. Diff `prev_sha..new_sha`:
   - `configs/vault-agent/**` → **force-recreate consumer'ов** (env_file читается только при CREATE).
   - `configs/{traefik,crowdsec,postgres,otel-agent}/**` → restart этих сервисов.

### Hot-fix прямо на VPS

Допустимо при инциденте, но строго временно: `/opt/<p>-infra/` — рабочая копия git-репо. Следующий `make ship` / `make deploy` сделает `git pull --ff-only` и **затрёт правки**. Поэтому hot-fix = **обязательный backport в git в тот же день**.

Если оператор упомянул что правил на хосте — флажь как `⚠ on-server drift, нужен backport`. Исключение — gitignored файлы (`.env`, `.runtime/`), они на VPS правятся легально.

Debug-mode на самом VPS: `ssh root@<vps> 'cd /opt/<p>-infra && make deploy'` (видишь пошаговый stdout вместо `--wait`-таймаутов через SSH).

## Шаги

### 1. Собрать сводку

```bash
bash scripts/tools/status.sh
```

Парси секции:
- `== Branch ==` — где стоим, drift с upstream
- `== Working tree ==` — modified / staged / untracked
- `== Compose ==` — кол-во фрагментов и .tpl
- `== Recent commits ==` — последние 5

(SSH-проверки сервера в шаблоне отсутствуют — single-VPS, доступ может быть не настроен в локальной сессии. Если оператор хочет — `ssh root@<vps>` руками.)

### 2. Если задача от юзера сформулирована — оцени размер

| Признаки | Действие |
|---|---|
| Меньше 5 атомарных шагов, без неочевидностей | Иди делать. План не нужен. |
| Меняет vault-agent config / agent.hcl.parts/ / templates/ | Security-sensitive — нужен план + явный OK. |
| Меняет traefik static (`configs/traefik/traefik.yml`) | Нужен план — рестарт Traefik = downtime. |
| Меняет `containers/backup/` или `compose/backup.yml` | Сначала спросить — может потерять restore-points. |
| Затрагивает >2 сервиса или их networking | План рекомендован. Спроси: "план или сразу делать?" |
| Disaster-recovery / restore | Активируй skill `dr-restore`. |
| Подъём нового VPS / клиента | Активируй skill `bootstrap-vps`. |
| Добавление нового сервиса | Активируй skill `add-service`. |
| Юзер сам сказал "распиши план" | Создай файл в `.claude/plans/<slug>.md`. |

### 3. Если задачи нет — предложи следующее действие

Приоритеты (сверху вниз):

1. **Незакоммиченные изменения** в working tree — спросить, нужен ли коммит / что планируется.
2. **Активный план** (`.claude/plans/<slug>.md` со status=in-progress) — продолжить.
3. **Drift с upstream >0 ahead/behind** — спросить, нужен ли push / pull.
4. **Пустое state** — спросить юзера какую задачу решать.

(На проектной стороне нет alerting/cert-monitoring locally — это покрывает корп-сторона через `otel-agent` → `otel.stit.tech`. Так что проверки cert-expiry и backup-age делает корп.)

### 4. Формат вывода

Один markdown-блок ≤25 строк:

```
## Состояние

**Ветка:** `<branch>` <ahead/behind>
**Working tree:** N modified, M staged, K untracked
**Compose:** N фрагментов, M .tpl
**Последний коммит:** <hash> <subject> (<ago>)

## Свежие коммиты
- <hash> <subject>
- ...

## Что висит
- <untracked / WIP>
- <активный план если есть>

## Предлагаю
<одно конкретное действие>
```

Если юзер сразу дал задачу — после сводки переходи к её оценке (см. шаг 2) одним абзацем.

## Что не делает smartdev

- Не делает edits / коммитов сам.
- Не запускает `make deploy` / `make backup`.
- Не делает `git pull` / `fetch` без явной просьбы.
- Не делает развёрнутого диагноза — это работа конкретных skill'ов.

## Anti-patterns

- Дамп всего вывода `status.sh` в чат. Сводка — резюме.
- Briefing на 100 строк.
- Сразу прыгать в `add-service` минуя оценку — если задача делается одним Edit, делай Edit.
