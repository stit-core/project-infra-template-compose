#!/usr/bin/env bash
# Pre-deploy gate: compose syntax + yamllint + .tpl render + .env.example
# coverage + frontmatter (skills/rules) + умолчания безопасности edge + синтаксис
# шелл-скриптов стека и форма расписаний.
# Concise-by-default (строка на проверку + каноничный хвост):
#   OK              — все проверки прошли/skip
#   FAIL: <чеки>    — список упавших, exit 1
# --format=detailed — полный per-item разбор (как раньше).
set -o pipefail
cd "$(dirname "$0")/../.."

DETAILED=0
[ "${1:-}" = "--format=detailed" ] && DETAILED=1

fail=0
declare -a failed=()

# rec <name> <PASS|SKIP|FAIL> <note> <detail-block>
rec() {
  local name="$1" status="$2" note="$3" detail="$4"
  [ "$status" = "FAIL" ] && { fail=1; failed+=("$name"); }
  if [ "$DETAILED" = "1" ]; then
    echo "== $name =="
    [ -n "$detail" ] && printf '%s\n' "$detail" | sed 's/^/  /'
    echo
  else
    printf "  %-16s %s%s\n" "$name" "$status" "${note:+ ($note)}"
  fi
}

# Форма .env — раньше, чем его прочтут compose и шелл: на строке не той формы они сами
# печатают её кусок — хеш, пароль.
env_err=""
if [ -f .env ] && ! env_cap=$(bash scripts/preflight-env.sh form 2>&1); then
  env_err=$(printf '%s\n' "$env_cap" | sed -n 's/^ENV-ERR: //p' | head -n 1)
fi

# 1. compose syntax
if ! command -v docker >/dev/null; then
  rec "compose syntax" SKIP "docker не установлен" "docker не установлен — пропускаем"
elif [ ! -f .env ]; then
  rec "compose syntax" SKIP "нет .env" ".env отсутствует — для подстановок нужен реальный .env"
elif [ -n "$env_err" ]; then
  rec "compose syntax" FAIL "$env_err" "$env_cap"
else
  args=(-f docker-compose.yml)
  for f in compose/*.yml; do [ -f "$f" ] && args+=(-f "$f"); done
  if cap=$(docker compose "${args[@]}" --env-file .env config -q 2>&1); then
    rec "compose syntax" PASS "" "OK"
  elif echo "$cap" | grep -qi 'cannot connect to the docker daemon\|is the docker daemon running'; then
    rec "compose syntax" SKIP "docker daemon недоступен" "$cap"
  else
    rec "compose syntax" FAIL "" "$cap"
  fi
fi

# 2. yamllint configs/ compose/
if ! command -v yamllint >/dev/null; then
  rec "yamllint" SKIP "не установлен" "yamllint не установлен (pip install yamllint)"
else
  if cap=$(yamllint -d "{extends: relaxed, rules: {line-length: disable}}" \
             configs/ compose/ docker-compose.yml 2>&1); then
    rec "yamllint" PASS "" "OK"
  else
    rec "yamllint" FAIL "" "$cap"
  fi
fi

# 3. .tpl rendering
shopt -s globstar nullglob
tpls=(configs/**/*.tpl)
if [ ${#tpls[@]} -eq 0 ]; then
  rec ".tpl render" SKIP "нет .tpl" ".tpl-файлов нет"
else
  # shellcheck disable=SC1091
  set -a; [ -f .env ] && [ -z "$env_err" ] && . ./.env; set +a
  bad=(); lines=""
  for tpl in "${tpls[@]}"; do
    if envsubst < "$tpl" >/dev/null 2>&1; then
      lines+="$tpl: OK"$'\n'
    else
      lines+="$tpl: FAIL"$'\n'; bad+=("$tpl")
    fi
  done
  lines="${lines%$'\n'}"
  if [ ${#bad[@]} -eq 0 ]; then
    rec ".tpl render" PASS "${#tpls[@]}" "$lines"
  else
    rec ".tpl render" FAIL "${bad[*]}" "$lines"
  fi
fi
shopt -u globstar nullglob

# 4. .env.example coverage
if [ ! -f .env.example ]; then
  rec ".env coverage" FAIL ".env.example отсутствует" ".env.example отсутствует"
else
  used=$(grep -rhoP '(?<!\$)\$\{[A-Z_][A-Z0-9_]*' compose/ configs/ docker-compose.yml 2>/dev/null \
          | sed 's/${//' | sort -u)
  missing=()
  while read -r var; do
    [ -z "$var" ] && continue
    grep -qE "^#?\s*$var=" .env.example || missing+=("$var")
  done <<<"$used"
  if [ ${#missing[@]} -eq 0 ]; then
    rec ".env coverage" PASS "" "OK — все used vars в .env.example"
  else
    rec ".env coverage" FAIL "${missing[*]}" "missing in .env.example: ${missing[*]}"
  fi
fi

# 5. frontmatter YAML (skills + rules) — невалидный ломает Gitea-рендер
#    (типичный кейс — ': ' в незакавыченном description). Авторитетно — python3+yaml;
#    нет его — дешёвый awk-fallback ловит тот же класс (guard работает и на голом окружении).
fm_files=()
for f in .claude/skills/*/SKILL.md .claude/rules/*.md; do [ -f "$f" ] && fm_files+=("$f"); done
if [ ${#fm_files[@]} -eq 0 ]; then
  rec "frontmatter" SKIP "нет skill/rule .md" "файлов нет"
elif command -v python3 >/dev/null && python3 -c 'import yaml' 2>/dev/null; then
  bad=$(python3 - "${fm_files[@]}" <<'PY'
import sys, yaml
for f in sys.argv[1:]:
    L = open(f, encoding='utf-8').read().split('\n')
    if not L or L[0].strip() != '---':
        print(f + ": нет открывающего ---"); continue
    try:
        end = L[1:].index('---') + 1
    except ValueError:
        print(f + ": нет закрывающего ---"); continue
    try:
        d = yaml.safe_load('\n'.join(L[1:end]))
    except Exception as e:
        print(f + ": " + str(e).splitlines()[0]); continue
    if not isinstance(d, dict) or 'name' not in d or 'description' not in d:
        print(f + ": нет name/description в frontmatter")
PY
)
  if [ -z "$bad" ]; then
    rec "frontmatter" PASS "${#fm_files[@]}" "OK — все frontmatter валидны"
  else
    rec "frontmatter" FAIL "$(printf '%s' "$bad" | paste -sd';' -)" "$bad"
  fi
else
  # fallback без python3+yaml: ': ' в незакавыченном scalar (name:/description:).
  bad=$(awk '
    FNR==1 { infm=0 }
    FNR==1 && $0=="---" { infm=1; next }
    infm && $0=="---" { infm=0; next }
    infm && /^[a-z_]+: / {
      v=$0; sub(/^[a-z_]+: /,"",v); q=substr(v,1,1)
      if (q!="\"" && q!="'\''" && v ~ /: /) print FILENAME": невалидный YAML — \x27: \x27 в незакавыченном "$0
    }
  ' "${fm_files[@]}")
  if [ -z "$bad" ]; then
    rec "frontmatter" SKIP "python3+yaml нет; awk-fallback чист" "поставь PyYAML (make setup) для полной проверки"
  else
    rec "frontmatter" FAIL "$(printf '%s' "$bad" | paste -sd';' -)" "$bad"
  fi
fi

# 6. Умолчания безопасности edge — по тексту compose/ и configs/, без docker и .env:
#    то, что снаружи выглядит рабочим стеком, а запрос пускает мимо edge.
#    Пределы — проверка читает текст, а не разобранный YAML и не итог `compose config`:
#      - роутеры видит только в labels сервисов compose; роутеры file-провайдера
#        (configs/traefik/dynamic/) и labels из extends, якорей и override-файлов — нет;
#      - `${VAR}` не раскрывает: цепочка начинается с crowdsec@file буквально;
#      - порт любого назначения у сервиса с включённым роутером — отказ
#        (правило compose-and-services), порт сервиса без роутера — нет; порт traefik —
#        только строкой "80:80" или "443:443", запись другой формы — отказ;
#      - catch-all правилом HostRegexp и docker-сокет, смонтированный не каталогом
#        /var/run или /run и не файлом docker.sock, не видит;
#      - поведение edge (заголовки, лимиты, редиректы, порядок цепочек) не видит.
edge_bad=()
# Один проход по сервисам. Роутеры из labels (map- и list-форма, значение в одну строку
# или с продолжением): у каждого есть цепочка, она начинается с crowdsec@file, а правило
# называет хост — catch-all отдаёт сервис чужому Host. Сервис с включённым роутером не
# публикует порт и не сидит в сети хоста: это вход мимо edge — без crowdsec, лимитов и
# Host-роутинга. docker-сокет — только у сервиса traefik, а его порты — только 80 и 443:
# на 8080 у Traefik ping и API.
while IFS= read -r line; do
  [ -n "$line" ] && edge_bad+=("$line")
done < <(awk '
  function ltrim(s) { sub(/^[ \t]+/, "", s); return s }
  FNR == 1 { insvc = 0; si = -1; svc = ""; pend = ""; inports = 0 }
  /^[ \t]*(#|$)/ { next }
  {
    match($0, /^[ \t]*/); i = RLENGTH
    if (pend != "") {
      if (i > pi) { val[pend] = val[pend] " " ltrim($0); next }
      pend = ""
    }
    if (inports) {
      if (i > porti) {
        port = ltrim($0); sub(/[ \t]+#.*$/, "", port); sub(/^-[ \t]*/, "", port); gsub(/["\047]/, "", port)
        if (svc == "traefik" && port != "80:80" && port != "443:443") extra[FILENAME SUBSEP svc] = extra[FILENAME SUBSEP svc] " " port
        next
      }
      inports = 0
    }
    if (i == 0) { insvc = ($0 ~ /^services:/); si = -1; svc = ""; next }
    if (!insvc) next
    if (si < 0) si = i
    if (i == si) {
      svc = ltrim($0); sub(/[ \t]*:.*$/, "", svc); gsub(/["\047]/, "", svc)
      file[FILENAME SUBSEP svc] = FILENAME; name[FILENAME SUBSEP svc] = svc; next
    }
    id = FILENAME SUBSEP svc
    if ($0 ~ /^[ \t]+ports:/) { ports[id] = 1; inports = 1; porti = i }
    if ($0 ~ /docker\.sock/ || $0 ~ /^[ \t]*-[ \t]*["\047]?\/(var\/)?run\/?:/) sock[id] = 1
    if ($0 ~ /^[ \t]+network_mode:[ \t]*["\047]?host/) hostnet[id] = 1
    if ($0 ~ /traefik\.enable["\047]?[:=][ \t]*["\047]?true/) on[id] = 1
    if (match($0, /traefik\.http\.routers\.[A-Za-z0-9_-]+\.(rule|middlewares)["\047]?[:=]/)) {
      key = substr($0, RSTART, RLENGTH); rest = substr($0, RSTART + RLENGTH)
      split(key, part, "."); field = part[5]; sub(/["\047]?[:=]$/, "", field)
      r = FILENAME ": роутер " part[4]
      seen[r] = 1; pend = r SUBSEP field; pi = i
      rest = ltrim(rest); if (rest ~ /^[>|][+-]?[ \t]*$/) rest = ""
      val[pend] = rest
    }
  }
  END {
    for (r in seen) {
      if (!((r SUBSEP "middlewares") in val)) print r " — без цепочки middlewares"
      else {
        chain = val[r SUBSEP "middlewares"]; gsub(/^[ \t"\047]+|[ \t"\047]+$/, "", chain)
        if (chain !~ /^crowdsec@file(,|\$|$)/) print r " — цепочка начинается не с crowdsec@file"
      }
      if (((r SUBSEP "rule") in val) && val[r SUBSEP "rule"] !~ /Host(Regexp)?\(/) print r " — правило не называет Host"
    }
    for (id in file) {
      if ((id in on) && (id in ports)) print file[id] ": сервис с Traefik-роутером публикует порт (ports:) — " name[id]
      if ((id in hostnet) && ((id in on) || name[id] == "traefik")) print file[id] ": network_mode: host — сервис слушает на хосте мимо edge — " name[id]
      if ((id in sock) && name[id] != "traefik") print file[id] ": docker-сокет — только у traefik — " name[id]
      if (id in extra) print file[id] ": traefik публикует порт сверх 80 и 443 —" extra[id]
    }
  }' docker-compose.yml compose/*.yml | sort)
# sanitizePath — умолчание Traefik (включён): правила на путь сопоставляются с приведённым
# путём, и выключенный он открывает запрет /_image записью //_image. Комментарий не считается.
while IFS= read -r line; do
  [ -n "$line" ] && edge_bad+=("$line: sanitizePath — умолчание Traefik не трогаем")
done < <(grep -rilE '^[^#]*sanitizePath' compose configs docker-compose.yml 2>/dev/null | sort)
# API и dashboard Traefik закрыты: api.insecure открывает их на 8080 без пароля, роутер на
# api@internal — наружу; API отдаёт dynamic-конфиг с ключом bouncer и хешем замка.
while IFS= read -r line; do
  [ -n "$line" ] && edge_bad+=("$line: API и dashboard Traefik наружу не открываем (api.insecure, api@internal)")
done < <(grep -rlE '^[^#]*(insecure:[[:space:]]*["'"'"']?true|--api\.insecure([[:space:]"'"'"']|=true|$)|api@internal)' compose configs docker-compose.yml 2>/dev/null | sort)
# Журнал доступа берёт из заголовков запроса только названные: с defaultMode: keep в него
# уходят Authorization и Cookie.
while IFS= read -r line; do
  [ -n "$line" ] && edge_bad+=("$line: журнал доступа с headers.defaultMode: keep пишет Authorization и Cookie")
done < <(awk '
  /^[ \t]*(#|$)/ { next }
  { match($0, /^[ \t]*/); i = RLENGTH }
  inhdr && i <= hi { inhdr = 0 }
  /^[ \t]*headers:[ \t]*$/ { inhdr = 1; hi = i; next }
  inhdr && /defaultMode:[ \t]*["\047]?keep/ { print FILENAME; nextfile }' configs/traefik/*.tpl 2>/dev/null | sort -u)
# Отрендеренный сосед .tpl несёт значения .env (ключ bouncer, хеш замка): вне .gitignore
# его закоммитит `git add -A` из make ship.
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  while IFS= read -r tpl; do
    git check-ignore -q "${tpl%.tpl}" || edge_bad+=("${tpl%.tpl}: отрендеренный файл не под .gitignore")
  done < <(find configs -type f -name '*.tpl' | sort)
fi
if [ ${#edge_bad[@]} -eq 0 ]; then
  rec "edge defaults" PASS "" "OK — crowdsec@file на каждом роутере, Host в правилах, сервисы с роутером без портов и не в сети хоста, docker-сокет — только у traefik, у traefik — порты 80 и 443, API и dashboard закрыты, sanitizePath не тронут, журнал без лишних заголовков, отрендеренные конфиги под .gitignore"
else
  detail=$(printf '%s\n' "${edge_bad[@]}")
  rec "edge defaults" FAIL "$(printf '%s' "$detail" | paste -sd';' - | sed 's/;/; /g')" "$detail"
fi

# 7. Скрипты стека и расписания. Синтаксическую ошибку в задании расписания деплой не
#    видит: задание падает в свой час. Строку расписания не той формы crond пропускает
#    молча. Интерпретатор — по первой строке файла; расписание — пять полей времени и
#    команда, файл задания edge (/opt/edge/<имя> — каталог configs/crowdsec) существует.
sh_bad=()
while IFS= read -r f; do
  case "$(head -n 1 "$f")" in
    '#!/bin/sh'*) sh -n "$f" 2>/dev/null || sh_bad+=("$f: синтаксис sh") ;;
    '#!'*bash*)   bash -n "$f" 2>/dev/null || sh_bad+=("$f: синтаксис bash") ;;
  esac
done < <(find configs containers scripts -type f | sort)
for f in configs/*/crontab containers/*/crontab; do
  [ -f "$f" ] || continue
  while IFS= read -r line; do
    [ -n "$line" ] && sh_bad+=("$f: $line")
  done < <(awk '
    /^[ \t]*(#|$)/ { next }
    {
      ok = (NF >= 6)
      for (i = 1; i <= 5 && ok; i++) if ($i !~ /^[0-9*\/,-]+$/) ok = 0
      if (!ok) { print "строка " FNR " — не «пять полей времени и команда»"; next }
      for (i = 6; i <= NF; i++) if ($i ~ /^\/opt\/edge\//) {
        job = $i; sub(/^\/opt\/edge\//, "", job)
        if ((getline probe < ("configs/crowdsec/" job)) < 0) print "строка " FNR " — нет задания configs/crowdsec/" job
        close("configs/crowdsec/" job)
      }
    }' "$f")
done
if [ ${#sh_bad[@]} -eq 0 ]; then
  rec "stack scripts" PASS "" "OK — синтаксис шелл-скриптов configs/, containers/, scripts/; форма расписаний"
else
  detail=$(printf '%s\n' "${sh_bad[@]}")
  rec "stack scripts" FAIL "$(printf '%s' "$detail" | paste -sd';' - | sed 's/;/; /g')" "$detail"
fi

[ "$DETAILED" = "0" ] && echo
if [ "$fail" -eq 0 ]; then
  echo "OK"
else
  echo "FAIL: ${failed[*]}"
  exit 1
fi
