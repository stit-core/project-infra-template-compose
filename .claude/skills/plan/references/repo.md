# Профиль репо для /plan — project-infra-template-compose (хаб)

- **Роль:** хаб проекта (`<org>/infra`). Сквозная задача, которая меняет больше одного репо,
  планируется здесь как программа — `references/program.md`: фазы по репо, отправка агентов в
  сиблинги, выкатка. Работа самого хаба (compose, configs, ansible, скрипты) — обычный план.
- **Гейт перед «готово»:** `make check` (validate + doctor + plan-check + project-check); после
  деплоя — `make ps`.
- **Проверка планов:** `make plan-check` (входит в `make check`; pre-commit проверяет, когда
  меняется `.claude/plans/`).
- **Сводка планов:** `make status` → `== Plan ==`.
- **Типовые проверки шагов:** `make validate` → OK · `make doctor` → OK (локально без `.env` —
  SKIP, это норма) · `make check` → зелёный · после `make ship` — `make ps` → healthy · выкатка
  тега — `make bump SVC=<svc> TAG=<tag>` → `make ps` healthy.
- **Handoff:** оператору VPS — значения новых `${VAR}` в `.env` по `.env.example`, DNS, доступ к
  registry; сиблингам — через фазы программы.
- **Разбор падений:** skill `/triage` — сначала воспроизвести падение (RED).
- **До плана выясни:**
  - скоуп и что не входит; какие сервисы, среды (dev / staging / prod) и профили
    `COMPOSE_PROFILES` затронуты;
  - env и секреты: новые `${VAR}` — в `.env.example` с комментарием, как получить значение; кто и
    когда заполнит `.env` на VPS;
  - топология и сети: новый сервис, сеть `proxy` или `backend-net`, публичность через traefik с
    `crowdsec@file`, зависимость от postgres;
  - выкатка и простой: рестарт traefik static — это простой; смена environment пересоздаёт
    потребителей; порядок выкатки;
  - откат: откатывает ли down-путь; есть ли restore-point до destructive-шага (backup, restic);
  - сквозная ли задача: если нужны правки в сиблингах — это программа (`references/program.md`).
