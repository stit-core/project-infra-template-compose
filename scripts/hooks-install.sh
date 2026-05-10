#!/usr/bin/env bash
# Symlink scripts/git-hooks/* into .git/hooks/ so they activate on git ops.
set -euo pipefail
cd "$(dirname "$0")/.."

if [ ! -d .git ]; then
  echo "ERR: not in a git repo (no .git/)" >&2
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
