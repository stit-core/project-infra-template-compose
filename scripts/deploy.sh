#!/usr/bin/env bash
# Идемпотентный deploy: pull → render → compose up. Все секреты и конфиг-
# значения — в .env (compose интерполирует их в environment сервисов при
# `up`, смена значения в .env → compose сам пересоздаёт затронутые сервисы).
# Image-теги (<SVC>_TAG) тоже живут в .env: смена тега меняет интерполированный
# compose-конфиг, и финальный `up -d` пересоздаёт сервис сам (канон бампа —
# `make bump SVC= TAG=`).
#
# Запускать на проектном VPS из /opt/<project>-infra/.
set -euo pipefail
cd "$(dirname "$0")/.."

[ -f .env ] || { echo "ERR: .env missing" >&2; exit 1; }
docker info >/dev/null 2>&1 || { echo "ERR: docker not reachable" >&2; exit 1; }

# Identity: .env обязан содержать PROJECT_NAME и ENV — без них не резолвятся
# image-пути registry и APP_ENV.
grep -qE '^PROJECT_NAME=.+' .env || { echo "ERR: PROJECT_NAME пустой в .env" >&2; exit 1; }
grep -qE '^ENV=.+'          .env || { echo "ERR: ENV пустой в .env (dev/prod/...)" >&2; exit 1; }

# MULTI-HOST: роль ЭТОГО хоста (.env). all = single-host (весь стек, дефолт).
# Split — отдельный VPS на роль (один VPS = одна среда → несколько VPS на env);
# project name = имя директории (хосты физически разные, коллизий томов нет).
# Карта роль → compose-файлы. Граница (cross-host сеть / репликация / HA — дело
# потребителя) и эндпоинты в .env (PG_HOST/PG_PORT, RESTIC_REPOSITORY) —
# docs/reference/architecture.md § Multi-host split.
HOST_ROLE=$(sed -nE 's/^HOST_ROLE=//p' .env | tail -1)
HOST_ROLE="${HOST_ROLE:-all}"
declare -A ROLE_FILES=(
  [all]="docker-compose.yml compose/*.yml"
  [edge]="docker-compose.yml compose/traefik.yml compose/crowdsec.yml compose/landing.yml compose/backend.yml"
  [db]="docker-compose.yml compose/postgres.yml"
  [storage]="docker-compose.yml compose/minio.yml compose/backup.yml"
)
sel="${ROLE_FILES[$HOST_ROLE]:-}"
[ -n "$sel" ] || { echo "ERR: unknown HOST_ROLE=$HOST_ROLE (all|edge|db|storage)" >&2; exit 1; }

prev_sha=$(git rev-parse HEAD 2>/dev/null || echo "none")
git pull --ff-only origin main || true
new_sha=$(git rev-parse HEAD 2>/dev/null || echo "none")

bash scripts/render-configs.sh

# Preflight: DNS A-records. Warning'и если A-записи не указывают на этот VPS.
# Не fail'ится — стек поднимется, traefik сам ретрайнет ACME когда DNS
# подтянется. Цель — поймать в логах ДО compose-wait.
bash scripts/preflight-dns.sh || true

# Lazy-stack validation: storage профиль требует одновременной активации
# postgres (backup-контейнер делает pg_dumpall, без postgres он сразу падает).
# Только single-host: при split postgres на db-хосте, backup на storage-хосте
# делает pg_dumpall по сети (PG_HOST из .env) — co-location не требуется
# (cross-host доступ — дело потребителя).
COMPOSE_PROFILES=$(sed -nE 's/^COMPOSE_PROFILES=//p' .env | tail -1)
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

# Compose-файлы по роли (sel из ROLE_FILES). all → docker-compose.yml + все
# compose/*.yml (single-host, прежний набор). Намеренный word-split + glob.
# shellcheck disable=SC2086
args=()
for f in $sel; do args+=(-f "$f"); done

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

docker compose "${args[@]}" up -d --remove-orphans --wait --wait-timeout 180

# Рестарт сервисов с изменёнными bind-mounted конфигами: environment compose
# отслеживает сам (up пересоздаёт), а контент bind-mount'ов — нет. Traefik
# читает static config только на старте — при diff в configs/<dir>/ рестартуем
# затронутый сервис явно.
if [ "$prev_sha" != "$new_sha" ] && [ "$prev_sha" != "none" ]; then
  declare -A configmap=(
    [traefik]="traefik"
    [crowdsec]="crowdsec"
    [postgres]="postgres"
  )
  mapfile -t changed_dirs < <(git diff --name-only "$prev_sha" "$new_sha" -- configs/ \
    | awk -F/ 'NF>=2 {print $2}' | sort -u)
  to_restart=()
  for d in "${changed_dirs[@]}"; do
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
