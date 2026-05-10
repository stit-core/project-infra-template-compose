#!/usr/bin/env bash
# Симлинк scripts/git-hooks/* в .git/hooks/ — чтобы хуки активировались на git-операциях.
set -euo pipefail
cd "$(dirname "$0")/.."

if [ ! -d .git ]; then
  echo "ERR: не git-репо (нет .git/)" >&2
  exit 1
fi

mkdir -p .git/hooks
for hook in scripts/git-hooks/*; do
  name=$(basename "$hook")
  ln -sf "../../$hook" ".git/hooks/$name"
  chmod +x "$hook"
  echo "  installed: $name"
done

echo "OK"
