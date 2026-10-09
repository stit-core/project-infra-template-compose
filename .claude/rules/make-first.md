---
name: make-first
description: make-first дисциплина — все операции через `make <verb>` (единый словарь из Makefile), скрипты за таргетами напрямую не дёргаем. Список легитимных raw-docker исключений (restic/cscli/mc/ls через `docker exec`, `docker compose config`, throwaway `docker run` в DR) и local-vs-remote split (authoring локально, ops на VPS). Грузится при правке Makefile, scripts/, скилов.
paths:
  - "Makefile"
  - "scripts/**"
  - ".claude/skills/**/*.md"
---

# make-first

Единый интерфейс к репо — `make <verb>`. `make help` печатает сгруппированный словарь.
Скрипты за таргетами (`scripts/tools/*`, `scripts/*.sh`) реализуют детали — **напрямую их
не зови** из скилов/доков: верб стабилен, путь скрипта — нет. Это держит один способ сделать
вещь и одно место для его эволюции.

## Словарь вербов

| Группа | Верб | Что |
|---|---|---|
| LOOP | `validate` / `doctor` / `check` | compose syntax+tpl+.env / live preflight / `validate`+`doctor`+`plan-check`+`project-check` |
| SHIP | `ship MSG="…"` / `deploy` / `render` | commit+check+push+(main)ssh-deploy / server-side / envsubst для `.tpl` |
| OPS | `ps` / `logs SVC=` / `restart SVC=` / `recreate SVC=` / `build SVC=` | статус / логи / рестарт / пересоздать (подхват нового значения `.env` или тега) / сборка образа сервиса (на VPS) |
| | `bump SVC= TAG=` | бамп image-тега: `<SVC>_TAG` в `.env` на VPS + force-recreate, ждёт healthy. Теги — строго через `.env` |
| | `backup` / `restore-pg SNAPSHOT=` | one-shot backup / restore postgres из restic |
| INTEL | `status` / `search Q= [P=]` | cockpit-сводка (локальный `status.sh` + серверный смок `== Server ==` по SSH при `.env.local`) / поиск по compose+configs+scripts+docs |
| PROVISION | `new-env` | bootstrap `.env` на чистом VPS |
| SETUP | `setup` | симлинк git-хуков (commit-msg, pre-commit) в `.git/hooks/` + PyYAML для frontmatter-проверки |
| META | `plan-check` / `project-check` | формат планов `.claude/plans/` / инфра-слой `docs/project/` (stack + сервисы) |

Канонический gate перед claim «готово» / push — **`make check`** (validate + doctor + plan-check + project-check).

## Raw-docker — когда легитимно

Прямой `docker`/`docker compose` оправдан только там, где make-верба нет и команда говорит
сама за себя. Каждый такой вызов в доке/скиле помечай как explanatory (зачем именно raw):

- **`docker exec <c> <tool> …`** для инструмента внутри контейнера, у которого нет make-обёртки:
  `restic` (в `backup`), `cscli` (в `crowdsec`), `mc` (в `minio`).
  Пример: `docker exec backup restic snapshots --compact`.
- **`docker compose config`** — разбор отрендеренного compose при триаже (`make validate` его гоняет,
  но при отладке полезен напрямую).
- **`docker run --rm` throwaway** — эфемерный контейнер вне стека (например temp-postgres в DR для
  проверки дампа), не управляется compose-проектом.
- **`docker logs <svc>`** — быстрый взгляд при триаже; для одного сервиса предпочитай `make logs SVC=<svc>`.
- **Внутренности `scripts/deploy.sh`** (`docker compose up -d --force-recreate <consumer>` и пр.) —
  explanatory, описывают что делает сервер-side скрипт, а не инструкция звать руками.

## Local vs remote

Репо живёт на **рабочей станции оператора**: authoring / `validate` / `plan` / `ship` —
локально, живого стека тут нет. Ops-вербы (`ps`/`logs`/`restart`/`backup`/`restore-pg`)
выполняются **на проектном VPS** и **сами проксируют туда**: sentinel — наличие `.env` (живёт
только на сервере). Нет `.env` (workstation) → верб уходит через `scripts/tools/ssh.sh exec make
<verb>` на VPS; есть `.env` (на VPS) → локальный `docker`. Произвольная команда на VPS —
`bash scripts/tools/ssh.sh exec '…'` (см. ниже).

Connection (host/port/user/project) берётся из **`.env.local`** (workstation, gitignored —
`.claude/rules/env-local.md`), **не хардкодится**; fallback — `ansible/inventory.ini`. `make ship`
пушит и триггерит remote `deploy.sh`.

## SSH: произвольная команда на VPS

Канон произвольной remote-команды — **`bash scripts/tools/ssh.sh exec '<command>'`**, команда
**одной строкой в кавычках**. Это задокументированное исключение из make-first: make-обёртки
нет сознательно — make-слой добавляет лишний проход разбора (make → локальный shell → remote
shell) и ломает вложенные кавычки/`$`. Скрипт передаёт строку на VPS без перепарса (`printf %q`
+ remote `bash -lc`; login-shell заодно гарантирует `make`/`docker` в PATH):

```bash
bash scripts/tools/ssh.sh exec 'docker ps --format "{{.Names}}" | sort'
```

Остальные сабкоманды `ssh.sh` (`status`/`smoke`/`deploy`/`restart`/`logs`) — внутренности
make-вербов, напрямую их не зови: `make status` / `make ps` / `make logs SVC=` / `make restart SVC=`.

## Запреты

`docker volume rm`, `docker compose … down -v/--volumes`, `git push --force`, `--no-verify` —
блокирует `permissions.deny` в `.claude/settings.json` (теряют данные / историю). Если такое
реально нужно — это осознанный destructive-шаг с явным OK юзера (см. skill `dr-restore`).
