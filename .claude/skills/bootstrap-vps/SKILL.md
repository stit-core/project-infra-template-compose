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

### 1. Inventory

`ansible/inventory.ini` (gitignored — создаётся локально):

```ini
[project_vps]
<client>-prod ansible_host=<IP> ansible_user=root

[project_vps:vars]
project_name=<client>
project_repo_url=https://git.stit.tech/<client-org>/infra.git
```

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

### 5. Заполнить .env

На VPS:

```bash
ssh root@<IP>
cd /opt/<project>-infra
bash scripts/new-env.sh
```

Скрипт интерактивный — он попросит:
- `PROJECT_NAME`, `DOMAIN`, `ACME_EMAIL`
- `VAULT_ROLE_ID` / `VAULT_SECRET_ID` / `VAULT_ADDR` (paste из onboard-блока)
- `OTEL_*`
- `BACKEND_TAG` (image версия)
- `RESTIC_*` + `AWS_*` (для backup в корп Minio)
- `GITEA_RUNNER_REG_TOKEN` (опционально, можно пустым — потом через `register-runner.sh`)

В конце — `.env` создан с `chmod 0600`.

### 6. Первый деплой

```bash
make deploy
```

Что произойдёт:
1. `git pull --ff-only` (no-op на первом запуске).
2. `scripts/render-configs.sh` — envsubst для `.tpl` (vault-agent agent.hcl, traefik middlewares).
3. `docker compose up -d --wait --wait-timeout 120`:
   - Traefik стартует, пытается выпустить LE certs (HTTP-01).
   - vault-agent аутентифицируется в Vault, рендерит `.runtime/secrets/*.env`, выставляет `.ready`.
   - Postgres стартует.
   - Backend ждёт vault-agent + postgres, потом стартует.
   - otel-agent стартует, форвардит в `otel.stit.tech`.

**Если что-то не поднимается** — `docker compose logs <svc>` для конкретного сервиса. Типовые проблемы:
- vault-agent не healthy → AppRole creds в `.env` неправильные / Vault unreachable.
- LE cert не выпустился → DNS не указывает на VPS, или 80/443 закрыты файрволом.
- backend падает → секреты в `.runtime/secrets/backend.env` не сматчили image-expectations.

### 7. CrowdSec bouncer key

После первого подъёма CrowdSec'а:

```bash
docker exec crowdsec cscli bouncers add traefik
```

Скопируй API-key, обнови `CROWDSEC_BOUNCER_API_KEY` в `.env`, `make deploy` (или `make restart SVC=traefik`).

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

```bash
make backup
```

Должно завершиться успехом. Проверь на корп-Minio: `mc ls corp/backups-<project>/` — должен появиться initial snapshot.

## Guard'рейлы

- **Не запускай ssh-hardening без проверки** что в `/root/.ssh/authorized_keys` есть твой ключ. Роль `ssh-hardening` обязана это assert'нуть, но дополнительно проверь руками — `ansible -m shell -a 'cat /root/.ssh/authorized_keys' project_vps`.
- **Не публикуй deploy-key из stdout/log'а** — это секрет. Передай оператору приватным каналом.
- **DNS-cutover до первого deploy** — иначе LE rate-limit съедает попытки выпуска.

## После

- Записать в credentials store клиента: IP VPS, deploy-key fingerprint, `.env` хеш / Vaultwarden ссылку.
- На корп-стороне — добавить uptime-kuma monitor на `https://api.${DOMAIN}/healthz`.
- Создать `docs/incidents/` skeleton (если ещё нет).
