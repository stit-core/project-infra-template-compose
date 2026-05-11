#!/usr/bin/env bash
# Идемпотентный deploy: pull → render → vault-agent first → compose up.
# После vault-template-change — force-recreate consumer'ов (env_file
# читается docker'ом при container CREATE, не start; обычный `restart`
# не подхватит новый контент).
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

# Touch пустых env_file'ов: compose валидирует их EXISTENCE до старта
# любого сервиса. На свежем bootstrap'е vault-agent ещё не отрендерил
# реальный контент — без этих заглушек compose отказывается стартовать.
# Vault-agent перепишет файлы по мере рендера. Если добавляешь новый
# template в configs/vault-agent/templates/ — добавь имя сюда же.
for f in backend postgres backup minio; do
  [ -e ".runtime/secrets/$f.env" ] || touch ".runtime/secrets/$f.env"
done

args=(-f docker-compose.yml)
for f in compose/*.yml; do
  args+=(-f "$f")
done

# Two-stage: vault-agent первым, чтобы он отрендерил .runtime/secrets/*.env
# через consul-template ДО того, как docker создаст consumer-контейнеры.
# Docker фиксирует env_file в момент container CREATE (не start);
# depends_on у consumer'ов задерживает CREATE до vault-agent healthy,
# и тогда env_file уже непустой.
echo "→ vault-agent first (renders runtime secrets)"
docker compose "${args[@]}" up -d --wait --wait-timeout 60 vault-agent

# Если vault-templates поменялись (.tpl или agent.hcl.tpl) — vault-agent
# перерендерит при рестарте, но consumer-контейнеры уже работают со
# старым env_file. Force-recreate чтобы они перечитали — env_file
# фиксируется при CREATE, не при start.
if [ "$prev_sha" != "$new_sha" ] && [ "$prev_sha" != "none" ]; then
  changed_tpls=$(git diff --name-only "$prev_sha" "$new_sha" -- \
    'configs/vault-agent/templates/*.tpl' configs/vault-agent/agent.hcl.tpl 2>/dev/null)
  if [ -n "$changed_tpls" ]; then
    echo "vault-template change → restart vault-agent + force-recreate consumers"
    docker compose "${args[@]}" restart vault-agent
    docker compose "${args[@]}" up -d --wait --wait-timeout 60 vault-agent
    consumers=$(docker compose "${args[@]}" config 2>/dev/null \
      | awk '/^  [a-z][a-z0-9_-]*:$/ {svc=$1; sub(":$","",svc)} /\.runtime\/secrets\/.*\.env/ {print svc}' \
      | sort -u)
    if [ -n "$consumers" ]; then
      docker compose "${args[@]}" up -d --no-deps --force-recreate $consumers
    fi
  fi
fi

docker compose "${args[@]}" up -d --remove-orphans --wait --wait-timeout 180

# Рестарт сервисов с изменёнными bind-mounted конфигами (не vault-templates —
# их обработали выше; это про traefik/crowdsec/postgres/otel-agent configs).
if [ "$prev_sha" != "$new_sha" ] && [ "$prev_sha" != "none" ]; then
  declare -A configmap=(
    [traefik]="traefik"
    [crowdsec]="crowdsec"
    [postgres]="postgres"
    [otel-agent]="otel-agent"
  )
  changed_dirs=$(git diff --name-only "$prev_sha" "$new_sha" -- configs/ \
    | awk -F/ 'NF>=2 {print $2}' | sort -u)
  to_restart=()
  for d in $changed_dirs; do
    [ "$d" = "vault-agent" ] && continue   # уже обработали выше
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
