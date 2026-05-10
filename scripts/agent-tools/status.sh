#!/usr/bin/env bash
# Repo state summary for /smartdev. No SSH; for full server-side checks
# pass --full (TBD when ssh.sh wrapper is added).
set -eo pipefail
cd "$(dirname "$0")/../.."

echo "== Branch =="
branch=$(git symbolic-ref --short HEAD 2>/dev/null || echo '(detached)')
if git rev-parse --verify HEAD >/dev/null 2>&1; then
  upstream=$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)
  if [ -n "$upstream" ]; then
    ahead=$(git rev-list --count "$upstream..HEAD" 2>/dev/null || echo 0)
    behind=$(git rev-list --count "HEAD..$upstream" 2>/dev/null || echo 0)
    echo "$branch ($ahead ahead, $behind behind $upstream)"
  else
    echo "$branch (no upstream)"
  fi
  echo "last: $(git log -1 --format='%h %s (%ar)')"
else
  echo "$branch (no commits yet)"
fi

echo
echo "== Working tree =="
mod=$(git status --short | grep -c '^ M' || true)
sta=$(git status --short | grep -c '^M ' || true)
unt=$(git status --short | grep -c '^??' || true)
echo "modified: $mod, staged: $sta, untracked: $unt"

echo
echo "== Compose =="
shopt -s globstar nullglob
fragments=(compose/*.yml)
echo "fragments: ${#fragments[@]}"
tpls=(configs/**/*.tpl)
echo "tpl-configs: ${#tpls[@]}"
shopt -u globstar nullglob

echo
echo "== Recent commits =="
git log --oneline -5 2>/dev/null | sed 's/^/  /' || echo "  (none)"

echo
echo "OK"
