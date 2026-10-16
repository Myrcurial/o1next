#!/bin/sh
# o1keys.sh MACHINE FLOP1 [FLOP2] [SECONDS]
#
# Boot FLOP1 (and put FLOP2 in drive B), press RETURN at the BIOS prompt, then
# drive the guest with the scripted keystrokes in O1_KEYS. MAME writes back into
# FLOP1/FLOP2 in place, so pass *copies* of any image you want to inspect
# afterwards. See o1keys.lua for the directive language and why.
#
# Environment:
#   O1_KEYS     the keystroke script (required), see o1keys.lua
#   O1_WAIT     seconds to wait for a `wait` pattern (default 30)
#   O1_ROMPATH  ROM path (default tools/emulator-setup/roms). Must be absolute:
#               MAME is run from a neutral directory.
#   O1_BIOS     optional MAME BIOS slot (e.g. ver144)
#   O1_RUNDIR   working directory MAME runs in (default /tmp)
#   O1_MAME_EXTRA  MAME's own arguments, *replacing* the default `-nothrottle`.
#               Set it to "" to run at the machine's real speed: a guest that
#               prints a 4700-line listing scrolls the answer past in under a
#               second of wall time, so a diagnostic run wants throttling and a
#               slow `dump` cadence (#247 step 8, turn 3).
#
# Written for #178 -- see docs/harddisk-decision.md 7.2.
set -eu

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
MACHINE="${1:?usage: o1keys.sh MACHINE FLOP1 [FLOP2] [SECONDS]}"
FLOP1="${2:?usage: o1keys.sh MACHINE FLOP1 [FLOP2] [SECONDS]}"
FLOP2="${3:-}"
BUDGET="${4:-300}"
ROMPATH="${O1_ROMPATH:-$REPO/tools/emulator-setup/roms}"
BIOS="${O1_BIOS:-}"
# Validated, not stored: O1_KEYS is already in the environment and is inherited by
# MAME below, so this line's only job is to fail fast when it is unset.  (Storing
# it in a variable that nothing reads is what SC2034 flags, and it is right.)
: "${O1_KEYS:?set O1_KEYS to a keystroke script (see o1keys.lua)}"

[ -f "$FLOP1" ] || { echo "o1keys.sh: no such image: $FLOP1" >&2; exit 1; }
FLOP1="$(cd "$(dirname "$FLOP1")" && pwd)/$(basename "$FLOP1")"
if [ -n "$FLOP2" ]; then
    [ -f "$FLOP2" ] || { echo "o1keys.sh: no such image: $FLOP2" >&2; exit 1; }
    FLOP2="$(cd "$(dirname "$FLOP2")" && pwd)/$(basename "$FLOP2")"
fi
[ -d "$ROMPATH" ] || { echo "o1keys.sh: no such ROM path: $ROMPATH" >&2; exit 1; }
case "$ROMPATH" in /*) ;; *) echo "o1keys.sh: O1_ROMPATH must be absolute" >&2; exit 1;; esac
command -v mame >/dev/null || { echo "mame not found (brew install mame)" >&2; exit 1; }

LINKROOT=""
if [ ! -e "$ROMPATH/osborne1.zip" ] && [ ! -d "$ROMPATH/osborne1" ]; then
    LINKROOT="${TMPDIR:-/tmp}/o1roms.$$"
    mkdir -p "$LINKROOT"
    ln -s "$ROMPATH" "$LINKROOT/osborne1"
    echo "note: ROMs are loose in $ROMPATH; using $LINKROOT/osborne1" >&2
    ROMPATH="$LINKROOT"
fi

RUN_LUA="${TMPDIR:-/tmp}/o1keys.$$.lua"
RUN_ACB="${TMPDIR:-/tmp}/acb4000.$$.lua"
trap 'rm -f "$RUN_LUA" "$RUN_ACB"; [ -n "$LINKROOT" ] && rm -rf "$LINKROOT"' EXIT
cat "$HERE/o1keys.lua" > "$RUN_LUA"
cp "$HERE/acb4000.lua" "$RUN_ACB"

cd "${O1_RUNDIR:-/tmp}"

# MAME's own arguments.  The default is the `-nothrottle` every existing caller
# has always got; `-` rather than `:-` is deliberate, so an *empty* O1_MAME_EXTRA
# means "no extra arguments" -- i.e. run at the machine's real speed -- instead
# of quietly falling back to the fast one a diagnostic cannot read (#247).
MAME_EXTRA="${O1_MAME_EXTRA--nothrottle}"

# shellcheck disable=SC2086
O1_MACHINE="$MACHINE" O1_FLOP1="$FLOP1" O1_FLOP2="$FLOP2" O1_ACB_LUA="$RUN_ACB" \
SDL_VIDEODRIVER=dummy \
mame "$MACHINE" ${BIOS:+-bios "$BIOS"} -flop1 "$FLOP1" ${FLOP2:+-flop2 "$FLOP2"} \
    -video none -sound none ${MAME_EXTRA} -autoboot_script "$RUN_LUA" \
    -seconds_to_run "$BUDGET" -rompath "$ROMPATH"
