#!/usr/bin/env bash
# Bootstrap .env на свежем проектном VPS. Корп-инфра (Vault/OTEL) зашита
# константами; от оператора нужны только 4 значения. Можно передать через
# env-vars (non-interactive) или ввести интерактивно.
#
# Non-interactive:
#   PROJECT_NAME=acme DOMAIN=acme.com \
#   VAULT_ROLE_ID=... VAULT_SECRET_ID=... \
#   bash scripts/new-env.sh
#
# Interactive: bash scripts/new-env.sh
set -euo pipefail
cd "$(dirname "$0")/.."

# ───────── Корп-инфра (одинакова для всех проектных VPS) ─────────
CORP_VAULT_ADDR="https://vault.stit.tech"
CORP_OTEL_ENDPOINT="otel.stit.tech:443"

if [ -f .env ]; then
  echo "ERR: .env уже существует. Правь вручную или удали." >&2
  exit 1
fi

prompt() {
  # prompt VAR "Описание" [default]
  local var="$1" desc="$2" default="${3:-}" value
  if [ -n "${!var:-}" ]; then
    # уже задано через env — используем без вопросов
    printf -v "$var" '%s' "${!var}"
    return
  fi
  if [ -n "$default" ]; then
    read -r -p "$desc [$default]: " value
    value="${value:-$default}"
  else
    read -r -p "$desc: " value
  fi
  [ -z "$value" ] && { echo "ERR: $var обязателен" >&2; exit 1; }
  printf -v "$var" '%s' "$value"
}

echo "=== Project identity ==="
prompt PROJECT_NAME "PROJECT_NAME (lowercase, e.g. acme)"
prompt DOMAIN "DOMAIN (e.g. acme.com)"

echo
echo "=== Vault AppRole (из вывода корп onboard-project.sh) ==="
prompt VAULT_ROLE_ID "VAULT_ROLE_ID"
prompt VAULT_SECRET_ID "VAULT_SECRET_ID"

# Опциональные перекрытия — только для редких кейсов (другой Vault/OTEL/email/tag).
VAULT_ADDR="${VAULT_ADDR:-$CORP_VAULT_ADDR}"
OTEL_EXPORTER_OTLP_ENDPOINT="${OTEL_EXPORTER_OTLP_ENDPOINT:-$CORP_OTEL_ENDPOINT}"
OTEL_EXPORTER_OTLP_INSECURE="${OTEL_EXPORTER_OTLP_INSECURE:-false}"
ACME_EMAIL="${ACME_EMAIL:-ops@$DOMAIN}"
BACKEND_TAG="${BACKEND_TAG:-latest}"
GITEA_RUNNER_REG_TOKEN="${GITEA_RUNNER_REG_TOKEN:-}"

cat > .env <<EOF
# Сгенерировано scripts/new-env.sh. Правь руками после первого деплоя:
#   - CROWDSEC_BOUNCER_API_KEY: после \`cscli bouncers add traefik\`
#   - GITEA_RUNNER_REG_TOKEN:   one-shot токен из Gitea admin, если поднимаешь CI runner
# Бэкап-креды (RESTIC/AWS) живут в Vault (kv/data/projects/$PROJECT_NAME/backup);
# vault-agent рендерит их в .runtime/secrets/backup.env при включённом backup-template.

PROJECT_NAME=$PROJECT_NAME
DOMAIN=$DOMAIN
ACME_EMAIL=$ACME_EMAIL

VAULT_ADDR=$VAULT_ADDR
VAULT_ROLE_ID=$VAULT_ROLE_ID
VAULT_SECRET_ID=$VAULT_SECRET_ID

OTEL_EXPORTER_OTLP_ENDPOINT=$OTEL_EXPORTER_OTLP_ENDPOINT
OTEL_EXPORTER_OTLP_INSECURE=$OTEL_EXPORTER_OTLP_INSECURE
OTEL_TENANT=$PROJECT_NAME

BACKEND_TAG=$BACKEND_TAG

CROWDSEC_BOUNCER_API_KEY=

GITEA_RUNNER_REG_TOKEN=$GITEA_RUNNER_REG_TOKEN
EOF
chmod 0600 .env

cat <<EOF

OK: .env записан (chmod 0600). Корп-инфра зашита:
  VAULT_ADDR  = $VAULT_ADDR
  OTEL        = $OTEL_EXPORTER_OTLP_ENDPOINT

Дальше — деплой:
  bash scripts/deploy.sh           # на VPS
  # либо локально с laptop'а оператора:
  make remote-deploy               # ssh → VPS → deploy

Опционально (по мере появления):
  • Backend:   COMPOSE_PROFILES=backend bash scripts/deploy.sh
  • Backup:    раскомментируй backup-template в configs/vault-agent/agent.hcl.tpl
               + COMPOSE_PROFILES=backup ...   (нужно kv/projects/$PROJECT_NAME/backup в Vault)
  • CrowdSec:  docker exec crowdsec cscli bouncers add traefik
               → CROWDSEC_BOUNCER_API_KEY в .env → redeploy
  • Runner:    bash scripts/register-runner.sh
EOF
