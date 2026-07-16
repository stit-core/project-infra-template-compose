#!/usr/bin/env bash
# Bootstrap .env на свежем проектном VPS.
#
# Multi-env: на каждом VPS свой ENV (dev/prod/...) и свой AppRole.
# .env минимален: identity (PROJECT_NAME, ENV, DOMAIN) + AppRole-bootstrap
# + image-теги (<SVC>_TAG — бампаются строго через .env, `make bump`).
# Всё остальное (acme email/caServer, restic endpoint, runtime секреты)
# живёт в Vault — корп-сторона засеивает при онбординге (meta+otel)
# и по запросу через skill `/request-secret` (печатает блок vault kv put).
#
# Non-interactive:
#   PROJECT_NAME=acme ENV=prod DOMAIN=acme.com \
#   VAULT_ROLE_ID=... VAULT_SECRET_ID=... \
#   bash scripts/new-env.sh
#
# Interactive: bash scripts/new-env.sh
set -euo pipefail
cd "$(dirname "$0")/.."

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

if [ -f .env ]; then
  echo "NOTE: .env уже существует, не перегенерирую."
  PROJECT_NAME=$(awk -F= '/^PROJECT_NAME=/{print $2; exit}' .env)
  ENV=$(awk -F= '/^ENV=/{print $2; exit}' .env)
else
  echo "=== Project identity ==="
  prompt PROJECT_NAME "PROJECT_NAME (lowercase, e.g. acme)"
  prompt ENV          "ENV (dev/prod/...; должен совпадать с env'ом в kv/projects/<p>/_meta)"
  prompt DOMAIN       "DOMAIN (e.g. acme.com)"

  echo
  echo "=== Vault AppRole (из вывода корп onboard-project --envs ...) ==="
  prompt VAULT_ROLE_ID   "VAULT_ROLE_ID"
  prompt VAULT_SECRET_ID "VAULT_SECRET_ID"

  cat > .env <<EOF
# Сгенерировано scripts/new-env.sh. См. .env.example для контракта.
# Vault-managed конфиг (acme email/caServer, restic endpoint) и
# runtime-секреты — в kv/projects/$PROJECT_NAME/$ENV/*.
# Image-теги — строго здесь (<SVC>_TAG, бамп через \`make bump\`), не в Vault.

PROJECT_NAME=$PROJECT_NAME
ENV=$ENV
DOMAIN=$DOMAIN

VAULT_ROLE_ID=$VAULT_ROLE_ID
VAULT_SECRET_ID=$VAULT_SECRET_ID

# Profile-based opt-in. По мере того, как корп засеивает соответствующие
# kv/projects/$PROJECT_NAME/$ENV/<kind>, добавляй сюда profile (через запятую):
#   postgres  — нужен kv/.../db
#   storage   — нужен kv/.../minio + kv/.../backup (+ postgres профиль)
#   backend   — нужен kv/.../{db,oidc,jwt} + BACKEND_TAG ниже
# COMPOSE_PROFILES=

# Image-тег backend; раскомментировать вместе с профилем backend.
# Бамп — \`make bump SVC=backend TAG=<tag>\`.
# BACKEND_TAG=

CROWDSEC_BOUNCER_API_KEY=
EOF
  chmod 0600 .env
  echo "OK: .env записан (chmod 0600)."
fi

cat <<EOF

================================================================================
Минимальный стек (traefik + vault-agent + crowdsec + otel-agent + node-exporter
+ cadvisor + landing) поднимется как только корп засеит kv/projects/$PROJECT_NAME/$ENV/{meta,otel}.
Это происходит при \`onboard-project --envs $ENV\` на корп-стороне.

Запусти:
  make ship      # с workstation; либо \`make deploy\` напрямую на VPS

По мере необходимости — запрашивай seed'ы вторичных секретов через Claude:
  /request-secret               # skill в .claude/skills/request-secret/

Claude сформирует блок \`vault kv put kv/projects/$PROJECT_NAME/$ENV/<name>\`
с правильными значениями (генерит пароли где надо) — отдай корп-админу.
После seed'а — обнови COMPOSE_PROFILES в .env и \`make ship\`.
================================================================================
EOF
