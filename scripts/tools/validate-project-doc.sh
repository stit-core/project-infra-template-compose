#!/usr/bin/env bash
# tools/validate-project-doc.sh — детерминированный валидатор инфра-слоя docs/project/.
#
# 2 kind'а: service (per hosted-сервис, services/<name>.md), stack (singleton — cross-cutting
# инфры VPS + карта сервисов + среды). frontmatter + обязательные H2-секции; при status: stable
# секции непусты. Артефакты — вход для skill `de-template` (`stack § Service map` выводит
# COMPOSE_PROFILES; секция `Generates` каждого service/stack описывает, что родится в инфре).
# Продуктовый контекст (Problem/Users/surfaces) живёт в соседнем `<org>/docs`, не здесь.
#
# Использование:
#   scripts/tools/validate-project-doc.sh <path>   # файл или директория
#   scripts/tools/validate-project-doc.sh          # вся docs/project/
#
# Проверяет:
#   1. Frontmatter: id, kind, name, status (обязательные); kind ∈ {service,stack}.
#      Для kind=service дополнительно subtype ∈ {backend,frontend,datastore,infra},
#      hosting ∈ {here,external}.
#   2. basename == frontmatter.name; id == "project.<name>".
#   3. Все обязательные H2 для kind присутствуют; при status: stable — непусты.
# _templates/ и README.md пропускаются.
#
# Выход: 0 — валидно; 1 — ошибки. bash + awk + grep, без внешних зависимостей.

set -uo pipefail
ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
cd "$ROOT"

TARGET="${1:-docs/project}"
[ -e "$TARGET" ] || { echo "FAIL: target not found: $TARGET"; exit 1; }

ERRORS=()
FILES_CHECKED=0

VALID_KINDS=(service stack)
VALID_SUBTYPES=(backend frontend datastore infra)
VALID_HOSTING=(here external)

required_sections() {
    case "$1" in
        service) echo "Hosting Identity Secrets Route Generates" ;;
        stack)   echo "'Service map' Domains Edge Networks Backup Observability Environments Generates" ;;
        *)       echo "" ;;
    esac
}

in_list() {
    local needle="$1"; shift
    local v
    for v in "$@"; do [ "$needle" = "$v" ] && return 0; done
    return 1
}

read_field() {
    awk -v field="$2" '
        /^---$/ { fm = !fm; if (!fm) exit; next }
        fm && $0 ~ "^"field":" {
            sub("^"field":[ \t]*", ""); gsub(/^[ \t]+|[ \t]+$/, ""); print; exit
        }
    ' "$1"
}

has_section() {
    grep -qE "^## ${2}([ \t]*$|[ \t]+)" "$1"
}

section_body_nonempty() {
    awk -v sec="$2" '
        BEGIN { in_sec = 0; has = 0 }
        /^## / {
            if (in_sec) exit
            h = $0; sub(/^## /, "", h)
            if (h == sec) { in_sec = 1; next }
        }
        in_sec {
            line = $0; gsub(/^[ \t]+|[ \t]+$/, "", line)
            if (line == "") next
            if (line ~ /^<!--/) next
            if (line ~ /^</ && line ~ />$/) next   # placeholder <...>
            has = 1
        }
        END { exit (has ? 0 : 1) }
    ' "$1"
}

validate_file() {
    local file="$1"
    case "$file" in */docs/project/_templates/*) return 0 ;; esac
    case "$(basename "$file")" in README.md) return 0 ;; esac
    FILES_CHECKED=$((FILES_CHECKED + 1))

    if ! head -1 "$file" | grep -qE '^---$'; then
        ERRORS+=("$file: нет frontmatter (должен начинаться с ---)"); return
    fi

    local id kind name status subtype hosting
    id=$(read_field "$file" id); kind=$(read_field "$file" kind)
    name=$(read_field "$file" name); status=$(read_field "$file" status)

    [ -z "$id" ]     && ERRORS+=("$file: frontmatter.id пуст")
    [ -z "$kind" ]   && ERRORS+=("$file: frontmatter.kind пуст")
    [ -z "$name" ]   && ERRORS+=("$file: frontmatter.name пуст")
    [ -z "$status" ] && ERRORS+=("$file: frontmatter.status пуст")

    if [ -n "$kind" ] && ! in_list "$kind" "${VALID_KINDS[@]}"; then
        ERRORS+=("$file: kind '$kind' не из {${VALID_KINDS[*]}}"); return
    fi
    if [ -n "$status" ] && [ "$status" != "draft" ] && [ "$status" != "stable" ]; then
        ERRORS+=("$file: status должен быть draft|stable (got '$status')")
    fi
    if [ -n "$name" ]; then
        local bn; bn=$(basename "$file" .md)
        [ "$bn" != "$name" ] && ERRORS+=("$file: basename '$bn' != frontmatter.name '$name'")
    fi
    if [ -n "$id" ] && [ -n "$name" ] && [ "$id" != "project.$name" ]; then
        ERRORS+=("$file: id '$id' должен быть 'project.$name'")
    fi

    if [ "$kind" = "service" ]; then
        subtype=$(read_field "$file" subtype); hosting=$(read_field "$file" hosting)
        [ -z "$subtype" ] && ERRORS+=("$file: kind=service требует frontmatter.subtype")
        [ -z "$hosting" ] && ERRORS+=("$file: kind=service требует frontmatter.hosting")
        if [ -n "$subtype" ] && ! in_list "$subtype" "${VALID_SUBTYPES[@]}"; then
            ERRORS+=("$file: subtype '$subtype' не из {${VALID_SUBTYPES[*]}}")
        fi
        if [ -n "$hosting" ] && ! in_list "$hosting" "${VALID_HOSTING[@]}"; then
            ERRORS+=("$file: hosting '$hosting' не из {${VALID_HOSTING[*]}}")
        fi
    fi

    if [ -n "$kind" ]; then
        local secs; secs=$(required_sections "$kind")
        eval "set -- $secs"
        for s in "$@"; do
            if ! has_section "$file" "$s"; then
                ERRORS+=("$file: нет H2-секции '$s' (kind=$kind)"); continue
            fi
            if [ "$status" = "stable" ] && ! section_body_nonempty "$file" "$s"; then
                ERRORS+=("$file: секция '$s' пуста (status=stable требует контент)")
            fi
        done
    fi
}

FILES=()
if [ -f "$TARGET" ]; then
    FILES=("$TARGET")
else
    while IFS= read -r f; do FILES+=("$f"); done \
        < <(find "$TARGET" -type f -name '*.md' ! -path '*/_templates/*' | sort)
fi

if [ "${#FILES[@]}" -eq 0 ]; then
    echo "OK (no project .md files under $TARGET)"; exit 0
fi

for f in "${FILES[@]}"; do validate_file "$f"; done

if [ "${#ERRORS[@]}" -gt 0 ]; then
    for e in "${ERRORS[@]}"; do echo "$e"; done
    echo "FAIL: ${#ERRORS[@]} error(s) across $FILES_CHECKED file(s)"
    exit 1
fi
echo "OK ($FILES_CHECKED file(s) checked)"
