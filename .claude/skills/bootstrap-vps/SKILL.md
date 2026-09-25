---
name: bootstrap-vps
description: Поднять новый VPS среды проекта с нуля — ansible-bootstrap, регистрация deploy-key в Gitea, заполнение .env, первый деплой, активация профилей. Multi-env (один VPS = один ENV). Вызывай, когда нужен сервер под новый проект или новую среду, перенос на новый хост или обкатка шаблона на тестовом VPS.
---

# Skill: bootstrap-vps

Provisioning нового VPS под клиентский проект — один VPS = один ENV (`dev` / `prod` / etc.). Цель: за один проход довести машину от чистой Debian/Ubuntu до состояния "always-on стек крутится, healthchecks зелёные".

## Когда применять

- "Подними новый VPS для <client>" — **production-режим**
- "Новый сервер, начнём с нуля" — **production-режим**
- "Перенос на новый хост" (после `dr-restore` для данных) — production-режим
- "Обкатка / тестовый прогон шаблона / пробую заново на тестовом VPS" — **rehearsal-режим** (см. ниже)
- "/bootstrap-vps"

### Production vs rehearsal — определи режим заранее

| Режим | Триггеры | LE endpoint | Что меняется |
|---|---|---|---|
| **production** | "клиентский VPS", "новый проект", "поднимаем для <client>", реальный домен заранее настроен | LE prod (`acme-v02.api.letsencrypt.org`) | Дефолт `ACME_CASERVER` в `.env` |
| **rehearsal** | "обкатка", "обкатываю шаблон", "тестовый прогон", "пробую заново", "тестовый VPS", "буду повторять bootstrap" | LE staging (`acme-staging-v02.api.letsencrypt.org`) — untrusted, rate-limits ~100× выше | `ACME_CASERVER` в `.env` — staging URL до первого deploy'я |

**Почему важно:** LE prod лимиты тесные:
- 5 failed validations / hostname / hour
- 5 duplicate certs / SAN-set / week
- 50 certs / registered domain / week

При rehearsal (DNS ещё не настроен → failed challenges, многократный teardown/redeploy → duplicate certs) лимит сжигается за день. Staging — те же API, лимиты ~30k/week.

Контроль: `ACME_CASERVER` живёт в `.env` на VPS. Если режим rehearsal — выстави staging URL до первого deploy:
```bash
# в .env на VPS
ACME_CASERVER=https://acme-staging-v02.api.letsencrypt.org/directory
```

**Migration prod ↔ staging на том же VPS:** acme.json привязан к CA-серверу. Сброс acme-volume —
**destructive**, требует явного OK; `docker volume rm` блокирует `permissions.deny` (агент его не
выполнит) — это ручной шаг оператора на VPS:
```bash
docker compose <args> down traefik
docker volume rm <p>-infra_traefik-acme   # destructive, оператор вручную
$EDITOR .env                              # ACME_CASERVER=<new>
make ship  # render-configs перерендерит traefik.yml, traefik подымется с новым CA
```

## Когда не применять

- Re-deploy на уже работающий хост — это `make deploy` / `make ship`.
- Доступы людей в Gitea (аккаунты, PAT, права на репо) — их выдаёт админ Gitea, не этот скилл.
- Bug на проде — диагностика, не bootstrap.

## Предусловия (уточни у юзера)

1. **VPS provisioned**, у тебя есть IP и root-доступ по SSH ключу (минимум один ключ в `/root/.ssh/authorized_keys`).

2. **DNS** для `${DOMAIN}` (а также `api.${DOMAIN}` etc. — по сабдоменам, которые будут активированы позже) указывает на IP VPS — нужно для HTTP-01 ACME challenge.

3. **Gitea-репо** `<client-org>/infra` существует и склонирован из шаблона `project-infra-template-compose`.

4. **Доступ к registry** `REGISTRY_HOST` (дефолт `git.stit.tech`) — Gitea-аккаунт с PAT, которым
   VPS будет пуллить образы сервис-репо (нужен к активации профиля `backend`, шаг 7).

Без любого из этих пунктов — стопори, проси подготовить.

## Шаги

### 1. Inventory + SSH key

`ansible/inventory.ini` (gitignored, скопируй из `inventory.example.ini`):

```ini
[project_vps]
prod ansible_host=<IP> ansible_user=root project_name=<p> project_repo_url=git@git.stit.tech:<client-org>/infra.git

[project_vps:vars]
ansible_python_interpreter=/usr/bin/python3
operator_ssh_pubkey="ssh-ed25519 AAAAC3Nz... operator@laptop"
```

(Если на каждый env свой VPS — несколько inventory'ев или несколько групп в одном.)

Коллекции Galaxy — один раз на рабочей станции (base-роль использует `ansible.posix`):
`ansible-galaxy collection install -r ansible/requirements.yml`.

Verify connectivity: `ansible -i ansible/inventory.ini project_vps -m ping`.

### 2. Bootstrap playbook (без onboard)

```bash
ansible-playbook -i ansible/inventory.ini ansible/bootstrap.yml --skip-tags onboard
```

Roles `base` → `ssh-hardening` → `docker` (skip'аем `stit-onboard` до регистрации deploy-key). По итогам — VPS с Docker engine, ssh-hardened, системные пакеты.

### 3. Onboard: deploy-key + clone

```bash
ansible-playbook -i ansible/inventory.ini ansible/bootstrap.yml --tags onboard
```

Сгенерит deploy-key в `/root/.ssh/<project>-deploy`, напечатает pubkey, попробует склонировать репо. **Первый запуск ожидаемо падает на clone** — deploy-key ещё не в Gitea.

Скопируй pubkey → **попроси оператора зарегистрировать в Gitea**:
- `git.stit.tech/<client-org>/infra` → Settings → Deploy Keys → Add → paste pubkey, **read-only**

### 4. Re-run onboard (после регистрации deploy-key)

```bash
ansible-playbook -i ansible/inventory.ini ansible/bootstrap.yml --tags onboard
```

Склонирует репо в `/opt/<project>-infra`, поставит git hooks.

### 5. Заполнить .env

На VPS:

```bash
ssh root@<IP>
cd /opt/<project>-infra
PROJECT_NAME=<p> ENV=<env> DOMAIN=<d> ACME_EMAIL=<email> \
make new-env
```

Создаёт `.env` (chmod 600) — identity + ACME. Секреты профилей допишешь по мере активации (шаг 7); image-теги — тоже в `.env` (`make bump`).

`.env` содержит **закомментированную** строку `# COMPOSE_PROFILES=` — будешь раскомментировать по мере активации сервисов (см. шаг 7).

**Rehearsal-режим** — добавь шаг до первого deploy'я:
```bash
# в .env на VPS
ACME_CASERVER=https://acme-staging-v02.api.letsencrypt.org/directory
```

### 6. Первый деплой — always-on стек

С laptop'а оператора:
```bash
make ship          # commit + check + push + (на main) ssh-deploy
```

Либо на VPS (debug-mode со пошаговым stdout):
```bash
ssh root@<IP>
cd /opt/<project>-infra
make deploy
```

Что произойдёт:
1. `render-configs.sh` — envsubst для traefik.yml/middlewares/landing из `.env`.
2. CrowdSec early для bouncer auto-register.
3. Остальные always-on: traefik / landing.
4. Traefik запрашивает LE-cert на `${DOMAIN}` (landing).

**Если что-то не поднимается:**
- traefik не healthy / пустой traefik.yml → `.env` не заполнен (`ACME_EMAIL`) или render не отработал; `make doctor` (секция «configs render») покажет.
- LE cert не выпустился → DNS не указывает на VPS, или 80/443 закрыты файрволом.
- crowdsec bouncer auto-register не сработал → fallback `docker exec crowdsec cscli bouncers add traefik` (cscli внутри контейнера — make-first исключение), прописать в `.env`, `make deploy`.

### 7. Активация дополнительных профилей (по мере необходимости)

Каждый сервис кроме always-on'а — за `COMPOSE_PROFILES`. Активация — два шага:
1. Дописать секцию секретов профиля в `.env` на VPS (контракт — `.env.example`;
   комментарии там объясняют, как сгенерировать каждое значение).
2. Обновить `COMPOSE_PROFILES` в `.env` и `make ship`.

Оператор берёт набор переменных профиля из `.env.example`, генерирует случайные
пароли где надо (`openssl rand`), дописывает блок `VAR=value` в `.env`.

После дописывания — на VPS:
```bash
$EDITOR .env   # COMPOSE_PROFILES=postgres,storage,backend
make ship
```

**Storage обязательно с postgres** (backup делает pg_dumpall, без postgres сразу падает — deploy.sh валидирует, ругнётся явно).

**Backend** (и любой образ сервис-репо) тянется из `REGISTRY_HOST`, поэтому до его профиля VPS
логинится в registry: оператор сам выполняет на VPS `docker login <REGISTRY_HOST>` с PAT из Gitea
(PAT в чат не попадает — rule `env-local`); тег — `BACKEND_TAG` в `.env`, дальше выкатка
`make bump SVC=backend TAG=<tag>`.

**Restic endpoint** живёт в `RESTIC_REPOSITORY` в `.env`. Оператор выбирает:
- external managed S3 (recommended для prod): `s3:https://s3.example.com/<p>-<env>-backups`
- bare-IP S3 на другом хосте: `s3:http://<ip>:9000/<p>-<env>-backups`
- local project minio (только rehearsal — хост уносит и репо): `s3:http://minio:9000/backups`

`RESTIC_PASSWORD` (в `.env`) **обязательно продублирован offsite** — без него restore из снапшотов невозможен.

### Day-2 workflow

После bootstrap'а — стандартный цикл изменений. Детали в smartdev skill (§ Deploy-флоу). Коротко:

```bash
make ship MSG="feat(foo): bar"   # add -A + commit + check + push + (на main) ssh-deploy
```

На чистом дереве MSG не нужен — просто push + deploy. Смена `COMPOSE_PROFILES` / значений в `.env` подхватывается `deploy.sh` (compose пересоздаёт затронутые сервисы сам).

### Verify

- `make ps` — always-on сервисы healthy.
- `https://${DOMAIN}/` — landing отдаётся через traefik + LE.
- `configs/traefik/traefik.yml` на VPS непустой (render отработал).

### Backup smoke-test (после активации storage профиля)

Daily backup гоняется внутри backup-контейнера (busybox crond, расписание в `containers/backup/crontab` — `0 3 * * * /usr/local/bin/backup-now`). Smoke прямо сейчас:

```bash
make backup
```

Должно завершиться успехом. Проверь в проектном Minio (или external endpoint) — `mc` внутри minio-контейнера (make-first исключение):
```bash
docker exec minio mc ls local/backups/
```

## Guard'рейлы

- **Не запускай ssh-hardening без проверки** что в `/root/.ssh/authorized_keys` есть твой ключ. Роль `ssh-hardening` обязана это assert'нуть, но дополнительно проверь руками.
- **Приватный deploy-key** (`/root/.ssh/<project>-deploy`) с VPS не выносим: в чат и в Gitea идёт
  только pubkey, который печатает onboard.
- **Креды tool-only.** Registry-PAT, токены — не эхо-ить значение в чат
  (подтверждай факт, не печатай секрет; `.claude/rules/env-local.md`). Connection к VPS для ops-вербов
  после bootstrap — в `.env.local` (workstation, gitignored), не хардкодь; `ssh.sh` читает его сам.
- **DNS-cutover до первого deploy** — иначе LE rate-limit съедает попытки выпуска.
- **Rehearsal — только staging**: production-лимиты LE сжигаются за день многократных итераций. Если режим rehearsal, а `ACME_CASERVER` в `.env` указывает на prod — поправь до deploy.
- **Production — только prod CA**: со staging клиент получит untrusted cert. Если режим production и видишь staging в `ACME_CASERVER` — стоп, перепроверь с юзером.

## После

- Записать в credentials store клиента: IP VPS, deploy-key fingerprint, копию `.env` (password-manager оператора).
- Создать `docs/incidents/` skeleton (если ещё нет).
