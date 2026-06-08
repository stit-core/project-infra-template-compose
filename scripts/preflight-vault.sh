#!/usr/bin/env bash
# Vault preflight: проверка что AppRole логинится и core KV-paths существуют.
#
# Если корп ещё не засеял kv/projects/<p>/<env>/{otel,meta,db} — vault-agent
# залипнет в retry-loop'е, traefik / backend.env не отрендерятся и стек не
# поднимется. Лучше поймать с friendly-error здесь, чем после 3 минут compose-wait.
#
# minio + backup KV-paths намеренно НЕ требуются (lazy stack — Phase 2):
# они нужны только когда оператор активирует COMPOSE_PROFILES=storage.
#
# Не fail'ит deploy жёстко (см. PREFLIGHT_HARD): по дефолту печатает блок-
# инструкцию и продолжает — vault-agent сам ретрайнет когда корп засеет.
set -euo pipefail
cd "$(dirname "$0")/.."

[ -f .env ] || { echo "vault-preflight: .env отсутствует — skip"; exit 0; }
# shellcheck disable=SC1091
. ./.env

: "${VAULT_ROLE_ID:?VAULT_ROLE_ID обязателен}"
: "${VAULT_SECRET_ID:?VAULT_SECRET_ID обязателен}"
: "${PROJECT_NAME:?PROJECT_NAME обязателен}"
: "${ENV:?ENV обязателен (multi-env: dev/prod/...)}"

# Адрес корп Vault: managed-дефолт `vault.stit.tech`, self-hosted задаёт свой
# через VAULT_ADDR в .env (managed = инстанс sftbmb, self-hosted = форк
# corp-infra-template).
VAULT_ADDR="${VAULT_ADDR:-https://vault.stit.tech}"

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
  echo "vault-preflight: AppRole login failed. Проверь VAULT_ROLE_ID/SECRET_ID в .env" >&2
  echo "                 (а также что AppRole создан для PROJECT_NAME=$PROJECT_NAME ENV=$ENV)" >&2
  [ "$PREFLIGHT_HARD" = "1" ] && exit 2 || exit 0
}

token=$(printf '%s' "$login_json" | jq -r '.auth.client_token // empty')
[ -n "$token" ] || {
  echo "vault-preflight: AppRole login вернул пустой token. Vault: $login_json" >&2
  [ "$PREFLIGHT_HARD" = "1" ] && exit 2 || exit 0
}

# 3. Profile-aware required KV paths:
#    - always-on: meta (BACKEND_TAG, ACME_EMAIL, ACME_CASERVER) + otel (token).
#    - profile postgres: + db (POSTGRES_*)
#    - profile backend:  + db, oidc, jwt
#    - profile storage:  + minio, backup (+ db через postgres-валидацию deploy.sh)
required=("meta" "otel")
case ",${COMPOSE_PROFILES:-}," in *,postgres,*) required+=("db") ;; esac
case ",${COMPOSE_PROFILES:-}," in *,backend,*)  required+=("db" "oidc" "jwt") ;; esac
case ",${COMPOSE_PROFILES:-}," in *,storage,*)  required+=("minio" "backup") ;; esac

# dedup
declare -A _seen=()
uniq_required=()
for k in "${required[@]}"; do
  [ -n "${_seen[$k]:-}" ] && continue
  _seen[$k]=1
  uniq_required+=("$k")
done

missing=()
for kv in "${uniq_required[@]}"; do
  if ! curl_v -H "X-Vault-Token: $token" \
    "$VAULT_ADDR/v1/kv/data/projects/$PROJECT_NAME/$ENV/$kv" >/dev/null 2>&1; then
    missing+=("kv/projects/$PROJECT_NAME/$ENV/$kv")
  fi
done

if [ "${#missing[@]}" -gt 0 ]; then
  cat <<EOF >&2

vault-preflight: ВНИМАНИЕ — в Vault отсутствуют paths для активных профилей:
  COMPOSE_PROFILES=${COMPOSE_PROFILES:-(none — always-on stack)}
$(printf '  • %s\n' "${missing[@]}")

Стек не поднимется до seed'а. Что делать:
  meta/otel    — корп-сторона онбординга (onboard-project --envs $ENV)
  всё остальное — Claude skill /request-secret (.claude/skills/request-secret/) → корп-админ

EOF
  [ "$PREFLIGHT_HARD" = "1" ] && exit 2 || exit 0
fi

echo "vault-preflight: OK (AppRole login + KV paths для активных профилей: ${uniq_required[*]})"
