#!/usr/bin/env bash
# Bootstrap .env на свежем проектном VPS.
#
# Multi-env: на каждом VPS свой ENV (dev/prod/...) и свой .env.
# Стартовый .env — identity (PROJECT_NAME, ENV, DOMAIN) + ACME + активные ключи
# .env.example с умолчаниями (ROBOTS_POLICY — по ENV, HOST_ROLE). Секреты
# профилей (postgres/storage/backend/site) оператор дописывает руками по мере
# активации — контракт и комментарии как сгенерировать в .env.example.
#
# Non-interactive:
#   PROJECT_NAME=acme ENV=prod DOMAIN=acme.com ACME_EMAIL=ops@acme.com \
#   bash scripts/new-env.sh
#
# Interactive: bash scripts/new-env.sh
set -euo pipefail
cd "$(dirname "$0")/.."

prompt() {
  # prompt VAR "Описание" [default]
  local var="$1" desc="$2" default="${3:-}" value
  if [ -n "${!var:-}" ]; then
    printf -v "$var" '%s' "${!var}"
    return
  fi
  if [ -n "$default" ]; then
    read -r -p "$desc [$default]: " value
    value="${value:-$default}"
  else
    read -r -p "$desc: " value
  fi
  [ -z "$value" ] && { echo "ERR: $var обязателен" >&2; exit 1; }
  printf -v "$var" '%s' "$value"
}

if [ -f .env ]; then
  echo "NOTE: .env уже существует, не перегенерирую."
  PROJECT_NAME=$(awk -F= '/^PROJECT_NAME=/{print $2; exit}' .env)
  ENV=$(awk -F= '/^ENV=/{print $2; exit}' .env)
else
  echo "=== Project identity ==="
  prompt PROJECT_NAME "PROJECT_NAME (lowercase, e.g. acme)"
  prompt ENV          "ENV (dev/prod/...)"
  # Запись хоста: сайт получает её как SITE_URL и с другой не стартует — форму держит
  # scripts/preflight-env.sh (ниже и на каждом make deploy).
  prompt DOMAIN       "DOMAIN (e.g. acme.com: строчные, IDN — в punycode xn--…, без https:// и точки на конце)"

  echo
  echo "=== ACME (Let's Encrypt) ==="
  prompt ACME_EMAIL   "ACME_EMAIL (получает LE expiry-нотификации)"

  # Индексацию открывает только прод-среда: любая другая стартует закрытой, и
  # незаполненный ключ не выпускает её в поиск.
  case "$ENV" in prod) ROBOTS_POLICY=index ;; *) ROBOTS_POLICY=noindex ;; esac

  cat > .env <<EOF
# Сгенерировано scripts/new-env.sh. См. .env.example для контракта.
# Единственный источник конфига и секретов стека — этот файл (chmod 600,
# gitignored). Секреты профилей дописывай руками по мере активации
# (комментарии как сгенерировать — в .env.example).
# Image-теги — строго здесь (<SVC>_TAG, бамп через \`make bump\`).

PROJECT_NAME=$PROJECT_NAME
ENV=$ENV
DOMAIN=$DOMAIN

ACME_EMAIL=$ACME_EMAIL
ACME_CASERVER=https://acme-v02.api.letsencrypt.org/directory

# Profile-based opt-in. Перед включением профиля заполни его секцию секретов
# (контракт — .env.example):
#   postgres  — POSTGRES_USER / POSTGRES_PASSWORD / POSTGRES_DB
#   storage   — MINIO_* + APP_S3_* + BACKUP_S3_* + RESTIC_* + BACKUP_AWS_* (+ postgres профиль)
#   backend   — OIDC_* + JWT_SECRET (+ секция postgres) + BACKEND_TAG ниже
#   site      — ROBOTS_POLICY (index — прод, noindex — не-прод) + канал формы
#               SITE_FORM_* / SITE_SMTP_URL + SITE_TAG ниже; на не-прод ещё
#               замок STAGING_BASIC_AUTH_USERS
# COMPOSE_PROFILES=

# Image-тег backend; раскомментировать вместе с профилем backend.
# Бамп — \`make bump SVC=backend TAG=<tag>\`.
# BACKEND_TAG=

# Image-тег site: первый тег и каждый следующий ставит
# \`make bump SVC=site TAG=<tag>\` при профиле site в COMPOSE_PROFILES.
# SITE_TAG=

# Индексация сайта: index — прод-среда, noindex — любая другая. Выставлено по
# ENV=$ENV; на не-прод среде сайт закрывает ещё и замок STAGING_BASIC_AUTH_USERS.
ROBOTS_POLICY=$ROBOTS_POLICY

CROWDSEC_BOUNCER_API_KEY=

# Роль хоста: all — весь стек на этом VPS (.env.example § MULTI-HOST).
HOST_ROLE=all
EOF
  chmod 0600 .env
  echo "OK: .env записан (chmod 0600)."
  bash scripts/preflight-env.sh || true
fi

cat <<EOF

================================================================================
Минимальный стек (traefik + crowdsec + landing)
готов к подъёму — секретов сверх ACME ему не нужно.

Запусти:
  make ship      # с workstation; либо \`make deploy\` напрямую на VPS

По мере необходимости — добавляй секреты профилей руками: заполни блок
переменных нужного профиля в .env по контракту .env.example (там же — как
сгенерировать каждое значение), обнови COMPOSE_PROFILES и \`make ship\`.
================================================================================
EOF
