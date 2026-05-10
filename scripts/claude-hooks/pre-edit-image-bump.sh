#!/usr/bin/env bash
# Claude Code hook: PreToolUse на Edit/Write/MultiEdit.
# Блокирует правки `image:` строк в compose/*.yml без явного OK.
#
# WHY: bumps версий контейнеров — security/breaking-change событие, юзер хочет
# видеть каждый bump перед apply. Hook страхует от случайного "поменял версию
# вместе с другой правкой".
#
# Bypass: SKIP_IMAGE_HOOK=1 в env (через ChatUI:
#         "сделай Edit с переменной SKIP_IMAGE_HOOK=1").

set -uo pipefail

# Bypass через env (доступен через Claude Code permissions окружения).
if [ "${SKIP_IMAGE_HOOK:-}" = "1" ]; then
    exit 0
fi

INPUT=$(cat)

if command -v jq >/dev/null 2>&1; then
    FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
    OLD=$(echo "$INPUT" | jq -r '.tool_input.old_string // empty')
    NEW=$(echo "$INPUT" | jq -r '.tool_input.new_string // empty')
    CONTENT=$(echo "$INPUT" | jq -r '.tool_input.content // empty')
else
    FILE=$(echo "$INPUT" | grep -oE '"file_path":"[^"]+"' | head -1 | sed 's/"file_path":"\(.*\)"/\1/')
    OLD=""
    NEW=""
    CONTENT=""
fi

[ -z "$FILE" ] && exit 0

# Реагируем только на compose-файлы.
ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
REL="${FILE#"$ROOT/"}"

case "$REL" in
    docker-compose.yml|compose/*.yml)
        ;;
    *)
        exit 0
        ;;
esac

# Проверяем меняется ли image-строка.
# Edit: old/new должны различаться по image-строке.
# Write: content содержит новые image-строки vs существующие.
match_image_change() {
    local before="$1"
    local after="$2"
    local before_imgs after_imgs
    before_imgs=$(echo "$before" | grep -E '^[[:space:]]*image:' | sort -u || true)
    after_imgs=$(echo "$after" | grep -E '^[[:space:]]*image:' | sort -u || true)
    [ "$before_imgs" != "$after_imgs" ]
}

CHANGED=0

if [ -n "$OLD" ] && [ -n "$NEW" ]; then
    if match_image_change "$OLD" "$NEW"; then
        CHANGED=1
    fi
elif [ -n "$CONTENT" ] && [ -f "$FILE" ]; then
    EXISTING=$(cat "$FILE")
    if match_image_change "$EXISTING" "$CONTENT"; then
        CHANGED=1
    fi
fi

if [ "$CHANGED" -eq 0 ]; then
    exit 0
fi

cat <<EOF >&2
БЛОК: правка image: строки в $REL.

Bumps версий — security-sensitive шаг. Покажи юзеру:
  - какая старая версия → новая
  - что нового в release-notes
  - есть ли breaking changes

Получи явный OK, затем выполни Edit с env-переменной:
  SKIP_IMAGE_HOOK=1 (передаётся через окружение запуска)

Альтернатива: оформи bump отдельным коммитом 'chore(<svc>): bump <name> to <ver>'.
EOF
exit 2
