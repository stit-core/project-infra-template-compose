# project-infra-template-compose

IaC шаблон проектной инфры для stit.tech: docker-compose стек одного VPS на проект. Копируется в новый репо `<client-org>/infra`, дорабатывается под клиентский домен и стек, разворачивается за день.

## Что внутри

- **Edge:** Traefik v3 + CrowdSec (HTTP-01 LE, WAF, IP-bans).
- **Core:** Postgres 17, backend (image `git.stit.tech/<org>/backend`), vault-agent (sidecar для secrets).
- **Telemetry:** otel-agent — proxy на корп `otel.stit.tech` (OTLP + Bearer-token из Vault).
- **Backup:** restic-cron — daily в корп Minio (или клиентский S3).
- **CI/CD:** gitea-runner на проектном VPS, pull-based деплой через тэги.
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

2. Создать клиентский репо `<org>/infra` из этого шаблона — через UI **Use this template** или API (см. секцию выше). Затем склонировать локально:
   ```bash
   git clone git@git.stit.tech:<org>/infra.git && cd infra
   ```

3. Заполнить `.env` (на проектном VPS, в `/opt/<project>-infra/`) блоком из step 1 + клиентским доменом, BACKEND_TAG, restic-кредами.

4. Bootstrap чистого VPS:
   ```bash
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

7. Первый деплой:
   ```bash
   ssh root@<vps> 'cd /opt/<project>-infra && make deploy'
   ```

См. `docs/onboarding.md` для расширенной версии (DNS, runner registration, restore-from-backup).

## Принципы

- **Конфиг → код.** Всё декларативно в `compose/*.yml` и `configs/`. Никаких "только на сервере, в репо нет".
- **Секреты — только в Vault.** В `.env` лежат deployment-time facts + AppRole creds. Всё остальное vault-agent забирает на старте и рендерит в `.runtime/secrets/*.env`.
- **Изоляция per-project.** AppRole + scoped policy на корпе → проект A не читает секреты проекта B даже при компрометации VPS.
- **Pull-based deploy.** `git push v*` в `<org>/backend` → корп-Gitea-CI собирает image → проектный gitea-runner pull'ит и `make deploy`.

## Контракт с корпом

- `vault.stit.tech` — secrets backend. AppRole `project-<p>` создаётся `onboard-project.sh`.
- `otel.stit.tech` — observability ingest. Tenant routing по `service.namespace=<project>` + `Authorization: Bearer <OTEL_TOKEN>`.
- `git.stit.tech` — registry для backend/worker/frontend images.
- `s3.stit.tech` — restic backup destination (по умолчанию).

См. также `docs/project-secrets.md` в `stit/infra` для KV-схемы и rotation flow.
