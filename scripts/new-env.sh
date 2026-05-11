#!/usr/bin/env bash
# Bootstrap .env + onboard-creds на свежем проектном VPS.
#
# Корп-инфра (Vault/OTEL) зашита константами; от оператора нужны только
# 4 значения (PROJECT_NAME/DOMAIN/VAULT_ROLE_ID/VAULT_SECRET_ID). Дальше
# скрипт сам генерит minio-креды и restic-password, складывает их в
# .onboard-creds (chmod 600, gitignored) и печатает блок vault kv put
# команд, который оператор передаёт корп-админу для seed'а в Vault.
#
# Идемпотентно: повторный запуск НЕ перегенерит .onboard-creds (если
# уже есть) — повторно покажет тот же блок команд. Это важно для случая,
# когда блок потерялся в чате/терминале до того, как админ его засеял.
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

prompt() {
  # prompt VAR "Описание" [default]
  local var="$1" desc="$2" default="${3:-}" value
  if [ -n "${!var:-}" ]; then
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

# ───────── .env ─────────
if [ -f .env ]; then
  echo "NOTE: .env уже существует, не перегенерирую."
  # подхватим PROJECT_NAME из существующего .env — нужен для onboard-creds блока ниже
  PROJECT_NAME=$(awk -F= '/^PROJECT_NAME=/{print $2; exit}' .env)
  DOMAIN=$(awk -F= '/^DOMAIN=/{print $2; exit}' .env)
else
  echo "=== Project identity ==="
  prompt PROJECT_NAME "PROJECT_NAME (lowercase, e.g. acme)"
  prompt DOMAIN "DOMAIN (e.g. acme.com)"

  echo
  echo "=== Vault AppRole (из вывода корп onboard-project.sh) ==="
  prompt VAULT_ROLE_ID "VAULT_ROLE_ID"
  prompt VAULT_SECRET_ID "VAULT_SECRET_ID"

  VAULT_ADDR="${VAULT_ADDR:-$CORP_VAULT_ADDR}"
  OTEL_EXPORTER_OTLP_ENDPOINT="${OTEL_EXPORTER_OTLP_ENDPOINT:-$CORP_OTEL_ENDPOINT}"
  OTEL_EXPORTER_OTLP_INSECURE="${OTEL_EXPORTER_OTLP_INSECURE:-false}"
  ACME_EMAIL="${ACME_EMAIL:-ops@$DOMAIN}"
  # LE: prod по дефолту. При обкатке/тестах передавать
  # ACME_CASERVER=https://acme-staging-v02.api.letsencrypt.org/directory
  # через env-var (lim'ы prod LE тесные: 5 failed/host/hour, 5 dup/SAN/week).
  ACME_CASERVER="${ACME_CASERVER:-}"
  BACKEND_TAG="${BACKEND_TAG:-latest}"
  GITEA_RUNNER_REG_TOKEN="${GITEA_RUNNER_REG_TOKEN:-}"

  cat > .env <<EOF
# Сгенерировано scripts/new-env.sh. Правь руками после первого деплоя:
#   - CROWDSEC_BOUNCER_API_KEY: после \`cscli bouncers add traefik\`
#   - GITEA_RUNNER_REG_TOKEN:   one-shot токен из Gitea admin, если поднимаешь CI runner
# Runtime-секреты (DB, OIDC, JWT, S3, RESTIC) живут в Vault и рендерятся
# vault-agent'ом в .runtime/secrets/*.env. Onboard-блок для админа — в
# .onboard-creds (создан тем же new-env.sh).

PROJECT_NAME=$PROJECT_NAME
DOMAIN=$DOMAIN
ACME_EMAIL=$ACME_EMAIL
ACME_CASERVER=$ACME_CASERVER

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
  echo "OK: .env записан (chmod 0600).$([ -n "$ACME_CASERVER" ] && echo " LE staging endpoint выбран — сертификаты будут untrusted.")"
fi

# ───────── .onboard-creds ─────────
# Генерим minio + restic креды локально, чтобы оператор отнёс их корп-админу
# для seed'а в Vault. Без этих секретов в Vault стек не поднимется:
# vault-agent залипнет в retry-loop'е по kv/projects/<p>/{minio,backup}.

if [ -f .onboard-creds ]; then
  echo "NOTE: .onboard-creds уже существует, не перегенерирую (re-print ниже)."
  # shellcheck disable=SC1091
  . .onboard-creds
else
  gen() { openssl rand -hex "$1"; }
  MINIO_ROOT_USER="${MINIO_ROOT_USER:-admin}"
  MINIO_ROOT_PASSWORD="$(gen 24)"
  APP_S3_ACCESS_KEY="$(gen 12)"
  APP_S3_SECRET_KEY="$(gen 24)"
  BACKUP_S3_ACCESS_KEY="$(gen 12)"
  BACKUP_S3_SECRET_KEY="$(gen 24)"
  RESTIC_PASSWORD="$(gen 32)"

  umask 077
  cat > .onboard-creds <<EOF
# Сгенерировано scripts/new-env.sh. НЕ КОММИТИТЬ (gitignored, chmod 600).
# Эти креды нужны корп-админу для seed'а в Vault. После seed'а stay-here
# как back-up; rotation — через корп-сторону (vault kv put + redeploy).
# RESTIC_PASSWORD ОБЯЗАТЕЛЬНО продублируй offsite (без него restore невозможен).
MINIO_ROOT_USER='$MINIO_ROOT_USER'
MINIO_ROOT_PASSWORD='$MINIO_ROOT_PASSWORD'
APP_S3_ACCESS_KEY='$APP_S3_ACCESS_KEY'
APP_S3_SECRET_KEY='$APP_S3_SECRET_KEY'
BACKUP_S3_ACCESS_KEY='$BACKUP_S3_ACCESS_KEY'
BACKUP_S3_SECRET_KEY='$BACKUP_S3_SECRET_KEY'
RESTIC_PASSWORD='$RESTIC_PASSWORD'
EOF
  chmod 0600 .onboard-creds
  echo "OK: .onboard-creds записан (chmod 0600)."
fi

# ───────── Блок для корп-админа ─────────
cat <<EOF

================================================================================
ОТНЕСИ ЭТО КОРП-АДМИНУ (stit/infra). До seed'а — стек НЕ поднимется.
Команды для корп-Vault (требуется VAULT_TOKEN с правами kv.write на kv/projects/):
--------------------------------------------------------------------------------
vault kv put kv/projects/$PROJECT_NAME/minio \\
  root_user='$MINIO_ROOT_USER' \\
  root_password='$MINIO_ROOT_PASSWORD' \\
  app_access_key='$APP_S3_ACCESS_KEY' \\
  app_secret_key='$APP_S3_SECRET_KEY' \\
  backup_access_key='$BACKUP_S3_ACCESS_KEY' \\
  backup_secret_key='$BACKUP_S3_SECRET_KEY'

vault kv put kv/projects/$PROJECT_NAME/backup \\
  password='$RESTIC_PASSWORD'
--------------------------------------------------------------------------------
После seed'а — \`bash scripts/deploy.sh\` (или \`make deploy\`) на VPS.
Блок снова показать: \`bash scripts/show-onboard-creds.sh\`.
================================================================================

Дальше — деплой:
  bash scripts/deploy.sh           # на VPS
  # либо локально с laptop'а оператора:
  make remote-deploy               # ssh → VPS → deploy

Опционально (по мере появления):
  • Backend:   COMPOSE_PROFILES=backend bash scripts/deploy.sh
               (image должен быть опубликован в git.stit.tech/$PROJECT_NAME/backend)
  • CrowdSec:  docker exec crowdsec cscli bouncers add traefik
               → CROWDSEC_BOUNCER_API_KEY в .env → redeploy
  • Runner:    bash scripts/register-runner.sh
EOF
