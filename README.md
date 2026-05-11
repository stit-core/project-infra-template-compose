# project-infra-template-compose

IaC шаблон проектной инфры для stit.tech: docker-compose стек одного VPS на проект. Копируется в новый репо `<client-org>/infra`, дорабатывается под клиентский домен и стек, разворачивается за день.

## Что внутри

- **Edge:** Traefik v3 + CrowdSec (HTTP-01 LE, WAF, IP-bans).
- **Core:** Postgres 17, backend (image `git.stit.tech/<client-org>/backend`, opt-in), vault-agent (sidecar для secrets).
- **Telemetry:** otel-agent — proxy на корп `otel.stit.tech` (OTLP + Bearer-token из Vault).
- **Storage:** Minio (S3-compat), on by default — bucket `app-uploads` для backend, `backups` для restic.
- **Backup:** self-contained контейнер (alpine + restic + pg_dumpall + busybox crond), daily в restic-репо `$RESTIC_REPOSITORY` (дефолт — `s3:http://minio:9000/backups`, внутренний minio через docker network). Для prod / off-site менять endpoint в `.env`.
- **Bootstrap:** ansible (apt + swap + journald + ssh-hardening + docker).

См. `docs/architecture.md` для деталей.

## Использовать как шаблон

В Gitea этот репо помечен `template: true`. Старт нового проекта:

1. Открыть https://git.stit.tech/stit/project-infra-template-compose → **Use this template** → создать `<client-org>/infra`.
2. Дальше идти по Day-0 quickstart ниже — шаг 2 уже выполнен (репо создан, история чистая).

Альтернатива через Gitea API:
```bash
curl -X POST -H "Authorization: token $GITEA_TOKEN" -H "Content-Type: application/json" \
  -d '{"owner":"<client-org>","name":"infra","private":true}' \
  https://git.stit.tech/api/v1/repos/generate \
  --url-query 'template_owner=stit' --url-query 'template_repo=project-infra-template-compose'
```

## Day-0 quickstart

1. На корп-стороне (`stit/infra`):
   ```bash
   VAULT_TOKEN=<root> bash scripts/onboard-project.sh acme
   ```
   Получаешь блок `.env`-переменных + AppRole.

2. Создать клиентский репо `<client-org>/infra` из этого шаблона — через UI **Use this template** или API (см. секцию выше). Затем склонировать локально:
   ```bash
   git clone git@git.stit.tech:<client-org>/infra.git && cd infra
   ```

3. Заполнить `.env` + сгенерить onboard-креды (на проектном VPS, в `/opt/<project>-infra/`):
   ```bash
   PROJECT_NAME=acme DOMAIN=acme.com \
   VAULT_ROLE_ID=<id> VAULT_SECRET_ID=<id> \
   bash scripts/new-env.sh
   ```
   Создаст `.env` (chmod 600) + `.onboard-creds` (chmod 600, gitignored) с
   сгенерированными minio-кредами и RESTIC_PASSWORD. Выведет блок
   `vault kv put` команд — **отнеси корп-админу**, без seed'а стек не
   поднимется (vault-agent залипнет в retry-loop'е). Повторно показать:
   `bash scripts/show-onboard-creds.sh`.

4. Bootstrap чистого VPS:
   ```bash
   # Один раз — SSH ключ на VPS (либо задай operator_ssh_pubkey в inventory.ini):
   ssh-copy-id root@<vps>

   ansible-playbook -i ansible/inventory.ini ansible/bootstrap.yml
   ```

5. На VPS залогиниться в registry (для pull image'ей):
   ```bash
   ssh root@<vps>
   docker login git.stit.tech -u <user> -p <PAT>      # PAT из gitea: Settings → Applications
   ```

6. (Опц., но **сильно рекомендовано** при ручной сборке с dev-машины)
   Whitelist'нуть IP dev-машины в корпном CrowdSec, иначе `docker push`
   быстро триггерит `crowdsecurity/http-probing` бан:
   ```bash
   # на корп-VPS
   bash /opt/stit-infra/scripts/onboard-project.sh <project> --source-ip <dev-ip>
   ```
   (Если проект уже onboard'ен — отредактируй `configs/crowdsec/whitelists.yaml`
   и `docker compose ... restart crowdsec` руками.)

7. Первый деплой — c laptop'а оператора:
   ```bash
   make ship          # commit + push + (на main) ssh-deploy. На чистом дереве MSG не нужен.
   ```
   Minio + backup поднимаются по дефолту. Backend opt-in: image должен быть
   опубликован в `git.stit.tech/<p>/backend` → `COMPOSE_PROFILES=backend make deploy`.

См. `docs/onboarding.md` для расширенной версии (DNS, restore-from-backup).

## Принципы

- **Конфиг → код.** Всё декларативно в `compose/*.yml` и `configs/`. Никаких "только на сервере, в репо нет".
- **Секреты — только в Vault.** В `.env` лежат deployment-time facts + AppRole creds. Всё остальное vault-agent забирает на старте и рендерит в `.runtime/secrets/*.env`.
- **Изоляция per-project.** AppRole + scoped policy на корпе → проект A не читает секреты проекта B даже при компрометации VPS.
- **Локальный CI.** Билд/тесты backend-образа гоняются у разработчика; `make ship` пушит код + ssh-деплоит. Никаких gitea-runner'ов / webhook'ов / push-trigger'ов на сервере.

## Контракт с корпом

- `vault.stit.tech` — secrets backend. AppRole `project-<p>` создаётся `onboard-project.sh`.
- `otel.stit.tech` — observability ingest. Tenant routing по `service.namespace=<project>` + `Authorization: Bearer <OTEL_TOKEN>`.
- `git.stit.tech` — registry для backend/worker/frontend images.

(Backup по дефолту пишет в **проектный** Minio на том же VPS — это не off-site DR, а удобная отправная точка. Если хост умрёт целиком, бэкапы умрут вместе с базой. Для off-site менять `RESTIC_REPOSITORY` в `.env` на внешний S3 / корп-Minio.)

См. также `docs/project-secrets.md` в `stit/infra` для KV-схемы и rotation flow.
