#!/usr/bin/env bash
# Interactive bootstrap of .env on a fresh project VPS.
# Prompts for project facts, paste-friendly block from corp onboard.
set -euo pipefail
cd "$(dirname "$0")/.."

if [ -f .env ]; then
  echo "ERR: .env already exists. Edit it manually or remove first." >&2
  exit 1
fi

prompt() {
  local var="$1" desc="$2" default="${3:-}" value
  if [ -n "$default" ]; then
    read -r -p "$desc [$default]: " value
    value="${value:-$default}"
  else
    read -r -p "$desc: " value
  fi
  printf -v "$var" '%s' "$value"
}

echo "=== Project identity ==="
prompt PROJECT_NAME "PROJECT_NAME (lowercase, e.g. acme)"
prompt DOMAIN "DOMAIN (e.g. acme.com)"
prompt ACME_EMAIL "ACME_EMAIL (LE notifications)" "ops@$DOMAIN"

echo
echo "=== Vault AppRole (paste from corp onboard-project.sh output) ==="
prompt VAULT_ROLE_ID "VAULT_ROLE_ID"
prompt VAULT_SECRET_ID "VAULT_SECRET_ID"
prompt VAULT_ADDR "VAULT_ADDR" "https://vault.stit.tech"

echo
echo "=== Telemetry routing ==="
prompt OTEL_EXPORTER_OTLP_ENDPOINT "OTEL_EXPORTER_OTLP_ENDPOINT" "otel.stit.tech:443"
prompt OTEL_EXPORTER_OTLP_INSECURE "OTEL_EXPORTER_OTLP_INSECURE" "false"
OTEL_TENANT="$PROJECT_NAME"

echo
echo "=== Image tags ==="
prompt BACKEND_TAG "BACKEND_TAG" "latest"

echo
echo "=== Backup (restic) ==="
prompt RESTIC_REPOSITORY "RESTIC_REPOSITORY" "s3:https://s3.stit.tech/backups-$PROJECT_NAME"
prompt RESTIC_PASSWORD "RESTIC_PASSWORD (32+ random chars)" "$(openssl rand -hex 32)"
prompt AWS_ACCESS_KEY_ID "AWS_ACCESS_KEY_ID (corp Minio key)"
prompt AWS_SECRET_ACCESS_KEY "AWS_SECRET_ACCESS_KEY"

echo
echo "=== Gitea runner registration ==="
prompt GITEA_RUNNER_REG_TOKEN "GITEA_RUNNER_REG_TOKEN (one-shot from Gitea admin UI)" ""

CROWDSEC_BOUNCER_API_KEY=""

cat > .env <<EOF
PROJECT_NAME=$PROJECT_NAME
DOMAIN=$DOMAIN
ACME_EMAIL=$ACME_EMAIL

VAULT_ADDR=$VAULT_ADDR
VAULT_ROLE_ID=$VAULT_ROLE_ID
VAULT_SECRET_ID=$VAULT_SECRET_ID

OTEL_EXPORTER_OTLP_ENDPOINT=$OTEL_EXPORTER_OTLP_ENDPOINT
OTEL_EXPORTER_OTLP_INSECURE=$OTEL_EXPORTER_OTLP_INSECURE
OTEL_TENANT=$OTEL_TENANT

BACKEND_TAG=$BACKEND_TAG

CROWDSEC_BOUNCER_API_KEY=$CROWDSEC_BOUNCER_API_KEY

RESTIC_REPOSITORY=$RESTIC_REPOSITORY
RESTIC_PASSWORD=$RESTIC_PASSWORD
AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID
AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY

GITEA_RUNNER_REG_TOKEN=$GITEA_RUNNER_REG_TOKEN
EOF
chmod 0600 .env

cat <<EOF

OK: .env written (chmod 0600).

Next:
  1. First deploy:                bash scripts/deploy.sh
  2. CrowdSec bouncer key:        docker exec crowdsec cscli bouncers add traefik
                                  (paste API key into CROWDSEC_BOUNCER_API_KEY in .env, redeploy)
  3. Register gitea-runner:       bash scripts/register-runner.sh
                                  (or set GITEA_RUNNER_REG_TOKEN before first deploy and let runner self-register)

If OIDC / 3rd-party API keys are needed, seed them on corp side via
  VAULT_TOKEN=<root> bash scripts/seed-project-secrets.sh $PROJECT_NAME <env-file>
EOF
