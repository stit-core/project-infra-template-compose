#!/usr/bin/env bash
# Pre-deploy gate: compose syntax + .env.example coverage + tpl render.
set -eo pipefail
cd "$(dirname "$0")/../.."

fail=0

echo "== compose syntax =="
if ! command -v docker >/dev/null; then
  echo "  docker not installed locally — skipped"
else
  args=(-f docker-compose.yml)
  for f in compose/*.yml; do [ -f "$f" ] && args+=(-f "$f"); done
  if [ -f .env ]; then
    if docker compose "${args[@]}" --env-file .env config -q 2>/tmp/compose-validate.err; then
      echo "  OK"
    else
      echo "  FAIL"
      sed 's/^/    /' /tmp/compose-validate.err
      fail=1
    fi
  else
    echo "  .env missing — skipping (need real .env for substitutions)"
  fi
fi

echo
echo "== yamllint configs/ =="
if ! command -v yamllint >/dev/null; then
  echo "  yamllint not installed — skipped (install: pip install yamllint)"
else
  if yamllint -d "{extends: relaxed, rules: {line-length: disable}}" configs/ compose/ docker-compose.yml 2>&1 | sed 's/^/  /'; then
    echo "  OK"
  else
    fail=1
  fi
fi

echo
echo "== .tpl rendering =="
shopt -s globstar nullglob
tpls=(configs/**/*.tpl)
if [ ${#tpls[@]} -eq 0 ]; then
  echo "  no .tpl files"
else
  set -a
  [ -f .env ] && . ./.env
  set +a
  for tpl in "${tpls[@]}"; do
    if envsubst < "$tpl" >/dev/null 2>&1; then
      echo "  $tpl: OK"
    else
      echo "  $tpl: FAIL"
      fail=1
    fi
  done
fi

echo
echo "== .env.example coverage =="
# Find ${VAR} references in compose + configs, check presence in .env.example.
if [ ! -f .env.example ]; then
  echo "  .env.example missing"
  fail=1
else
  used=$(grep -rhoE '\$\{[A-Z_][A-Z0-9_]*' compose/ configs/ docker-compose.yml 2>/dev/null \
          | sed 's/${//' | sort -u)
  missing=()
  while read -r var; do
    [ -z "$var" ] && continue
    if ! grep -qE "^#?\s*$var=" .env.example; then
      missing+=("$var")
    fi
  done <<<"$used"
  if [ ${#missing[@]} -eq 0 ]; then
    echo "  OK — все used vars в .env.example"
  else
    echo "  FAIL — missing in .env.example:"
    printf '    %s\n' "${missing[@]}"
    fail=1
  fi
fi

echo
if [ $fail -eq 0 ]; then echo "OK"; else echo "FAIL"; exit 1; fi
