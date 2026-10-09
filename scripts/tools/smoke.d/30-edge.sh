#!/usr/bin/env bash
# smoke.d/30-edge.sh — состояние edge: задания расписания рядом с CrowdSec.
# Часть drop-in смока (см. smoke-run.sh): бежит НА хосте, read-only, self exit 0.
# `ATTENTION:` в колонке 0 — задание allowlist ботов идёт дольше своего срока: его замок
# занят, и ни расписание, ни make allowlist, ни шаг деплоя allowlist не обновляют.
set -o pipefail

echo "-- edge --"

if ! command -v docker >/dev/null 2>&1 ||
   [ "$(docker inspect -f '{{.State.Running}}' crowdsec 2>/dev/null)" != true ]; then
  echo "  SKIP (контейнер crowdsec не запущен)"
  exit 0
fi

# Состояние называет само задание: замок и срок — его знание.
state=$(docker exec crowdsec sh /opt/edge/bots-allowlist.sh state 2>&1 | tail -n 1)
state=${state#bots-allowlist: }
printf "  %-12s %s\n" "allowlist:" "${state#WARN }"
case "$state" in WARN*) echo "ATTENTION: allowlist ботов — ${state#WARN }" ;; esac

exit 0
