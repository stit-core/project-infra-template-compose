#!/usr/bin/env bash
# Идемпотентный deploy: pull → render → compose up. Дополнительно
# рестартит сервисы, у которых поменялись bind-mounted конфиги
# (compose `up -d` смотрит только на YAML, не на содержимое bind-mount).
#
# Запускать на проектном VPS из /opt/<project>-infra/.
set -euo pipefail
cd "$(dirname "$0")/.."

[ -f .env ] || { echo "ERR: .env missing" >&2; exit 1; }
docker info >/dev/null 2>&1 || { echo "ERR: docker not reachable" >&2; exit 1; }

prev_sha=$(git rev-parse HEAD 2>/dev/null || echo "none")
git pull --ff-only origin main || true
new_sha=$(git rev-parse HEAD 2>/dev/null || echo "none")

bash scripts/render-configs.sh

# Создаём runtime-директории до того, как vault-agent попытается их bind-mount'ить.
mkdir -p .runtime/secrets .runtime/secrets-bootstrap
chmod 0700 .runtime/secrets .runtime/secrets-bootstrap

args=(-f docker-compose.yml)
for f in compose/*.yml; do
  args+=(-f "$f")
done

docker compose "${args[@]}" up -d --remove-orphans --wait --wait-timeout 180

# Рестарт сервисов с изменёнными bind-mounted конфигами.
if [ "$prev_sha" != "$new_sha" ] && [ "$prev_sha" != "none" ]; then
  declare -A configmap=(
    [traefik]="traefik"
    [crowdsec]="crowdsec"
    [postgres]="postgres"
    [vault-agent]="vault-agent"
    [otel-agent]="otel-agent"
  )
  changed_dirs=$(git diff --name-only "$prev_sha" "$new_sha" -- configs/ \
    | awk -F/ 'NF>=2 {print $2}' | sort -u)
  to_restart=()
  for d in $changed_dirs; do
    for s in ${configmap[$d]:-}; do to_restart+=("$s"); done
  done
  if [ ${#to_restart[@]} -gt 0 ]; then
    existing=$(docker compose "${args[@]}" ps --services 2>/dev/null || true)
    final=$(printf '%s\n' "${to_restart[@]}" | sort -u | grep -Fxf <(echo "$existing") || true)
    if [ -n "$final" ]; then
      echo "Restarting services with changed configs: $(echo $final)"
      docker compose "${args[@]}" restart $final
    fi
  fi
fi

docker compose "${args[@]}" ps
