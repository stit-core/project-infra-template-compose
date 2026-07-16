#!/usr/bin/env bash
# Live fail-fast preflight. Каждая проверка → PASS / SKIP (неприменимо в
# текущем контексте) / WARN (advisory — корп засеет / DNS подтянется) /
# FAIL (актуально сломано и чинится локально). Каноничная строка:
#   OK            — ни одного FAIL (WARN/SKIP допустимы)
#   FAIL: <чек>   — есть hard-фейл, exit 1
#
# FAIL только на том, что точно ломает стек И actionable здесь (compose
# config invalid, .env без identity). DNS/Vault-seed — WARN (vault-agent
# сам ретрайнет, см. preflight-*.sh). Поэтому на чистом лаптоп-чекауте
# (нет .env/docker) doctor = OK (всё SKIP) — make check остаётся зелёным.
#
# Arg: --full — печатать захваченный stderr WARN/FAIL-проверок.
#
# Без set -e намеренно: doctor — диагностический оркестратор, он сам
# гоняет команды, которые ожидаемо падают (docker inspect отсутствующего
# контейнера, preflight без .env). Статус копится в $fail, не в exit-коде
# под-команд.
set -o pipefail
cd "$(dirname "$0")/../.."

FULL=0
[ "${1:-}" = "--full" ] && FULL=1

fail=0
declare -a failed=()

# st <name> <PASS|SKIP|WARN|FAIL> <note> [captured]
st() {
  printf "  %-16s %s%s\n" "$1" "$2" "${3:+ ($3)}"
  [ "$2" = "FAIL" ] && { fail=1; failed+=("$1"); }
  if [ "$FULL" = "1" ] && [ -n "${4:-}" ]; then
    printf '%s\n' "$4" | sed 's/^/      | /'
  fi
}

echo "== doctor =="

# 1. compose config — синтаксис при реальном .env
if ! command -v docker >/dev/null 2>&1; then
  st "compose config" SKIP "docker недоступен"
elif [ ! -f .env ]; then
  st "compose config" SKIP "нет .env"
else
  args=(-f docker-compose.yml)
  for f in compose/*.yml; do [ -f "$f" ] && args+=(-f "$f"); done
  if cap=$(docker compose "${args[@]}" --env-file .env config -q 2>&1); then
    st "compose config" PASS
  elif echo "$cap" | grep -qi 'cannot connect to the docker daemon\|is the docker daemon running'; then
    st "compose config" SKIP "docker daemon недоступен"
  else
    st "compose config" FAIL "невалидный compose" "$cap"
  fi
fi

# 2. .env identity — без неё AppRole-login и интерполяция не работают
if [ ! -f .env ]; then
  st ".env identity" SKIP "нет .env (pre-bootstrap)"
else
  # shellcheck disable=SC1091
  miss=$(. ./.env; for k in PROJECT_NAME ENV DOMAIN VAULT_ROLE_ID VAULT_SECRET_ID; do
           [ -z "${!k:-}" ] && echo "$k"; done)
  if [ -z "$miss" ]; then
    st ".env identity" PASS
  else
    st ".env identity" FAIL "пусто: $(echo "$miss" | tr '\n' ' ')"
  fi
fi

# 3. .runtime отрендерен (vault-agent пишет configs + secrets/*.env)
if [ ! -f .env ]; then
  st ".runtime render" SKIP "нет .env"
elif [ -s .runtime/configs/traefik.yml ]; then
  st ".runtime render" PASS
else
  st ".runtime render" WARN ".runtime/configs/traefik.yml пуст/нет — make render/deploy"
fi

# 4. vault-agent контейнер жив (рендерит секреты для consumer'ов)
if ! command -v docker >/dev/null 2>&1; then
  st "vault-agent" SKIP "docker недоступен"
else
  state=$(docker inspect -f '{{.State.Status}}' vault-agent 2>/dev/null | tr -d '[:space:]')
  case "$state" in
    running) st "vault-agent" PASS ;;
    "")      st "vault-agent" SKIP "контейнер не создан / docker daemon недоступен" ;;
    *)       st "vault-agent" WARN "state=$state — make logs SVC=vault-agent" ;;
  esac
fi

# 5. DNS preflight (LE HTTP-01) — advisory, self-skip без .env
if [ ! -f .env ]; then
  st "dns" SKIP "нет .env"
else
  cap=$(bash scripts/preflight-dns.sh 2>&1 || true)
  if echo "$cap" | grep -q 'DNS-WARN'; then
    st "dns" WARN "$(echo "$cap" | grep -c 'DNS-WARN') host(s) — cert не выпустится" "$cap"
  else
    st "dns" PASS
  fi
fi

# 6. Vault preflight (AppRole login + KV для активных профилей) — advisory
if [ ! -f .env ]; then
  st "vault KV" SKIP "нет .env"
else
  cap=$(bash scripts/preflight-vault.sh 2>&1 || true)
  if echo "$cap" | grep -q 'ВНИМАНИЕ'; then
    st "vault KV" WARN "missing KV-paths — /request-secret → корп" "$cap"
  elif echo "$cap" | grep -q 'недоступен\|login failed'; then
    st "vault KV" WARN "Vault недоступен / login fail" "$cap"
  else
    st "vault KV" PASS
  fi
fi

# 7. .env покрывает обязательные ключи .env.example
if [ ! -f .env ] || [ ! -f .env.example ]; then
  st ".env coverage" SKIP "нет .env / .env.example"
else
  req=$(grep -oE '^[A-Z_][A-Z0-9_]*=' .env.example | sed 's/=$//' | sort -u)
  miss=()
  while read -r k; do
    [ -z "$k" ] && continue
    grep -qE "^[[:space:]]*$k=" .env || miss+=("$k")
  done <<<"$req"
  if [ ${#miss[@]} -eq 0 ]; then
    st ".env coverage" PASS
  else
    st ".env coverage" WARN "нет в .env: ${miss[*]}"
  fi
fi

echo
if [ "$fail" -eq 0 ]; then
  echo "OK"
else
  echo "FAIL: ${failed[*]}"
  exit 1
fi
