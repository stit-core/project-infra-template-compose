# Вклад в project-infra-template-compose

Это форкаемый шаблон проектной инфры — docker-compose стек одного VPS на
клиентский проект. Вклад полезен, когда он делает шаблон чище, безопаснее или
удобнее для того, кто разворачивает свою VPS — не когда он зашивает значения
конкретного хостинга.

## С чего начать

- Прочитай `CLAUDE.md` (ядро + роутер) и `docs/reference/architecture.md` (как
  устроен стек: сети, профили, edge).
- Поднимать ничего не нужно: `make validate` гоняет синтаксис compose, yamllint,
  `.tpl` и покрытие `.env.example` без живой инфры. Git-хуки — `make setup`.

## Принципы

- **Конфиг → код.** Любой сервис декларативен в `compose/*.yml` + `configs/`.
  Ничего «только на сервере, в репо нет» — это путь к drift'у.
- **Всё в .env.** Один gitignored-файл на VPS (identity, ACME, image-теги,
  секреты профилей) — оператор заполняет и ротирует руками. Inline-секретов
  в compose/`configs/` не бывает — только `${VAR}` с декларацией в `.env.example`.
- **Никаких реальных секретов в репо.** Токены, пароли, ключи, IP, домены
  конкретного хостинга в коммит не попадают. Параметры — через `${VAR}` /
  `.env.example` с пустыми значениями и комментарием как сгенерировать.
- **Pinned images.** Образы закреплены конкретной версией; `:latest` ловит
  `make validate`.
- **Multi-env физически.** Один шаблон, N VPS, у каждого свой `ENV` и свой `.env`.
- **Без вендор-лока.** Control-plane может быть managed (stit) или self-hosted —
  меняется только хост registry в `.env`, не зашит. Не вшивай
  зависимость от одного провайдера там, где это мешает self-host.
- **Forward-only документация.** Текст описывает текущее состояние, без «было/стало» —
  история живёт в `git log`.

## Форк, issue, PR

- **Issue** — для багов и предложений: что наблюдаешь, как воспроизвести, ожидаемое
  поведение.
- **PR** — форкни репозиторий, заведи ветку, открой pull request с понятным описанием
  «зачем». Держи PR сфокусированным; не подмешивай несвязанные правки.
- Тронул corp-поверхность (compose-профили, `.env.example`,
  `ansible/`) — опиши это в PR отдельно (в проекте изменения, требующие действия
  корп-стороны, передаются оператору корп-инфры out-of-band).

## Перед PR

```bash
make validate    # compose syntax + yamllint + .tpl + .env coverage
```

Зелёный `make validate` — gate пройден. Для форка с живым VPS канонический gate —
`make check` (validate + doctor + plan-check + project-check), деплой — `make ship`.

- Новый `${VAR}` в compose/configs → добавлен в `.env.example` с комментарием как
  сгенерировать.
- Каждый сервис имеет `restart`, `healthcheck`, `container_name`, явный `networks`.
  Public сервис — в `proxy` сети + traefik labels с `crowdsec@file` middleware.
- **Conventional Commits** (хук `commit-msg`): `<type>(<scope>)?: <subject>`,
  subject ≤72. Типы: `feat`, `fix`, `refactor`, `docs`, `test`, `chore`, `meta`.
  Пример: `feat(postgres): add read-replica service`.

## Что меняется осторожно

Traefik static-конфиг, `compose/backup.yml` / `containers/backup/` — security- и
data-sensitive. Помечай такие правки отдельным коммитом, чтобы было видно в blame.

## Стиль

Спокойно и по делу, без хайпа. YAML 2-space indent, без табов. Все операции —
через `make <verb>` (`make help`), не дёргай скрипты за таргетами напрямую.
Комментарии — только когда WHY неочевидно, не пересказ YAML.

## Лицензия

Контрибьютя, ты соглашаешься, что вклад выходит под лицензией **Apache-2.0** —
той же, под которой распространяется репозиторий (см. `LICENSE`).
