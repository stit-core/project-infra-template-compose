#!/usr/bin/env bash
# smoke.d/20-containers.sh — здоровье контейнеров стека (автодискавери из docker ps).
# Часть drop-in смока (см. smoke-run.sh): бежит НА хосте, где docker уместен; status.sh
# docker не трогает. `ATTENTION:` в колонке 0 на unhealthy, exited и петлю рестартов (его
# ловит smartdev → triage). Read-only, self exit 0; без docker — SKIP-строка.
#
# Петля рестартов — контейнер сейчас перезапускается или перезапущен не раз, и последний
# старт моложе окна: RestartCount копится с создания контейнера, и разовый рестарт (сбой
# загрузки плагина Traefik при старте) — строка restarts без ATTENTION.
set -o pipefail

WINDOW_MIN="${SMOKE_RESTART_WINDOW_MIN:-10}"  # окно петли рестартов, минуты

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
# рестарты: счётчик с создания контейнера и возраст последнего старта
restarts=""; loop=""; now=$(date +%s)
while IFS= read -r name; do
  [ -z "$name" ] && continue
  read -r rc again started < <(docker inspect -f '{{.RestartCount}} {{.State.Restarting}} {{.State.StartedAt}}' "$name" 2>/dev/null)
  [ "${rc:-0}" -gt 0 ] 2>/dev/null || continue
  age=$(( now - $(date -d "$started" +%s 2>/dev/null || echo 0) ))
  restarts="$restarts $name($rc, старт $(( age / 60 )) мин назад)"
  if [ "$again" = true ] || { [ "$rc" -ge 2 ] && [ "$age" -lt $(( WINDOW_MIN * 60 )) ]; }; then
    loop="$loop $name($rc)"
  fi
done < <(printf '%s\n' "$running" | cut -f1)

printf "  %-12s %s\n" "unhealthy:"  "${unhealthy:-none}"
printf "  %-12s %s\n" "exited:"     "${exited:-none}"
printf "  %-12s %s\n" "restarts:"   "${restarts:-none}"

[ -n "$unhealthy" ] && echo "ATTENTION: unhealthy: $unhealthy — make logs SVC=<svc> / triage"
[ -n "$exited" ]    && echo "ATTENTION: exited: $exited — make ps / triage"
[ -n "$loop" ]      && echo "ATTENTION: restart-loop:$loop — make logs SVC=<svc> / triage"

exit 0
