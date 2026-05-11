#!/usr/bin/env bash
# SSH-обёртка операций на проектном VPS. Connection-данные берутся из
# ansible/inventory.ini (первая запись под [project_vps]); override через
# HOST=user@ip или SSH_HOST/SSH_PORT/SSH_USER/PROJECT_NAME env.
#
# Subcommands:
#   status       — remote `make ps` + status.sh
#   deploy       — ssh + git pull + make deploy
#   restart SVC  — ssh + make restart SVC=<name>
#   logs SVC     — ssh + tail логов одного сервиса
#   exec CMD ... — ssh + произвольная команда в /opt/<project>-infra/
set -euo pipefail
cd "$(dirname "$0")/../.."

# Парсим inventory если HOST не задан явно.
if [ -z "${HOST:-}" ] && [ -f ansible/inventory.ini ]; then
  line=$(awk '/^\[project_vps\]/{flag=1; next} /^\[/{flag=0} flag && /ansible_host/' \
         ansible/inventory.ini | head -1)
  SSH_HOST="${SSH_HOST:-$(grep -oE 'ansible_host=[^ ]+' <<<"$line" | cut -d= -f2)}"
  SSH_PORT="${SSH_PORT:-$(grep -oE 'ansible_port=[^ ]+' <<<"$line" | cut -d= -f2)}"
  SSH_USER="${SSH_USER:-$(grep -oE 'ansible_user=[^ ]+' <<<"$line" | cut -d= -f2)}"
  PROJECT_NAME="${PROJECT_NAME:-$(grep -oE 'project_name=[^ ]+' <<<"$line" | cut -d= -f2)}"
fi

# HOST=user@ip override (например для разовой сессии на staging).
if [ -n "${HOST:-}" ]; then
  SSH_USER="${HOST%@*}"
  SSH_HOST="${HOST#*@}"
fi

: "${SSH_HOST:?SSH_HOST не определён (ansible/inventory.ini нет, и HOST не задан)}"
: "${PROJECT_NAME:?PROJECT_NAME не определён}"
SSH_PORT="${SSH_PORT:-22}"
SSH_USER="${SSH_USER:-root}"

REMOTE_DIR="/opt/${PROJECT_NAME}-infra"
SSH="ssh -p $SSH_PORT $SSH_USER@$SSH_HOST"

case "${1:-}" in
  status)
    $SSH "cd $REMOTE_DIR && make ps && bash scripts/agent-tools/status.sh"
    ;;
  deploy)
    $SSH "cd $REMOTE_DIR && make deploy"
    ;;
  restart)
    [ -n "${2:-}" ] || { echo "usage: $0 restart <service>" >&2; exit 2; }
    $SSH "cd $REMOTE_DIR && make restart SVC=$2"
    ;;
  logs)
    [ -n "${2:-}" ] || { echo "usage: $0 logs <service>" >&2; exit 2; }
    $SSH "cd $REMOTE_DIR && docker logs --tail=200 -f $2"
    ;;
  exec)
    shift
    $SSH "cd $REMOTE_DIR && $*"
    ;;
  *)
    echo "usage: $0 {status|deploy|restart SVC|logs SVC|exec CMD ...}" >&2
    exit 2
    ;;
esac
