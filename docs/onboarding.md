# Onboarding — Day-0 / Day-1

End-to-end: от заказа VPS до работающего production-стека. Multi-env: один проект имеет N сред (`dev`, `prod`, ...) — **N отдельных VPS**, по одному на ENV.

## Pre-requisites

- Куплены VPS (Debian 12 / Ubuntu 24.04, 2-4 GB RAM, 40+ GB disk) — по одному на env.
- Опубликованы домены для каждого env с A-записью на IP соответствующего VPS (для LE HTTP-01). Convention — `<env>.<domain>` или `<env>-<domain>`, но это outside шаблона.
- Доступ к корп-инфре stit.tech: Vault root token, Gitea admin.
- Локально: ansible 2.15+, git, ssh.

## Day-0: Корп-сторона

### 1. Онбоардинг проекта в корп-Vault

На корп-VPS, оператор с Vault root-токеном:

```bash
ssh root@stit-corp 'cd /opt/stit-infra && \
  VAULT_TOKEN=<root> bash scripts/onboard-project.sh --name acme --envs dev,prod'
```

Создаёт per-env:
- AppRole `projects-acme-<env>` (flat — Vault не принимает слеши в `auth/approle/role/<name>`) + policy `projects-acme-<env>-read` на `kv/data/projects/acme/<env>/*` (read) и `kv/metadata/projects/acme/<env>/*` (read,list).
- `kv/projects/acme/<env>/otel` — bearer token + accountID для отправки телеметрии в `otel.stit.tech`.
- `kv/projects/acme/<env>/meta` — default'ы (`backend_tag=latest`, `acme_email=ops@<domain>`, `acme_caserver=<prod LE>`).

Возвращает по одному блоку на env:
```
=== acme / dev ===
PROJECT_NAME=acme
ENV=dev
VAULT_ROLE_ID=<id>
VAULT_SECRET_ID=<id>
```

Сохрани вывод — пригодится в Day-1 шаг 6.

### 2. Создать проектные репо в Gitea

Через UI (`https://git.stit.tech`) или API:

- `<org>/infra` — копия `stit-infra/project-infra-template-compose`.
- `<org>/backend` — копия `stit-infra/go-backend-template` (когда backend нужен).
- (опц) `<org>/frontend` / `<org>/worker`.

## Day-1: Проектная сторона (каждый VPS отдельно)

### 3. Bootstrap чистого VPS

```bash
git clone https://git.stit.tech/<org>/infra.git && cd infra
cp ansible/inventory.example.ini ansible/inventory.ini
$EDITOR ansible/inventory.ini   # ansible_host, project_name, project_repo_url, operator_ssh_pubkey
# Один раз — SSH ключ на VPS:
ssh-copy-id root@<vps>
ansible-playbook -i ansible/inventory.ini ansible/bootstrap.yml
```

Что произойдёт:
1. `base` — apt update, swap 2G, journald limits, sysctl tuning.
2. `ssh-hardening` — no password auth, root login key-only, fail2ban на :22.
3. `docker` — docker-ce + compose-plugin.
4. `stit-onboard` — `/opt/<project>-infra/`, ed25519 deploy key (печатает pubkey), clone из `<org>/infra` (упадёт на первом запуске — см. шаг 4).

### 4. Зарегистрировать deploy key в Gitea

Из вывода ansible скопируй pubkey, добавь в `<org>/infra` → Settings → Deploy Keys (read-only). Перезапусти clone:

```bash
ansible-playbook -i ansible/inventory.ini ansible/bootstrap.yml --tags onboard
```

### 5. Залогиниться в registry

```bash
ssh root@<vps>
docker login git.stit.tech -u <user> -p <PAT>      # PAT из gitea: Settings → Applications
```

### 6. Заполнить `.env` на VPS

```bash
ssh root@<vps>
cd /opt/<project>-infra
PROJECT_NAME=acme ENV=prod DOMAIN=acme.com \
VAULT_ROLE_ID=<id> VAULT_SECRET_ID=<id> \
bash scripts/new-env.sh
```

Создаст `.env` (chmod 600) с 5 переменными. Всё остальное — в Vault (засеется по мере необходимости через шаг 8). CrowdSec-key заполняется автоматически на первом deploy'е.

`.env` содержит **закомментированную** строку `# COMPOSE_PROFILES=` — будешь раскомментировать по мере активации сервисов (см. шаг 8).

### 7. Первый деплой — минимальный стек

С laptop'а оператора:
```bash
make ship          # commit + push + (на main) ssh-deploy
```

Или на VPS (debug-mode со пошаговым stdout): `make deploy`.

Что произойдёт:
1. `render-configs.sh` собирает `agent.hcl` из `agent.hcl.parts/` под активный `COMPOSE_PROFILES` (на старте — пусто, только always-on) + envsubst для middlewares/landing.
2. Compose стартует vault-agent (логин по AppRole, рендер `.runtime/{env,secrets,configs}/*` из `kv/projects/<p>/<env>/{meta,otel}`).
3. Always-on сервисы (traefik / crowdsec / otel-agent / node-exporter / cadvisor / landing) стартуют после vault-agent healthy.
4. Traefik запрашивает LE-cert на `${DOMAIN}` (landing).
5. CrowdSec bouncer auto-register на первом подъёме — заполняет `CROWDSEC_BOUNCER_API_KEY` в `.env`.

### 8. Активация дополнительных профилей

По мере того, как нужны postgres / storage / backend — запрашиваешь seed и активируешь profile:

Через Claude skill (`.claude/skills/request-secret/`):
- `/request-secret` — Claude спросит NAME (любой slug: `db`, `minio`, `backup`, `oidc`, `jwt`, `stripe-key`, ...), поля + значения; сгенерит случайные где нужно (`openssl rand`).

Печатает stdout-блок `vault kv put kv/projects/<p>/<env>/<name>` готовый для копи-паста. Отдай корп-админу, он выполнит.

После seed'а — на VPS отредактируй `.env`:
```
COMPOSE_PROFILES=postgres,storage,backend
```
(storage обязательно с postgres — backup делает pg_dumpall; deploy.sh валидирует.)

`make ship` (без MSG, чистое дерево → push + deploy). При смене `COMPOSE_PROFILES` deploy.sh:
- rerender'ит `agent.hcl` с новыми template-блоками,
- restart'ит vault-agent,
- force-recreate consumer'ов (env_file читается только при container CREATE).

## Smoke-чек

```bash
make ps                                                # все сервисы healthy
docker exec vault-agent ls -la /secrets/               # rendered env-files
docker exec vault-agent cat /env/compose.env           # BACKEND_TAG из Vault
docker exec backup restic snapshots                    # после первой ночи — snapshots
curl -fsS https://${DOMAIN}/                           # landing через traefik+LE
```

## Что должно работать "из коробки"

- `https://${DOMAIN}` отдаёт landing (или backend на `api.${DOMAIN}` после активации профиля).
- `docker logs backend` показывает trace IDs от OTel.
- В корп Grafana (`https://grafana.stit.tech`) при выборе variable `$tenant=<project>-<env>` видны host/контейнерные метрики, логи и трейсы соответствующей VPS.
- В корп Vault видны лизы (`vault list sys/leases/lookup/auth/approle/login`).
- После первой ночи в restic появляется snapshot.

## Ротация секрета централизованно

```bash
# корп-сторона
vault kv patch kv/projects/acme/prod/db password=<new>
```

Vault-agent на VPS заметит, перерендерит `.runtime/secrets/{postgres,backend,backup}.env`. Чтобы consumer'ы перечитали — на следующем `make ship` deploy.sh force-recreate'нет. Без deploy'я можно вручную: `docker compose ... up -d --no-deps --force-recreate <consumer>`.

## Если что-то сломалось — `docs/runbook.md`.
