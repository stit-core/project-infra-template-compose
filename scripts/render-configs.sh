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

set -a
# shellcheck disable=SC1091
. ./.env
set +a

# Дефолт CA-сервера — прод-LE (оператор переопределяет ACME_CASERVER в .env
# для staging-тестов). envsubst не умеет ${VAR:-default}, поэтому здесь.
export ACME_CASERVER="${ACME_CASERVER:-https://acme-v02.api.letsencrypt.org/directory}"

# Неизменённый файл не перезаписывается, изменённый пишется одним вызовом: за
# каталогом dynamic следит Traefik, и файл, прочитанный посреди записи, на
# секунды оставляет роутеры без middleware. Запись — поверх (inode тот же):
# bind-mount одного файла подмены не видит.
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
