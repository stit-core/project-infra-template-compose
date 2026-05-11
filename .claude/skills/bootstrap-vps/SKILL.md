---
name: bootstrap-vps
description: Поднять новый клиентский VPS с нуля — ansible-bootstrap, регистрация deploy-key в Gitea, заполнение .env, первый make deploy. Активируй на "/bootstrap-vps", "новый VPS", "подними сервер для клиента", "первый запуск".
---

# Skill: bootstrap-vps

Provisioning нового VPS под клиентский проект. Цель — за один проход довести машину от чистой Debian/Ubuntu до состояния "сервисы крутятся, healthchecks зелёные".

## Когда применять

- "Подними новый VPS для <client>"
- "Новый сервер, начнём с нуля"
- "Перенос на новый хост" (после `dr-restore` для данных)
- "/bootstrap-vps"

## Когда НЕ применять

- Re-deploy на уже работающий хост — это `make deploy`.
- Onboarding пользователя в Gitea — это корп-задача (skill `onboard-user` в `stit/infra`).
- Bug на проде — диагностика, не bootstrap.

## Предусловия (СПРОСИ юзера)

1. **Корп-сторона онбоарднула проект?** На `stit/infra` оператор выполнил:
   ```bash
   VAULT_TOKEN=<root> bash scripts/onboard-project.sh <project>
   ```
   На выходе — блок с `PROJECT_NAME`, `VAULT_ROLE_ID`, `VAULT_SECRET_ID`, `OTEL_*`. Без этого блока на проектной стороне делать нечего.

2. **Дополнительные секреты seed'нуты?** Если backend ожидает OIDC client_secret или 3rd-party API keys — на корп-стороне:
   ```bash
   bash scripts/seed-project-secrets.sh <project> <env-file>
   ```

3. **VPS provisioned**, у тебя есть IP и root-доступ по SSH ключу (минимум один ключ в `/root/.ssh/authorized_keys` уже на хосте).

4. **DNS** для `${DOMAIN}` (и `api.${DOMAIN}`, прочие сабдомены) указывает на IP VPS — нужно для HTTP-01 ACME challenge.

5. **Gitea-репо** `<client-org>/infra` существует и склонирован из шаблона `project-infra-template-compose`. Адаптации (image org, домен) — внесены в файлы.

Без любого из этих пунктов — стопори, проси подготовить.

## Шаги

### 1. Inventory + SSH key

`ansible/inventory.ini` (gitignored — создаётся локально, скопируй из `inventory.example.ini`):

```ini
[project_vps]
prod ansible_host=<IP> ansible_user=root project_name=<p> project_repo_url=git@git.stit.tech:<org>/infra.git

[project_vps:vars]
ansible_python_interpreter=/usr/bin/python3
operator_ssh_pubkey="ssh-ed25519 AAAAC3Nz... operator@laptop"
```

Если SSH key-auth уже работает (например `ssh-copy-id root@<vps>` запущен заранее) — `operator_ssh_pubkey` можно оставить пустым. Иначе — base-role положит pubkey в `/root/.ssh/authorized_keys` до ssh-hardening (и hardening не залочит хост).

Verify connectivity: `ansible -i ansible/inventory.ini project_vps -m ping`.

### 2. Bootstrap playbook (без onboard)

```bash
ansible-playbook -i ansible/inventory.ini ansible/bootstrap.yml --skip-tags onboard
```

Прогоняет roles `base` → `ssh-hardening` → `docker`. По итогам — VPS с Docker engine, ssh-hardened (passwords disabled, проверь что у тебя ключ в authorized_keys ДО запуска), системные пакеты.

**Если playbook падает** — фикси и re-run, он идемпотентен.

### 3. Deploy-key для Gitea

Роль `stit-onboard` (запускаемая отдельно) сгенерирует deploy-key в `/root/.ssh/id_ed25519_<project>` и выведет публичную часть. Чтобы её получить без полного onboard:

```bash
ansible-playbook -i ansible/inventory.ini ansible/bootstrap.yml --tags onboard --start-at-task "Generate deploy key"
```

(Точное имя таска проверь в `ansible/roles/stit-onboard/tasks/main.yml`.)

Скопируй public-key, **попроси оператора зарегистрировать его в Gitea**:
- Settings → Deploy Keys → Add → paste pub-key, read-only
- На клиентский репо `<client-org>/infra`

### 4. Onboard (clone repo)

После регистрации deploy-key:

```bash
ansible-playbook -i ansible/inventory.ini ansible/bootstrap.yml --tags onboard
```

Это склонирует репо в `/opt/<project>-infra`.

### 5. Заполнить .env + сгенерить onboard-креды

На VPS:

```bash
ssh root@<IP>
cd /opt/<project>-infra
PROJECT_NAME=<p> DOMAIN=<d> VAULT_ROLE_ID=<id> VAULT_SECRET_ID=<id> bash scripts/new-env.sh
```

Создаёт **два файла** (оба chmod 600, gitignored):
- `.env` — bootstrap-vars (PROJECT_NAME, DOMAIN, VAULT_*, OTEL_*, BACKEND_TAG)
- `.onboard-creds` — сгенерированные `openssl rand` minio-креды + RESTIC_PASSWORD

В конце выводит **блок `vault kv put` команд** — отнеси корп-админу для seed'а в Vault (`kv/projects/<p>/minio` + `kv/projects/<p>/backup`). Без seed'а vault-agent залипнет в retry-loop'е → стек не поднимется.

**Stop** на этом шаге, пока админ не подтвердит seed.

Повторно показать блок (если терялся): `bash scripts/show-onboard-creds.sh`.

`RESTIC_PASSWORD` из `.onboard-creds` ОБЯЗАТЕЛЬНО продублируй offsite (без него restore из снапшотов невозможен).

### 6. Первый деплой

С laptop'а оператора (после bootstrap'а — у тебя уже есть SSH-доступ и inventory.ini):
```bash
make remote-deploy
```

Либо на самом VPS:
```bash
ssh root@<IP>
cd /opt/<project>-infra
make deploy
```

Minio + backup поднимаются по дефолту (после Vault seed'а). Backend остаётся opt-in — image должен быть опубликован в `git.stit.tech/<project>/backend:<tag>` → `COMPOSE_PROFILES=backend make deploy`.

Что произойдёт при первом `deploy`:
1. `git pull --ff-only` (no-op на первом запуске).
2. `scripts/render-configs.sh` — envsubst для `.tpl` (vault-agent agent.hcl, traefik middlewares).
3. `docker compose up -d --wait --wait-timeout 180`:
   - vault-agent аутентифицируется в Vault, рендерит `.runtime/secrets/*.env`, выставляет `.ready`.
   - Postgres + minio + backup + otel-agent + crowdsec стартуют после vault-agent.healthy.
   - minio-init создаёт bucket'ы (app-uploads, backups) и service accounts из minio.env.
   - Traefik стартует, LE-certs выпустятся на публичные роуты (s3.${DOMAIN}, minio.${DOMAIN} сразу).

**Если что-то не поднимается** — `docker compose logs <svc>` для конкретного сервиса. Типовые проблемы:
- vault-agent не healthy / retry-loop на kv/projects/<p>/{minio,backup} → корп не засеял Vault (см. шаг 5).
- minio-init упал с `<no value>` в bucket name → Vault поле `buckets` отсутствует — это не блокер, шаблон даёт пустую строку → дефолт `app-uploads`. Если видишь старый сбой — обнови `configs/vault-agent/templates/minio.env.tpl`.
- LE cert не выпустился → DNS не указывает на VPS, или 80/443 закрыты файрволом.
- backend падает → секреты в `.runtime/secrets/backend.env` не сматчили image-expectations.

### Day-2 workflow

После bootstrap'а — стандартный цикл изменений шаблона / правок:

```bash
# 1. правки локально (compose, configs, и т.п.)
git add -p && git commit -m "feat(...): ..."
make ship                 # push текущей ветки; если main — авто-remote-deploy
                          # если не main — открой PR в Gitea, мержи, потом git pull && make ship
```

Если хочешь только триггернуть деплой (без push): `make remote-deploy`.

### 7. CrowdSec bouncer key

`scripts/deploy.sh` автоматически дёргает `cscli bouncers add traefik` при первом подъёме, прописывает ключ в `.env` и перерендеривает traefik dynamic config — ручной шаг не нужен. Если по какой-то причине auto-register не сработал, fallback:

```bash
docker exec crowdsec cscli bouncers add traefik
```

Скопируй API-key, обнови `CROWDSEC_BOUNCER_API_KEY` в `.env`, `make deploy`.

### 8. Gitea-runner (если нужен)

Если runner не самозарегистрировался через `GITEA_RUNNER_REG_TOKEN`:

```bash
bash scripts/register-runner.sh
```

(Получит one-shot token из Gitea admin UI, зарегистрирует.)

### 9. Verify

- `make ps` — все сервисы healthy.
- `https://api.${DOMAIN}/healthz` — backend отвечает 200.
- `docker logs otel-agent | tail -5` — нет auth-ошибок при экспорте в `otel.stit.tech`.
- `docker logs vault-agent | tail -10` — successful render, нет re-auth циклов.

### 10. Backup smoke-test

Host-cron для daily backup ставится ansible'ом (`stit-onboard` role): `0 3 * * * docker exec backup /usr/local/bin/run-backup.sh >> /var/log/<p>-backup.log`. Smoke прямо сейчас:

```bash
make backup
```

Должно завершиться успехом. Проверь в проектном Minio:
```bash
docker exec minio mc ls local/backups/
```
После первого backup-run появятся restic-объекты (config, snapshots/, data/).

## Guard'рейлы

- **Не запускай ssh-hardening без проверки** что в `/root/.ssh/authorized_keys` есть твой ключ. Роль `ssh-hardening` обязана это assert'нуть, но дополнительно проверь руками — `ansible -m shell -a 'cat /root/.ssh/authorized_keys' project_vps`.
- **Не публикуй deploy-key из stdout/log'а** — это секрет. Передай оператору приватным каналом.
- **DNS-cutover до первого deploy** — иначе LE rate-limit съедает попытки выпуска.

## После

- Записать в credentials store клиента: IP VPS, deploy-key fingerprint, `.env` хеш / Vaultwarden ссылку.
- На корп-стороне — добавить uptime-kuma monitor на `https://api.${DOMAIN}/healthz`.
- Создать `docs/incidents/` skeleton (если ещё нет).
