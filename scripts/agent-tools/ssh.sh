#!/usr/bin/env bash
# SSH wrapper for project VPS operations. Reads SSH_HOST/SSH_PORT from
# .env (or environment) so you can run from your dev machine without
# memorizing connection strings.
#
# Subcommands:
#   status       — quick remote `make ps` + `make status` summary
#   deploy       — ssh + git pull + make deploy (on server)
#   restart SVC  — ssh + make restart SVC=<name>
#   logs SVC     — ssh + tail logs of one service
#   exec CMD ... — ssh + run arbitrary command inside /opt/<project>-infra/
set -euo pipefail
cd "$(dirname "$0")/../.."

[ -f .env ] && set -a && . ./.env && set +a

: "${SSH_HOST:?SSH_HOST not set (add to .env or export)}"
: "${SSH_PORT:=22}"
: "${PROJECT_NAME:?PROJECT_NAME not set}"
: "${SSH_USER:=root}"

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
