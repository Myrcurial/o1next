#!/bin/sh
# bootscreen-check.sh -- ROM 2.0's boot screen, drawn in the machine (#247 step 8;
# rewritten for #278, 2026-10-17).
#
# WHY THIS EXISTS
#   The rest of step 8's harnesses check a door: `romservice-check.sh` drives the
#   transaction and reads page 1, `softrom-check.sh` reads the window.  None of them
#   can say the screen is *drawn*, because drawing it is the monitor's own code --
#   fill the attribute array bright, print the fallback, return.
#
#   So this is the acceptance that reads the *result*: ROM 2.0's monitor in the
#   window, nothing mounted beside it, and the two video planes read back off the
#   machine and compared against the animation's own two lines and its own
#   bright/dim runs.
#
#   That comparison is the whole point.  The fallback *is* the trigger the RP2354B
#   watches for -- it plays the animation and stops on the Z80's first video-RAM
#   write -- so this is the one thing the frame path's retirement must not disturb
#   (#278; docs/rom-pico-protocol.md 5.1, docs/o1-rom-2.0.md 4.9).
#
#   And there is nothing left to mount: the `-frame` and `-bootsplash` slots went
#   with the frame path, and the screen's code is 26 bytes in the monitor's own
#   tail.  So the run is the machine, the monitor, and the two planes.
#
# USAGE
#   tools/emulator-setup/mame-osborne1nx/bootscreen-check.sh
#
# ENVIRONMENT
#   O1_MAME         the patched `osborne1nx` binary (default: the usual trees)
#   O1_ROM2_MONITOR a ROM 2.0 monitor image to use.  Unset means build one with
#                   tools/research/rom2asm.sh first -- which takes a few minutes,
#                   because the assembly runs on an emulated Osborne 1.
#   O1_ROMPATH      ROM path (default the repo's tools/emulator-setup/roms)
#   O1_WORK         scratch directory (default /tmp/o1next-bootscreen-check)
set -eu

HERE="$(cd "$(dirname "$0")" && pwd)"
MACHINE=osborne1nx
REPO="$(cd "$HERE/../../.." && pwd)"

[ -f "$REPO/AGENTS.md" ] || {
    echo "bootscreen-check.sh: this script belongs in the repo (tools/emulator-setup/mame-osborne1nx/)" >&2
    exit 1; }

MAME="${O1_MAME:-}"
if [ -z "$MAME" ] && [ -x "$HERE/mame/$MACHINE" ]; then MAME="$HERE/mame/$MACHINE"; fi
if [ -z "$MAME" ]; then
    for cand in "$HOME/scratch/mame-verify/mame-mame0289/$MACHINE" \
                "$HOME/scratch/mame-mame0289/$MACHINE" \
                "$HOME/scratch/mame-clean/mame-mame0289/$MACHINE"; do
        if [ -x "$cand" ]; then MAME="$cand"; break; fi
    done
fi
[ -n "$MAME" ] || {
    echo "bootscreen-check.sh: no $MACHINE binary -- build one with apply.sh, or set O1_MAME" >&2
    exit 1; }
[ -x "$MAME" ] || { echo "bootscreen-check.sh: not executable: $MAME" >&2; exit 1; }

ROMPATH="${O1_ROMPATH:-$REPO/tools/emulator-setup/roms}"
WORK="${O1_WORK:-/tmp/o1next-bootscreen-check}"
LUA="$HERE/o1next-bootscreen.lua"

[ -d "$ROMPATH" ] || { echo "bootscreen-check.sh: no such ROM path: $ROMPATH" >&2; exit 1; }
[ -f "$LUA" ] || { echo "bootscreen-check.sh: no harness at $LUA" >&2; exit 1; }

# The scratch directory first: the monitor build below writes into it, and MAME
# writes its cfg/ and snap/ into the current directory.
mkdir -p "$WORK"
cd "$WORK"

# The monitor: given, or built here (which is the slow part, so it is said).
MONITOR="${O1_ROM2_MONITOR:-}"
if [ -z "$MONITOR" ]; then
    echo "== no O1_ROM2_MONITOR; assembling ROM 2.0's monitor (a few minutes) =="
    MONITOR="$WORK/rom2-monitor.rom"
    "$REPO/tools/research/rom2asm.sh" -o "$MONITOR" "$WORK/rom2asm"
fi
[ -f "$MONITOR" ] || { echo "bootscreen-check.sh: no such monitor: $MONITOR" >&2; exit 1; }

echo "== the image: the monitor plus rom2image.py's payload =="
python3 "$REPO/tools/research/rom2image.py" --monitor "$MONITOR" \
    -o "$WORK/rom2.rom" --work "$WORK/rom2image" > "$WORK/rom2image.log" 2>&1
grep -E '^  ok  monitor|^wrote' "$WORK/rom2image.log"

echo "== the machine =="
echo "  binary:  $MAME"
echo "  monitor: $MONITOR"
echo "  assets:  none -- there are none to mount any more (#278)"
echo

FAIL=0
verdict() {  # verdict LABEL RESULT
    if [ "$2" = 0 ]; then echo "  PASS  $1"; else echo "  FAIL  $1"; FAIL=1; fi
}

# --- the screen: the fallback, read back off the two planes ------------------
echo "== the screen: the fallback on the character plane, its dim runs on the other"
SDL_VIDEODRIVER=dummy "$MAME" "$MACHINE" -softrom "$WORK/rom2.rom" \
    -video none -sound none -nothrottle -rompath "$ROMPATH" \
    -autoboot_script "$LUA" -seconds_to_run 30 > "$WORK/screen.log" 2>&1 || true
grep -E '^  (PASS|FAIL)|^SCREEN:|^  \|' "$WORK/screen.log" | sed 's/^/  /'
if grep -q '^SCREEN: PASS' "$WORK/screen.log"; then
    verdict "the fallback is the screen's own two lines, at its own rows and runs" 0
else
    verdict "the fallback is the screen's own two lines, at its own rows and runs" 1
fi
echo

if [ "$FAIL" = 0 ]; then
    echo "bootscreen-check.sh: all checks passed"
else
    echo "bootscreen-check.sh: FAILED -- see the log in $WORK" >&2
fi
exit "$FAIL"
