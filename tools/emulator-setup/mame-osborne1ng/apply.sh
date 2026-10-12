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
# A source build on macOS wants SDL3 (the OSD defaults to sdl3 there); OSD=mac
# uses the tree's own Cocoa layer instead, so nothing has to be installed.
OSD_OPT=""
case "$(uname -s)" in
    Darwin) OSD_OPT="OSD=mac" ;;
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
    ( cd /tmp && O1NG_LOG=/tmp/o1ng.log "$BIN" "$SUBTARGET" \
        -rompath "$REPO/tools/emulator-setup/roms" \
        -video none -sound none -nothrottle \
        -autoboot_script "$HERE/o1ng-probe.lua" -seconds_to_run 6 )
fi

echo "==> done"
