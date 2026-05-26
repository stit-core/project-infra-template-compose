#!/usr/bin/env bash
# Идемпотентный deploy: pull → render → vault-agent first → compose up.
# После vault-template-change ЛИБО compose.env-change (Vault meta tag-rollout:
# BACKEND_TAG и пр. приходят из kv/.../meta, git-diff'а не порождают) —
# force-recreate consumer'ов (env_file и image-тег читаются docker'ом при
# container CREATE, не start; обычный `restart` не подхватит).
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
mkdir -p .runtime/secrets .runtime/secrets-bootstrap .runtime/env .runtime/configs
chmod 0700 .runtime/secrets .runtime/secrets-bootstrap

# Lazy-stack validation: storage профиль требует одновременной активации
# postgres (backup-контейнер делает pg_dumpall, без postgres он сразу падает
# и vault-agent залипает на kv/.../db).
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

# Touch пустых заглушек: compose валидирует EXISTENCE bind-mount'ов и env_file
# до старта любого сервиса. На свежем bootstrap'е vault-agent ещё не отрендерил
# реальный контент — без заглушек compose отказывается стартовать. Vault-agent
# перепишет их по мере рендера. Если добавляешь новый template в
# configs/vault-agent/templates/ — добавь имя в этот список.
for f in otel postgres backend minio backup; do
  [ -e ".runtime/secrets/$f.env" ] || touch ".runtime/secrets/$f.env"
done
[ -e ".runtime/env/compose.env" ]      || touch ".runtime/env/compose.env"
[ -e ".runtime/configs/traefik.yml" ]   || touch ".runtime/configs/traefik.yml"
# vault-health.sh заглушка — render-configs.sh перезапишет реальным контентом.
# Без этого vault-agent healthcheck сразу fail'ит до первой здравой проверки.
[ -e ".runtime/configs/vault-health.sh" ] || {
  printf '#!/bin/sh\nexit 1\n' > .runtime/configs/vault-health.sh
  chmod +x .runtime/configs/vault-health.sh
}

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

# CrowdSec early: чтобы успеть зарегистрировать bouncer ДО старта traefik.
# Если первый прогон и в .env CROWDSEC_BOUNCER_API_KEY= (пустой), без этого
# traefik вываливает "CrowdsecLapiKey ... cannot be all empty" на каждом
# роуте — плагин валидирует ключ при загрузке роута, file-watcher на
# middlewares.yml не подхватит уже-сломанный плагин без recreate.
# Идемпотентно: после первого прогона .env уже с ключом, блок ниже skip'ает.
echo "→ crowdsec early (для bouncer auto-register)"
docker compose "${args[@]}" up -d --wait --wait-timeout 60 crowdsec

# CrowdSec bouncer auto-register. Если в .env ключ пустой — генерим сейчас,
# ДО старта traefik (см. комментарий выше про порядок). Раньше блок жил в
# конце deploy.sh, после полного --wait — partial failure (например,
# minio-init exit 1) обрывал set -euo pipefail и блок никогда не запускался.
if grep -qE '^CROWDSEC_BOUNCER_API_KEY=$' .env; then
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

# compose.env change (Vault meta tag-rollout): корп патчит kv/.../meta
# (backend_tag и пр.) → vault-agent перерендеривает .runtime/env/compose.env.
# Это НЕ git-коммит — template_changed его не ловит. Без этого детекта
# централизованный BACKEND_TAG rollout (multi-env.md) не пересоздаёт backend
# и новый образ не выкатывается. Baseline .composeenv-prev — последний
# успешно-deploy'ed (пишется в конце скрипта, retry-safe).
composeenv_changed=0
if [ -s .runtime/env/compose.env ]; then
  if [ -e .runtime/.composeenv-prev ]; then
    cmp -s .runtime/.composeenv-prev .runtime/env/compose.env || composeenv_changed=1
  else
    composeenv_changed=1
  fi
fi

if [ "$template_changed" -eq 1 ] || [ "$profile_changed" -eq 1 ] || [ "$composeenv_changed" -eq 1 ]; then
  reason=""
  [ "$template_changed" -eq 1 ]   && reason="vault-template change"
  [ "$profile_changed" -eq 1 ]    && reason="${reason:+$reason + }profile set change"
  [ "$composeenv_changed" -eq 1 ] && reason="${reason:+$reason + }compose.env change (Vault meta tag-rollout)"
  echo "$reason → restart vault-agent + force-recreate consumers"
  # Инвалидируем rendered-секреты ДО рестарта vault-agent. Иначе vault-health.sh
  # (test -s) проходит МГНОВЕННО по непустым файлам с ПРОШЛОГО деплоя: up --wait
  # рапортует healthy ещё до того, как consul-template отрисовал новые значения,
  # и force-recreate ниже фиксирует в consumer'ах СТАРЫЙ env (падение на
  # ротированных кредах / старом backend_tag — «vault не успел переренжерить»).
  # Пустой файл → test -s красный → --wait реально ждёт свежий рендер; vault-agent
  # перепишет файлы атомарно при restart. compose.env/traefik.yml не трогаем —
  # они тоже перерендерятся, а healthcheck и так блокируется на пустых secrets.
  for f in .runtime/secrets/*.env; do [ -e "$f" ] && : > "$f"; done
  docker compose "${args[@]}" restart vault-agent
  docker compose "${args[@]}" up -d --wait --wait-timeout 60 vault-agent
  consumers=$(docker compose "${args[@]}" config 2>/dev/null \
    | awk '/^  [a-z][a-z0-9_-]*:$/ {svc=$1; sub(":$","",svc)} /\.runtime\/secrets\/.*\.env/ {print svc}' \
    | sort -u)
  if [ -n "$consumers" ]; then
    # Явный pull ДО force-recreate: новый image-тег (из compose.env) может
    # физически отсутствовать на хосте. Без этого pull policy=missing молча
    # оставляет старый контейнер на прежнем теге. Fail виден (RED), не тихий
    # застой. Pinned third-party теги (postgres/minio) — pull = no-op.
    docker compose "${args[@]}" pull --quiet $consumers \
      || { echo "ERR: docker compose pull failed for: $consumers" >&2; exit 1; }
    docker compose "${args[@]}" up -d --no-deps --force-recreate $consumers
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

# Зафиксировать compose.env как baseline для следующего deploy (tag-rollout
# detect выше). Пишем здесь, в самом конце — если deploy упал раньше
# (pull fail / non-healthy reconcile), set -e не даёт сюда дойти, baseline
# не сдвигается, следующий ship повторит force-recreate.
[ -s .runtime/env/compose.env ] && cp .runtime/env/compose.env .runtime/.composeenv-prev

docker compose "${args[@]}" ps
