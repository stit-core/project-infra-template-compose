#!/usr/bin/env bash
# Vault preflight: проверка что AppRole логинится и нужные KV-paths
# существуют. Если корп ещё не засеял kv/projects/<p>/{minio,backup} —
# vault-agent залипнет в retry-loop'е, стек не поднимется. Лучше поймать
# это здесь с friendly-error, чем после 3 минут compose-wait.
#
# Не fail'ит deploy жёстко на отсутствующих KV (см. флаг PREFLIGHT_HARD):
# по дефолту печатает блок-инструкцию для оператора и продолжает —
# vault-agent сам ретрайнет когда корп засеет.
set -euo pipefail
cd "$(dirname "$0")/.."

[ -f .env ] || { echo "vault-preflight: .env отсутствует — skip"; exit 0; }
# shellcheck disable=SC1091
. ./.env

: "${VAULT_ADDR:?VAULT_ADDR обязателен}"
: "${VAULT_ROLE_ID:?VAULT_ROLE_ID обязателен}"
: "${VAULT_SECRET_ID:?VAULT_SECRET_ID обязателен}"
: "${PROJECT_NAME:?PROJECT_NAME обязателен}"

PREFLIGHT_HARD="${PREFLIGHT_HARD:-0}"

curl_v() { curl -fsS --max-time 8 "$@"; }

# 1. Vault reachable?
if ! curl_v "$VAULT_ADDR/v1/sys/health" >/dev/null 2>&1; then
  echo "vault-preflight: $VAULT_ADDR недоступен (сетевая ошибка / DNS / firewall)" >&2
  [ "$PREFLIGHT_HARD" = "1" ] && exit 2 || exit 0
fi

# 2. AppRole login.
login_json=$(curl_v -X POST -H "Content-Type: application/json" \
  -d "{\"role_id\":\"$VAULT_ROLE_ID\",\"secret_id\":\"$VAULT_SECRET_ID\"}" \
  "$VAULT_ADDR/v1/auth/approle/login" 2>/dev/null) || {
  echo "vault-preflight: AppRole login failed. Проверь VAULT_ROLE_ID/SECRET_ID в .env." >&2
  [ "$PREFLIGHT_HARD" = "1" ] && exit 2 || exit 0
}

token=$(printf '%s' "$login_json" | jq -r '.auth.client_token // empty')
[ -n "$token" ] || {
  echo "vault-preflight: AppRole login вернул пустой token. Vault: $login_json" >&2
  [ "$PREFLIGHT_HARD" = "1" ] && exit 2 || exit 0
}

# 3. KV paths — kv/data/projects/<p>/{minio,backup}. Без них vault-agent
# залипнет в retry-loop'е и .runtime/secrets/{minio,backup}.env будут пустые.
missing=()
for kv in minio backup; do
  if ! curl_v -H "X-Vault-Token: $token" \
    "$VAULT_ADDR/v1/kv/data/projects/$PROJECT_NAME/$kv" >/dev/null 2>&1; then
    missing+=("kv/projects/$PROJECT_NAME/$kv")
  fi
done

if [ "${#missing[@]}" -gt 0 ]; then
  cat <<EOF >&2

vault-preflight: ВНИМАНИЕ — в Vault отсутствуют:
  $(printf '  • %s\n' "${missing[@]}")

Стек поднимется, но vault-agent залипнет в retry-loop'е, minio + backup
не получат свои секреты. Прогон \`bash scripts/show-onboard-creds.sh\` и
отдай блок \`vault kv put\` корп-админу.

EOF
  [ "$PREFLIGHT_HARD" = "1" ] && exit 2 || exit 0
fi

echo "vault-preflight: OK (AppRole login + kv/projects/$PROJECT_NAME/{minio,backup} доступны)"
