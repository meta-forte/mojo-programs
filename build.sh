#!/usr/bin/env bash
# Build Mojo programs into build/, mirroring the source folders, and
# optionally run them from there. Sources are never written to.
#
#   L01/dce.mojo  ->  build/L01/dce
#
# Usage: ./build.sh [options] [target ...] [-- program args ...]
#
#   target         A .mojo file or a folder. Folders are searched
#                  recursively. Default: the whole project.
#   -r, --run      Run each built program, with its build folder as the
#                  working directory.
#   --run-only     Run already built programs without rebuilding.
#   --no-cache     Compile with an empty Mojo cache, so compile-time code
#                  (and compile-time print) runs again.
#   -h, --help     Show this help.
#   Any other option starting with '-' (e.g. -O0, -g, -D ASSERT=none,
#   --target-cpu x86-64) is passed to 'mojo build'. Arguments after '--'
#   are passed to the programs.
#
# Only files that define 'def main(' are built; library modules are skipped.
#
# Examples:
#   ./build.sh                     build everything
#   ./build.sh L01                 build all programs in L01
#   ./build.sh -r L01/dce.mojo     build and run one program
#   ./build.sh -r -O0 L01/dce.mojo -- arg1 arg2
#   ./build.sh -r -D ASSERT=none --target-cpu x86-64 L01/simd_search.mojo

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$ROOT/build"

# Folders that hold reference material or tooling, not programs.
EXCLUDES=(build .git .venv .pixi mojo-src notes/mojo-release-notes)

usage() { sed -n '2,/^$/{s/^# \{0,1\}//;p}' "${BASH_SOURCE[0]}"; }

run=false
build=true
no_cache=false
mojo_flags=()
targets=()
prog_args=()

while (($#)); do
    case "$1" in
        -r|--run) run=true ;;
        --run-only) run=true; build=false ;;
        --no-cache) no_cache=true ;;
        -h|--help) usage; exit 0 ;;
        --) shift; prog_args=("$@"); break ;;
        # 'mojo build' options that take a separate value, e.g. -D ASSERT=none.
        -D|-I|--target-triple|--target-cpu|--target-features|--target-abi|\
        --target-accelerator|--march|--mcpu|--mtune)
            if (($# < 2)); then
                echo "error: $1 needs a value" >&2
                exit 1
            fi
            mojo_flags+=("$1" "$2"); shift ;;
        -*) mojo_flags+=("$1") ;;
        *) targets+=("$1") ;;
    esac
    shift
done

# Mojo lives in the project venv; its activate script also sets
# LD_LIBRARY_PATH, which the built programs need.
if ! command -v mojo >/dev/null 2>&1; then
    # shellcheck disable=SC1091
    source "$ROOT/.venv/bin/activate"
fi

if $no_cache; then
    # The name prefix lets compcache_cleanup.sh find it if a run is killed.
    XDG_CACHE_HOME="$(mktemp -d -t mojo-nocache.XXXXXX)"
    export XDG_CACHE_HOME
    trap 'rm -rf "$XDG_CACHE_HOME"' EXIT
fi

# Collect .mojo files that have an entry point.
find_programs() {
    local prune=()
    for d in "${EXCLUDES[@]}"; do
        prune+=(-path "$ROOT/$d" -o)
    done
    find "$1" \( "${prune[@]}" -false \) -prune -o -type f -name '*.mojo' -print |
        sort |
        while IFS= read -r f; do
            grep -q '^def main(' "$f" && printf '%s\n' "$f"
        done
}

((${#targets[@]})) || targets=("$ROOT")

files=()
for t in "${targets[@]}"; do
    if [[ ! -e "$t" ]]; then
        echo "error: no such file or folder: $t" >&2
        exit 1
    fi
    abs="$(realpath "$t")"
    if [[ "$abs" != "$ROOT" && "$abs" != "$ROOT"/* ]]; then
        echo "error: $t is outside the project ($ROOT)" >&2
        exit 1
    fi
    if [[ -d "$abs" ]]; then
        while IFS= read -r f; do files+=("$f"); done < <(find_programs "$abs")
    elif [[ "$abs" == *.mojo ]]; then
        files+=("$abs")
    else
        echo "error: not a .mojo file or folder: $t" >&2
        exit 1
    fi
done

if ((${#files[@]} == 0)); then
    echo "No programs (files with 'def main(') found." >&2
    exit 1
fi

failed=0
for src in "${files[@]}"; do
    rel="${src#"$ROOT"/}"
    out="$BUILD_DIR/${rel%.mojo}"

    if $build; then
        echo "==> build ${rel} -> build/${rel%.mojo}"
        mkdir -p "$(dirname "$out")"
        # -I ROOT lets programs import shared packages kept at the top level.
        if ! mojo build "${mojo_flags[@]}" -I "$ROOT" -o "$out" "$src"; then
            echo "!! build failed: $rel" >&2
            failed=$((failed + 1))
            continue
        fi
    fi

    if $run; then
        if [[ ! -x "$out" ]]; then
            echo "!! not built: build/${rel%.mojo}" >&2
            failed=$((failed + 1))
            continue
        fi
        echo "==> run build/${rel%.mojo}"
        if ! (cd "$(dirname "$out")" && "./$(basename "$out")" "${prog_args[@]}"); then
            echo "!! run failed: $rel" >&2
            failed=$((failed + 1))
        fi
    fi
done

if ((failed)); then
    echo "$failed of ${#files[@]} failed." >&2
    exit 1
fi
