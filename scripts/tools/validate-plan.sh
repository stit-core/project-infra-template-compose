#!/usr/bin/env bash
# Валидатор структуры планов .claude/plans/*.md (skill plan). Каноничный хвост:
#   OK            — все планы структурны
#   FAIL: <план>  — список проблемных, exit 1
#
# Проверяет на каждый <slug>.md (roadmap.md исключён):
#   - обязательные: **Slug:**, **Статус:**, ## Контекст, ## Атомы,
#     ## Corp impact, ## Чекпоинты
#   - каждый атом (- [ ]/[x] **AN:**) имеет под-строки `Verify:` и `Зависит от:`
#   - атомов ≤ 15
#   - атомов > 8 без `### Phase` — advisory (не фейл)
#
# Arg: путь к конкретному плану; по умолчанию — все .claude/plans/*.md.
set -o pipefail
cd "$(dirname "$0")/../.."

shopt -s nullglob
if [ -n "${1:-}" ]; then
  files=("$1")
else
  files=()
  for f in .claude/plans/*.md; do
    [ "$(basename "$f")" = "roadmap.md" ] && continue
    files+=("$f")
  done
fi

if [ ${#files[@]} -eq 0 ]; then
  echo "OK (планов нет)"
  exit 0
fi

fail=0
declare -a failed=()

for f in "${files[@]}"; do
  issues=$(awk '
    BEGIN { atoms=0; phases=0; in_atom=0 }
    function finalize() {
      if (!in_atom) return
      if (!hasv) print "  " aname ": нет Verify:"
      if (!hasd) print "  " aname ": нет Зависит от:"
      in_atom=0
    }
    /^### Phase / { phases++ }
    /^- \[[ x]\] \*\*A[0-9]+/ {
      finalize()
      atoms++
      aname=$0; sub(/^- \[[ x]\] \*\*/, "", aname); sub(/:\*\*.*/, "", aname)
      in_atom=1; hasv=0; hasd=0
      next
    }
    /^## / { finalize() }
    in_atom && /Verify:/      { hasv=1 }
    in_atom && /Зависит от:/  { hasd=1 }
    END {
      finalize()
      if (atoms == 0)  print "  атомов не найдено (нет `- [ ] **AN:**`)"
      if (atoms > 15)  print "  атомов " atoms " > 15 — разбей на зависимые планы"
      if (atoms > 8 && phases == 0) print "  ADVISORY: " atoms " атомов без `### Phase` — сгруппируй по фазам"
    }
  ' "$f")

  # обязательные секции/поля
  for need in '\*\*Slug:\*\*' '\*\*Статус:\*\*' '^## Контекст' '^## Атомы' '^## Corp impact' '^## Чекпоинты'; do
    grep -qE "$need" "$f" || issues+=$'\n'"  отсутствует: ${need//\\/}"
  done

  # ADVISORY-строки не фейлят
  hard=$(echo "$issues" | grep -v 'ADVISORY:' | grep -v '^[[:space:]]*$' || true)
  if [ -n "$hard" ]; then
    echo "== $f =="
    echo "$issues" | grep -v '^[[:space:]]*$'
    fail=1
    failed+=("$(basename "$f")")
  elif echo "$issues" | grep -q 'ADVISORY:'; then
    echo "== $f =="
    echo "$issues" | grep 'ADVISORY:'
  fi
done

echo
if [ "$fail" -eq 0 ]; then
  echo "OK"
else
  echo "FAIL: ${failed[*]}"
  exit 1
fi
