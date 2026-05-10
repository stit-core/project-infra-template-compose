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

args=(-f docker-compose.yml)
for f in compose/*.yml; do
    args+=(-f "$f")
done

if [ -n "$TMP_ENV" ]; then
    OUT=$(docker compose --env-file "$TMP_ENV" "${args[@]}" config -q 2>&1)
    EXIT=$?
    rm -f "$TMP_ENV"
else
    OUT=$(docker compose "${args[@]}" config -q 2>&1)
    EXIT=$?
fi

if [ "$EXIT" -eq 0 ]; then
    exit 0
fi

# Падает — кормим фидбек агенту через stderr + exit 2.
{
    echo "compose-validation не прошла после правки $REL:"
    echo
    echo "$OUT" | head -15
    echo
    echo "Запусти 'scripts/agent-tools/validate.sh' для полного отчёта."
} >&2

exit 2
