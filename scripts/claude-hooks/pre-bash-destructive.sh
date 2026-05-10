#!/usr/bin/env bash
# Claude Code hook: PreToolUse на Bash.
# Блокирует destructive-команды без явного opt-in:
#   --no-verify (обход git-хуков)
#   git push --force / -f
#   git reset --hard
#   git clean -f
#   rm -rf без явного path
#   docker volume rm
#   docker compose down -v
#   git commit -n (короткая форма --no-verify)

set -uo pipefail

INPUT=$(cat)

if command -v jq >/dev/null 2>&1; then
    CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
else
    CMD=$(echo "$INPUT" | grep -oE '"command":"[^"]+"' | head -1 | sed 's/"command":"\(.*\)"/\1/')
fi

[ -z "$CMD" ] && exit 0

block() {
    local reason="$1"
    cat <<EOF >&2
БЛОК: $reason

Если действительно нужно — пользователь должен явно одобрить
(или экспортировать SKIP_HOOK=1 в одной команде).

Команда: $CMD
EOF
    exit 2
}

# Bypass.
if echo "$CMD" | grep -qE '(^|[[:space:]])SKIP_HOOK=1[[:space:]]'; then
    exit 0
fi

# --no-verify / --no-gpg-sign / --no-edit
if echo "$CMD" | grep -qE '(^|[[:space:]])(--no-verify|--no-gpg-sign|--no-edit)([[:space:]]|$)'; then
    block "флаг --no-verify (или --no-gpg-sign / --no-edit) обходит git-хуки. Если хук падает — разбирайся с причиной."
fi

# git commit -n
if echo "$CMD" | grep -qE 'git[[:space:]]+(.*[[:space:]])?commit[[:space:]].*[[:space:]]-n([[:space:]]|$)'; then
    block "'git commit -n' эквивалентно --no-verify."
fi

# git push --force / -f
if echo "$CMD" | grep -qE 'git[[:space:]]+(.*[[:space:]])?push[[:space:]].*(--force|--force-with-lease|[[:space:]]-f)([[:space:]]|$)'; then
    block "git push --force перезаписывает remote-историю."
fi

# git reset --hard
if echo "$CMD" | grep -qE 'git[[:space:]]+(.*[[:space:]])?reset[[:space:]].*--hard'; then
    block "git reset --hard теряет working tree безвозвратно."
fi

# git clean -f
if echo "$CMD" | grep -qE 'git[[:space:]]+(.*[[:space:]])?clean[[:space:]].*-f'; then
    block "git clean -f удаляет untracked-файлы."
fi

# rm -rf на корне или пустом пути.
if echo "$CMD" | grep -qE '(^|[[:space:]])rm[[:space:]].*-r[[:space:]]*-?f?[[:space:]]*(/|/\*|/[[:space:]]|$)'; then
    block "rm -rf на корне."
fi
if echo "$CMD" | grep -qE '(^|[[:space:]])rm[[:space:]]+-rf?[[:space:]]+\$\{'; then
    block "rm -rf c unset/empty переменной — высокий риск catastrophic delete."
fi

# docker volume rm
if echo "$CMD" | grep -qE 'docker[[:space:]]+volume[[:space:]]+rm'; then
    block "docker volume rm удаляет персистентные данные. Бэкап есть, но это руками-восстанавливаемый шаг."
fi

# docker compose down -v
if echo "$CMD" | grep -qE 'docker[[:space:]]+compose[[:space:]].*down[[:space:]].*(-v|--volumes)'; then
    block "docker compose down -v удаляет все volumes. Это приговор данным без явного OK."
fi

exit 0
