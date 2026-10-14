#!/usr/bin/env bash
# smoke.d/90-site.sh — сервис site (профиль site), контракт сайта: infra-handoff.md в <org>/site.
# Часть drop-in смока (см. smoke-run.sh): бежит НА хосте, read-only, self exit 0; `ATTENTION:` в
# колонке 0. Проверяет:
#   - liveness — /healthz у контейнера;
#   - через edge — статус и заголовки главной по среде: прод — 200 без X-Robots-Tag, не-прод —
#     401 замка с X-Robots-Tag: noindex; не-прод без замка — ATTENTION; TTFB — печать без порога;
#   - содержимое — у контейнера (на не-прод edge без пароля отвечает 401 на всё): robots.txt —
#     на проде группа * с Allow: / и абсолютный Sitemap, на не-прод Disallow: /; sitemap.xml —
#     непустой список <loc>, все URL — https и свой домен.
# Домен и среду смок берёт у запущенного контейнера — SITE_URL, ROBOTS_POLICY и цепочку роутера
# site (замок — staging@file), — а не из .env: смок .env не читает.
set -o pipefail

echo "-- site --"

if ! command -v docker >/dev/null 2>&1 ||
   [ "$(docker inspect -f '{{.State.Running}}' site 2>/dev/null)" != true ]; then
  echo "  SKIP (контейнер site не запущен)"
  exit 0
fi

env=$(docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' site)
origin=$(sed -n 's/^SITE_URL=//p' <<<"$env"); host=${origin#https://}
policy=$(sed -n 's/^ROBOTS_POLICY=//p' <<<"$env")
chain=$(docker inspect -f '{{index .Config.Labels "traefik.http.routers.site.middlewares"}}' site)
lock=0; case ",$chain," in *,staging@file,*) lock=1 ;; esac
in_site() { docker exec site wget -qO- "http://127.0.0.1:3000$1" 2>/dev/null; }

if in_site /healthz >/dev/null; then
  printf "  %-12s %s\n" "liveness:" "ok (/healthz у контейнера)"
else
  printf "  %-12s %s\n" "liveness:" "нет ответа /healthz у контейнера"
  echo "ATTENTION: site не отвечает на /healthz — make logs SVC=site / triage"
fi

if [ "$lock" = 1 ]; then env_name="не-прод (замок, ROBOTS_POLICY=$policy)"
elif [ "$policy" = noindex ]; then env_name="не-прод без замка (ROBOTS_POLICY=noindex)"
else env_name="прод (ROBOTS_POLICY=${policy:-index})"; fi
printf "  %-12s %s\n" "env:" "$env_name; $origin"
[ "$lock" = 1 ] || [ "$policy" != noindex ] ||
  echo "ATTENTION: не-прод без замка — сайт открыт без пароля: STAGING_BASIC_AUTH_USERS в .env, затем make deploy"

if ! command -v curl >/dev/null 2>&1; then
  printf "  %-12s %s\n" "edge /:" "SKIP (нет curl)"
else
  h=$(curl -sk -o /dev/null -D - -w '\n%{http_code} %{time_starttransfer}' --max-time 10 \
        --resolve "$host:443:127.0.0.1" "https://$host/" 2>/dev/null | tr -d '\r')
  read -r code ttfb <<<"$(tail -n 1 <<<"$h")"
  xrt=$(grep -i '^x-robots-tag:' <<<"$h" | head -n 1 | cut -d' ' -f2-)
  printf "  %-12s %s\n" "edge /:" "${code:-000}, TTFB ${ttfb:-?} с, X-Robots-Tag: ${xrt:-нет}"
  if [ "$lock" = 1 ]; then
    [ "$code" = 401 ] && [[ "$xrt" == noindex* ]] ||
      echo "ATTENTION: не-прод: / через edge — ${code:-000}, X-Robots-Tag: ${xrt:-нет} (ждали 401 замка и noindex) — make accept SVC=site"
  elif [ "$policy" != noindex ]; then
    [ "$code" = 200 ] && [ -z "$xrt" ] ||
      echo "ATTENTION: прод: / через edge — ${code:-000}, X-Robots-Tag: ${xrt:-нет} (ждали 200 без него) — make accept SVC=site"
  fi
fi

robots=$(in_site /robots.txt)
if [ "$policy" = noindex ]; then
  if grep -qx 'Disallow: /' <<<"$robots"; then printf "  %-12s %s\n" "robots.txt:" "Disallow: /"
  else
    printf "  %-12s %s\n" "robots.txt:" "без Disallow: / при ROBOTS_POLICY=noindex"
    echo "ATTENTION: не-прод: robots.txt сайта открывает индексацию — make logs SVC=site"
  fi
else
  sitemap_line=$(grep -i '^Sitemap:' <<<"$robots" | head -n 1)
  if [ "$(head -n 2 <<<"$robots" | tr '\n' '|')" = "User-agent: *|Allow: /|" ] && [ "$sitemap_line" = "Sitemap: $origin/sitemap.xml" ]; then
    printf "  %-12s %s\n" "robots.txt:" "группа * открыта, $sitemap_line"
  else
    printf "  %-12s %s\n" "robots.txt:" "не тот: $(head -n 2 <<<"$robots" | tr '\n' ' ')${sitemap_line:-без Sitemap}"
    echo "ATTENTION: прод: robots.txt — не группа * с Allow: / и Sitemap $origin/sitemap.xml — make logs SVC=site"
  fi
fi

locs=$(in_site /sitemap.xml | grep -o '<loc>[^<]*</loc>')
total=$(grep -c . <<<"$locs")
foreign=$(grep -vc "^<loc>$origin/" <<<"$locs")
if [ "$total" -gt 0 ] && [ "$foreign" = 0 ]; then
  printf "  %-12s %s\n" "sitemap.xml:" "$total URL, все на $origin/"
else
  printf "  %-12s %s\n" "sitemap.xml:" "$total URL, не на $origin/ — $foreign"
  echo "ATTENTION: sitemap.xml сайта пуст или не на $origin — штамповка origin (make logs SVC=site)"
fi

exit 0
