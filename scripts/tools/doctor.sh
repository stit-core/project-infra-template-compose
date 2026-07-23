#!/usr/bin/env bash
# Live fail-fast preflight. Каждая проверка → PASS / SKIP (неприменимо в
# текущем контексте) / WARN (advisory — корп засеет / DNS подтянется) /
# FAIL (актуально сломано и чинится локально). Каноничная строка:
#   OK            — ни одного FAIL (WARN/SKIP допустимы)
#   FAIL: <чек>   — есть hard-фейл, exit 1
#
# FAIL только на том, что точно ломает стек И actionable здесь (compose
# config invalid, .env без identity). DNS — WARN (traefik сам ретрайнет
# ACME, см. preflight-dns.sh). Поэтому на чистом лаптоп-чекауте
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

# 2. .env identity — без неё интерполяция compose и ACME-рендер не работают
if [ ! -f .env ]; then
  st ".env identity" SKIP "нет .env (pre-bootstrap)"
else
  # shellcheck disable=SC1091
  miss=$(. ./.env; for k in PROJECT_NAME ENV DOMAIN ACME_EMAIL; do
           [ -z "${!k:-}" ] && echo "$k"; done)
  if [ -z "$miss" ]; then
    st ".env identity" PASS
  else
    st ".env identity" FAIL "пусто: $(echo "$miss" | tr '\n' ' ')"
  fi
fi

# 3. configs отрендерены (render-configs.sh: envsubst *.tpl)
if [ ! -f .env ]; then
  st "configs render" SKIP "нет .env"
elif [ -s configs/traefik/traefik.yml ]; then
  st "configs render" PASS
else
  st "configs render" WARN "configs/traefik/traefik.yml пуст/нет — make render/deploy"
fi

# 4. DNS preflight (LE HTTP-01) — advisory, self-skip без .env
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

# 5. .env покрывает обязательные ключи .env.example
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
