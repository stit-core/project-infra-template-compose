---
name: bootstrap-vps
description: Поднять новый клиентский VPS с нуля — ansible-bootstrap, регистрация deploy-key в Gitea, заполнение .env, первый make deploy. Multi-env (один VPS = один ENV). Активируй на "/bootstrap-vps", "новый VPS", "подними сервер для клиента", "первый запуск".
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
| **production** | "клиентский VPS", "новый проект", "поднимаем для <client>", реальный домен заранее настроен | LE prod (`acme-v02.api.letsencrypt.org`) | Дефолт `kv/projects/<p>/<env>/meta.acme_caserver` |
| **rehearsal** | "обкатка", "обкатываю шаблон", "тестовый прогон", "пробую заново", "тестовый VPS", "буду повторять bootstrap" | LE staging (`acme-staging-v02.api.letsencrypt.org`) — untrusted, rate-limits ~100× выше | Корп-админ patch'ит `meta.acme_caserver` на staging URL перед первым deploy'ем |

**Почему важно:** LE prod лимиты тесные:
- 5 failed validations / hostname / hour
- 5 duplicate certs / SAN-set / week
- 50 certs / registered domain / week

При rehearsal (DNS ещё не настроен → failed challenges, многократный teardown/redeploy → duplicate certs) лимит сжигается за день. Staging — те же API, лимиты ~30k/week.

Контроль на корп-стороне: `acme_caserver` живёт в `kv/projects/<p>/<env>/meta` (засеивается `onboard-project.sh`). Если режим rehearsal — оператор просит корп-админа выставить staging URL при онбординге **либо** patch'ит после:
```bash
vault kv patch kv/projects/acme/dev/meta acme_caserver=https://acme-staging-v02.api.letsencrypt.org/directory
```

**Migration prod ↔ staging на том же VPS:** acme.json привязан к CA-серверу:
```bash
docker compose <args> down traefik
docker volume rm <p>-infra_traefik-acme
# на корп-стороне: vault kv patch kv/projects/<p>/<env>/meta acme_caserver=<new>
make ship  # vault-agent перерендерит traefik.yml, traefik подымется с новым CA
```

## Когда НЕ применять

- Re-deploy на уже работающий хост — это `make deploy` / `make ship`.
- Onboarding пользователя в Gitea — корп-задача (skill `onboard-user` в `stit-infra/infra`).
- Bug на проде — диагностика, не bootstrap.

## Предусловия (СПРОСИ юзера)

1. **Корп-сторона онбоарднула проект и нужный ENV?** На `stit-infra/infra`:
   ```bash
   VAULT_TOKEN=<root> bash scripts/onboard-project.sh \
     --name <p> --envs dev,prod \
     --source-ip dev=<vps-egress-ip>,prod=<vps-egress-ip>
   ```
   Создаст per-env AppRole + засеит `kv/projects/<p>/<env>/{meta,otel}`. Вернёт блок `PROJECT_NAME / ENV / VAULT_ROLE_ID / VAULT_SECRET_ID` для каждого env. Без этого делать нечего.

   `--source-ip` пишет egress-IP проектной VPS в корп CrowdSec whitelist. Без него otel-collector UA попадает под `crowdsecurity/http-bad-user-agent` и весь трафик с проектной VPS режется 403'ами (метрики/логи перестанут доходить до `otel.stit.tech`). Можно опустить флаг, если IP заранее неизвестен — добавляется потом `echo` в `configs/crowdsec/whitelists.yaml` + `docker compose restart crowdsec` на корп-VPS (см. `stit-infra/infra/.claude/rules/crowdsec-whitelist.md`).

2. **VPS provisioned**, у тебя есть IP и root-доступ по SSH ключу (минимум один ключ в `/root/.ssh/authorized_keys`).

3. **DNS** для `${DOMAIN}` (а также `api.${DOMAIN}` etc. — по сабдоменам, которые будут активированы позже) указывает на IP VPS — нужно для HTTP-01 ACME challenge.

4. **Gitea-репо** `<client-org>/infra` существует и склонирован из шаблона `project-infra-template-compose`.

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
PROJECT_NAME=<p> ENV=<env> DOMAIN=<d> \
VAULT_ROLE_ID=<id> VAULT_SECRET_ID=<id> \
bash scripts/new-env.sh
```

Создаёт `.env` (chmod 600) с **5 переменными** — identity + AppRole. Всё остальное (image tags, ACME-config, restic endpoint, runtime-секреты) приходит из Vault.

`.env` содержит **закомментированную** строку `# COMPOSE_PROFILES=` — будешь раскомментировать по мере активации сервисов (см. шаг 7).

**Rehearsal-режим** — добавь шаг до первого deploy'я:
```bash
# на корп-стороне
vault kv patch kv/projects/<p>/<env>/meta acme_caserver=https://acme-staging-v02.api.letsencrypt.org/directory
```

### 6. Первый деплой — always-on стек

С laptop'а оператора:
```bash
make ship          # commit + push + (на main) ssh-deploy
```

Либо на VPS (debug-mode со пошаговым stdout):
```bash
ssh root@<IP>
cd /opt/<project>-infra
make deploy
```

Что произойдёт:
1. `render-configs.sh` собирает `agent.hcl` из `agent.hcl.parts/` под пустой `COMPOSE_PROFILES` (только always-on блок) + envsubst для middlewares/landing + генерит `.runtime/configs/vault-health.sh`.
2. `compose up vault-agent` → AppRole-логин, рендер `.runtime/{env/compose.env, configs/traefik.yml, secrets/otel.env, secrets/.ready}` из `kv/projects/<p>/<env>/{meta,otel}`.
3. CrowdSec early для bouncer auto-register.
4. Остальные always-on: traefik / otel-agent / node-exporter / cadvisor / landing.
5. Traefik запрашивает LE-cert на `${DOMAIN}` (landing).

**Если что-то не поднимается:**
- vault-agent не healthy / retry-loop на `kv/.../meta` или `kv/.../otel` → корп не онбоарднул env (см. предусловия). `bash scripts/preflight-vault.sh` покажет какие KV-paths отсутствуют.
- LE cert не выпустился → DNS не указывает на VPS, или 80/443 закрыты файрволом.
- crowdsec bouncer auto-register не сработал → fallback `docker exec crowdsec cscli bouncers add traefik`, прописать в `.env`, `make deploy`.

### 7. Активация дополнительных профилей (по мере необходимости)

Каждый сервис кроме always-on'а — за `COMPOSE_PROFILES`. Активация требует двух шагов:
1. Корп-админ засевает соответствующий KV-объект.
2. Оператор обновляет `COMPOSE_PROFILES` в `.env` и `make ship`.

Запросить scaffold для админа — Claude skill `/request-secret` (см. `.claude/skills/request-secret/SKILL.md`). Skill спросит имя KV-объекта (произвольный slug: `db`, `minio`, `backup`, `oidc`, `jwt`, project-specific), сгенерит случайные поля где надо, напечатает блок `vault kv put kv/projects/<p>/<env>/<name>` для копи-паста админу.

После seed'а — на VPS:
```bash
$EDITOR .env   # COMPOSE_PROFILES=postgres,storage,backend
make ship
```

**Storage обязательно с postgres** (backup делает pg_dumpall, без postgres сразу падает — deploy.sh валидирует, ругнётся явно).

**Restic endpoint** живёт в `kv/projects/<p>/<env>/backup.repository`. Корп-админ выбирает:
- external managed S3 (recommended для prod): `s3:https://s3.example.com/<p>-<env>-backups`
- bare-IP S3 на другом хосте: `s3:http://<ip>:9000/<p>-<env>-backups`
- local project minio (ТОЛЬКО rehearsal): `s3:http://minio:9000/backups`

`RESTIC_PASSWORD` (в `.../backup.password`) **обязательно продублирован offsite** — без него restore из снапшотов невозможен. Это политика корп-стороны.

### Day-2 workflow

После bootstrap'а — стандартный цикл изменений. Детали в smartdev skill (§ Deploy-флоу). Коротко:

```bash
make ship MSG="feat(foo): bar"   # add -A + commit + push + (на main) ssh-deploy
```

На чистом дереве MSG не нужен — просто push + deploy. Смена `COMPOSE_PROFILES` в `.env` подхватывается `deploy.sh` (rerender agent.hcl + force-recreate vault-agent + consumer'ов).

### Verify

- `make ps` — always-on сервисы healthy.
- `https://${DOMAIN}/` — landing отдаётся через traefik + LE.
- `docker exec vault-agent ls -la /secrets/ /env /configs` — rendered файлы.
- `docker logs otel-agent | tail -5` — нет auth-ошибок при экспорте в `otel.stit.tech`.
- `docker logs vault-agent | tail -10` — successful render, нет re-auth циклов.

### Backup smoke-test (после активации storage профиля)

Daily backup гоняется внутри backup-контейнера (busybox crond, расписание в `containers/backup/crontab` — `0 3 * * * /usr/local/bin/backup-now`). Smoke прямо сейчас:

```bash
make backup
```

Должно завершиться успехом. Проверь в проектном Minio (или external endpoint):
```bash
docker exec minio mc ls local/backups/
```

## Guard'рейлы

- **Не запускай ssh-hardening без проверки** что в `/root/.ssh/authorized_keys` есть твой ключ. Роль `ssh-hardening` обязана это assert'нуть, но дополнительно проверь руками.
- **Не публикуй deploy-key из stdout/log'а** — это секрет. Передай оператору приватным каналом.
- **DNS-cutover до первого deploy** — иначе LE rate-limit съедает попытки выпуска.
- **Rehearsal → ВСЕГДА staging** — production LE сжигается за день многократных итераций. Если режим rehearsal, но `meta.acme_caserver` указывает на prod — это твоя ошибка, проси корп-патч.
- **Production → НИКОГДА staging** — клиент получит untrusted cert. Если режим production и видишь staging в `kv/.../meta.acme_caserver` — стоп, перепроверь с юзером.

## После

- Записать в credentials store клиента: IP VPS, deploy-key fingerprint, `.env` хеш / Vaultwarden ссылку.
- На корп-стороне — добавить uptime-kuma monitor на `https://${DOMAIN}/`.
- Создать `docs/incidents/` skeleton (если ещё нет).
