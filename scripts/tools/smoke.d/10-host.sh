#!/usr/bin/env bash
# smoke.d/10-host.sh — хостовые витали VPS (load / RAM / swap / disk / OOM).
# Часть drop-in смока (см. smoke-run.sh): бежит НА хосте, печатает блок строк,
# `ATTENTION:` в колонке 0 на превышении порога (его ловит smartdev → triage).
# Read-only, дешёвый, self exit 0. Пороги — env-override (дефолты ниже).
set -o pipefail

LOAD_FACTOR="${SMOKE_LOAD_FACTOR:-2}"   # ATTENTION при load1 > FACTOR×ncpu
RAM_MIN_PCT="${SMOKE_RAM_MIN_PCT:-10}"  # ATTENTION при available RAM < N% от total
DISK_PCT="${SMOKE_DISK_PCT:-90}"        # ATTENTION при use% тома > N

echo "-- host --"

# load average
if [ -r /proc/loadavg ]; then
  read -r l1 l5 l15 _ </proc/loadavg
  ncpu=$(nproc 2>/dev/null || echo 1)
  printf "  %-10s %s %s %s (%s cpu)\n" "load:" "$l1" "$l5" "$l15" "$ncpu"
  # bc может отсутствовать — сравниваем через awk
  if awk -v l="$l1" -v c="$ncpu" -v f="$LOAD_FACTOR" 'BEGIN{exit !(l > c*f)}'; then
    echo "ATTENTION: load1 $l1 > ${LOAD_FACTOR}×${ncpu} cpu — хост перегружен (make logs / triage)"
  fi
else
  echo "  load:      SKIP (нет /proc/loadavg)"
fi

# RAM + swap (free -m)
if command -v free >/dev/null 2>&1; then
  # строки Mem:/Swap: — total used free shared buff/cache available
  read -r _ mtot mused _ _ _ mavail < <(free -m | awk '/^Mem:/')
  read -r _ stot sused _          < <(free -m | awk '/^Swap:/')
  printf "  %-10s %s/%s MB used, %s avail\n" "ram:" "${mused:-?}" "${mtot:-?}" "${mavail:-?}"
  printf "  %-10s %s/%s MB\n" "swap:" "${sused:-0}" "${stot:-0}"
  if [ -n "${mtot:-}" ] && [ "${mtot:-0}" -gt 0 ] 2>/dev/null; then
    if awk -v a="${mavail:-0}" -v t="$mtot" -v p="$RAM_MIN_PCT" 'BEGIN{exit !(a < t*p/100)}'; then
      echo "ATTENTION: RAM available ${mavail}MB < ${RAM_MIN_PCT}% от ${mtot}MB — память на исходе"
    fi
  fi
else
  echo "  ram:       SKIP (нет free)"
fi

# disk — root + docker data-root, если резолвится
mounts=("/")
if command -v docker >/dev/null 2>&1; then
  droot=$(docker info -f '{{.DockerRootDir}}' 2>/dev/null || true)
  [ -n "$droot" ] && [ "$droot" != "/var/lib/docker" ] && mounts+=("$droot")
fi
for m in "${mounts[@]}"; do
  [ -d "$m" ] || continue
  read -r size used _ pct < <(df -Ph "$m" 2>/dev/null | awk 'NR==2{print $2, $3, $4, $5}')
  pctn=${pct%\%}
  printf "  %-10s %s (%s/%s)\n" "disk ${m}:" "${pct:-?}" "${used:-?}" "${size:-?}"
  if [ -n "$pctn" ] && [ "$pctn" -ge "$DISK_PCT" ] 2>/dev/null; then
    echo "ATTENTION: disk $m at ${pct} — освободи место / расширь том (deploy/backup упрётся)"
  fi
done

# OOM — best-effort, не падаем если ядро/journal недоступны
oom=""
if command -v dmesg >/dev/null 2>&1; then
  oom=$(dmesg -T 2>/dev/null | grep -i 'killed process\|out of memory' | tail -3)
fi
if [ -z "$oom" ] && command -v journalctl >/dev/null 2>&1; then
  oom=$(journalctl -k --no-pager 2>/dev/null | grep -i 'killed process\|out of memory' | tail -3)
fi
if [ -n "$oom" ]; then
  echo "  oom:       recent OOM-kill (см. ниже)"
  printf '%s\n' "$oom" | sed 's/^/      | /'
  echo "ATTENTION: недавний OOM-kill на хосте — сервис мог быть убит (triage)"
else
  echo "  oom:       none recent"
fi
