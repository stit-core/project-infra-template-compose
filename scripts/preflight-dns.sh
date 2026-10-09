#!/usr/bin/env bash
# DNS preflight: проверка что A-записи на $DOMAIN и стандартные сабдомены
# указывают на этот VPS. Без них LE HTTP-01 challenge упадёт с NXDOMAIN,
# а traefik будет вечно ретрайнить и спамить логи.
#
# Не fail'ится — деплой продолжается, стек поднимается. Цель — дать
# оператору явный warning до того, как он начнёт диагностировать
# "почему cert не выпустился" по traefik-логам.
#
# Подключается из scripts/deploy.sh перед `compose up`.
set -euo pipefail
cd "$(dirname "$0")/.."

[ -f .env ] || exit 0
# shellcheck disable=SC1091
. ./.env

# IP этого VPS. ipify — публичный echo-сервис; fallback на hostname -I.
VPS_IP=$(curl -fsS --max-time 5 https://api.ipify.org 2>/dev/null \
         || hostname -I | awk '{print $1}')

# Хосты, которые ждут LE-cert. Корневой `$DOMAIN` — всегда (landing always-on).
# Сабдомены — только под активные профили: s3/minio под `storage`, api под
# `backend`, www под `site` (роутер site-www, редирект на корень). Иначе
# минимальный стек (без этих профилей) даёт ложный DNS-WARN на ещё не
# маршрутизируемые хосты — их роутеры/cert'ы поднимутся только с профилем.
hosts=("$DOMAIN")
profiles=",${COMPOSE_PROFILES:-},"
case "$profiles" in *,storage,*) hosts+=("s3.$DOMAIN" "minio.$DOMAIN") ;; esac
case "$profiles" in *,backend,*) hosts+=("api.$DOMAIN") ;; esac
case "$profiles" in *,site,*) hosts+=("www.$DOMAIN") ;; esac

# dig может отсутствовать на голой Debian — берём то что есть.
resolve() {
  if command -v dig >/dev/null 2>&1; then
    dig +short +time=3 +tries=1 @8.8.8.8 "$1" A 2>/dev/null | head -1
  elif command -v getent >/dev/null 2>&1; then
    getent ahostsv4 "$1" 2>/dev/null | awk '{print $1; exit}'
  else
    return 0
  fi
}

issues=0
for h in "${hosts[@]}"; do
  resolved=$(resolve "$h" || true)
  if [ -z "$resolved" ]; then
    echo "DNS-WARN: $h → NXDOMAIN. LE cert не выпустится."
    issues=$((issues + 1))
  elif [ "$resolved" != "$VPS_IP" ]; then
    echo "DNS-WARN: $h → $resolved (ожидали $VPS_IP). LE-валидация упадёт."
    issues=$((issues + 1))
  fi
done

if [ "$issues" -gt 0 ]; then
  cat <<EOF

$issues DNS-warning'ов. Cert на эти хосты не выпустится до фикса DNS.
Деплой продолжается — стек поднимется, traefik сам ретрайнет ACME
когда DNS будет на месте. Wildcard \`*.$DOMAIN A $VPS_IP\` покрывает
все сабдомены одной записью.

EOF
fi
