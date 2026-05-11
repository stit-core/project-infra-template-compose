#!/usr/bin/env bash
# Единственный путь изменений → сервер.
#
# Usage:
#   bash scripts/ship.sh "feat(foo): bar"    # add -A + commit + push + (if main) ssh-deploy
#   bash scripts/ship.sh                     # push + (if main) ssh-deploy. Без коммита (working tree чистый).
#
# Адрес VPS читается из ansible/inventory.ini (host=root@<ip>).
set -euo pipefail
cd "$(dirname "$0")/.."

msg="${1:-}"
branch=$(git symbolic-ref --short HEAD 2>/dev/null) || { echo "ERR: not on a branch" >&2; exit 1; }

dirty=0
if ! git diff --quiet HEAD 2>/dev/null \
   || ! git diff --cached --quiet 2>/dev/null \
   || [ -n "$(git ls-files --others --exclude-standard)" ]; then
  dirty=1
fi

if [ "$dirty" -eq 1 ]; then
  [ -z "$msg" ] && {
    echo "ERR: working tree dirty — передай commit message:" >&2
    echo "     make ship MSG='feat(foo): bar'" >&2
    exit 1
  }
  echo "→ commit"
  git add -A
  git commit -m "$msg"
fi

echo "→ push origin $branch"
git push origin "$branch"

if [ "$branch" != "main" ]; then
  echo "→ branch '$branch' запушена. Открой PR в Gitea, мержи в main, потом ship снова."
  exit 0
fi

# SSH-deploy: адрес VPS из ansible/inventory.ini.
[ -f ansible/inventory.ini ] || { echo "ERR: ansible/inventory.ini нет — bootstrap-vps сначала" >&2; exit 1; }
line=$(awk '/^\[project_vps\]/{flag=1; next} /^\[/{flag=0} flag && /ansible_host/' \
       ansible/inventory.ini | head -1)
ip=$(grep -oE 'ansible_host=[^ ]+'  <<<"$line" | cut -d= -f2)
user=$(grep -oE 'ansible_user=[^ ]+' <<<"$line" | cut -d= -f2)
project=$(grep -oE 'project_name=[^ ]+' <<<"$line" | cut -d= -f2)
[ -z "$ip" ]      && { echo "ERR: ansible_host не найден в inventory" >&2; exit 1; }
[ -z "$project" ] && { echo "ERR: project_name не найден в inventory" >&2; exit 1; }
user="${user:-root}"

echo "→ deploy /opt/$project-infra on $user@$ip"
exec ssh -t -o StrictHostKeyChecking=accept-new "$user@$ip" \
  "cd /opt/$project-infra && bash scripts/deploy.sh"
