#!/usr/bin/env bash
# Render .tpl configs to their non-.tpl counterparts via envsubst.
# Run on the server before `docker compose up`. Run locally (with .env
# populated) for validate.sh dry-runs.
set -euo pipefail
cd "$(dirname "$0")/.."

if [ ! -f .env ]; then
  echo "ERR: .env not found" >&2
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
done < <(find configs -type f -name '*.tpl')
