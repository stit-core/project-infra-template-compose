#!/usr/bin/env bash
# Pre-deploy gate: compose syntax + yamllint + .tpl render + .env.example
# coverage + frontmatter (skills/rules) + умолчания безопасности edge.
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

# 1. compose syntax
if ! command -v docker >/dev/null; then
  rec "compose syntax" SKIP "docker не установлен" "docker не установлен — пропускаем"
elif [ ! -f .env ]; then
  rec "compose syntax" SKIP "нет .env" ".env отсутствует — для подстановок нужен реальный .env"
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
  set -a; [ -f .env ] && . ./.env; set +a
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
edge_bad=()
# Роутеры из labels (map- и list-форма): у каждого есть цепочка, она начинается с
# crowdsec@file, а правило называет хост — catch-all отдаёт сервис чужому Host.
while IFS= read -r line; do
  [ -n "$line" ] && edge_bad+=("$line")
done < <(awk '
  /^[ \t]*#/ { next }
  match($0, /traefik\.http\.routers\.[A-Za-z0-9_-]+\.(rule|middlewares)["\047]?[:=]/) {
    key = substr($0, RSTART, RLENGTH); val = substr($0, RSTART + RLENGTH)
    n = split(key, part, "."); name = part[4]; field = part[5]; sub(/["\047]?[:=]$/, "", field)
    gsub(/^[ \t"\047]+|[ \t"\047]+$/, "", val)
    id = FILENAME ": роутер " name
    seen[id] = 1
    if (field == "rule") rule[id] = val; else chain[id] = val
  }
  END {
    for (id in seen) {
      if (!(id in chain)) print id " — без цепочки middlewares"
      else if (chain[id] !~ /^crowdsec@file(,|\$|$)/) print id " — цепочка начинается не с crowdsec@file"
      if ((id in rule) && rule[id] !~ /Host(Regexp)?\(/) print id " — правило не называет Host"
    }
  }' compose/*.yml | sort)
for f in compose/*.yml; do
  # Порт сервиса с Traefik-роутером — вход мимо edge: без crowdsec, лимитов и Host-роутинга.
  if grep -qE '^[^#]*traefik\.enable' "$f" && grep -qE '^[[:space:]]*ports:' "$f"; then
    edge_bad+=("$f: сервис с Traefik-роутером публикует порт (ports:)")
  fi
  if [ "$f" != compose/traefik.yml ] && grep -qE '^[^#]*docker\.sock' "$f"; then
    edge_bad+=("$f: docker-сокет — только у traefik")
  fi
done
# sanitizePath — умолчание Traefik (включён): правила на путь сопоставляются с приведённым
# путём, и выключенный он открывает запрет /_image записью //_image.
while IFS= read -r line; do
  [ -n "$line" ] && edge_bad+=("$line: sanitizePath — умолчание Traefik не трогаем")
done < <(grep -rilE 'sanitizePath' compose configs docker-compose.yml 2>/dev/null | sort)
# Отрендеренный сосед .tpl несёт значения .env (ключ bouncer, хеш замка): вне .gitignore
# его закоммитит `git add -A` из make ship.
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  while IFS= read -r tpl; do
    git check-ignore -q "${tpl%.tpl}" || edge_bad+=("${tpl%.tpl}: отрендеренный файл не под .gitignore")
  done < <(find configs -type f -name '*.tpl' | sort)
fi
if [ ${#edge_bad[@]} -eq 0 ]; then
  rec "edge defaults" PASS "" "OK — crowdsec@file на каждом роутере, Host в правилах, сервисы с роутером без портов, docker-сокет — только у traefik, sanitizePath не тронут, отрендеренные конфиги под .gitignore"
else
  detail=$(printf '%s\n' "${edge_bad[@]}")
  rec "edge defaults" FAIL "$(printf '%s' "$detail" | paste -sd';' - | sed 's/;/; /g')" "$detail"
fi

[ "$DETAILED" = "0" ] && echo
if [ "$fail" -eq 0 ]; then
  echo "OK"
else
  echo "FAIL: ${failed[*]}"
  exit 1
fi
