#!/usr/bin/env bash
# make setup: git-хуки (симлинк scripts/git-hooks/* → .git/hooks/) + dev-deps (PyYAML).
set -euo pipefail
cd "$(dirname "$0")/.."

if [ ! -d .git ]; then
  echo "ERR: не git-репо (нет .git/)" >&2
  exit 1
fi

echo "→ git-хуки"
mkdir -p .git/hooks
for hook in scripts/git-hooks/*; do
  name=$(basename "$hook")
  ln -sf "../../$hook" ".git/hooks/$name"
  chmod +x "$hook"
  echo "  installed: $name"
done

# Dev-deps: PyYAML — авторитетная ветка frontmatter-проверки в make validate
# (scripts/tools/validate.sh). Best-effort: без него validate падает на awk-fallback
# (ловит основной класс ': ' в скаляре), поэтому setup НЕ фейлится, если pip залочен
# (PEP 668 на Debian) — только подсказывает поставить вручную.
echo "→ dev-deps: PyYAML (frontmatter-валидатор)"
if python3 -c 'import yaml' 2>/dev/null; then
  echo "  PyYAML: уже есть"
elif command -v python3 >/dev/null && python3 -m pip install --user --quiet pyyaml 2>/dev/null; then
  echo "  PyYAML: установлен (--user)"
else
  echo "  PyYAML: автоустановка не прошла (нет pip / PEP 668-lock) — поставь вручную:"
  echo "          apt install python3-yaml   ИЛИ   pip install --user --break-system-packages pyyaml"
  echo "          (необязательно — validate использует awk-fallback)"
fi

echo "OK"
