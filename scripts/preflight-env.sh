#!/usr/bin/env bash
# Preflight .env: форма строк файла, замок не-прод среды и пара её контуров.
#   ENV-ERR:  строку шелл и compose прочтут по-разному или не прочтут вовсе, либо замок,
#             с которым роутеры сайта не собираются или войти нельзя, — код 1;
#   ENV-WARN: среда поднимется, но закрыта не так, как задумано.
# Значений не печатает — только ключ и номер строки.
#
# Бежит раньше, чем .env прочтут шелл и compose: на строке не той формы они сами печатают
# её кусок — хеш, пароль. Зовут scripts/render-configs.sh (с ним make render и make deploy)
# и make doctor; в режиме `form` (только форма строк) — make validate и ops-вербы Makefile.
set -euo pipefail
cd "$(dirname "$0")/.."

[ -f .env ] || exit 0

rc=0
q="'"

# Строка .env — пусто, комментарий или KEY=значение с начала строки, без пробелов у `=`.
# Значение — слово без пробелов, кавычек и знаков шелла, либо '…', либо "…" без
# подстановок; после него — только комментарий. Такую строку одинаково читают
# `. ./.env` скриптов, compose и построчное чтение ключей (sed, grep).
word='[^[:space:]"`$\;&|<>()'"$q"']*'
form="^([[:blank:]]*(#.*)?|[A-Za-z_][A-Za-z0-9_]*=($word|$q[^$q]*$q|\"[^\"\`\$\\]*\")([[:blank:]]+#.*)?[[:blank:]]*)\$"
lock_text="ENV-ERR: STAGING_BASIC_AUTH_USERS — нужна одна строка 'user:hash' в одинарных кавычках: логин из латинских букв, цифр и ._@-, хеш — bcrypt целиком: htpasswd -nbB <user> '<пароль>' (.env.example § profile site)."

# У строки замка форма одна: пусто или '…' — `$` хеша вне одинарных кавычек шелл и compose
# читают как подстановку.
bad=$(grep -nvE "$form" .env | grep -vE '^[0-9]+:STAGING_BASIC_AUTH_USERS=' || true)
shown=0
while IFS= read -r line; do
  [ -n "$line" ] || continue
  shown=$((shown + 1)); rc=1
  [ "$shown" -le 5 ] || continue
  n=${line%%:*}; key=""
  # Имя ключа печатается, только когда оно похоже на имя: слева от `=` в битой строке
  # может стоять и кусок значения.
  [[ ${line#*:} =~ ^[[:blank:]]*([A-Z][A-Z0-9_]*)[[:blank:]]*= ]] && key=${BASH_REMATCH[1]}
  echo "ENV-ERR: ${key:+$key — }.env, строка $n: нужна форма KEY=значение с начала строки, без пробелов у «=»; значение с пробелом, \$, кавычкой или знаком шелла — в одинарных кавычках (перевод строки — LF)."
done <<<"$bad"
[ "$shown" -le 5 ] || echo "ENV-ERR: .env — ещё строк не той формы: $((shown - 5))."
locks=$(sed -n 's/^STAGING_BASIC_AUTH_USERS=//p' .env)
if [ -n "$locks" ] && printf '%s\n' "$locks" | grep -qvE "^(|$q[^$q]*$q)\$"; then
  echo "$lock_text"; rc=1
fi

if [ "${1:-}" = form ] || [ "$rc" -ne 0 ]; then exit "$rc"; fi

# Значение ключа — последняя строка `KEY=…` без обрамляющих кавычек: её же берут шелл и compose.
val() { sed -n "s/^$1=//p" .env | tail -n 1 | sed -e "s/^'\(.*\)'\$/\1/" -e 's/^"\(.*\)"$/\1/'; }
site=0
case ",$(val COMPOSE_PROFILES)," in *,site,*) site=1 ;; esac

# Замок не-прод среды уходит в basicAuth как есть. Логин — буквы, цифры и `._@-`: на `{{`
# Traefik отвергает весь файл dynamic-конфига и молча живёт на прежнем. Хеш — bcrypt
# целиком: с открытым паролем, обрезанным или незнакомым хешем замок закрыт, а войти нельзя.
lock=$(val STAGING_BASIC_AUTH_USERS)
if [ -n "$lock" ] && ! printf '%s\n' "$lock" | grep -qE '^[A-Za-z0-9._@-]+:[$]2[aby][$][0-9]{2}[$][./A-Za-z0-9]{53}$'; then
  echo "$lock_text"; rc=1
fi

# Не-прод среду сайта закрывает пара: ROBOTS_POLICY=noindex и замок.
if [ "$site" = 1 ]; then
  policy=$(val ROBOTS_POLICY)
  if [ "$policy" = noindex ] && [ -z "$lock" ]; then
    echo "ENV-WARN: ROBOTS_POLICY=noindex, а STAGING_BASIC_AUTH_USERS пуст — сайт не-прод среды открыт без пароля."
  elif [ "$policy" != noindex ] && [ -n "$lock" ]; then
    echo "ENV-WARN: STAGING_BASIC_AUTH_USERS задан, а ROBOTS_POLICY не noindex — за замком robots.txt сайта разрешает индексацию."
  fi
fi

exit "$rc"
