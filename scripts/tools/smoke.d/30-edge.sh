#!/usr/bin/env bash
# smoke.d/30-edge.sh — состояние edge: журнал доступа, его чтение CrowdSec, allowlist и баны ботов.
# Часть drop-in смока (см. smoke-run.sh): бежит НА хосте, self exit 0; меняет только одно — проба
# через edge (запрос на 127.0.0.1:443) оставляет строку в журнале. `ATTENTION:` в колонке 0:
#   - журнала нет, в нём запись старше суток (суточная ротация не идёт) или он от 512 МиБ
#     (не идёт внеочередная);
#   - edge не ответил на пробу, или CrowdSec её не прочёл — источник acquisition не читает журнал;
#   - сверка задания allowlist (configs/crowdsec/bots-allowlist.sh state) — строкой WARN: задание
#     идёт дольше своего срока, allowlist нужного бота нет, он старше недели с запасом, пуст или
#     лишний, бот под баном.
# Журнал смок читает через контейнер crowdsec: каталог журнала — только root.
set -o pipefail

JOURNAL_MAX_MB="${SMOKE_JOURNAL_MAX_MB:-512}"   # вдвое выше порога внеочередной ротации
JOURNAL_AGE_H="${SMOKE_JOURNAL_AGE_H:-26}"     # суточная ротация и запас

echo "-- edge --"

if ! command -v docker >/dev/null 2>&1 ||
   [ "$(docker inspect -f '{{.State.Running}}' crowdsec 2>/dev/null)" != true ]; then
  echo "  SKIP (контейнер crowdsec не запущен)"
  exit 0
fi

ago() { local s=$1; if [ "$s" -lt 7200 ]; then echo "$((s / 60)) мин"; elif [ "$s" -lt 172800 ]; then echo "$((s / 3600)) ч"; else echo "$((s / 86400)) дн"; fi; }
in_cs() { docker exec crowdsec sh -c "$1" 2>/dev/null; }

# Журнал: размер, возраст первой записи (суточная ротация уносит её в копию), копии.
log=/var/log/traefik/access.log
if ! in_cs "[ -f $log ]"; then
  printf "  %-12s %s\n" "journal:" "нет файла $log"
  echo "ATTENTION: журнала доступа нет — Traefik пишет его в $log (docs/reference/runbook.md)"
else
  now=$(date +%s)
  size=$(in_cs "stat -c %s $log"); size=${size:-0}
  first=$(in_cs "head -n 1 $log" | grep -o '"time":"[^"]*"' | cut -d'"' -f4)
  first=$(date -d "$first" +%s 2>/dev/null || echo "")
  copies=$(in_cs "ls $log.*.gz 2>/dev/null | wc -l")
  fresh=$(in_cs "stat -c %Y $log.1.gz")
  if [ "$size" -lt 1048576 ]; then line="$((size / 1024)) КиБ"; else line="$((size / 1048576)) МиБ"; fi
  [ -z "$first" ] || line="$line, первая запись — $(ago $((now - first))) назад"
  line="$line; копий ${copies:-0}"
  [ -z "$fresh" ] || line="$line, свежая — $(ago $((now - fresh))) назад"
  printf "  %-12s %s\n" "journal:" "$line"
  [ "$size" -lt $((JOURNAL_MAX_MB * 1048576)) ] ||
    echo "ATTENTION: журнал доступа $((size / 1048576)) МиБ — внеочередная ротация не идёт (configs/crowdsec/crontab, docs/reference/runbook.md)"
  [ -z "$first" ] || [ $((now - first)) -lt $((JOURNAL_AGE_H * 3600)) ] ||
    echo "ATTENTION: в журнале доступа запись старше ${JOURNAL_AGE_H} ч — суточная ротация не идёт (configs/crowdsec/crontab, docs/reference/runbook.md)"
fi

# Источник acquisition: проба через edge обязана прибавить строку к прочитанным CrowdSec.
reads() {
  docker exec crowdsec cscli metrics show acquisition -o json 2>/dev/null | tr -d ' \n' |
    grep -o "\"file:$log\":{[^}]*}" | grep -o '"reads":[0-9]*' | cut -d: -f2
}
if ! command -v curl >/dev/null 2>&1; then
  printf "  %-12s %s\n" "acquisition:" "SKIP (нет curl для пробы через edge)"
else
  r0=$(reads); r0=${r0:-0}
  code=$(curl -sk -o /dev/null -w '%{http_code}' --max-time 5 https://127.0.0.1/ 2>/dev/null)
  if [ "${code:-000}" = 000 ]; then
    printf "  %-12s %s\n" "acquisition:" "проба не прошла: edge не ответил на 127.0.0.1:443"
    echo "ATTENTION: edge не отвечает на 443 — make ps / triage"
  else
    r1=$r0
    for _ in 1 2 3 4 5; do sleep 1; r1=$(reads); r1=${r1:-0}; [ "$r1" -gt "$r0" ] && break; done
    if [ "$r1" -gt "$r0" ]; then
      printf "  %-12s %s\n" "acquisition:" "CrowdSec читает журнал (проба через edge прочитана, строк всего $r1)"
    else
      printf "  %-12s %s\n" "acquisition:" "проба через edge не прочитана (строк источника: $r1)"
      echo "ATTENTION: CrowdSec не читает журнал доступа — configs/crowdsec/acquis.yaml (docs/reference/runbook.md)"
    fi
  fi
fi

# Allowlist и баны ботов: сверку ведёт само задание — знание его замка, срока и источников.
if [ "$(docker inspect -f '{{.State.Running}}' site 2>/dev/null)" != true ]; then
  printf "  %-12s %s\n" "allowlist:" "SKIP (контейнер site не запущен)"
  exit 0
fi
key="allowlist:"
while IFS= read -r line; do
  line=${line#bots-allowlist: }
  case "$line" in
    WARN\ *) line=${line#WARN }; printf "  %-12s %s\n" "$key" "$line"; echo "ATTENTION: edge — $line" ;;
    *) printf "  %-12s %s\n" "$key" "$line" ;;
  esac
  key=""
done < <(docker exec crowdsec sh /opt/edge/bots-allowlist.sh state 2>&1)

exit 0
