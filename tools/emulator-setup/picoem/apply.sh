#!/bin/sh
# apply.sh -- put o1next's fixes into a stock picoem checkout (#192).
#
#   tools/emulator-setup/picoem/apply.sh [PICOEM_SRC] [--build] [--test]
#
# PICOEM_SRC defaults to $PICOEM_SRC, then to ./picoem.  It must be a checkout
# at (or compatible with) the pinned commit -- see REQUIREMENTS.md for the pin
# and tools/picoem-bridge/Cargo.toml for the rev the bridge builds against.
#
# What it does, in order:
#   1. git apply the series (or patch -p1 outside a repo)
#   2. with --build, cargo build the workspace
#   3. with --test, cargo test -p rp2350-emu  (3674 pass, 0 fail)
#
# WHY THIS EXISTS RATHER THAN A PULL REQUEST
#   Not a preference: a pull request against picoem is **refused**.  Its issue
#   tracker is disabled (the API reports `has_issues: false`), and opening a PR
#   fails -- `CreatePullRequest` returns a permissions error while the REST
#   endpoint returns 404.  Upstream contribution is closed, not merely slow, and
#   its CONTRIBUTING.md says the safe path is to fork; the repository's settings
#   then enforce it.  So the fixes live in Myrcurial/picoem and are recorded
#   here as a patch, which keeps this repository self-describing even with no
#   fork and no network.
set -eu

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"

SRC="${PICOEM_SRC:-}"
BUILD=0
TEST=0
for arg in "$@"; do
    case "$arg" in
        --build) BUILD=1 ;;
        --test)  TEST=1; BUILD=1 ;;
        -*) echo "apply.sh: unknown option $arg" >&2; exit 1 ;;
        *) SRC="$arg" ;;
    esac
done
[ -n "$SRC" ] || SRC="./picoem"

[ -d "$SRC" ] || { echo "apply.sh: no such directory: $SRC" >&2; exit 1; }
[ -f "$SRC/crates/rp2350-emu/src/core/coprocessor.rs" ] || {
    echo "apply.sh: $SRC does not look like a picoem checkout" >&2; exit 1; }

PATCH="$HERE/rp2350-correctness.patch"
[ -f "$PATCH" ] || { echo "apply.sh: no patch at $PATCH" >&2; exit 1; }

# Already applied?  The series' first hunk adds the Cp0Reg enum; if it is there,
# say so and stop rather than failing on a reverse-check.
if grep -q 'enum Cp0Reg' "$SRC/crates/rp2350-emu/src/core/coprocessor.rs" 2>/dev/null; then
    echo "apply.sh: the series is already applied to $SRC"
else
    echo "apply.sh: applying $(basename "$PATCH") to $SRC"
    if [ -d "$SRC/.git" ]; then
        ( cd "$SRC" && git apply --index "$PATCH" ) || {
            echo "apply.sh: git apply failed -- is the tree at the pinned commit?" >&2
            echo "          REQUIREMENTS.md has the pin; the patch is against 8e20a82." >&2
            exit 1; }
    else
        ( cd "$SRC" && patch -p1 --forward < "$PATCH" ) || {
            echo "apply.sh: patch failed -- is the tree at the pinned commit?" >&2
            exit 1; }
    fi
fi

if [ "$BUILD" = 1 ]; then
    echo "apply.sh: cargo build"
    ( cd "$SRC" && cargo build --release )
fi

if [ "$TEST" = 1 ]; then
    echo "apply.sh: cargo test -p rp2350-emu"
    ( cd "$SRC" && cargo test -p rp2350-emu )
fi

echo "apply.sh: done.  The acceptance for the *bridge* is"
echo "  $REPO/tools/emulator-setup/mame-osborne1nx/picoem-check.sh"
