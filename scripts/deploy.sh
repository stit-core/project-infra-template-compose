#!/usr/bin/env bash
# Идемпотентный deploy: pull → render → vault-agent first → compose up.
# После vault-template-change — force-recreate consumer'ов (env_file читается
# docker'ом при container CREATE, не start; обычный `restart` не подхватит).
# Image-теги (<SVC>_TAG) живут в .env, НЕ в Vault: смена тега меняет
# интерполированный compose-конфиг, и финальный `up -d` пересоздаёт сервис
# сам (канон бампа — `make bump SVC= TAG=`).
#
# Запускать на проектном VPS из /opt/<project>-infra/.
set -euo pipefail
cd "$(dirname "$0")/.."

[ -f .env ] || { echo "ERR: .env missing" >&2; exit 1; }
docker info >/dev/null 2>&1 || { echo "ERR: docker not reachable" >&2; exit 1; }

# Multi-env: .env обязан содержать PROJECT_NAME и ENV — без них vault-agent
# не сможет залогиниться в правильный AppRole и резолвить KV-paths.
grep -qE '^PROJECT_NAME=.+' .env || { echo "ERR: PROJECT_NAME пустой в .env" >&2; exit 1; }
grep -qE '^ENV=.+'          .env || { echo "ERR: ENV пустой в .env (dev/prod/...)" >&2; exit 1; }

# MULTI-HOST: роль ЭТОГО хоста (.env). all = single-host (весь стек, дефолт).
# Split — отдельный VPS на роль (один VPS = одна среда → несколько VPS на env);
# project name = имя директории (хосты физически разные, коллизий томов нет).
# Карта роль → compose-файлы; vault-agent в каждой роли (рендерит секреты).
# Граница (cross-host сеть / репликация / HA — дело потребителя) и эндпоинты в KV —
# docs/reference/architecture.md § Multi-host split.
HOST_ROLE=$(sed -nE 's/^HOST_ROLE=//p' .env | tail -1)
HOST_ROLE="${HOST_ROLE:-all}"
declare -A ROLE_FILES=(
  [all]="docker-compose.yml compose/*.yml"
  [edge]="docker-compose.yml compose/traefik.yml compose/crowdsec.yml compose/vault-agent.yml compose/otel-agent.yml compose/node-exporter.yml compose/cadvisor.yml compose/landing.yml compose/backend.yml"
  [db]="docker-compose.yml compose/vault-agent.yml compose/postgres.yml"
  [storage]="docker-compose.yml compose/vault-agent.yml compose/minio.yml compose/backup.yml"
)
sel="${ROLE_FILES[$HOST_ROLE]:-}"
[ -n "$sel" ] || { echo "ERR: unknown HOST_ROLE=$HOST_ROLE (all|edge|db|storage)" >&2; exit 1; }

prev_sha=$(git rev-parse HEAD 2>/dev/null || echo "none")
git pull --ff-only origin main || true
new_sha=$(git rev-parse HEAD 2>/dev/null || echo "none")

bash scripts/render-configs.sh

# Preflight: DNS A-records + Vault seed.
# DNS: warning'и если A-записи не указывают на этот VPS.
# Vault: warning'и если корп ещё не засеял kv/projects/<p>/{minio,backup}.
# Оба не fail'ятся — стек поднимется, traefik / vault-agent сами ретрайнут
# когда зависимости появятся. Цель — поймать в логах ДО compose-wait.
bash scripts/preflight-dns.sh || true
bash scripts/preflight-vault.sh || true

# Создаём runtime-директории до того, как docker попытается их bind-mount'ить
# (если их нет, docker создаст их сам как root c 0755 — но мы хотим 0700
# для secrets).
mkdir -p .runtime/secrets .runtime/secrets-bootstrap .runtime/configs
chmod 0700 .runtime/secrets .runtime/secrets-bootstrap

# Lazy-stack validation: storage профиль требует одновременной активации
# postgres (backup-контейнер делает pg_dumpall, без postgres он сразу падает
# и vault-agent залипает на kv/.../db). Только single-host: при split postgres
# на db-хосте, backup на storage-хосте делает pg_dumpall по сети (db.host из KV) —
# co-location не требуется (cross-host доступ — дело потребителя).
if [ "$HOST_ROLE" = all ]; then
  case ",${COMPOSE_PROFILES:-}," in
    *,storage,*)
      case ",${COMPOSE_PROFILES:-}," in
        *,postgres,*) ;;
        *)
          echo "ERR: COMPOSE_PROFILES=storage требует одновременной активации postgres (backup делает pg_dumpall)." >&2
          echo "     Правка .env: COMPOSE_PROFILES=postgres,storage[,backend]" >&2
          exit 1 ;;
      esac ;;
  esac
fi

# Touch пустых заглушек: compose валидирует EXISTENCE bind-mount'ов и env_file
# до старта любого сервиса. На свежем bootstrap'е vault-agent ещё не отрендерил
# реальный контент — без заглушек compose отказывается стартовать. Vault-agent
# перепишет их по мере рендера. Если добавляешь новый template в
# configs/vault-agent/templates/ — добавь имя в этот список.
for f in otel postgres backend minio backup; do
  [ -e ".runtime/secrets/$f.env" ] || touch ".runtime/secrets/$f.env"
done
[ -e ".runtime/configs/traefik.yml" ]   || touch ".runtime/configs/traefik.yml"
# vault-health.sh заглушка — render-configs.sh перезапишет реальным контентом.
# Без этого vault-agent healthcheck сразу fail'ит до первой здравой проверки.
[ -e ".runtime/configs/vault-health.sh" ] || {
  printf '#!/bin/sh\nexit 1\n' > .runtime/configs/vault-health.sh
  chmod +x .runtime/configs/vault-health.sh
}

# Compose-файлы по роли (sel из ROLE_FILES). all → docker-compose.yml + все
# compose/*.yml (single-host, прежний набор). Намеренный word-split + glob.
# shellcheck disable=SC2086
args=()
for f in $sel; do args+=(-f "$f"); done

# Two-stage: vault-agent первым, чтобы он отрендерил .runtime/secrets/*.env
# через consul-template ДО того, как docker создаст consumer-контейнеры.
# Docker фиксирует env_file в момент container CREATE (не start);
# depends_on у consumer'ов задерживает CREATE до vault-agent healthy,
# и тогда env_file уже непустой.
echo "→ vault-agent first (renders runtime secrets)"
docker compose "${args[@]}" up -d --wait --wait-timeout 60 vault-agent

# CrowdSec early: чтобы успеть зарегистрировать bouncer ДО старта traefik.
# Если первый прогон и в .env CROWDSEC_BOUNCER_API_KEY= (пустой), без этого
# traefik вываливает "CrowdsecLapiKey ... cannot be all empty" на каждом
# роуте — плагин валидирует ключ при загрузке роута, file-watcher на
# middlewares.yml не подхватит уже-сломанный плагин без recreate.
# Идемпотентно: после первого прогона .env уже с ключом, блок ниже skip'ает.
# MULTI-HOST: crowdsec/traefik — роли edge (и all). На db/storage-хостах их нет,
# bouncer-bootstrap пропускаем (нет crowdsec-контейнера для cscli).
crowdsec_here=0
case "$HOST_ROLE" in all|edge) crowdsec_here=1 ;; esac
if [ "$crowdsec_here" = 1 ]; then
  echo "→ crowdsec early (для bouncer auto-register)"
  docker compose "${args[@]}" up -d --wait --wait-timeout 60 crowdsec
fi

# CrowdSec bouncer auto-register. Если в .env ключ пустой — генерим сейчас,
# ДО старта traefik (см. комментарий выше про порядок) и ДО полного --wait:
# при set -euo pipefail partial failure в --wait (например minio-init exit 1)
# прервал бы скрипт, не дойдя до регистрации bouncer'а.
if [ "$crowdsec_here" = 1 ] && grep -qE '^CROWDSEC_BOUNCER_API_KEY=$' .env; then
  echo "→ auto-registering CrowdSec bouncer (traefik)"
  if key=$(docker exec crowdsec cscli bouncers add traefik -o raw 2>/dev/null); then
    [ -n "$key" ] && {
      sed -i "s|^CROWDSEC_BOUNCER_API_KEY=$|CROWDSEC_BOUNCER_API_KEY=$key|" .env
      bash scripts/render-configs.sh
      echo "→ CROWDSEC_BOUNCER_API_KEY set + middlewares re-rendered"
    }
  fi
fi

# Vault-template change ИЛИ profile-set change → force-recreate consumer'ов:
#   - .tpl правки + agent.hcl.parts/* → vault-agent заново отрендерит env_file'ы,
#     но docker фиксирует env_file при CREATE контейнера, не start.
#   - смена COMPOSE_PROFILES → новый набор active blocks в agent.hcl, vault-agent
#     должен пере-инициализировать template set. .runtime/.profiles-cur пишется
#     render-configs.sh каждый прогон; .profiles-prev — последний deploy'ed.
profile_changed=0
if [ -e .runtime/.profiles-prev ] && [ -e .runtime/.profiles-cur ]; then
  cmp -s .runtime/.profiles-prev .runtime/.profiles-cur || profile_changed=1
elif [ -e .runtime/.profiles-cur ]; then
  profile_changed=1
fi

template_changed=0
if [ "$prev_sha" != "$new_sha" ] && [ "$prev_sha" != "none" ]; then
  changed_tpls=$(git diff --name-only "$prev_sha" "$new_sha" -- \
    'configs/vault-agent/templates/*.tpl' 'configs/vault-agent/agent.hcl.parts/*' 2>/dev/null)
  [ -n "$changed_tpls" ] && template_changed=1
fi

if [ "$template_changed" -eq 1 ] || [ "$profile_changed" -eq 1 ]; then
  reason=""
  [ "$template_changed" -eq 1 ]   && reason="vault-template change"
  [ "$profile_changed" -eq 1 ]    && reason="${reason:+$reason + }profile set change"
  echo "$reason → restart vault-agent + force-recreate consumers"
  # Инвалидируем rendered-секреты ДО рестарта vault-agent. Иначе vault-health.sh
  # (test -s) проходит МГНОВЕННО по непустым файлам с ПРОШЛОГО деплоя: up --wait
  # рапортует healthy ещё до того, как consul-template отрисовал новые значения,
  # и force-recreate ниже фиксирует в consumer'ах СТАРЫЙ env (падение на
  # ротированных кредах — «vault не успел переренжерить»).
  # Пустой файл → test -s красный → --wait реально ждёт свежий рендер; vault-agent
  # перепишет файлы атомарно при restart. traefik.yml не трогаем —
  # он тоже перерендерится, а healthcheck и так блокируется на пустых secrets.
  for f in .runtime/secrets/*.env; do [ -e "$f" ] && : > "$f"; done
  docker compose "${args[@]}" restart vault-agent
  docker compose "${args[@]}" up -d --wait --wait-timeout 60 vault-agent
  mapfile -t consumers < <(docker compose "${args[@]}" config 2>/dev/null \
    | awk '/^  [a-z][a-z0-9_-]*:$/ {svc=$1; sub(":$","",svc)} /\.runtime\/secrets\/.*\.env/ {print svc}' \
    | sort -u)
  if [ ${#consumers[@]} -gt 0 ]; then
    # Явный pull ДО force-recreate: образ под текущим тегом может физически
    # отсутствовать на хосте (свежий bootstrap / прочищенный кеш). Fail виден
    # (RED), не тихий застой. Pinned third-party теги (postgres/minio) — pull = no-op.
    docker compose "${args[@]}" pull --quiet "${consumers[@]}" \
      || { echo "ERR: docker compose pull failed for: ${consumers[*]}" >&2; exit 1; }
    docker compose "${args[@]}" up -d --no-deps --force-recreate "${consumers[@]}"
  fi
fi
# Зафиксировать текущий profile-набор как baseline для следующего deploy.
[ -e .runtime/.profiles-cur ] && cp .runtime/.profiles-cur .runtime/.profiles-prev

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
  mapfile -t changed_dirs < <(git diff --name-only "$prev_sha" "$new_sha" -- configs/ \
    | awk -F/ 'NF>=2 {print $2}' | sort -u)
  to_restart=()
  for d in "${changed_dirs[@]}"; do
    [ "$d" = "vault-agent" ] && continue   # уже обработали выше
    svc="${configmap[$d]:-}"
    [ -n "$svc" ] && to_restart+=("$svc")
  done
  if [ ${#to_restart[@]} -gt 0 ]; then
    existing=$(docker compose "${args[@]}" ps --services 2>/dev/null || true)
    mapfile -t final < <(printf '%s\n' "${to_restart[@]}" | sort -u | grep -Fxf <(echo "$existing") || true)
    if [ ${#final[@]} -gt 0 ]; then
      echo "Restarting services with changed configs: ${final[*]}"
      docker compose "${args[@]}" restart "${final[@]}"
    fi
  fi
fi

docker compose "${args[@]}" ps
