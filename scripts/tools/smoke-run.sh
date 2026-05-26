#!/usr/bin/env bash
# smoke-run.sh — раннер серверного смока. Бежит НА хосте (на VPS локально, либо
# через scripts/tools/ssh.sh smoke с workstation). Композит на входе собирает
# таргет `make status` (секция `== Server ==`) — здесь только запуск проверок.
#
# Контракт drop-in: каждый scripts/tools/smoke.d/*.sh —
#   - бежит на хосте, read-only, дёшево, self exit 0 (падение чека ≠ падение смока);
#   - печатает свой блок `-- <label> --` + строки `  ключ: значение`;
#   - на проблеме печатает `ATTENTION: <msg>` в колонке 0 — это ловит smartdev
#     (как и `== Critical ==`) и чейнит в triage.
# Файлы гоняются в лексикографическом порядке: 10-host, 20-containers, … 90-<svc>
# (проектные/bespoke). Растёт добавлением файлов — см. skill add-service.
set -o pipefail
cd "$(dirname "$0")/../.."

shopt -s nullglob
checks=(scripts/tools/smoke.d/*.sh)
shopt -u nullglob

if [ ${#checks[@]} -eq 0 ]; then
  echo "  SKIP (нет smoke.d/*.sh)"
  exit 0
fi

for c in "${checks[@]}"; do
  bash "$c" || echo "  (смок-чек $c упал — exit $?, не критично для раннера)"
done

exit 0
