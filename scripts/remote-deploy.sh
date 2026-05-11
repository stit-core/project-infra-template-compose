#!/usr/bin/env bash
# Локальный (laptop-side) триггер деплоя: SSH на проектный VPS, git pull +
# deploy.sh. Цель — `make remote-deploy` после push'а в main, без захода
# на хост руками. Reads ansible/inventory.ini для адреса.
#
# Использование:
#   bash scripts/remote-deploy.sh                  # auto из inventory
#   HOST=root@1.2.3.4 bash scripts/remote-deploy.sh
set -euo pipefail
cd "$(dirname "$0")/.."

if [ -n "${HOST:-}" ]; then
  ssh_target="$HOST"
  project="${PROJECT_NAME:-$(awk -F'=' '/^PROJECT_NAME=/{print $2}' .env 2>/dev/null || true)}"
  [ -z "$project" ] && { echo "ERR: PROJECT_NAME не определён (нет .env и не передан через env)" >&2; exit 1; }
else
  [ -f ansible/inventory.ini ] || { echo "ERR: ansible/inventory.ini нет — задай HOST=user@ip" >&2; exit 1; }
  # Берём первую строку с ansible_host под [project_vps].
  line=$(awk '/^\[project_vps\]/{flag=1; next} /^\[/{flag=0} flag && /ansible_host/' \
         ansible/inventory.ini | head -1)
  ip=$(grep -oE 'ansible_host=[^ ]+'  <<<"$line" | cut -d= -f2)
  user=$(grep -oE 'ansible_user=[^ ]+' <<<"$line" | cut -d= -f2)
  project=$(grep -oE 'project_name=[^ ]+' <<<"$line" | cut -d= -f2)
  [ -z "$ip" ]      && { echo "ERR: ansible_host не найден в inventory" >&2; exit 1; }
  [ -z "$project" ] && { echo "ERR: project_name не найден в inventory" >&2; exit 1; }
  user="${user:-root}"
  ssh_target="$user@$ip"
fi

echo "→ deploy /opt/$project-infra on $ssh_target"
# -t для нормального вывода прогресса; StrictHostKeyChecking=accept-new даёт
# зацепиться на свежий VPS без ручного yes/no.
exec ssh -t -o StrictHostKeyChecking=accept-new "$ssh_target" \
  "cd /opt/$project-infra && bash scripts/deploy.sh"
