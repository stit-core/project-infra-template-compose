#!/usr/bin/env bash
# envsubst для .tpl → файл без .tpl. На сервере запускается перед
# `docker compose up`. Локально (с заполненным .env) — для validate.sh dry-run.
#
# ВАЖНО: configs/vault-agent/templates/ исключаются. Эти .tpl читаются
# vault-agent'ом напрямую (consul-template syntax: {{ with secret ... }}),
# envsubst здесь только засрёт директорию orphan-копиями без .tpl,
# которые никто не читает.
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

while IFS= read -r tpl; do
  out="${tpl%.tpl}"
  envsubst < "$tpl" > "$out"
  echo "rendered $out"
done < <(find configs -type f -name '*.tpl' -not -path 'configs/vault-agent/templates/*')
