#!/usr/bin/env bash
# smoke.d/20-containers.sh — здоровье контейнеров стека (автодискавери из docker ps).
# Часть drop-in смока (см. smoke-run.sh): бежит НА хосте, где docker уместен.
# Это новый дом для docker-проверок, ушедших из status.sh (тот теперь pure-local).
# `ATTENTION:` в колонке 0 на unhealthy/exited (его ловит smartdev → triage).
# Read-only, self exit 0; без docker — SKIP-строка.
set -o pipefail

echo "-- containers --"

if ! command -v docker >/dev/null 2>&1; then
  echo "  SKIP (docker недоступен)"
  return 0 2>/dev/null || exit 0
fi
if ! docker info >/dev/null 2>&1; then
  echo "  SKIP (docker daemon недоступен)"
  return 0 2>/dev/null || exit 0
fi

# Сводка по running-контейнерам compose-проекта (автодискавери — без хардкода имён).
running=$(docker ps --filter label=com.docker.compose.project \
            --format '{{.Names}}\t{{.Status}}' 2>/dev/null)
total=$(printf '%s\n' "$running" | grep -c . || true)
printf "  %-12s %s running\n" "stack:" "${total:-0}"

# health: unhealthy сейчас
unhealthy=$(docker ps --filter health=unhealthy --format '{{.Names}}' 2>/dev/null | paste -sd' ' -)
# exited compose-контейнеры (упали / не поднялись)
exited=$(docker ps -a --filter status=exited --filter label=com.docker.compose.project \
           --format '{{.Names}}' 2>/dev/null | paste -sd' ' -)
# restart-counts > 0 — крутится в перезапусках
restarting=""
while IFS= read -r name; do
  [ -z "$name" ] && continue
  rc=$(docker inspect -f '{{.RestartCount}}' "$name" 2>/dev/null || echo 0)
  [ "${rc:-0}" -gt 0 ] 2>/dev/null && restarting="$restarting $name($rc)"
done < <(printf '%s\n' "$running" | cut -f1)

printf "  %-12s %s\n" "unhealthy:"  "${unhealthy:-none}"
printf "  %-12s %s\n" "exited:"     "${exited:-none}"
printf "  %-12s %s\n" "restarts:"   "${restarting:-none}"

[ -n "$unhealthy" ] && echo "ATTENTION: unhealthy: $unhealthy — make logs SVC=<svc> / triage"
[ -n "$exited" ]    && echo "ATTENTION: exited: $exited — make ps / triage"
[ -n "$restarting" ] && echo "ATTENTION: restart-loop:$restarting — make logs SVC=<svc> / triage"

exit 0
