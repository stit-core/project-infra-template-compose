#!/usr/bin/env bash
# Сводка состояния репо для cockpit-skill smartdev. Секции парсятся им
# детерминированно для чейнинга:
#   == Critical ==     ATTENTION: <…>  → чейн в triage   (none = чисто)
#   == Infra-touch ==  список corp-классов → чейн в corp-handoff (none = чисто)
#   == Plan ==         активный план из roadmap → продолжить атомы
# Без SSH; серверные проверки — через scripts/tools/ssh.sh status.
# Сам всегда exit 0 (информационный); сигналы — в тексте секций.
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
crit=0
if [ "${behind:-0}" -gt 0 ] 2>/dev/null; then
  echo "ATTENTION: upstream разошлась ($behind behind) — git pull --ff-only / deploy упадёт"
  crit=1
fi
if command -v docker >/dev/null 2>&1; then
  unhealthy=$(docker ps --filter health=unhealthy --format '{{.Names}}' 2>/dev/null | paste -sd' ' -)
  exited=$(docker ps -a --filter status=exited --filter label=com.docker.compose.project \
             --format '{{.Names}}' 2>/dev/null | paste -sd' ' -)
  [ -n "$unhealthy" ] && { echo "ATTENTION: unhealthy: $unhealthy — make logs SVC=<svc> / skill triage"; crit=1; }
  [ -n "$exited" ]    && { echo "ATTENTION: exited: $exited — make ps / skill triage"; crit=1; }
fi
[ "$crit" -eq 0 ] && echo "none"

echo
echo "== Infra-touch =="
# Working tree задел corp-поверхность? → smartdev чейнит в corp-handoff.
paths=$(git status --porcelain 2>/dev/null | cut -c4-)
declare -a hits=()
grep -qE '^configs/vault-agent/'              <<<"$paths" && hits+=("vault-agent-config")
grep -qE '^compose/.*\.ya?ml'                 <<<"$paths" && hits+=("compose-topology/profiles")
grep -qE '(^|[ >])\.env\.example'             <<<"$paths" && hits+=("env-contract")
grep -qE 'configs/crowdsec/whitelists\.yaml'  <<<"$paths" && hits+=("crowdsec-whitelist")
grep -qE '^ansible/'                          <<<"$paths" && hits+=("ansible-bootstrap")
if [ ${#hits[@]} -eq 0 ]; then
  echo "none"
else
  printf '%s\n' "${hits[*]}"
  echo "(тронута corp-поверхность — оформи CORP-HANDOFF до claim «готово», skill corp-handoff)"
fi

echo
echo "== Plan =="
# Единый roadmap: Current focus + по секции ## Active — slug, статус, следующий открытый атом.
# Метадата-строки якорятся к ^** (проза атомов с `**Статус:**` иначе ломает парс).
roadmap=.claude/plans/roadmap.md
if [ -f "$roadmap" ]; then
  foc=$(grep -m1 '^\*\*Current focus:\*\*' "$roadmap" | sed -E 's/\*\*Current focus:\*\*[[:space:]]*//')
  [ -n "$foc" ] && echo "  focus: $foc"
  awk '
    function flush(){ if(slug!="") printf "  %s: %s | next: %s\n", slug, st, (nx==""?"—":nx) }
    /^## Active/ { inact=1; next }
    /^## /       { flush(); inact=0; slug=""; next }
    !inact       { next }
    /^### /      { flush(); slug=$0; sub(/^### /,"",slug); sub(/ .*/,"",slug); st="?"; nx=""; next }
    slug=="" { next }
    /^\*\*Создан:\*\*/ { if ($0 ~ /\*\*Статус:\*\*/){ s=$0; sub(/.*\*\*Статус:\*\*[[:space:]]*/,"",s); sub(/[[:space:]].*$/,"",s); st=s } }
    /^\*\*Статус:\*\*/ { s=$0; sub(/^\*\*Статус:\*\*[[:space:]]*/,"",s); sub(/[[:space:]].*$/,"",s); st=s }
    /^- \[ \] \*\*A[0-9]/ && nx=="" { n=$0; sub(/^- \[ \] \*\*/,"",n); sub(/:.*/,"",n); nx=n }
    END { flush() }
  ' "$roadmap"
  grep -q '^### ' "$roadmap" || echo "  none (нет активных планов)"
else
  echo "none (roadmap отсутствует)"
fi

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

echo
echo "OK"
