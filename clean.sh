#!/usr/bin/env bash
# Remove build artifacts.
#
# Usage: ./clean.sh [options]
#
#   (no options)   Delete the build/ folder.
#   --strays       Also delete artifacts left in source folders by running
#                  'mojo build' or 'mojo precompile' by hand:
#                    - executables named after a .mojo file, either next to
#                      that file or at the project root
#                    - *.mojoc precompiled packages
#   --cache        Also clear the Mojo compile cache by running
#                  compcache_cleanup.sh (see that script for details).
#                  Safe: Mojo rebuilds it, the next builds are just slower.
#   --all          Same as --strays --cache.
#   -n, --dry-run  Only print what would be deleted.
#   -h, --help     Show this help.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXCLUDES=(build .git .venv .pixi mojo-src notes/mojo-release-notes)

usage() { sed -n '2,/^$/{s/^# \{0,1\}//;p}' "${BASH_SOURCE[0]}"; }

strays=false
cache=false
dry=false

while (($#)); do
    case "$1" in
        --strays) strays=true ;;
        --cache) cache=true ;;
        --all) strays=true; cache=true ;;
        -n|--dry-run) dry=true ;;
        -h|--help) usage; exit 0 ;;
        *) echo "error: unknown option: $1" >&2; usage >&2; exit 1 ;;
    esac
    shift
done

remove() {
    if $dry; then
        echo "would remove: $1"
    else
        echo "removing: $1"
        rm -rf -- "$1"
    fi
}

is_executable_binary() {
    [[ -f "$1" && -x "$1" ]] && file -b "$1" | grep -q '^ELF'
}

[[ -e "$ROOT/build" ]] && remove "$ROOT/build"

if $strays; then
    prune=()
    for d in "${EXCLUDES[@]}"; do
        prune+=(-path "$ROOT/$d" -o)
    done

    # Executables named after a source file.
    while IFS= read -r src; do
        stem="$(basename "${src%.mojo}")"
        for cand in "${src%.mojo}" "$ROOT/$stem"; do
            is_executable_binary "$cand" && remove "$cand"
        done
    done < <(find "$ROOT" \( "${prune[@]}" -false \) -prune -o -type f -name '*.mojo' -print)

    # Precompiled packages.
    while IFS= read -r f; do
        remove "$f"
    done < <(find "$ROOT" \( "${prune[@]}" -false \) -prune -o -type f -name '*.mojoc' -print)
fi

if $cache; then
    cache_args=()
    $dry && cache_args+=(--dry-run)
    "$ROOT/compcache_cleanup.sh" "${cache_args[@]}"
fi

exit 0
