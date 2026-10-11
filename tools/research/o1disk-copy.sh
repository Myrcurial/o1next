#!/bin/sh
# o1disk-copy.sh MACHINE FLOP1 FLOP2 "CP/M COMMAND" [SECONDS] [SHOT.png]
#
# Boot FLOP1 in drive A and FLOP2 in drive B on one of MAME's Osborne 1
# machines, press RETURN at the BIOS prompt, wait for A>, type the command (e.g.
# "PIP B:=A:MBASIC.COM"), and report the screen before and after. MAME writes
# the result back into FLOP1/FLOP2 in place, so the caller should pass *copies*
# of the images it wants to inspect afterwards. See o1disk-copy.lua for why.
#
# Environment:
#   O1_ROMPATH  ROM path (default tools/emulator-setup/roms). Loose files are
#               handled by a temporary 'osborne1' symlink, as in mame-boot-probe.
#   O1_BIOS     optional MAME BIOS slot (e.g. ver14 / ver143 / ver144)
#   O1_RUNDIR   working directory MAME runs in (default /tmp)
#
# Written for #95 -- see docs/dd-upgrade-formats.md.
set -eu

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
MACHINE="${1:?usage: o1disk-copy.sh MACHINE FLOP1 FLOP2 \"CMD\" [SECONDS] [SHOT]}"
FLOP1="${2:?usage: o1disk-copy.sh MACHINE FLOP1 FLOP2 \"CMD\" [SECONDS] [SHOT]}"
FLOP2="${3:?usage: o1disk-copy.sh MACHINE FLOP1 FLOP2 \"CMD\" [SECONDS] [SHOT]}"
CMD="${4:?usage: o1disk-copy.sh MACHINE FLOP1 FLOP2 \"CMD\" [SECONDS] [SHOT]}"
BUDGET="${5:-150}"
SHOT="${6:-}"
ROMPATH="${O1_ROMPATH:-$REPO/tools/emulator-setup/roms}"
BIOS="${O1_BIOS:-}"

for f in "$FLOP1" "$FLOP2"; do
    [ -f "$f" ] || { echo "o1disk-copy.sh: no such image: $f" >&2; exit 1; }
done
FLOP1="$(cd "$(dirname "$FLOP1")" && pwd)/$(basename "$FLOP1")"
FLOP2="$(cd "$(dirname "$FLOP2")" && pwd)/$(basename "$FLOP2")"
[ -d "$ROMPATH" ] || { echo "o1disk-copy.sh: no such ROM path: $ROMPATH" >&2; exit 1; }
command -v mame >/dev/null || { echo "mame not found (brew install mame)" >&2; exit 1; }

LINKROOT=""
if [ ! -e "$ROMPATH/osborne1.zip" ] && [ ! -d "$ROMPATH/osborne1" ]; then
    LINKROOT="${TMPDIR:-/tmp}/o1roms.$$"
    mkdir -p "$LINKROOT"
    ln -s "$ROMPATH" "$LINKROOT/osborne1"
    echo "note: ROMs are loose in $ROMPATH; using $LINKROOT/osborne1" >&2
    ROMPATH="$LINKROOT"
fi

RUN_LUA="${TMPDIR:-/tmp}/o1diskcopy.$$.lua"
trap 'rm -f "$RUN_LUA"; [ -n "$LINKROOT" ] && rm -rf "$LINKROOT"' EXIT
cat "$HERE/o1disk-copy.lua" > "$RUN_LUA"

cd "${O1_RUNDIR:-/tmp}"

# shellcheck disable=SC2086
O1_MACHINE="$MACHINE" O1_FLOP1="$FLOP1" O1_FLOP2="$FLOP2" O1_CMD="$CMD" \
O1_SHOT="$SHOT" SDL_VIDEODRIVER=dummy \
mame "$MACHINE" ${BIOS:+-bios "$BIOS"} -flop1 "$FLOP1" -flop2 "$FLOP2" \
    -video none -sound none -nothrottle -autoboot_script "$RUN_LUA" \
    -seconds_to_run "$BUDGET" -rompath "$ROMPATH"
