#!/bin/sh
# apply.sh -- put the osborne1ng machine into a stock MAME source tree.
#
#   tools/emulator-setup/mame-osborne1ng/apply.sh [MAME_SRC] [--build] [--probe]
#
# MAME_SRC defaults to $MAME_SRC, then to ./mame.  It must be a *source* tree
# (a checkout or an unpacked release tarball), not a brew install: the patch
# adds a device and a machine, so the tree has to be rebuilt.
#
# What it does, in order:
#   1. patch -p1 the five files in osborne1ng.patch
#   2. with --build, make the osborne subtarget
#   3. with --probe, run the headless decode/presence check
#
# Nothing here is exotic: GNU make and a C++20 compiler (Xcode CLT) are all the
# tree needs.  See README.md for the macOS OSD note -- a source build wants SDL3
# by default and OSD=mac avoids that.
set -eu

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"

SRC="${MAME_SRC:-}"
BUILD=0
PROBE=0
for arg in "$@"; do
    case "$arg" in
        --build) BUILD=1 ;;
        --probe) PROBE=1 ;;
        -*) echo "apply.sh: unknown option $arg" >&2; exit 1 ;;
        *) SRC="$arg" ;;
    esac
done
[ -n "$SRC" ] || SRC="./mame"

[ -f "$SRC/src/mame/osborne/osborne1.cpp" ] || {
    echo "apply.sh: $SRC does not look like a MAME source tree" >&2; exit 1; }

PATCH="$HERE/osborne1ng.patch"
SUBTARGET=osborne1ng
# The OSD is left at the tree's default.  On macOS that is sdl3, which is what
# the repo's documented headless recipe expects (SDL_VIDEODRIVER=dummy plus
# -video none -sound none; docs/mame-emulation.md section 6).  MAME finds SDL
# through pkg-config, so without pkg-config the build cannot find <SDL3/SDL.h>
# and the only way left is the mac OSD -- which creates a window whatever
# -video says, and takes the whole display unless -window is passed.  That is a
# fallback, not a second way of doing this: REQUIREMENTS.md lists pkg-config.
OSD_OPT=""
case "$(uname -s)" in
    Darwin)
        if ! command -v pkg-config >/dev/null 2>&1 && ! command -v pkgconf >/dev/null 2>&1; then
            echo "apply.sh: no pkg-config, so MAME cannot find sdl3 (REQUIREMENTS.md);" >&2
            echo "          falling back to OSD=mac, which needs -window to stay" >&2
            echo "          off the display (docs/mame-emulation.md section 6)" >&2
            OSD_OPT="OSD=mac"
        fi
        ;;
esac

if [ -e "$SRC/src/devices/machine/acb4000_host_adapter.cpp" ]; then
    # patch --forward would skip the hunks and scatter .rej files about; a tree
    # that already has the device is a tree that is already patched.
    echo "==> $SRC already has the osborne1ng machine; not patching again"
else
    echo "==> patching $SRC"
    (cd "$SRC" && patch -p1 --forward < "$PATCH")
fi

if [ "$BUILD" = 1 ]; then
    echo "==> building the osborne subtarget (this takes a while)"
    (cd "$SRC" && make -j"$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)" \
        $OSD_OPT SOURCES=src/mame/osborne SUBTARGET="$SUBTARGET" NOWERROR=1)
fi

if [ "$PROBE" = 1 ]; then
    BIN="$SRC/$SUBTARGET"
    [ -x "$BIN" ] || { echo "apply.sh: no $BIN -- run with --build first" >&2; exit 1; }
    echo "==> probing the decode and the card"
    # SDL_VIDEODRIVER=dummy is what makes an SDL build headless
    # (docs/mame-emulation.md section 6); -window is what makes the mac OSD
    # stop taking the display, and is harmless to an SDL build.
    ( cd /tmp && SDL_VIDEODRIVER=dummy O1NG_LOG=/tmp/o1ng.log "$BIN" "$SUBTARGET" \
        -rompath "$REPO/tools/emulator-setup/roms" \
        -video none -sound none -window -nothrottle \
        -autoboot_script "$HERE/o1ng-probe.lua" -seconds_to_run 6 )
fi

echo "==> done"
