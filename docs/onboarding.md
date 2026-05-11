# Onboarding — Day-0 / Day-1

End-to-end: от заказа VPS до работающего production-стека.

## Pre-requisites

- Купленный VPS (Debian 12 / Ubuntu 24.04, 2-4 GB RAM, 40+ GB disk).
- Pубликованный домен `<project>.com` с A-записью на IP VPS (нужно для Let's Encrypt HTTP-01).
- Доступ к корп-инфре stit.tech: Vault root token, Gitea admin (для создания репо + runner reg-token).
- Локально: ansible 2.15+, git, ssh.

## Day-0: Корп-сторона

### 1. Онбоардинг проекта в корп-Vault

На корп-VPS, оператор с Vault root-токеном:

```bash
ssh root@stit-corp 'cd /opt/stit-infra && VAULT_TOKEN=<root> bash scripts/onboard-project.sh acme'
```

Создаёт:
- `kv/observability/tenants/acme` (token + accountID)
- `kv/projects/acme/{db,oidc,jwt}` со stub'ами
- AppRole `project-acme` + scoped policy
- Возвращает `.env`-блок (PROJECT_NAME, VAULT_ROLE_ID/SECRET_ID, OTEL_*)

Сохрани вывод — он понадобится в шаге 4.

### 2. Засеять project-specific секреты (опционально на день-0)

Если уже знаешь OIDC/3rd-party креды — засей сразу:

```bash
cat > /tmp/acme-secrets.env <<EOF
oidc.client_id=acme-backend
oidc.client_secret=<from Authentik>
3rd-party.stripe.api_key=<sk_live_...>
EOF

ssh root@stit-corp 'cd /opt/stit-infra && VAULT_TOKEN=<root> bash scripts/seed-project-secrets.sh acme /tmp/acme-secrets.env'
```

Если нет — отложи до момента, когда сервис заработает на стандартных stub'ах.

### 3. Создать проектные репо в Gitea

Через UI (`https://git.stit.tech`) или API:

- `<org>/infra` — копия этого шаблона. Самый простой путь:
  ```bash
  git clone https://git.stit.tech/stit/project-infra-template-compose.git acme-infra
  cd acme-infra
  rm -rf .git && git init -b main
  git remote add origin https://git.stit.tech/<org>/infra.git
  ```
- `<org>/backend` — копия `stit/go-backend-template`.
- (опц) `<org>/frontend` / `<org>/worker`.

### 4. Получить Gitea-runner registration token

Gitea admin → Site Administration → Actions → Runners → **Create new runner**. Скопируй single-use token — попадёт в `.env` на проектном VPS.

## Day-1: Проектная сторона

### 5. Bootstrap чистого VPS

```bash
cd <client>-infra
cp ansible/inventory.example.ini ansible/inventory.ini
$EDITOR ansible/inventory.ini   # ansible_host, project_name, project_repo_url
ansible-playbook -i ansible/inventory.ini ansible/bootstrap.yml
```

Что произойдёт:
1. `base` — apt update, swap 2G, journald limits, sysctl tuning.
2. `ssh-hardening` — no password auth, root login key-only, fail2ban на :22.
3. `docker` — docker-ce + compose-plugin.
4. `stit-onboard` — `/opt/<project>-infra/`, ed25519 deploy key (печатает pubkey), clone из `<org>/infra` (упадёт на первом запуске — см. шаг 6).

### 6. Зарегистрировать deploy key в Gitea

Из вывода ansible скопируй pubkey, добавь в `<org>/infra` → Settings → Deploy Keys (read-only). Перезапусти clone:

```bash
ansible-playbook -i ansible/inventory.ini ansible/bootstrap.yml --tags onboard
```

### 7. Заполнить `.env` на VPS + сгенерить onboard-креды

```bash
ssh root@<vps>
cd /opt/acme-infra
PROJECT_NAME=acme DOMAIN=acme.com \
VAULT_ROLE_ID=<id> VAULT_SECRET_ID=<id> \
bash scripts/new-env.sh
```

Минимум — 4 значения; всё остальное (VAULT_ADDR, OTEL_*, ACME_EMAIL=ops@$DOMAIN, BACKEND_TAG=latest) выводится скриптом. Runner-токен/CrowdSec-key опциональны и заполняются позже руками. Создаст `.env` + `.onboard-creds` с правами 0600.

`.onboard-creds` содержит сгенерированные minio + restic креды. Скрипт выведет блок `vault kv put` команд — **отнеси корп-админу** для seed'а в Vault:

```bash
ssh root@stit-corp 'cd /opt/stit-infra && VAULT_TOKEN=<root> vault kv put kv/projects/acme/minio root_user=... ...'
ssh root@stit-corp 'cd /opt/stit-infra && VAULT_TOKEN=<root> vault kv put kv/projects/acme/backup password=...'
```

Без seed'а vault-agent залипает в retry-loop'е на `kv/projects/<p>/{minio,backup}` и стек не поднимается. RESTIC_PASSWORD из `.onboard-creds` **продублируй offsite** — без него restore из снапшотов невозможен. Повторно показать блок: `bash scripts/show-onboard-creds.sh`.

### 8. Первый деплой

С laptop'а оператора:
```bash
make remote-deploy
```

Или на VPS: `make deploy`.

Что произойдёт:
1. `render-configs.sh` рендерит `.tpl` → `.yml/.hcl`.
2. compose стартует vault-agent (логин по AppRole, рендер env-файлов в `.runtime/secrets/`).
3. Postgres + otel-agent + minio + minio-init + backup стартуют после vault-agent.healthy.
4. Traefik запрашивает LE-cert на публичные хосты (s3.${DOMAIN}, minio.${DOMAIN} сразу; api.${DOMAIN} — когда backend появится).
5. **Backend по умолчанию в `profiles: [backend]`** — поднимется только когда добавишь `COMPOSE_PROFILES=backend` (т.е. когда image в `git.stit.tech/<p>/backend` опубликован).
6. `gitea-runner` (`profiles: [ci]`) — не стартует по умолчанию; включи с `COMPOSE_PROFILES=ci` когда нужен CI.

### 9. Сгенерировать CrowdSec bouncer-key

CrowdSec нужно сказать Traefik'у API-key для bouncer plugin:

```bash
docker exec crowdsec cscli bouncers add traefik
# скопируй выведенный API key
$EDITOR /opt/acme-infra/.env   # CROWDSEC_BOUNCER_API_KEY=<key>
make deploy                     # перерендерит middlewares.yml.tpl + рестартанет traefik
```

### 10. Скопировать workflow в `<org>/backend`

В backend-репо:
```bash
mkdir -p .gitea/workflows
cp <инфра-шаблон>/ci/gitea/workflows/deploy.yml .gitea/workflows/deploy.yml
git add .gitea/ && git commit -m "ci: add deploy workflow"
git push origin main
```

В Gitea repo → Settings → Variables → добавь `PROJECT_NAME=acme`. Push на main → staging deploy. `git tag v0.1.0 && git push --tags` → prod deploy.

## Smoke-чек

```bash
# На VPS
make ps                                                # все сервисы healthy
docker exec backend wget -qO- http://localhost:8080/healthz
curl -fsS https://api.acme.com/healthz                 # через traefik+LE
docker exec vault-agent ls -la /secrets/               # rendered files
docker exec backup restic snapshots                    # пусто на старте; после первой ночи — snapshots
```

## Что должно работать "из коробки" после Day-1

- `https://api.<DOMAIN>/...` отдаёт backend.
- `docker logs backend` показывает trace IDs от OTel.
- В корп Grafana (`https://grafana.stit.tech`) при выборе variable `$tenant=<project>` в дашбордах **Cadvisor**, **Node Exporter Full** и в Explore (Loki/Tempo) видны host-метрики, контейнерные метрики, логи и трейсы проектной VPS.
- В корп Vault видны лизы (`vault list sys/leases/lookup/auth/approle/login`).
- На завтра в restic появляется snapshot за прошлую ночь.

## Если что-то сломалось — `docs/runbook.md`.
