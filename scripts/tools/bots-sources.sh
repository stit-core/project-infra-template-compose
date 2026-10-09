#!/usr/bin/env bash
# bots-sources.sh — список источников allowlist ботов: configs/crowdsec/ai-bots.sources.
#
# Файл — печать реестра ботов соседа <org>/site: норма одна и у сайта, хаб своей копии
# реестра, сетей и токенов не носит. Первая строка — версия реестра (sha256 файла
# src/shared/seo/crawlers.yaml), дальше строка на бота: «назначение токен ip_list_url rdns».
# Читает файл задание configs/crowdsec/bots-allowlist.sh.
#
#   bots-sources.sh         печать: `pnpm -s bots:sources` соседа → файл (make bots-sources)
#   bots-sources.sh check   сверка версии файла с реестром соседа: строка «PASS|WARN|SKIP
#                           пояснение» (make doctor)
#
# Сосед — SITE_REPO_PATH из окружения или .env.local, иначе ../site
# (docs/reference/ecosystem.md). Обновлять файл — когда строка AI-BOTS handoff релиза сайта
# называет другую версию реестра.
set -euo pipefail
cd "$(dirname "$0")/../.."

OUT=configs/crowdsec/ai-bots.sources
REGISTRY=src/shared/seo/crawlers.yaml
HEAD_RE='^# crawlers\.yaml sha256:[0-9a-f]{64}$'
# Строка бота — та же форма, что принимает задание allowlist.
LINE_RE='^(search|user_fetch|training) [A-Za-z0-9._-]+ (https://[A-Za-z0-9._~:/?#@!&=+%-]+|—) ([a-z0-9.,-]+|—)$'

site=${SITE_REPO_PATH:-}
if [ -z "$site" ] && [ -f .env.local ]; then
  site=$({ grep -E '^SITE_REPO_PATH=' .env.local || true; } | tail -n 1 | sed -E "s/^SITE_REPO_PATH=//; s/[[:space:]]+#.*\$//; s/^[\"']//; s/[\"']\$//")
fi
site=${site:-../site}

if [ "${1:-}" = check ]; then
  [ -f "$OUT" ] || { echo "WARN нет $OUT — make bots-sources"; exit 0; }
  have=$(sed -n '1s/^# crawlers\.yaml sha256:\([0-9a-f]\{64\}\)$/\1/p' "$OUT")
  [ -n "$have" ] || { echo "WARN первая строка $OUT — не версия реестра: make bots-sources"; exit 0; }
  [ -f "$site/$REGISTRY" ] || { echo "SKIP нет соседа <org>/site с реестром ботов ($site)"; exit 0; }
  want=$(sha256sum "$site/$REGISTRY" | cut -d' ' -f1)
  if [ "$have" = "$want" ]; then echo "PASS реестр ${have:0:12}"
  else echo "WARN реестр соседа ${want:0:12} ≠ ${have:0:12} в $OUT — make bots-sources"; fi
  exit 0
fi

[ -f "$site/package.json" ] || { echo "ERR: сосед <org>/site не найден: $site (SITE_REPO_PATH в .env.local)" >&2; exit 1; }
command -v pnpm >/dev/null || { echo "ERR: нужен pnpm — источники печатает команда пакета сайта (pnpm -s bots:sources)" >&2; exit 1; }
new=$(cd "$site" && pnpm -s bots:sources) || { echo "ERR: pnpm -s bots:sources в $site завершилась отказом" >&2; exit 1; }

# Форма печати: чужой вывод в файл источников уходит, только когда он весь — её строки.
first=${new%%$'\n'*}; rest=${new#"$first"}; rest=${rest#$'\n'}
[[ $first =~ $HEAD_RE ]] || { echo "ERR: первая строка печати — не «# crawlers.yaml sha256:<64 знака>»" >&2; exit 1; }
bad=$({ grep -nvE "$LINE_RE" <<<"$rest" || true; } | cut -d: -f1 | paste -sd' ' -)
[ -z "$bad" ] || { echo "ERR: строки печати не той формы (номера после первой: $bad) — файл не тронут" >&2; exit 1; }
[ -n "$rest" ] || { echo "ERR: в печати нет ни одного бота — файл не тронут" >&2; exit 1; }

ver=${first#*sha256:}; ver=${ver:0:12}
bots=$(grep -c . <<<"$rest")
lists=$(grep -c ' https://' <<<"$rest" || true)
at=$(git -C "$site" describe --tags --always --dirty 2>/dev/null || echo "вне git")
if [ -f "$OUT" ] && [ "$new" = "$(cat "$OUT")" ]; then state="без изменений"
else printf '%s\n' "$new" > "$OUT"; state="обновлён — git diff $OUT, затем make ship"; fi
echo "$OUT: реестр $ver, ботов $bots, со списком сетей $lists; сосед — $site ($at); $state"
