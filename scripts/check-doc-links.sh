#!/usr/bin/env bash
# Checks that every relative markdown link target in docs/, AGENTS.md, CLAUDE.md,
# and README.md points at a file that actually exists. Skips URLs, anchors, and
# mailto: links. Wired into `scripts/ci.sh` and pr.yml's "Docs sanity" step.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

files=(AGENTS.md CLAUDE.md README.md)
while IFS= read -r -d '' f; do
    files+=("$f")
done < <(find docs -name '*.md' -print0 2>/dev/null)

fail=0
for f in "${files[@]}"; do
    [ -f "$f" ] || continue
    dir="$(dirname "$f")"
    # Extract the (target) part of every [text](target) markdown link.
    while IFS= read -r target; do
        [ -z "$target" ] && continue
        case "$target" in
            http://*|https://*|mailto:*|\#*) continue ;;
        esac
        target="${target%%#*}"   # strip a trailing #anchor
        [ -z "$target" ] && continue
        resolved="$dir/$target"
        if [ ! -e "$resolved" ]; then
            echo "BROKEN LINK: $f -> $target" >&2
            fail=1
        fi
    done < <(sed -E 's/`[^`]*`//g' "$f" | grep -oE '\]\([^)]+\)' | sed -E 's/^\]\((.*)\)$/\1/')
done

if [ "$fail" -ne 0 ]; then
    echo "error: broken doc links found" >&2
    exit 1
fi
echo "ok: no broken doc links"
