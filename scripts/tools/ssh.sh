#!/usr/bin/env bash
# SSH-обёртка операций на проектном VPS. Connection берётся из .env.local
# (workstation, gitignored) — приоритет: explicit-env > .env.local > inventory.ini.
# Host не хардкодится. Значения читаются grep'ом и живут внутри процесса —
# в stdout не печатаются (см. .claude/rules/env-local.md).
#
# Subcommands:
#   status       — remote `make ps` + status.sh
#   smoke        — remote `smoke-run.sh` (серверный смок: host-витали + контейнеры)
#   deploy       — ssh + git pull + make deploy
#   restart SVC  — ssh + make restart SVC=<name>
#   logs SVC     — ssh + tail логов одного сервиса (без follow)
#   exec CMD     — произвольная команда в /opt/<project>-infra/
#
# exec — канон произвольной команды на VPS (задокументированное исключение
# make-first). Команду передавай ОДНОЙ строкой в кавычках — она уходит на VPS
# без перепарса (printf %q), кавычки/пайпы/$ внутри живут как написаны:
#   scripts/tools/ssh.sh exec 'docker ps --format "{{.Names}}" | sort'
# Remote-команды идут через login-shell (bash -lc): non-interactive ssh не
# грузит профиль, и make/docker могут отсутствовать в его PATH.
set -euo pipefail
cd "$(dirname "$0")/../.."

# usage — до резолва connection (работает без .env.local).
case "${1:-}" in
  status|smoke|deploy|restart|logs|exec) ;;
  *)
    echo "usage: $0 {status|smoke|deploy|restart SVC|logs SVC|exec '<command>'}" >&2
    exit 2
    ;;
esac

# read_local KEY FILE — извлечь значение dotenv-ключа grep'ом (не source).
# Возвращает 0 даже если ключа нет (пустая строка) — иначе pipefail+set -e убьёт скрипт.
read_local() {
  [ -f "$2" ] || return 0
  { grep -E "^(export[[:space:]]+)?$1=" "$2" | tail -1 \
      | sed -E "s/^(export[[:space:]]+)?$1=//; s/^[\"']//; s/[\"']$//"; } || true
}

# 1. .env.local (primary, после explicit-env).
[ -z "${HOST:-}" ] && HOST="$(read_local HOST .env.local)"
SSH_HOST="${SSH_HOST:-$(read_local SSH_HOST .env.local)}"
SSH_PORT="${SSH_PORT:-$(read_local SSH_PORT .env.local)}"
SSH_USER="${SSH_USER:-$(read_local SSH_USER .env.local)}"
PROJECT_NAME="${PROJECT_NAME:-$(read_local PROJECT_NAME .env.local)}"

# 2. inventory.ini (fallback — bootstrap-контекст до .env.local).
if [ -z "${HOST:-}" ] && [ -z "${SSH_HOST:-}" ] && [ -f ansible/inventory.ini ]; then
  line=$(awk '/^\[project_vps\]/{flag=1; next} /^\[/{flag=0} flag && /ansible_host/' \
         ansible/inventory.ini | head -1)
  SSH_HOST="${SSH_HOST:-$(grep -oE 'ansible_host=[^ ]+' <<<"$line" | cut -d= -f2)}"
  SSH_PORT="${SSH_PORT:-$(grep -oE 'ansible_port=[^ ]+' <<<"$line" | cut -d= -f2)}"
  SSH_USER="${SSH_USER:-$(grep -oE 'ansible_user=[^ ]+' <<<"$line" | cut -d= -f2)}"
  PROJECT_NAME="${PROJECT_NAME:-$(grep -oE 'project_name=[^ ]+' <<<"$line" | cut -d= -f2)}"
fi

# 3. HOST=user@ip override (разовая сессия / .env.local HOST=).
if [ -n "${HOST:-}" ]; then
  SSH_USER="${HOST%@*}"
  SSH_HOST="${HOST#*@}"
fi

: "${SSH_HOST:?SSH_HOST не определён (нет в .env.local / ansible/inventory.ini, HOST не задан)}"
: "${PROJECT_NAME:?PROJECT_NAME не определён}"
SSH_PORT="${SSH_PORT:-22}"
SSH_USER="${SSH_USER:-root}"

REMOTE_DIR="/opt/${PROJECT_NAME}-infra"
# BatchMode=yes: не зависать на password-prompt при отсутствии/неверном ключе —
# падать сразу (ssh-agent/ключ работают, отключается только пароль).
SSH_OPTS=(-p "${SSH_PORT}" -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new)

run() {
  ssh "${SSH_OPTS[@]}" "${SSH_USER}@${SSH_HOST}" "$@"
}

# run_dir <cmd...> — команда в REMOTE_DIR через remote login-shell (см. шапку).
run_dir() {
  run "bash -lc $(printf '%q' "cd $REMOTE_DIR && $*")"
}

case "${1:-}" in
  status)
    run_dir "make ps && bash scripts/tools/status.sh"
    ;;
  smoke)
    run_dir "bash scripts/tools/smoke-run.sh"
    ;;
  deploy)
    run_dir "make deploy"
    ;;
  restart)
    [ -n "${2:-}" ] || { echo "usage: $0 restart <service>" >&2; exit 2; }
    run_dir "make restart SVC=$2"
    ;;
  logs)
    [ -n "${2:-}" ] || { echo "usage: $0 logs <service>" >&2; exit 2; }
    run_dir "docker logs --tail=200 $2 2>&1 | tail -200"
    ;;
  exec)
    shift
    [ $# -gt 0 ] || { echo "usage: $0 exec '<command>'" >&2; exit 2; }
    run_dir "$*"
    ;;
  *)
    echo "usage: $0 {status|smoke|deploy|restart SVC|logs SVC|exec '<command>'}" >&2
    exit 2
    ;;
esac
