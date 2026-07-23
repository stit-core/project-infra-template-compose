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

while IFS= read -r tpl; do
  out="${tpl%.tpl}"
  envsubst < "$tpl" > "$out"
  echo "rendered $out"
done < <(find configs -type f -name '*.tpl')
