#!/usr/bin/env bash
# Регистрация gitea-runner в корп-Gitea. Token — из admin UI
# (site admin → Actions → Runners → Create new runner) или API.
# One-shot: runner хранит креды в volume, token можно убрать из .env.
set -euo pipefail
cd "$(dirname "$0")/.."

[ -f .env ] || { echo "ERR: .env missing" >&2; exit 1; }
set -a; . ./.env; set +a

if [ -z "${GITEA_RUNNER_REG_TOKEN:-}" ]; then
  echo "ERR: GITEA_RUNNER_REG_TOKEN не задан в .env" >&2
  echo "Получить token: https://git.stit.tech → site admin → Actions → Runners" >&2
  exit 1
fi

# Если runner уже работает с валидными creds — entrypoint пропустит
# re-registration. Force re-register только по явному запросу.
if docker ps --format '{{.Names}}' | grep -qx gitea-runner; then
  echo "gitea-runner уже запущен. Force re-register: docker compose ... down gitea-runner и удалить runner-data volume."
  echo "Текущий статус:"
  docker logs --tail=5 gitea-runner 2>&1 | sed 's/^/  /'
  exit 0
fi

# act_runner регистрируется на первом старте, когда задан REG_TOKEN.
# deploy.sh поднимет контейнер; этот скрипт — документация флоу + verify.
echo "gitea-runner ещё не запущен. Запусти: bash scripts/deploy.sh"
exit 1
