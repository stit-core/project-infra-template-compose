#!/bin/sh
# Allowlist ботов в CrowdSec — задание расписания edge (configs/crowdsec/crontab), шаг
# make deploy и верб make allowlist.
#   bots-allowlist.sh [all|missing]
# all (умолчание) обновляет allowlist каждого бота; missing — только отсутствующие и те,
# что не обновлялись дольше шести дней: деплой не ходит к вендорам без нужды.
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
# ipv4Prefix, ipv6Prefix, ip_prefix и ipv6_prefix, записанные адресом или сетью; сеть шире
# /16 (IPv4) или /32 (IPv6) отвергается — чужой ответ не открывает edge. Ничего из ответа
# не исполняется: значения проходят фильтр знаков и уходят в файл для cscli.
#
# Источник не ответил или не дал ни одной сети — прежний allowlist бота остаётся. Записи
# живут 21 день: сети источника, который перестал отвечать совсем, уходят сами. Сервис
# site не ответил — allowlist не меняется вовсе.
#
# Код: 0 — сделано; 1 — запуск не состоялся (нет сайта, списка источников); 2 — часть
# allowlist не обновлена (строки WARN).
set -u

SRC=/opt/edge/ai-bots.sources
ROBOTS=http://site:3000/robots.txt
PREFIX=bot-
TTL=504h
REFRESH=518400
V4_MIN=16
V6_MIN=32
MAX_BYTES=2097152
mode=${1:-all}

say() { echo "bots-allowlist: $*"; }
case "$mode" in all|missing) ;; *) say "режим? all|missing"; exit 1 ;; esac

exec 9> /tmp/bots-allowlist.lock
flock -n 9 || { say "уже идёт — пропуск"; exit 0; }
tmp=$(mktemp -d) || exit 1
trap 'rm -f "$tmp"/*; rmdir "$tmp"' EXIT

version=$(sed -n '1s/^# crawlers\.yaml sha256:\([0-9a-f]\{12\}\)[0-9a-f]\{52\}$/\1/p' "$SRC" 2>/dev/null)
[ -n "$version" ] || { say "нет списка источников или его первая строка — не версия реестра: $SRC (make bots-sources)"; exit 1; }
# Строки печати: назначение, токен, https-адрес списка сетей или «—», суффиксы rDNS или «—».
grep -E '^(search|user_fetch|training) [A-Za-z0-9._-]+ (https://[A-Za-z0-9._~:/?#@!&=+%-]+|—) ([a-z0-9.,-]+|—)$' "$SRC" > "$tmp/bots"
odd=$(grep -cvE '^(#|$)' "$SRC"); odd=$((odd - $(wc -l < "$tmp/bots")))

# Политика сайта — robots.txt сервиса, а не публичный адрес: на не-прод тот за замком.
wget -q -T 10 -O "$tmp/robots" "$ROBOTS" 2>/dev/null && grep -qi '^user-agent[[:space:]]*:' "$tmp/robots" ||
  { say "сервис site не отвечает ($ROBOTS) — allowlist не меняется"; exit 1; }
# Токены именных групп с полным запретом (группа `*` — не про ботов из списка).
awk '{ sub(/#.*/, ""); gsub(/\r/, ""); line = tolower($0) }
     line ~ /^[ \t]*user-agent[ \t]*:/ { if (rules) { n = 0; rules = 0 }; v = line; sub(/^[^:]*:[ \t]*/, "", v); sub(/[ \t]+$/, "", v); agent[++n] = v; next }
     line ~ /^[ \t]*(allow|disallow)[ \t]*:/ { rules = 1; v = line; sub(/^[^:]*:[ \t]*/, "", v); sub(/[ \t]+$/, "", v)
       if (line ~ /^[ \t]*disallow/ && v == "/") for (i = 1; i <= n; i++) if (agent[i] != "*") print agent[i] }' "$tmp/robots" | sort -u > "$tmp/closed"

# Боты к allowlist: с адресом списка и не закрытые сайтом.
: > "$tmp/want"; closed=0
while read -r purpose token url rdns; do
  [ "$url" != "—" ] || continue
  if grep -qxF "$(printf '%s' "$token" | tr 'A-Z' 'a-z')" "$tmp/closed"; then closed=$((closed + 1)); continue; fi
  echo "$token $url" >> "$tmp/want"
done < "$tmp/bots"

cscli allowlists list -o raw > "$tmp/have.csv" 2>/dev/null || { say "cscli allowlists не отвечает"; exit 1; }
# name,description,created_at,…: имя и возраст в секундах для своих allowlist.
now=$(date -u +%s)
awk -F, -v p="$PREFIX" 'NR > 1 && index($1, p) == 1 { t = $3; sub(/T/, " ", t); sub(/Z$/, "", t); print $1 "," t }' "$tmp/have.csv" |
  while IFS=, read -r name at; do echo "$name $((now - $(date -u -d "$at" +%s 2>/dev/null || echo 0)))"; done > "$tmp/have"

# Чужой и закрытый: allowlist бота, которого нет среди нужных, удаляется.
removed=0
while read -r name age; do
  awk -v t="${name#"$PREFIX"}" '$1 == t { found = 1 } END { exit !found }' "$tmp/want" && continue
  cscli allowlists delete "$name" >/dev/null 2>&1 && removed=$((removed + 1))
done < "$tmp/have"

# Кого обновлять: все или только отсутствующие и давние.
: > "$tmp/todo"
while read -r token url; do
  age=$(awk -v n="$PREFIX$token" '$1 == n { print $2 }' "$tmp/have")
  if [ "$mode" = all ] || [ -z "$age" ] || [ "$age" -gt "$REFRESH" ]; then echo "$token $url" >> "$tmp/todo"; fi
done < "$tmp/want"

# Ответы вендоров — параллельно, каждый адрес один раз. Ответ целиком и не больше
# MAX_BYTES (ulimit обрывает запись); до четырёх попыток — соединение с вендором рвётся и
# на исправном источнике.
cut -d' ' -f2 "$tmp/todo" | sort -u > "$tmp/urls"
fetch() { # <адрес> <файл>
  n=0
  while [ "$n" -lt 4 ]; do
    ( ulimit -f $((MAX_BYTES / 512)); exec wget -q -T 15 -U 'Mozilla/5.0 (compatible; edge-bots-allowlist)' -O "$2" "$1" ) 2>/dev/null && [ -s "$2" ] && return 0
    : > "$2"; n=$((n + 1)); sleep 1
  done
  return 1
}
i=0; : > "$tmp/index"
while read -r url; do
  i=$((i + 1)); echo "$i $url" >> "$tmp/index"
  fetch "$url" "$tmp/r$i" &
done < "$tmp/urls"
wait

# Сети из ответа: только значения известных ключей, только адрес или сеть, не шире порога.
networks() { # <файл ответа> <файл сетей> <файл отвергнутых>
  [ -s "$1" ] || return 1
  grep -oE '"(ipv4Prefix|ipv6Prefix|ip_prefix|ipv6_prefix)"[[:space:]]*:[[:space:]]*"[0-9A-Fa-f:./]{2,49}"' "$1" |
    sed -E 's/.*"([^"]*)"$/\1/' |
    awk -v v4="$V4_MIN" -v v6="$V6_MIN" -v wide="$3" '
      { n = split($0, p, "/"); if (n > 2 || (n == 2 && p[2] !~ /^[0-9]+$/)) next
        addr = p[1]
        if (addr ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/) {
          split(addr, o, "."); ok = 1
          for (i = 1; i <= 4; i++) if (length(o[i]) > 3 || o[i] + 0 > 255) ok = 0
          len = (n == 2) ? p[2] + 0 : 32
          if (!ok || len > 32) next
          if (len < v4) { print $0 >> wide; next }
          print addr "/" len
        } else if (addr ~ /^[0-9A-Fa-f:]+$/ && addr ~ /:/) {
          len = (n == 2) ? p[2] + 0 : 128
          if (len > 128) next
          if (len < v6) { print $0 >> wide; next }
          print tolower(addr) "/" len
        } }' | sort -u > "$2"
  [ -s "$2" ]
}

updated=0; failed=0
while read -r token url; do
  i=$(awk -v u="$url" '$2 == u { print $1 }' "$tmp/index"); name=$PREFIX$token
  : > "$tmp/wide"
  if ! networks "$tmp/r$i" "$tmp/nets" "$tmp/wide"; then
    say "WARN $token: источник не ответил или не дал ни одной сети ($url) — прежний allowlist оставлен"
    failed=$((failed + 1)); continue
  fi
  [ ! -s "$tmp/wide" ] || { say "WARN $token: сети шире порога отвергнуты — $(tr '\n' ' ' < "$tmp/wide")($url)"; failed=$((failed + 1)); }
  { echo "value,expiration,comment"; sed "s/\$/,$TTL,/" "$tmp/nets"; } > "$tmp/nets.csv"
  cscli allowlists delete "$name" >/dev/null 2>&1
  if cscli allowlists create "$name" -d "$url" >/dev/null 2>&1 && cscli allowlists import "$name" -i "$tmp/nets.csv" >/dev/null 2>&1; then
    updated=$((updated + 1))
  else
    say "WARN $token: cscli allowlists не принял сети ($(wc -l < "$tmp/nets"))"; failed=$((failed + 1))
  fi
done < "$tmp/todo"

[ "$odd" -eq 0 ] || { say "WARN строк не той формы в $SRC: $odd — пропущены (make bots-sources)"; failed=$((failed + 1)); }
total=$(cscli allowlists list -o raw 2>/dev/null | awk -F, -v p="$PREFIX" 'NR > 1 && index($1, p) == 1 { n++; s += $6 } END { print n + 0 " allowlist, " s + 0 " сетей" }')
say "реестр $version — к allowlist ботов: $(wc -l < "$tmp/want"), закрыто robots.txt: $closed, обновлено: $updated, снято: $removed; итого $total"
[ "$failed" -eq 0 ] || exit 2
