---
name: secrets-and-env
description: Правила секретов в проектной инфре. Все секреты и конфиг-значения — в .env на VPS (gitignored, single source), сервисы получают их через compose-интерполяцию environment, ротация = правка .env + make deploy/recreate. Грузится при работе с .env, .tpl, compose.
paths:
  - ".env"
  - ".env.example"
  - "**/*.tpl"
  - "compose/**"
---

# Секреты и .env

## Модель: .env — единственный источник

Все секреты и конфиг-значения стека живут в **одном** `.env` на VPS (gitignored,
chmod 600). Оператор заполняет и ротирует его руками. Сервисы получают значения
через compose-интерполяцию `${VAR}` в `environment:`; конфиг-файлы с
переменными (traefik static, middlewares, landing) рендерятся из `.tpl`
envsubst'ом (`scripts/render-configs.sh`).

| Категория | Что | Кто пишет |
|---|---|---|
| Identity | `PROJECT_NAME`, `ENV`, `DOMAIN` | `scripts/new-env.sh` |
| ACME | `ACME_EMAIL`, `ACME_CASERVER` | `scripts/new-env.sh` / оператор |
| Local-managed | `CROWDSEC_BOUNCER_API_KEY`, `COMPOSE_PROFILES`, `HOST_ROLE` | auto-register / оператор |
| Image-теги | `BACKEND_TAG` (конвенция `<SVC>_TAG`) | оператор (`make bump SVC= TAG=`) |
| Registry | `REGISTRY_HOST` (дефолт `git.stit.tech` в compose) | оператор, если registry другой |
| Секреты профилей | `POSTGRES_*`, `OIDC_*`, `JWT_SECRET`, `MINIO_*`, `APP_S3_*`, `BACKUP_S3_*`, `RESTIC_*`, `BACKUP_AWS_*` | оператор (по `.env.example`) |

## Multi-env

Один проект = N сред = N **отдельных VPS**, каждый со своим `ENV` и своим
`.env`. Контракт per-env `.env` — `.claude/rules/multi-env.md`. Этот документ —
про **механику секретов**: имена, рендер, ротация, что нельзя коммитить.

## Что куда

| Файл | В репо? | Зачем |
|---|---|---|
| `.env.example` | да | Полный контракт переменных: активные — заполняются на bootstrap, профильные — закомментированы с комментарием как сгенерировать |
| `.env` | **нет** (gitignored) | Реальные значения на VPS |
| `configs/<svc>/*.tpl` | да | envsubst-шаблоны с .env-vars (`traefik.yml.tpl` с `${ACME_EMAIL}`, `middlewares.yml.tpl` с `${CROWDSEC_BOUNCER_API_KEY}`) |
| rendered `configs/<svc>/<file>` | **нет** (gitignored) | Выход render-configs.sh, пересобирается каждый deploy |

## Правила

### .env / .env.example

- `.env*` не коммитятся: `.gitignore` их покрывает, а `make ship` делает `git add -A` — проверяй
  `git status` перед коммитом, если заводил файл с нестандартным именем.
- `.env.example` — контракт: каждый `${VAR}` из compose/configs присутствует
  там (активный или закомментированный `# VAR=`) с комментарием откуда взять /
  как сгенерировать (`openssl rand -hex 32` для паролей). `make validate`
  ловит пропуски детерминированно.
- Имена: `<SERVICE>_<PURPOSE>` UPPER_SNAKE_CASE.
- Форма строки — `KEY=значение` с начала строки, без пробелов у `=`; значение с пробелом,
  `$`, кавычкой или знаком шелла — в одинарных кавычках. Файл читают шелл скриптов
  (`. ./.env`), compose и построчное чтение ключей: строку другой формы они читают
  по-разному, а в тексте ошибки сами печатают её кусок — хеш, пароль. Форму держит
  `scripts/preflight-env.sh` раньше каждого чтения: `make deploy`, `make render`,
  `make doctor`, `make validate` и ops-вербы на такой строке отказывают, называя ключ и
  номер строки, без значения.
- Секреты профилей закомментированы в `.env.example` и раскомментируются в
  `.env` вместе с профилем.

### Новый секрет / новый render-target

Новая переменная для сервиса — **две** правки:
1. `${VAR}` в `compose/<svc>.yml` (`environment:`) или в `configs/<svc>/<file>.tpl`.
2. Декларация в `.env.example` с комментарием как сгенерировать.

После — `make ship`; на VPS оператор дописывает значение в `.env` по
`.env.example` (комментарий там объясняет, как сгенерировать) и `make deploy`.

### Ротация

Источник истины — `.env` на VPS:

```bash
# на VPS
$EDITOR .env          # заменить значение
make deploy           # compose пересоздаст сервисы с изменённым environment
```

`docker compose up` сравнивает интерполированный конфиг и пересоздаёт только
затронутые сервисы. Точечно — `make recreate SVC=<svc>` (`restart` НЕ
перечитывает environment — контейнер фиксирует env при CREATE).

Смена `ACME_*` — рестарт traefik руками (`make restart SVC=traefik`): traefik
читает static config только на старте, а контент bind-mount'а compose не
отслеживает. Замок не-прод среды (`STAGING_BASIC_AUTH_USERS`) рендерится в
dynamic-конфиг: `make deploy` включает его, меняет пароль и снимает без рестарта
traefik. Значение — одна строка `'user:hash'` в одинарных кавычках: логин — латинские
буквы, цифры и `._@-`, хеш — bcrypt целиком (`htpasswd -nbB`). Другую форму, как и
открытый пароль, обрезанный или не-bcrypt хеш, `make deploy`, `make render` и
`make doctor` отвергают (`scripts/preflight-env.sh`): с таким значением замок закрыт,
а войти нельзя.

### Profile-based opt-in

Минимальный стек (always-on) — traefik / crowdsec / landing. Поднимается на
identity + ACME из `.env`, других секретов не требует.

Опциональные сервисы за `COMPOSE_PROFILES`:

| Profile | Сервисы | Требует в .env |
|---|---|---|
| `postgres` | postgres | `POSTGRES_USER` / `POSTGRES_PASSWORD` / `POSTGRES_DB` |
| `storage` | minio, minio-init, backup | `MINIO_*`, `APP_S3_*`, `BACKUP_S3_*`, `RESTIC_*`, `BACKUP_AWS_*` (+ обязательно `postgres` профиль) |
| `backend` | backend | `OIDC_*`, `JWT_SECRET` (+ секция postgres) + `BACKEND_TAG` |
| `site` | site | `SITE_TAG`, `ROBOTS_POLICY`, канал формы (`SITE_FORM_*`, `SITE_SMTP_URL`); на не-прод — `ROBOTS_POLICY=noindex` и замок `STAGING_BASIC_AUTH_USERS` |

Значения оператор берёт из `.env.example` (комментарии объясняют, как
сгенерировать каждое), генерирует пароли (`openssl rand`) и дописывает в
`.env` на VPS.

## Что нельзя коммитить (cross-check)

`git diff --cached` перед коммитом — убедись что нет:
- `.env` или `.env.local` / `.env.production`
- `.onboard-creds` (safety-net в .gitignore)
- `*.pem`, `*.key`
- Inline-секретов в `compose/*.yml` (значения вида `password: actual_secret` —
  должно быть `${VAR}` с декларацией в `.env.example`)
- Rendered-файлов из `.tpl` (gitignored: `configs/traefik/traefik.yml`,
  `configs/traefik/dynamic/middlewares.yml` — в нём ключ bouncer и хеш замка не-прод среды)

`.gitignore` страхует от типовых имён; `git diff --cached` ловит остальное.

## Чек перед коммитом

- В `.env.example` нет реальных значений (только placeholder / пусто)?
- Любой новый `${VAR}` в compose/configs — добавлен в `.env.example`
  (активный или закомментированный) с комментарием как сгенерировать?
- `make validate` зелёный (он ловит missing vars в `.env.example`)?
