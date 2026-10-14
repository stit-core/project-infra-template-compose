#!/usr/bin/env bash
# Приёмка сервиса после деплоя — машиной, на VPS: make accept SVC=site. Проверки — по контракту
# сайта (infra-handoff.md в <org>/site, § Edge и § Боты) в профиле среды, который приёмка
# берёт у запущенного контейнера: замок (staging@file в цепочке роутера site) — не-прод, без
# замка — прод. На не-прод edge без пароля отвечает 401 на всё, поэтому страницы, формы адреса и
# сжатия проверяет прод-профиль, а не-прод — замок, X-Robots-Tag и то, что стоит до замка.
#   - страница для проверок формы адреса — из sitemap.xml сайта, UA-проба — по токенам
#     configs/crowdsec/ai-bots.sources: каждому тот же ответ, что без UA; в User-Agent проб — метка
#     make-accept: отчёт «бот × статус» (runbook) их не считает;
#   - смок edge и сайта (smoke.d/30-edge.sh, 90-site.sh) — без ATTENTION;
#   - сверх списка: записи Host на www и apex (порт, регистр, точка в конце), ключи записи журнала
#     доступа, закрытые dashboard и API Traefik, отказ WAF — 429 адресу под решением (решение — на
#     адрес временного клиента в сети proxy: решения на свой адрес хост не ставит).
# Что сайт проверяет в образе сам (pnpm accept:image: отказ без SITE_URL, CSP, дренаж) — не здесь;
# дренаж на работающей среде не проверяется: он останавливает сайт. TLS-цепочка — строка без оценки:
# на стенде шаблона сертификат самоподписанный.
# Код: 0 — всё зелёное, иначе — ✗ в выводе или «принимать нечего».
set -uo pipefail
cd "$(dirname "$0")/../.."

svc=${1:-}
[ "$svc" = site ] || { echo "приёмка есть у сервиса site: make accept SVC=site" >&2; exit 2; }
[ "$(docker inspect -f '{{.State.Running}}' site 2>/dev/null)" = true ] ||
  { echo "контейнер site не запущен — make bump SVC=site TAG=<тег> (docs/reference/runbook.md)" >&2; exit 2; }

env=$(docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' site)
origin=$(sed -n 's/^SITE_URL=//p' <<<"$env"); host=${origin#https://}
policy=$(sed -n 's/^ROBOTS_POLICY=//p' <<<"$env")
chain=$(docker inspect -f '{{index .Config.Labels "traefik.http.routers.site.middlewares"}}' site)
prod=1; case ",$chain," in *,staging@file,*) prod=0 ;; esac
U=$origin
in_site() { docker exec site wget -qO- "http://127.0.0.1:3000$1" 2>/dev/null; }
paths=$(in_site /sitemap.xml | grep -o '<loc>[^<]*</loc>' | sed -e "s#^<loc>$origin##" -e 's#</loc>$##')
page=$(grep -E '^/[a-z0-9-]+$' <<<"$paths" | head -n 1)
section=$(grep -E '^/[a-z0-9-]+/[a-z0-9-]+$' <<<"$paths" | head -n 1)

fails=0
check() { # <имя> <факт> <ERE ожидания>
  if printf '%s' "$2" | grep -qE "$3"; then echo "  ✓ $1: $2"; else echo "  ✗ $1: $2 (ждали: $3)"; fails=$((fails + 1)); fi
}
say() { printf '\n== %s ==\n' "$1"; }
# Запросы к edge этого хоста: имена сайта — на 127.0.0.1, путь — как записан.
c() { curl -sk --max-time 10 --path-as-is --resolve "$host:443:127.0.0.1" --resolve "www.$host:443:127.0.0.1" \
        --resolve "$host:80:127.0.0.1" "$@" 2>/dev/null; }
code() { c -o /dev/null -w '%{http_code}' "$@"; }
hop() { c -o /dev/null -w '%{http_code} %{redirect_url}' "$@"; }
hdrs() { c -o /dev/null -D - "$@" | tr -d '\r'; }
# Чей ответ: site — у ответов сайта CSP, иначе edge (сам Traefik или заглушка).
who() { local h; h=$(hdrs "$@"); printf '%s %s' "$(grep -qi '^content-security-policy:' <<<"$h" && echo site || echo edge)" "$(head -n 1 <<<"$h" | grep -oE '[0-9]{3}' | head -n 1)"; }

# Решение пробы WAF снимается вместе с его тревогой: в истории CrowdSec приёмка следа не оставляет.
waf=""; dec=""
cleanup() { [ -z "$dec" ] || docker exec crowdsec cscli alerts delete --ip "$dec" >/dev/null 2>&1; [ -z "$waf" ] || docker rm -f "$waf" >/dev/null 2>&1; }
trap cleanup EXIT

if [ "$prod" = 1 ]; then profile="прод"; want=200; else profile="не-прод (замок)"; want=401; fi
echo "приёмка site: $origin, профиль — $profile, ROBOTS_POLICY=${policy:-index}; страница — ${page:-нет}, двухсегментная — ${section:-нет}"
tls=$(c -o /dev/null -w '%{ssl_verify_result}' "$U/")
echo "TLS: $([ "$tls" = 0 ] && echo "цепочка сертификата проверена" || echo "цепочка сертификата не проверена (код ${tls:-?}) — сертификат ещё не выпущен?")"

say "сервис"
check "site healthy" "$(docker inspect -f '{{.State.Health.Status}}' site)" '^healthy$'
check "плейсхолдер origin в выходе сборки — файлов" "$(docker exec site sh -c 'grep -rl __site_origin__ /app/dist/client 2>/dev/null | wc -l' | tr -d ' ')" '^0$'
stamp=$(docker logs site 2>&1 | grep -o "\[entrypoint\] stamped https://__site_origin__ -> $origin in /app/dist/client" | tail -n 1)
echo "    строка штамповки в логе: ${stamp:-нет (лог мог уйти ротацией)}"
check "ошибок в логе сайта" "$(docker logs site 2>&1 | grep -c '"lvl":"error"')" '^0$'
check "страница из sitemap.xml" "${page:-нет}" '^/'

say "смок edge и сайта"
for f in scripts/tools/smoke.d/30-edge.sh scripts/tools/smoke.d/90-site.sh; do
  out=$(bash "$f" 2>&1)
  grep -v '^ATTENTION' <<<"$out" | sed 's/^/    /'
  while IFS= read -r a; do [ -z "$a" ] || { echo "  ✗ $a"; fails=$((fails + 1)); }; done <<<"$(grep '^ATTENTION' <<<"$out")"
done

say "адрес и среда"
h=$(hdrs "$U/")
if [ "$prod" = 1 ]; then
  check "/ — код и X-Robots-Tag" "$(head -n 1 <<<"$h" | grep -oE '[0-9]{3}') [$(grep -i '^x-robots-tag:' <<<"$h")]" '^200 \[\]$'
  robots=$(c "$U/robots.txt")
  check "robots.txt: группа *" "$(head -n 2 <<<"$robots" | tr '\n' ' ')" '^User-agent: \* Allow: / $'
  check "robots.txt: Clean-param" "$(grep -i '^Clean-param:' <<<"$robots" | head -n 1 | cut -c1-80)" '^Clean-param: [^ ]'
  check "robots.txt: Sitemap" "$(grep -i '^Sitemap:' <<<"$robots" | head -n 1)" "^Sitemap: $origin/sitemap\\.xml\$"
  locs=$(c "$U/sitemap.xml" | grep -o '<loc>[^<]*</loc>')
  check "sitemap.xml: URL / не https://$host" "$(grep -c . <<<"$locs") / $(grep -vc "^<loc>$origin/" <<<"$locs")" '^[1-9][0-9]* / 0$'
  check "адрес без страницы — 404" "$(code "$U/net-takogo-accept")" '^404$'
  check "/index.html — 301 на /" "$(hop "$U/index.html")" "^301 $origin/\$"
  check "$page/index.html — 301 на $page" "$(hop "$U$page/index.html")" "^301 $origin$page\$"
  check "$page/ — 301 на $page" "$(hop "$U$page/")" "^301 $origin$page\$"
  if [ -n "$section" ]; then
    check "${section%/*}%2F${section##*/} — 404" "$(code "$U${section%/*}%2F${section##*/}")" '^404$'
  else
    echo "    двухсегментной страницы в sitemap.xml нет — проверка %2F пропущена"
  fi
  check "/$page — 200, canonical на канон" "$(code "$U/$page") $(c "$U/$page" | grep -o '<link rel="canonical" href="[^"]*"' | head -n 1)" "^200 <link rel=\"canonical\" href=\"$origin$page\"\$"
  check "/healthz — 200 no-store" "$(code "$U/healthz") $(hdrs "$U/healthz" | grep -i '^cache-control:' | head -n 1)" '^200 [Cc]ache-[Cc]ontrol: no-store$'
  check "плейсхолдер origin в HTML главной" "$(c "$U/" | grep -c __site_origin__)" '^0$'
  check "/llms.txt — 404 text/plain" "$(code "$U/llms.txt") $(hdrs "$U/llms.txt" | grep -i '^content-type:' | head -n 1 | cut -d' ' -f2)" '^404 text/plain'
else
  check "/ без пароля — 401 замка с X-Robots-Tag" "$(head -n 1 <<<"$h" | grep -oE '[0-9]{3}') [$(grep -i '^x-robots-tag:' <<<"$h")]" '^401 \[[Xx]-[Rr]obots-[Tt]ag: noindex, nofollow, noarchive\]$'
  check "robots.txt и sitemap.xml без пароля — 401" "$(code "$U/robots.txt") $(code "$U/sitemap.xml")" '^401 401$'
fi
check "http:// — один редирект на https" "$(hop "http://$host/") / $(c -L -o /dev/null -w '%{num_redirects}' "http://$host/") хоп" "^30[18] $origin/ / 1 хоп\$"
check "www — один 301 на apex" "$(hop "https://www.$host/") / $(c -L -o /dev/null -w '%{num_redirects}' "https://www.$host/") хоп" "^301 $origin/ / 1 хоп\$"
for p in '/_image?href=/og-default.png&f=webp' '//_image' '/./_image' '/%5Fimage'; do
  check "$p — 403 на edge" "$(code "$U$p")" '^403$'
done

say "записи Host"
for hv in "www.$host" "www.$host:443" "WWW.$host" "www.$host."; do
  check "www «$hv»: $page — 301 на apex" "$(hop --http1.1 -H "Host: $hv" "https://www.$host$page")" "^301 $origin$page\$"
done
[ "$prod" = 1 ] && apex='^site 200$' || apex='^edge 401$'
for hv in "$host:443" "$(tr '[:lower:]' '[:upper:]' <<<"$host")" "$host."; do
  check "apex «$hv»: $page" "$(who --http1.1 -H "Host: $hv" "$U$page")" "$apex"
done
check "чужой Host — 404 edge, до сайта не доходит" "$(who --http1.1 -H 'Host: accept.invalid' "$U$page")" '^edge 404$'

say "методы"
check "POST / — не 200" "$(code -X POST "$U/")" '^[45][0-9][0-9]$'
check "TRACE / — не 200" "$(code -X TRACE "$U/")" '^[45][0-9][0-9]$'

say "заголовки"
if [ "$prod" = 1 ]; then
  h=$(hdrs -H 'Accept-Encoding: br' "$U/")
else
  h=$(hdrs "$U/")
fi
check "четыре заголовка edge" "$(grep -ciE '^(strict-transport-security: max-age=31536000; includeSubDomains|x-content-type-options: nosniff|referrer-policy: strict-origin-when-cross-origin|permissions-policy: camera=\(\), microphone=\(\), geolocation=\(\))$' <<<"$h")" '^4$'
check "X-Frame-Options и X-XSS-Protection" "$(grep -ciE '^(x-frame-options|x-xss-protection):' <<<"$h")" '^0$'
if [ "$prod" = 1 ]; then
  check "CSP приложения с frame-ancestors 'none'" "$(grep -ci "^content-security-policy: .*frame-ancestors 'none'" <<<"$h")" '^1$'
  check "сжатие HTML (GET, Accept-Encoding: br)" "$(grep -i '^content-encoding:' <<<"$h")" '^[Cc]ontent-[Ee]ncoding: br$'
fi

say "форма"
series=""
for _ in 1 2 3 4 5 6 7 8; do
  s=$(code -X POST -H "Origin: $origin" -d 'name=&email=&message=' "$U/api/contact"); series="$series $s"
  [ "$s" = 429 ] && break
done
check "серия POST /api/contact упирается в 429, без 403 и принятой заявки (303)" "$series" '^( (200|401))* 429$'

say "UA-проба: ответ edge тот же, что без UA ($want)"
bad=""
for ua in $(awk 'NR > 1 && NF == 4 { print $2 }' configs/crowdsec/ai-bots.sources); do
  s=$(code -A "Mozilla/5.0 (compatible; $ua/1.0; make-accept)" "$U/"); [ "$s" = "$want" ] || bad="$bad $ua=$s"
done
check "ботов из ai-bots.sources — $(awk 'NR > 1 && NF == 4' configs/crowdsec/ai-bots.sources | wc -l | tr -d ' '), с другим ответом" "[${bad# }]" '^\[\]$'

say "CrowdSec и журнал"
check "постоверфлоу rdns и seo-bots-whitelist" "$(docker exec crowdsec cscli postoverflows list -o raw 2>/dev/null | grep -cE '^crowdsecurity/(rdns|seo-bots-whitelist),enabled,')" '^2$'
# Запись ищется по своему X-Request-Id; Authorization и Cookie запроса в неё попасть не должны.
mark="make-accept-$$-$(date +%s)"
code -A "Mozilla/5.0 (compatible; $mark)" -H "X-Request-Id: $mark" -H 'Authorization: Basic YWNjZXB0OmFjY2VwdA==' \
  -H 'Cookie: accept=1' "$U/" >/dev/null
rec=""
for _ in 1 2 3 4 5; do
  sleep 1; rec=$(docker exec crowdsec grep -F "\"request_X-Request-Id\":\"$mark\"" /var/log/traefik/access.log 2>/dev/null | tail -n 1)
  [ -n "$rec" ] && break
done
check "запись журнала: статус и request_User-Agent" "$(grep -o '"DownstreamStatus":[0-9]*' <<<"$rec") $(grep -o '"request_User-Agent":"[^"]*"' <<<"$rec")" "^\"DownstreamStatus\":$want \"request_User-Agent\":\"Mozilla/5.0 \\(compatible; $mark\\)\"\$"
check "ключи request_* записи — только User-Agent и X-Request-Id" "$(grep -o '"request_[^"]*"' <<<"$rec" | sort -u | tr '\n' ' ')" '^"request_User-Agent" ("request_X-Request-Id" )?$'
# Отказ WAF: решение на адрес временного клиента в сети proxy; у нового адреса прежнего вердикта
# в кеше bouncer нет — ответ edge сразу 429.
img=$(docker inspect -f '{{.Config.Image}}' traefik)
waf=accept-waf-$$
if docker run -d --rm --name "$waf" --network proxy --entrypoint sleep "$img" 120 >/dev/null 2>&1; then
  dec=$(docker inspect -f '{{with index .NetworkSettings.Networks "proxy"}}{{.IPAddress}}{{end}}' "$waf")
  docker exec crowdsec cscli decisions add --ip "$dec" --duration 2m --reason make-accept >/dev/null 2>&1
  s=$(docker exec "$waf" wget -q -S -O /dev/null --no-check-certificate --header "Host: $host" https://traefik/ 2>&1 | awk '/^ *HTTP\//{ c = $2 } END { print c }')
  check "адрес под решением CrowdSec — 429 от edge, а не 403" "${s:-нет ответа}" '^429$'
else
  check "временный клиент в сети proxy для пробы WAF" "не запустился ($img)" '^запущен$'
fi

say "edge"
check "порты traefik наружу — только 80 и 443" "$(docker port traefik | cut -d/ -f1 | sort -un | tr '\n' ' ')" '^443 80 $|^80 443 $'
check "dashboard и API Traefik через edge — не открыты" "$(code "$U/dashboard/") $(code "$U/api/rawdata")" '^(301|308|401|404) (401|404)$'

echo
if [ "$fails" -gt 0 ]; then echo "приёмка site, профиль — $profile: не прошло — $fails"; exit 1; fi
echo "приёмка site, профиль — $profile: всё зелёное"
