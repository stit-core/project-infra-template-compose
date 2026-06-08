#!/usr/bin/env bash
# Единственный путь изменений → сервер.
#
# Usage:
#   bash scripts/ship.sh "feat(foo): bar"    # add -A + commit + push + (if main) ssh-deploy
#   bash scripts/ship.sh                     # push + (if main) ssh-deploy. Без коммита (working tree чистый).
#
# Адрес VPS читается из ansible/inventory.ini (host=root@<ip>).
set -euo pipefail
cd "$(dirname "$0")/.."

msg="${1:-}"
branch=$(git symbolic-ref --short HEAD 2>/dev/null) || { echo "ERR: not on a branch" >&2; exit 1; }

dirty=0
if ! git diff --quiet HEAD 2>/dev/null \
   || ! git diff --cached --quiet 2>/dev/null \
   || [ -n "$(git ls-files --others --exclude-standard)" ]; then
  dirty=1
fi

if [ "$dirty" -eq 1 ]; then
  [ -z "$msg" ] && {
    echo "ERR: working tree dirty — передай commit message:" >&2
    echo "     make ship MSG='feat(foo): bar'" >&2
    exit 1
  }
  echo "→ commit"
  git add -A
  git commit -m "$msg"
fi

echo "→ make check (pre-ship gate)"
if ! make check; then
  echo "ERR: make check красный — пуш отменён. Почини и повтори ship." >&2
  echo "     (коммит уже локально создан — amend после фикса либо новый коммит)" >&2
  exit 1
fi

# --- Corp-handoff агрегация (.claude/rules/corp-handoff.md) ---
# Печатает агрегированный Corp impact из активных планов; если corp-поверхность
# тронута в неотправленных коммитах, а блока нет — warn.
# Advisory: пуш не блокирует (передача корп-админу — out-of-band).
#
# Single-file модель: единый .claude/plans/roadmap.md. На каждую `### <slug>`-секцию
# под `## Active` — захватываем подсекцию `**Corp impact.**` (bold-лейбл) до следующего
# bold-лейбла / `#### `-фазы / `### `/`## `-границы. Пустой маркер `—` пропускаем.
corp_impact=""
roadmap=.claude/plans/roadmap.md
if [ -f "$roadmap" ]; then
  corp_impact=$(awk '
    function emit(s, line,   t) {
      t = line; gsub(/^[[:space:]]+|[[:space:]]+$/, "", t)
      if (t == "" || t == "—" || t == "|") return
      if (!hdr[s]) { print "--- " s " ---"; hdr[s] = 1 }
      print line
    }
    /^## Active/ { inact = 1; next }
    /^## /       { inact = 0; slug = ""; cap = 0; next }
    !inact       { next }
    /^### /      { slug = $0; sub(/^### /, "", slug); sub(/ .*/, "", slug); cap = 0; next }
    slug == ""   { next }
    /^\*\*Corp impact\.\*\*/ {
      cap = 1
      rest = $0; sub(/^\*\*Corp impact\.\*\*[[:space:]]*/, "", rest)
      emit(slug, rest)            # инлайн-хвост после лейбла, если есть
      next
    }
    cap && /^\*\*[^*]+\.\*\*/   { cap = 0; next }   # следующий bold-лейбл закрывает
    cap && /^(#### |### |## )/  { cap = 0 }
    cap                         { emit(slug, $0) }
  ' "$roadmap")
fi

range=""
if up=$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null); then
  range="$up..HEAD"
fi
touched=""
# CrowdSec-whitelist здесь не фильтруется: файл живёт corp-side (corp-infra-template),
# в проектном репо его нет — corp-handoff по нему оформляется вручную (skill corp-handoff).
[ -n "$range" ] && touched=$(git diff --name-only "$range" 2>/dev/null \
  | grep -E '^configs/vault-agent/|^compose/[^/]+\.ya?ml$|^\.env\.example$|^ansible/roles/stit-onboard/' || true)

if [ -n "$corp_impact" ]; then
  echo
  echo "=== CORP HANDOFF · агрегировано из активных планов · передай корп-админу ==="
  printf '%s' "$corp_impact"
  echo "=== (out-of-band: Slack / тикет / PR в corp-infra-template) ==="
elif [ -n "$touched" ]; then
  echo
  echo "⚠ corp-поверхность тронута в этом push, но **Corp impact.** пуст:" >&2
  printf '    %s\n' $touched >&2
  echo "  Оформи CORP-HANDOFF (skill corp-handoff) и передай корп-админу до claim «готово»." >&2
fi

echo "→ push origin $branch"
git push origin "$branch"

if [ "$branch" != "main" ]; then
  echo "→ branch '$branch' запушена. Открой PR в Gitea, мержи в main, потом ship снова."
  exit 0
fi

# SSH-deploy: адрес VPS из ansible/inventory.ini.
[ -f ansible/inventory.ini ] || { echo "ERR: ansible/inventory.ini нет — bootstrap-vps сначала" >&2; exit 1; }
line=$(awk '/^\[project_vps\]/{flag=1; next} /^\[/{flag=0} flag && /ansible_host/' \
       ansible/inventory.ini | head -1)
ip=$(grep -oE 'ansible_host=[^ ]+'  <<<"$line" | cut -d= -f2)
user=$(grep -oE 'ansible_user=[^ ]+' <<<"$line" | cut -d= -f2)
project=$(grep -oE 'project_name=[^ ]+' <<<"$line" | cut -d= -f2)
[ -z "$ip" ]      && { echo "ERR: ansible_host не найден в inventory" >&2; exit 1; }
[ -z "$project" ] && { echo "ERR: project_name не найден в inventory" >&2; exit 1; }
user="${user:-root}"

echo "→ deploy /opt/$project-infra on $user@$ip"
exec ssh -t -o StrictHostKeyChecking=accept-new "$user@$ip" \
  "cd /opt/$project-infra && bash scripts/deploy.sh"
