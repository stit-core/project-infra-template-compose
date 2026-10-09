#!/usr/bin/env bash
# Preflight .env: значение, которое рендер пишет в конфиг edge как есть, и пара контуров
# не-прод среды.
#   ENV-ERR:  значение сломает роутеры сайта — код 1, отказ до рендера и деплоя;
#   ENV-WARN: среда поднимется, но закрыта не так, как задумано.
# Сами значения не печатает.
#
# Зовут scripts/render-configs.sh (с ним make render и make deploy) и make doctor.
set -euo pipefail
cd "$(dirname "$0")/.."

[ -f .env ] || exit 0

# Сырое значение ключа — последняя строка `KEY=…`: её же берут шелл рендера и compose.
raw() { sed -n "s/^$1=//p" .env | tail -n 1; }
# То же без обрамляющих кавычек.
val() { raw "$1" | sed -e "s/^'\(.*\)'\$/\1/" -e 's/^"\(.*\)"$/\1/'; }

rc=0

# Замок не-прод среды. Значение уходит в basicAuth как есть: строку без `:`, с пробелом
# или кавычкой он не разбирает, и роутеры сайта с замком не собираются. Одинарные
# кавычки — чтобы `$` хеша одинаково прочли шелл рендера и compose.
lock=$(raw STAGING_BASIC_AUTH_USERS)
[ "$lock" = "''" ] && lock=""
if [ -n "$lock" ] && ! printf '%s\n' "$lock" | grep -qE "^'[^:'[:space:]]+:[^:'[:space:]]+'\$"; then
  echo "ENV-ERR: STAGING_BASIC_AUTH_USERS — нужна одна строка 'user:hash' в одинарных кавычках: htpasswd -nbB <user> '<пароль>' (.env.example § profile site)."
  rc=1
fi

# Не-прод среду сайта закрывает пара: ROBOTS_POLICY=noindex и замок.
case ",$(val COMPOSE_PROFILES)," in
  *,site,*)
    policy=$(val ROBOTS_POLICY)
    if [ "$policy" = noindex ] && [ -z "$lock" ]; then
      echo "ENV-WARN: ROBOTS_POLICY=noindex, а STAGING_BASIC_AUTH_USERS пуст — сайт не-прод среды открыт без пароля."
    elif [ "$policy" != noindex ] && [ -n "$lock" ]; then
      echo "ENV-WARN: STAGING_BASIC_AUTH_USERS задан, а ROBOTS_POLICY не noindex — за замком robots.txt сайта разрешает индексацию."
    fi ;;
esac

exit "$rc"
