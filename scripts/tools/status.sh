#!/usr/bin/env bash
# Локальная сводка состояния репо для cockpit-skill smartdev — pure-local:
# git / планы / fragments, БЕЗ docker и БЕЗ SSH. Секции парсятся smartdev'ом
# детерминированно для чейнинга:
#   == Critical ==     ATTENTION: <…> (git/deploy-drift) → чейн в triage (none = чисто)
#   == Plan ==         активные планы (validate-plan.sh --summary) → продолжить шаг
# Серверный смок (host-витали + здоровье контейнеров) — НЕ здесь: его собирает
# таргет `make status` секцией == Server == (smoke-run.sh на VPS / ssh.sh smoke
# с workstation). Сам всегда exit 0 (информационный); сигналы — в тексте секций.
set -o pipefail
cd "$(dirname "$0")/../.."

echo "== Branch =="
branch=$(git symbolic-ref --short HEAD 2>/dev/null || echo '(detached)')
behind=0
if git rev-parse --verify HEAD >/dev/null 2>&1; then
  upstream=$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)
  if [ -n "$upstream" ]; then
    ahead=$(git rev-list --count "$upstream..HEAD" 2>/dev/null || echo 0)
    behind=$(git rev-list --count "HEAD..$upstream" 2>/dev/null || echo 0)
    echo "$branch ($ahead ahead, $behind behind $upstream)"
  else
    echo "$branch (no upstream)"
  fi
  echo "last: $(git log -1 --format='%h %s (%ar)')"
else
  echo "$branch (no commits yet)"
fi

echo
echo "== Working tree =="
mod=$(git status --short | grep -c '^ M' || true)
sta=$(git status --short | grep -c '^M ' || true)
unt=$(git status --short | grep -c '^??' || true)
echo "modified: $mod, staged: $sta, untracked: $unt"

echo
echo "== Critical =="
# ATTENTION:-строки парсит smartdev → чейн в triage. none = чисто.
# Только git/deploy-drift — pure-local. Контейнерное здоровье VPS (unhealthy/
# exited/restart-loop) живёт в смоке (== Server ==, smoke.d/20-containers.sh):
# его собирает таргет make status, не этот скрипт (никакого docker здесь).
crit=0
if [ "${behind:-0}" -gt 0 ] 2>/dev/null; then
  echo "ATTENTION: upstream разошлась ($behind behind) — git pull --ff-only / deploy упадёт"
  crit=1
fi
[ "$crit" -eq 0 ] && echo "none"

echo
echo "== Plan =="
bash scripts/tools/validate-plan.sh --summary

echo
echo "== Compose =="
shopt -s globstar nullglob
fragments=(compose/*.yml)
echo "fragments: ${#fragments[@]}"
tpls=(configs/**/*.tpl)
echo "tpl-configs: ${#tpls[@]}"
shopt -u globstar nullglob

echo
echo "== Recent commits =="
git log --oneline -5 2>/dev/null | sed 's/^/  /' || echo "  (none)"
# Финальный маркер (== Server == + OK) печатает таргет make status — см. Makefile.
