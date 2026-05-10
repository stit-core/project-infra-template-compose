#!/usr/bin/env bash
# Register gitea-runner with the corp Gitea instance. Token comes from
# Gitea admin UI (site admin → Actions → Runners → Create new runner)
# or via API. One-shot — the runner stores credentials in its volume,
# token can be cleared from .env afterwards.
set -euo pipefail
cd "$(dirname "$0")/.."

[ -f .env ] || { echo "ERR: .env missing" >&2; exit 1; }
set -a; . ./.env; set +a

if [ -z "${GITEA_RUNNER_REG_TOKEN:-}" ]; then
  echo "ERR: GITEA_RUNNER_REG_TOKEN unset in .env" >&2
  echo "Get a token from https://git.stit.tech → site admin → Actions → Runners" >&2
  exit 1
fi

# If runner already running with valid creds, the entrypoint will skip
# re-registration. Force re-register only if explicitly asked.
if docker ps --format '{{.Names}}' | grep -qx gitea-runner; then
  echo "gitea-runner already running. To force re-register: docker compose ... down gitea-runner && rm runner-data volume."
  echo "Current status:"
  docker logs --tail=5 gitea-runner 2>&1 | sed 's/^/  /'
  exit 0
fi

# act_runner registers on first start when REG_TOKEN env is set.
# deploy.sh already brings the container up; this script exists to
# document the flow + verify state. For first-deploy, just run deploy.sh.
echo "gitea-runner not yet running. Run: bash scripts/deploy.sh"
exit 1
