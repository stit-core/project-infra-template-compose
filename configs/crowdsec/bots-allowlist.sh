#!/bin/sh
# Allowlist ботов в CrowdSec — задание расписания edge (configs/crowdsec/crontab), шаг
# make deploy и верб make allowlist.
#   bots-allowlist.sh [all|missing|state]
# all (умолчание) обновляет allowlist каждого бота; missing — только отсутствующие и те,
# что не обновлялись дольше шести дней: деплой не ходит к вендорам без нужды; state —
# сверка для смока, ничего не меняя: идёт ли задание; allowlist нужных ботов — есть ли все,
# сети и возраст; кто из ботов под баном — адрес из allowlist или PTR поисковика, которого
# бережёт только rDNS.
#
# Кого сайт пускает, того edge не банит. Источники — ai-bots.sources рядом (печать реестра
# ботов сайта, make bots-sources): строка «назначение токен ip_list_url rdns». Бот с
# ip_list_url получает allowlist `bot-<токен>` с сетями вендора, если robots.txt сервиса
# site не закрывает его именной группой с `Disallow: /`. Бот только с rdns-суффиксами
# проверяет постоверфлоу seo-bots-whitelist; бот без обоих полей в allowlist не попадает.
# По User-Agent allowlist не строится: его подделывают. Имена `bot-…` — за заданием:
# allowlist с таким именем, которого нет среди нужных, удаляется.
#
# Ответ вендора — недоверенные данные. Из него берутся только строковые значения ключей
# ipv4Prefix, ipv6Prefix, ip_prefix и ipv6_prefix, записанные адресом или сетью; ничего
# из ответа не исполняется. Список принимается целиком или не принимается вовсе: в нём нет
# частных, служебных и зарезервированных адресов (сети для документации проходят — см.
# networks), а число сетей и их суммарный охват — в пределах MAX_* ниже.
# Тот, кто отвечает за вендора, вносит в allowlist свои сети — в этих пределах, не шире.
# Редирект источника принимается один и только по https: его назначает сам вендор в ответе,
# подлинность которого держит TLS, — список по http и список за вторым редиректом в
# allowlist не попадают. Список с другого хоста итоговая строка называет вместе с хостом.
#
# Источник не ответил, не уложился в срок или его список не принят — прежний allowlist
# бота остаётся. Записи живут 21 день: сети источника, который перестал отвечать совсем,
# уходят сами. Сервис site не ответил — allowlist не меняется вовсе.
#
# Код: 0 — сделано или задание уже идёт; 1 — запуск не состоялся (нет сайта, списка
# источников); 2 — часть allowlist не обновлена (строки WARN).
set -u

SRC=/opt/edge/ai-bots.sources
ROBOTS=http://site:3000/robots.txt
PREFIX=bot-
TTL=504h
REFRESH=518400
LOCK=/tmp/bots-allowlist.lock
MAX_BYTES=2097152
# Пределы списка одного вендора. У списков реестра — до 1292 сетей (Amazonbot), 70 016
# адресов IPv4 (Google-Agent, самая широкая сеть — /16) и 256 сетей /64 IPv6 (CCBot, одна
# /56). Число сетей — с запасом втрое, охват IPv4 — ×3,7 (четыре сети /16), охват IPv6 —
# одна сеть /48.
MAX_NETS=4096
MAX_V4=262144
MAX_V6=65536
# Сроки в секундах: одна попытка загрузки, задание целиком, сверка state. Allowlist старше
# STALE — источник не обновлялся: расписание — раз в неделю.
FETCH_SEC=30
JOB_SEC=600
STATE_SEC=60
STALE=691200
mode=${1:-all}
tmp=${2:-}

say() { echo "bots-allowlist: $*"; }
case "$mode" in all|missing|state) ;; *) say "режим? all|missing|state"; exit 1 ;; esac

# Одно задание за раз, и у него срок. Работу ведёт дочерний процесс (тот же файл со вторым
# аргументом — рабочим каталогом) своей группой и под timeout; замок держат оба — и без
# надзирающего (SIGKILL) задание до своего конца остаётся одним. Загрузки замок не наследуют:
# зависшая загрузка и её помощник ssl_client (через него wget ведёт TLS, и он переживает
# wget, пока источник держит соединение) замка не держат, а с концом задания снимаются всей
# группой — её снимает и надзирающий, и само задание.
if [ -z "$tmp" ]; then
  exec 9>> "$LOCK"
  # Повтор через секунду: на миг замок берёт и проверка state.
  if ! flock -n 9 && { sleep 1; ! flock -n 9; }; then
    age=$(( $(date +%s) - $(stat -c %Y "$LOCK") ))
    if [ "$age" -gt $((JOB_SEC + 60)) ]; then
      say "WARN задание идёт $age с — дольше своего срока ($JOB_SEC с), allowlist не обновляется: make restart SVC=crowdsec (docs/reference/runbook.md)"
      exit 2
    fi
    if [ "$mode" = state ]; then say "задание идёт ($age с)"; else say "уже идёт ($age с) — пропуск"; fi
    exit 0
  fi
  # Сверка идёт без замка: задание она не задерживает.
  sec=$JOB_SEC
  if [ "$mode" = state ]; then say "задание не идёт"; exec 9>&-; sec=$STATE_SEC; else touch "$LOCK"; fi
  tmp=$(mktemp -d) || exit 1
  setsid timeout "$sec" sh "$0" "$mode" "$tmp" &
  job=$!
  trap 'kill -- "-$job" 2>/dev/null; rm -f "$tmp"/*; rmdir "$tmp" 2>/dev/null' EXIT
  trap 'exit 143' HUP INT TERM
  wait "$job" 2>/dev/null; rc=$?
  [ "$rc" -le 2 ] || { say "WARN задание прервано (код $rc; срок — $sec с) — allowlist обновлён не полностью"; rc=2; }
  exit "$rc"
fi
[ -d "$tmp" ] || { say "рабочего каталога нет: $tmp"; exit 1; }
# Задание — лидер своей группы (setsid): по концу, и по сроку, снимает её и свой каталог.
trap 'trap "" TERM; kill -- "-$$" 2>/dev/null; rm -f "$tmp"/*; rmdir "$tmp" 2>/dev/null' EXIT
trap 'exit 143' HUP INT TERM PIPE

# Одна загрузка: ответ целиком, не больше MAX_BYTES (ulimit обрывает запись) и не дольше
# FETCH_SEC; заголовки ответа — в <файл>.hdr. Фоном и с wait: о загрузке, снятой по сроку,
# шелл иначе печатает «Terminated».
get() { # <адрес> <файл>
  ( trap '' XFSZ; ulimit -f $((MAX_BYTES / 512))
    exec timeout "$FETCH_SEC" wget -q -S -T 15 -U 'Mozilla/5.0 (compatible; edge-bots-allowlist)' -O "$2" "$1" ) 2> "$2.hdr" 9>&- &
  wait $! 2>/dev/null
}
# Сертификат источника сверяет помощник ssl_client: без него wget busybox идёт по https,
# не проверяя сертификат.
command -v ssl_client >/dev/null || { say "WARN в образе нет ssl_client: сертификат источника не проверить — allowlist не меняется"; exit 1; }

version=$(sed -n '1s/^# crawlers\.yaml sha256:\([0-9a-f]\{12\}\)[0-9a-f]\{52\}$/\1/p' "$SRC" 2>/dev/null)
[ -n "$version" ] || { say "WARN нет списка источников или его первая строка — не версия реестра: $SRC (make bots-sources)"; exit 1; }
# Строки печати: назначение, токен, https-адрес списка сетей или «—», суффиксы rDNS или «—».
grep -E '^(search|user_fetch|training) [A-Za-z0-9._-]+ (https://[A-Za-z0-9._~:/?#@!&=+%-]+|—) ([a-z0-9.,-]+|—)$' "$SRC" > "$tmp/bots"
odd=$(grep -cvE '^(#|$)' "$SRC"); odd=$((odd - $(wc -l < "$tmp/bots")))

# Политика сайта — robots.txt сервиса, а не публичный адрес: на не-прод тот за замком.
get "$ROBOTS" "$tmp/robots" && grep -qi '^user-agent[[:space:]]*:' "$tmp/robots" ||
  { say "WARN сервис site не отвечает ($ROBOTS) — allowlist не меняется"; exit 1; }
# Токены именных групп с полным запретом (группа `*` — не про ботов из списка).
awk '{ sub(/#.*/, ""); gsub(/\r/, ""); line = tolower($0) }
     line ~ /^[ \t]*user-agent[ \t]*:/ { if (rules) { n = 0; rules = 0 }; v = line; sub(/^[^:]*:[ \t]*/, "", v); sub(/[ \t]+$/, "", v); agent[++n] = v; next }
     line ~ /^[ \t]*(allow|disallow)[ \t]*:/ { rules = 1; v = line; sub(/^[^:]*:[ \t]*/, "", v); sub(/[ \t]+$/, "", v)
       if (line ~ /^[ \t]*disallow/ && v == "/") for (i = 1; i <= n; i++) if (agent[i] != "*") print agent[i] }' "$tmp/robots" | sort -u > "$tmp/closed"

# Боты к allowlist: с адресом списка и не закрытые сайтом.
: > "$tmp/want"; closed=0
while read -r purpose token url rdns; do
  [ "$url" != "—" ] || continue
  if grep -qxF -e "$(printf '%s' "$token" | tr 'A-Z' 'a-z')" "$tmp/closed"; then closed=$((closed + 1)); continue; fi
  echo "$token $url" >> "$tmp/want"
done < "$tmp/bots"

cscli allowlists list -o raw > "$tmp/have.csv" 2>/dev/null || { say "WARN cscli allowlists не отвечает"; exit 1; }
# name,description,created_at,…,size: имя, возраст в секундах и число сетей своих allowlist.
now=$(date -u +%s)
awk -F, -v p="$PREFIX" 'NR > 1 && index($1, p) == 1 { t = $3; sub(/T/, " ", t); sub(/Z$/, "", t); print $1 "," t "," $6 }' "$tmp/have.csv" |
  while IFS=, read -r name at size; do echo "$name $((now - $(date -u -d "$at" +%s 2>/dev/null || echo 0))) $size"; done > "$tmp/have"

if [ "$mode" = state ]; then
  # Allowlist: нужные против записанных — счёт, сети (пустой или шире пределов задания — не
  # его работа), возраст; лишние — бот закрыт robots.txt или выпал из источников.
  line=$(awk -v p="$PREFIX" -v stale="$STALE" -v max="$((2 * MAX_NETS))" '
    function hum(t) { return t < 7200 ? int(t / 60) " мин" : t < 172800 ? int(t / 3600) " ч" : int(t / 86400) " дн" }
    FILENAME == ARGV[1] { want[p $1] = 1; nw++; next }
    { age[$1] = $2; size[$1] = $3 }
    END {
      for (n in want) {
        if (!(n in age)) { miss = miss " " substr(n, length(p) + 1); continue }
        nh++; nets += size[n]; if (age[n] > old) old = age[n]
        if (age[n] > stale) late = late " " n
        if (size[n] < 1 || size[n] > max) odd = odd " " n
      }
      for (n in age) if (!(n in want)) extra = extra " " n
      s = sprintf("allowlist ботов: %d из %d, сетей %d", nh, nw, nets) (nh ? ", старший — " hum(old) : "")
      if (miss != "") w = w "; нет:" miss
      if (late != "") w = w "; старше " hum(stale) ":" late
      if (odd != "") w = w "; сетей вне предела:" odd
      if (extra != "") w = w "; лишние:" extra
      print (w != "" ? "WARN " s w " — make allowlist" : s) }' "$tmp/want" "$tmp/have")
  say "$line"
  # Баны: адрес из allowlist ботов или PTR поисковика без списка сетей (его бережёт только
  # rDNS) — среди локальных решений, до 30 свежих адресов.
  cscli decisions list -o raw > "$tmp/dec.csv" 2>/dev/null || { say "WARN cscli decisions не отвечает"; exit 2; }
  awk -F, 'NR > 1 && ($2 == "crowdsec" || $2 == "cscli") && $3 ~ /^Ip:/ { print substr($3, 4) }' "$tmp/dec.csv" | awk '!seen[$0]++' | head -n 30 > "$tmp/banned"
  awk '$3 == "—" && $4 != "—" { n = split($4, a, ","); for (i = 1; i <= n; i++) print a[i] }' "$tmp/bots" | sort -u > "$tmp/rdns"
  : > "$tmp/hits"
  while read -r ip; do
    if cscli allowlists check "$ip" < /dev/null 2>/dev/null | grep -q " from $PREFIX"; then echo "$ip (allowlist)" >> "$tmp/hits"; fi
    ( name=$(timeout 3 nslookup "$ip" 2>/dev/null | sed -n 's/.*name = //p' | head -n 1); name=${name%.}
      while read -r suf; do case "$name" in *."$suf") echo "$ip ($name)" >> "$tmp/hits"; break ;; esac; done < "$tmp/rdns" ) &
  done < "$tmp/banned"
  wait
  if [ -s "$tmp/hits" ]; then
    say "WARN под баном боты: $(sort -u "$tmp/hits" | head -n 5 | tr '\n' ' ')— снять: cscli decisions delete --ip <адрес> (docs/reference/runbook.md)"
    exit 2
  fi
  say "под баном ботов нет (локальных решений: $(wc -l < "$tmp/banned"))"
  case "$line" in WARN*) exit 2 ;; esac
  exit 0
fi

# Чужой и закрытый: allowlist бота, которого нет среди нужных, удаляется.
removed=0
while read -r name age size; do
  awk -v t="${name#"$PREFIX"}" '$1 == t { found = 1 } END { exit !found }' "$tmp/want" && continue
  cscli allowlists delete "$name" >/dev/null 2>&1 && removed=$((removed + 1))
done < "$tmp/have"

# Кого обновлять: все или только отсутствующие и давние.
: > "$tmp/todo"
while read -r token url; do
  age=$(awk -v n="$PREFIX$token" '$1 == n { print $2 }' "$tmp/have")
  if [ "$mode" = all ] || [ -z "$age" ] || [ "$age" -gt "$REFRESH" ]; then echo "$token $url" >> "$tmp/todo"; fi
done < "$tmp/want"

# Ответы вендоров — параллельно, каждый адрес один раз. До четырёх попыток, и после
# попытки, снятой по сроку: соединение с вендором рвётся и на исправном источнике, а
# адрес, до которого нет маршрута, держит попытку до таймаута. Редиректу wget следует сам:
# запрос по адресу не по https и за вторым редиректом уходит, ответ не принимается,
# повтора нет.
cut -d' ' -f2 "$tmp/todo" | sort -u > "$tmp/urls"
fetch() { # <адрес> <файл>; причина отказа, если она не «нет ответа», — в <файл>.why,
          # хост, на который увёл редирект, — в <файл>.via
  host=${1#https://}; host=${host%%/*}; n=0
  while [ "$n" -lt 4 ]; do
    get "$1" "$2"; rc=$?
    sed -n 's/^ *[Ll][Oo][Cc][Aa][Tt][Ii][Oo][Nn]: *//p' "$2.hdr" | tr -d '\r' > "$2.loc"
    : > "$2.via"
    if [ "$(wc -l < "$2.loc")" -gt 1 ]; then
      echo "редиректов — $(wc -l < "$2.loc"), принимается один" > "$2.why"
      : > "$2"; return 1
    fi
    while read -r to; do
      case "$to" in
        "https://$host/"*|/*) ;;
        # Хост — после userinfo: wget идёт на него, а не на имя до «@».
        https://*) to=${to#https://}; to=${to%%/*}; printf '%s' "${to##*@}" | tr -cd 'A-Za-z0-9.:-' | cut -c1-80 > "$2.via" ;;
        *)
          echo "редирект на $(printf '%s' "$to" | tr -cd 'A-Za-z0-9._~:/?#@!&=+%-' | cut -c1-120) — принимается только https" > "$2.why"
          : > "$2"; return 1 ;;
      esac
    done < "$2.loc"
    [ "$rc" -eq 0 ] && [ -s "$2" ] && return 0
    : > "$2"; n=$((n + 1)); sleep 1
  done
  return 1
}
i=0; : > "$tmp/index"
while read -r url; do
  i=$((i + 1)); echo "$i $url" >> "$tmp/index"
  fetch "$url" "$tmp/r$i" 9>&- &
done < "$tmp/urls"
wait

# Сети из ответа: значения известных ключей в форме адреса или сети. Причина, по которой
# список не принят, — в файле причины.
networks() { # <файл ответа> <файл сетей> <файл причины>
  : > "$2"; : > "$3"
  [ -s "$1" ] || return 1
  grep -oE '"(ipv4Prefix|ipv6Prefix|ip_prefix|ipv6_prefix)"[[:space:]]*:[[:space:]]*"[0-9A-Fa-f:./]{2,49}"' "$1" |
    sed -E 's/.*"([^"]*)"$/\1/' |
    awk -v max="$MAX_NETS" -v max4="$MAX_V4" -v max6="$MAX_V6" -v why="$3" '
      function num(a,   o) { split(a, o, "."); return ((o[1] * 256 + o[2]) * 256 + o[3]) * 256 + o[4] }
      BEGIN {
        # Не адреса клиентов из сети: «эта сеть», частные, CGNAT, loopback, link-local,
        # служебные IETF, сети для замеров, multicast и резерв. Сети для документации
        # (192.0.2.0/24, 198.51.100.0/24, 203.0.113.0/24, 2001:db8::/32) проходят: трафика
        # из сети с них нет — allowlist с ними ничего не открывает, а на них стоят пробы стенда.
        nr = split("0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8 169.254.0.0/16 172.16.0.0/12 192.0.0.0/24 192.168.0.0/16 198.18.0.0/15 224.0.0.0/3", r, " ")
        for (i = 1; i <= nr; i++) { split(r[i], q, "/"); ra[i] = num(q[1]); rl[i] = q[2] + 0 } }
      { n = split($0, p, "/"); if (n > 2 || (n == 2 && p[2] !~ /^[0-9]+$/)) next
        addr = tolower(p[1]); spec = 0
        if (addr ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/) {
          split(addr, o, "."); len = (n == 2) ? p[2] + 0 : 32
          for (i = 1; i <= 4; i++) if (o[i] !~ /^(0|[1-9][0-9]?[0-9]?)$/ || o[i] + 0 > 255) next
          if (len > 32) next
          net = addr "/" len; if (net in seen) next
          a = num(addr)
          # Сеть задевает особую, когда у них совпадают первые min(длин) бит.
          for (i = 1; i <= nr && !spec; i++) { m = (len < rl[i]) ? len : rl[i]; d = 2 ^ (32 - m); spec = (int(a / d) == int(ra[i] / d)) }
          n4++; c4 += 2 ^ (32 - len); if (n4 == 1 || len < l4) { l4 = len; w4 = net }
        } else if (addr ~ /^[0-9a-f:]+$/ && addr ~ /:/) {
          len = (n == 2) ? p[2] + 0 : 128
          if (len > 128) next
          net = addr "/" len; if (net in seen) next
          # Адрес клиента IPv6 — глобальный, 2000::/3; охват считается сетями /64.
          spec = (addr !~ /^[23][0-9a-f][0-9a-f][0-9a-f]:/ || len < 3)
          n6++; c6 += (len < 64) ? 2 ^ (64 - len) : 1; if (n6 == 1 || len < l6) { l6 = len; w6 = net }
        } else next
        seen[net] = 1; out[++k] = net
        if (spec && ++nspec <= 5) specs = specs " " net }
      END {
        if (nspec) msg = sprintf("сети не из публичных адресов (%d):%s", nspec, specs)
        else if (n4 > max) msg = sprintf("сетей IPv4 — %d, предел — %d", n4, max)
        else if (n6 > max) msg = sprintf("сетей IPv6 — %d, предел — %d", n6, max)
        else if (c4 > max4) msg = sprintf("охват IPv4 — %.0f адресов, предел — %d; самая широкая сеть — %s", c4, max4, w4)
        else if (c6 > max6) msg = sprintf("охват IPv6 — %.0f сетей /64, предел — %d; самая широкая сеть — %s", c6, max6, w6)
        if (msg != "") { print msg > why; exit }
        for (i = 1; i <= k; i++) print out[i] }' | sort -u > "$2"
  [ -s "$2" ]
}

updated=0; failed=0; via=
while read -r token url; do
  i=$(awk -v u="$url" '$2 == u { print $1 }' "$tmp/index"); name=$PREFIX$token
  if ! networks "$tmp/r$i" "$tmp/nets" "$tmp/why"; then
    if [ -s "$tmp/r$i.why" ]; then why="список не принят — $(cat "$tmp/r$i.why")"
    elif [ -s "$tmp/why" ]; then why="список не принят — $(cat "$tmp/why")"
    else why="источник не ответил или не дал ни одной сети"; fi
    say "WARN $token: $why ($url) — прежний allowlist оставлен"
    failed=$((failed + 1)); continue
  fi
  { echo "value,expiration,comment"; sed "s/\$/,$TTL,/" "$tmp/nets"; } > "$tmp/nets.csv"
  cscli allowlists delete "$name" >/dev/null 2>&1
  if cscli allowlists create "$name" -d "$url" >/dev/null 2>&1 && cscli allowlists import "$name" -i "$tmp/nets.csv" >/dev/null 2>&1; then
    updated=$((updated + 1))
    [ ! -s "$tmp/r$i.via" ] || via="$via $token → $(cat "$tmp/r$i.via");"
  else
    say "WARN $token: cscli allowlists не принял сети ($(wc -l < "$tmp/nets"))"; failed=$((failed + 1))
  fi
done < "$tmp/todo"

[ "$odd" -eq 0 ] || { say "WARN строк не той формы в $SRC: $odd — пропущены (make bots-sources)"; failed=$((failed + 1)); }
total=$(cscli allowlists list -o raw 2>/dev/null | awk -F, -v p="$PREFIX" 'NR > 1 && index($1, p) == 1 { n++; s += $6 } END { print n + 0 " allowlist, " s + 0 " сетей" }')
[ -z "$via" ] || say "список взят по редиректу на другой хост:${via%;}"
say "реестр $version — к allowlist ботов: $(wc -l < "$tmp/want"), закрыто robots.txt: $closed, обновлено: $updated, снято: $removed; итого $total"
[ "$failed" -eq 0 ] || exit 2
