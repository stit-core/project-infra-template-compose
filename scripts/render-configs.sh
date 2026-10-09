#!/usr/bin/env bash
# Render-time config assembly: envsubst для configs/**/*.tpl → соседний файл
# без .tpl (rendered-файлы gitignored). Все значения — из .env (single source:
# identity, ACME, секреты профилей).
set -euo pipefail
cd "$(dirname "$0")/.."

if [ ! -f .env ]; then
  echo "ERR: .env не найден" >&2
  exit 1
fi

# Значение, которое сломает конфиг edge, не рендерится: отказ здесь — это и отказ
# make deploy до compose up.
bash scripts/preflight-env.sh

set -a
# shellcheck disable=SC1091
. ./.env
set +a

# Дефолт CA-сервера — прод-LE (оператор переопределяет ACME_CASERVER в .env
# для staging-тестов). envsubst не умеет ${VAR:-default}, поэтому здесь.
export ACME_CASERVER="${ACME_CASERVER:-https://acme-v02.api.letsencrypt.org/directory}"

# Пустой замок не-прод среды рендерится пользователем без пароля (`*`, как в
# /etc/shadow): войти под ним нельзя. Снятие замка рендерится раньше, чем compose
# пересоздаёт сайт без цепочки staging, — эти секунды роутер остаётся закрытым;
# с пустым пользователем basicAuth не собирается, и на адресах сайта отвечала
# бы заглушка.
export STAGING_BASIC_AUTH_USERS="${STAGING_BASIC_AUTH_USERS:-nobody:*}"

# Неизменённый файл не перезаписывается, изменённый пишется одним вызовом: за
# каталогом dynamic следит Traefik, и с файлом, прочитанным посреди записи,
# роутеры не собираются — секунды 404 на всём edge. Запись — поверх (inode
# тот же): bind-mount одного файла подмены не видит.
while IFS= read -r tpl; do
  out="${tpl%.tpl}"
  new=$(envsubst < "$tpl")
  if [ -f "$out" ] && [ "$new" = "$(cat "$out")" ]; then
    echo "unchanged $out"
  else
    printf '%s\n' "$new" > "$out"
    echo "rendered $out"
  fi
done < <(find configs -type f -name '*.tpl')
