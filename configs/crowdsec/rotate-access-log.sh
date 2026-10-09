#!/bin/sh
# Ротация журнала доступа Traefik — задание расписания edge (configs/crowdsec/crontab).
#   rotate-access-log.sh [порог в байтах]
# Без порога ротирует непустой файл, с порогом — только файл не меньше порога: страховка
# диска при всплеске трафика.
#
# Копия и сброс активного файла, а не переименование: Traefik держит файл открытым и
# переоткрывает его только по сигналу, а сигнал чужому контейнеру — это docker-сокет или
# общий PID-namespace. Traefik пишет с O_APPEND — после сброса запись идёт с начала файла;
# CrowdSec видит сброс и читает файл заново. Строки, пришедшие между копией и сбросом
# (миллисекунды), теряются.
#
# Копии — access.log.1.gz (свежая) … access.log.14.gz: источник CrowdSec берёт только
# *.log, отчёт «бот × статус» читает копии через zcat.
set -eu
log=/var/log/traefik/access.log
keep=14
min=${1:-1}

# Одна ротация за раз: суточная строка расписания и внеочередная могут совпасть.
exec 9< /var/log/traefik
flock -n 9 || exit 0

[ -f "$log" ] || exit 0
[ "$(stat -c %s "$log")" -ge "$min" ] || exit 0

i=$keep
while [ "$i" -gt 1 ]; do
  if [ -f "$log.$((i - 1)).gz" ]; then mv -f "$log.$((i - 1)).gz" "$log.$i.gz"; fi
  i=$((i - 1))
done
cp "$log" "$log.1"
: > "$log"
gzip -f "$log.1"
echo "rotate-access-log: access.log.1.gz — $(stat -c %s "$log.1.gz") байт"
