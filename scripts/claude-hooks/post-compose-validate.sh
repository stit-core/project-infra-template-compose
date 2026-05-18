#!/usr/bin/env bash
# Claude Code hook: PostToolUse на Edit/Write/MultiEdit.
# Если редактировался compose-файл — валидирует docker compose config.
# Tolerant: если docker недоступен (CI без docker) — skip без ошибки.

set -uo pipefail

INPUT=$(cat)

if command -v jq >/dev/null 2>&1; then
    FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
else
    FILE=$(echo "$INPUT" | grep -oE '"file_path":"[^"]+"' | head -1 | sed 's/"file_path":"\(.*\)"/\1/')
fi

[ -z "$FILE" ] && exit 0

# Нормализуем путь относительно корня репо.
ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
REL="${FILE#"$ROOT/"}"

# Реагируем только на compose-файлы.
case "$REL" in
    docker-compose.yml|compose/*.yml)
        ;;
    *)
        exit 0
        ;;
esac

cd "$ROOT" || exit 0

if ! command -v docker >/dev/null 2>&1; then
    # Молча пропускаем — на host'ах без docker (например, dev-машина без локального docker)
    # хук не должен мешать. Validate.sh покрывает это явно при запросе.
    exit 0
fi

# Подменяем .env временным дампом из .env.example, чтобы compose не ругался на unset vars.
TMP_ENV=""
if [ -f ".env.example" ]; then
    TMP_ENV=$(mktemp)
    sed -E 's/^([A-Z][A-Z0-9_]*)=$/\1=placeholder/' .env.example > "$TMP_ENV"
fi

# Compose валидирует существование env_file: + bind-mount путей до любого парсинга.
# На dev-машине .runtime/ не существует (vault-agent рендерит на VPS), поэтому
# touch'им placeholder'ы. Та же логика что в scripts/deploy.sh. Cleanup только
# тех файлов которые мы сами создали — чтобы не маскировать реальное состояние на VPS.
mkdir -p .runtime/secrets .runtime/env .runtime/configs
TOUCHED=()
touch_placeholder() {
    if [ ! -e "$1" ]; then
        touch "$1"
        TOUCHED+=("$1")
    fi
}
for f in backend postgres backup minio otel; do
    touch_placeholder ".runtime/secrets/$f.env"
done
touch_placeholder ".runtime/env/compose.env"
touch_placeholder ".runtime/configs/traefik.yml"

args=(-f docker-compose.yml)
for f in compose/*.yml; do
    args+=(-f "$f")
done

# Активируем все profile'ы для validate: без активации compose ругается на
# depends_on между profile-restricted сервисами ("undefined service" даже
# если оба в одном profile). Не отражает runtime-набор, но проверяет что
# вся модель парсится — для regression-check этого достаточно.
all_profiles=(postgres storage backend)
profile_args=()
for p in "${all_profiles[@]}"; do
    profile_args+=(--profile "$p")
done

# Makefile использует --env-file .env --env-file .runtime/env/compose.env;
# воспроизводим тот же порядок (поздние перекрывают ранние).
if [ -n "$TMP_ENV" ]; then
    OUT=$(docker compose --env-file "$TMP_ENV" --env-file .runtime/env/compose.env "${profile_args[@]}" "${args[@]}" config -q 2>&1)
    EXIT=$?
    rm -f "$TMP_ENV"
else
    OUT=$(docker compose --env-file .runtime/env/compose.env "${profile_args[@]}" "${args[@]}" config -q 2>&1)
    EXIT=$?
fi

# Cleanup placeholder'ов (только тех что сами создали).
for f in "${TOUCHED[@]}"; do rm -f "$f"; done

if [ "$EXIT" -eq 0 ]; then
    exit 0
fi

# Падает — кормим фидбек агенту через stderr + exit 2.
{
    echo "compose-validation не прошла после правки $REL:"
    echo
    echo "$OUT" | head -15
    echo
    echo "Запусти 'scripts/tools/validate.sh' для полного отчёта."
} >&2

exit 2
