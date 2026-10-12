#!/usr/bin/env bash
# Live fail-fast preflight. Каждая проверка → PASS / SKIP (неприменимо в
# текущем контексте) / WARN (advisory — DNS подтянется, render догонит deploy,
# ключ профиля ещё не дописан в .env) / FAIL (актуально сломано и чинится
# локально). Каноничная строка:
#   OK            — ни одного FAIL (WARN/SKIP допустимы)
#   FAIL: <чек>   — есть hard-фейл, exit 1
#
# FAIL только на том, что точно ломает стек И actionable здесь (compose
# config invalid, .env без identity, строка .env не той формы, замок не-прод
# среды, с которым не войти, Docker Engine старше 25 при профиле site, пустой
# тег образа включённого сервиса).
# DNS — WARN (traefik сам ретрайнет ACME, см. preflight-dns.sh).
# Поэтому на чистом лаптоп-чекауте (нет .env/docker) doctor = OK (всё SKIP) —
# make check остаётся зелёным.
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

# .env preflight считается раньше проверок, которые читают .env шеллом и compose: на
# строке не той формы они сами печатают её кусок — хеш, пароль. Такие проверки при
# отказе preflight пропускаются.
env_rc=0; env_cap=""
if [ -f .env ]; then env_cap=$(bash scripts/preflight-env.sh 2>&1); env_rc=$?; fi
env_skip=".env не читается — см. .env preflight"

# 1. Docker Engine — ключу healthcheck.start_interval (compose/site.yml) нужен Engine ≥ 25:
#    на старом движке такой контейнер не создаётся, а плагин compose тех лет не
#    разбирает сам файл — тогда красный и compose config ниже.
if ! command -v docker >/dev/null 2>&1; then
  st "docker engine" SKIP "docker недоступен"
elif [ ! -f .env ]; then
  st "docker engine" SKIP "нет .env"
else
  ver=$(docker version --format '{{.Server.Version}}' 2>/dev/null)
  need=$(grep -lE '^[^#]*start_interval:' compose/*.yml 2>/dev/null | paste -sd' ' -)
  case "${ver%%.*}" in
    ''|*[!0-9]*) st "docker engine" SKIP "${ver:+версия не разобрана: }${ver:-docker daemon недоступен}" ;;
    *)
      if [ "${ver%%.*}" -ge 25 ] || [ -z "$need" ]; then
        st "docker engine" PASS "$ver"
      else
        # FAIL — сервис с этим ключом уже включён: всегда поднят или его профиль активен
        # (имя профиля — имя файла); иначе WARN: деплой сломает включение профиля.
        sev=WARN
        profiles=",$(sed -nE 's/^COMPOSE_PROFILES=//p' .env | tail -n 1 | tr -d "\"'"),"
        for f in $need; do
          p=$(basename "$f" .yml)
          grep -qE '^[[:space:]]*profiles:' "$f" || sev=FAIL
          case "$profiles" in *",$p,"*) sev=FAIL ;; esac
        done
        st "docker engine" "$sev" "$ver — $need: healthcheck.start_interval требует Engine ≥ 25; обновление — docs/reference/runbook.md"
      fi ;;
  esac
fi

# 2. compose config — синтаксис при реальном .env
if ! command -v docker >/dev/null 2>&1; then
  st "compose config" SKIP "docker недоступен"
elif [ ! -f .env ]; then
  st "compose config" SKIP "нет .env"
elif [ "$env_rc" -ne 0 ]; then
  st "compose config" SKIP "$env_skip"
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

# 3. .env identity — без неё интерполяция compose и ACME-рендер не работают
if [ ! -f .env ]; then
  st ".env identity" SKIP "нет .env (pre-bootstrap)"
elif [ "$env_rc" -ne 0 ]; then
  st ".env identity" SKIP "$env_skip"
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

# 4. .env preflight — форма строк, замок не-прод среды и пара её контуров; тот же
#    скрипт останавливает make render, make deploy и ops-вербы
if [ ! -f .env ]; then
  st ".env preflight" SKIP "нет .env"
else
  note=$(printf '%s\n' "$env_cap" | sed -n 's/^ENV-[A-Z]*: //p' | head -n 1)
  if [ "$env_rc" -ne 0 ]; then
    st ".env preflight" FAIL "${note:-scripts/preflight-env.sh: код $env_rc}" "$env_cap"
  elif [ -n "$note" ]; then
    st ".env preflight" WARN "$note" "$env_cap"
  else
    st ".env preflight" PASS
  fi
fi

# 5. configs отрендерены (render-configs.sh: envsubst *.tpl)
if [ ! -f .env ]; then
  st "configs render" SKIP "нет .env"
elif [ -s configs/traefik/traefik.yml ]; then
  st "configs render" PASS
else
  st "configs render" WARN "configs/traefik/traefik.yml пуст/нет — make render/deploy"
fi

# 6. DNS preflight (LE HTTP-01) — advisory, self-skip без .env
if [ ! -f .env ]; then
  st "dns" SKIP "нет .env"
elif [ "$env_rc" -ne 0 ]; then
  st "dns" SKIP "$env_skip"
else
  cap=$(bash scripts/preflight-dns.sh 2>&1 || true)
  if echo "$cap" | grep -q 'DNS-WARN'; then
    st "dns" WARN "$(echo "$cap" | grep -c 'DNS-WARN') host(s) — cert не выпустится" "$cap"
  else
    st "dns" PASS
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

# 8. Тег образа сервис-репо (${<SVC>_TAG}) у включённого сервиса не пуст: с пустым make deploy
#    падает на ссылке образа (invalid reference format). Первый тег ставит make bump.
if [ ! -f .env ]; then
  st "image tags" SKIP "нет .env"
elif [ "$env_rc" -ne 0 ]; then
  st "image tags" SKIP "$env_skip"
else
  profiles=",$(sed -nE 's/^COMPOSE_PROFILES=//p' .env | tail -n 1 | tr -d "\"'"),"
  empty=""
  for f in compose/*.yml; do
    var=$(sed -nE 's/^[[:space:]]*image:.*\$\{([A-Z0-9_]+_TAG)\}.*/\1/p' "$f" | head -n 1)
    [ -n "$var" ] || continue
    p=$(sed -nE 's/^[[:space:]]*profiles:[[:space:]]*\[[[:space:]]*([a-z0-9_-]+).*/\1/p' "$f" | head -n 1)
    if [ -n "$p" ]; then case "$profiles" in *",$p,"*) ;; *) continue ;; esac; fi
    [ -n "$(sed -n "s/^$var=//p" .env | tail -n 1 | tr -d "\"'")" ] || empty="$empty $var"
  done
  if [ -z "$empty" ]; then st "image tags" PASS
  else st "image tags" FAIL "пусто при включённом профиле:$empty — make deploy упадёт; первый тег — make bump SVC=<svc> TAG=<тег>"; fi
fi

# 9. Список источников allowlist ботов — та же версия реестра, что у соседа <org>/site
#    (на VPS соседа нет — SKIP)
read -r bots_status bots_note < <(bash scripts/tools/bots-sources.sh check 2>&1)
case "$bots_status" in
  PASS|WARN|SKIP) st "bots sources" "$bots_status" "$bots_note" ;;
  *) st "bots sources" WARN "scripts/tools/bots-sources.sh check: $bots_status $bots_note" ;;
esac

echo
if [ "$fail" -eq 0 ]; then
  echo "OK"
else
  echo "FAIL: ${failed[*]}"
  exit 1
fi
