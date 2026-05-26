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
| LOOP | `validate` / `doctor` / `check` | compose syntax+tpl+.env / live preflight / оба + `plan-check` |
| SHIP | `ship MSG="…"` / `deploy` / `render` | commit+check+push+(main)ssh-deploy / server-side / envsubst+agent.hcl |
| OPS | `ps` / `logs SVC=` / `restart SVC=` | статус / логи сервиса / рестарт сервиса |
| | `backup` / `restore-pg SNAPSHOT=` | one-shot backup / restore postgres из restic |
| INTEL | `status` / `search Q= [P=]` | cockpit-сводка / поиск по compose+configs+scripts+docs |
| PROVISION | `new-env` | bootstrap `.env` на чистом VPS |
| SETUP | `setup` | симлинк git-хуков (commit-msg, pre-commit) в `.git/hooks/` |
| META | `plan-check` | валидатор структуры `.claude/plans/roadmap.md` |

Канонический gate перед claim «готово» / push — **`make check`** (validate + doctor + plan-check).

## Raw-docker — когда легитимно

Прямой `docker`/`docker compose` оправдан только там, где make-верба нет и команда говорит
сама за себя. Каждый такой вызов в доке/скиле помечай как explanatory (зачем именно raw):

- **`docker exec <c> <tool> …`** для инструмента внутри контейнера, у которого нет make-обёртки:
  `restic` (в `backup`), `cscli` (в `crowdsec`), `mc` (в `minio`), `ls`/инспекция rendered-файлов
  (в `vault-agent`). Пример: `docker exec backup restic snapshots --compact`.
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
логически выполняются **на проектном VPS** — через `scripts/tools/ssh.sh` (хост из
`ansible/inventory.ini`). `make ship` пушит и триггерит remote `deploy.sh`.

Реализация-план: сейчас ops-вербы Makefile (`make ps`/`logs`) гоняют **локальный** `docker compose`
на том хосте, где вызваны; сквозная ssh-обёртка ops-вербов из рабочей станции — Phase 7 (A23).
До неё remote-ops идут через `scripts/tools/ssh.sh <subcommand>` напрямую либо `ssh root@<vps>`.

## Запреты

`docker volume rm`, `docker compose … down -v/--volumes`, `git push --force`, `--no-verify` —
блокирует `permissions.deny` в `.claude/settings.json` (теряют данные / историю). Если такое
реально нужно — это осознанный destructive-шаг с явным OK юзера (см. skill `dr-restore`).
