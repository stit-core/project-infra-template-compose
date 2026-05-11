#!/usr/bin/env bash
# Повторно показать блок onboard-команд для корп-админа. Полезно когда блок
# потерялся в терминале/чате до того, как админ его засеял. Не перегенерит
# креды — читает .onboard-creds.
set -euo pipefail
cd "$(dirname "$0")/.."

[ -f .onboard-creds ] || { echo "ERR: .onboard-creds отсутствует — прогон \`scripts/new-env.sh\`." >&2; exit 1; }
[ -f .env ]           || { echo "ERR: .env отсутствует — прогон \`scripts/new-env.sh\`." >&2; exit 1; }

# shellcheck disable=SC1091
. .onboard-creds
PROJECT_NAME=$(awk -F= '/^PROJECT_NAME=/{print $2; exit}' .env)

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
EOF
