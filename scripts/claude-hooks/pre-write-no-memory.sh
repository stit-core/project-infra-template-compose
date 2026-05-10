#!/usr/bin/env bash
# Claude Code hook: PreToolUse на Edit/Write/MultiEdit/NotebookEdit.
# Блокирует запись в auto-memory: ~/.claude/projects/*/memory/**.
#
# WHY: в этом проекте автопамять отключена. Всё, что должно пережить сессию,
# фиксируется в репо под git (AGENTS.md, .claude/rules/, .claude/plans/, docs/).
# Память per-user/per-project не видна команде, не ревьюится, не воспроизводима.

set -uo pipefail

INPUT=$(cat)

if command -v jq >/dev/null 2>&1; then
    FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty')
else
    FILE=$(echo "$INPUT" | grep -oE '"(file_path|notebook_path)":"[^"]+"' | head -1 | sed 's/.*":"\(.*\)"/\1/')
fi

[ -z "$FILE" ] && exit 0

case "$FILE" in
    */.claude/projects/*/memory/*)
        cat <<EOF >&2
БЛОК: запись в auto-memory отключена в этом проекте.

Путь: $FILE

Автопамять Claude не используется. Всё, что должно пережить сессию,
фиксируется в репо под git:
  - правила/предпочтения      → AGENTS.md или .claude/rules/<topic>.md
  - решения/ADR               → docs/adrs/NNNN-<slug>.md
  - активные задачи           → .claude/plans/<slug>.md
  - reference на внешние сис. → docs/architecture.md / docs/onboarding.md / docs/runbook.md

См. AGENTS.md §"Auto-memory".
EOF
        exit 2
        ;;
esac

exit 0
