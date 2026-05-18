#!/usr/bin/env bash
# rg/grep по compose + configs + scripts + docs. Исключает .runtime/,
# rendered-конфиги и прочий шум.
set -euo pipefail
cd "$(dirname "$0")/../.."

if [ $# -lt 1 ]; then
  echo "usage: $0 <pattern> [path]" >&2
  exit 2
fi

pattern="$1"
path="${2:-}"

scope=()
if [ -n "$path" ]; then
  scope=("$path")
else
  for d in compose configs scripts docs ansible ci docker-compose.yml AGENTS.md README.md; do
    [ -e "$d" ] && scope+=("$d")
  done
fi

if command -v rg >/dev/null 2>&1; then
  rg --no-heading -n -S \
    --glob='!.runtime/**' --glob='!**/*.rendered' \
    "$pattern" "${scope[@]}"
else
  grep -rn -E "$pattern" "${scope[@]}"
fi
