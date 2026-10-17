#!/bin/sh
# bootscreen-check.sh -- ROM 2.0's boot screen, drawn in the machine (#247 step 8,
# turn 4).
#
# WHY THIS EXISTS
#   The rest of step 8's harnesses check a door: `romservice-check.sh` drives the
#   transaction and reads page 1, `softrom-check.sh` reads the window.  None of them
#   can say the screen is *drawn*, because drawing it is three things in a row that
#   no one of them owns -- the monitor's sign-on stub asks for the screen's code
#   with PRESENT(3), copies window page 1 to RAM at 4000h and jumps into it, and the
#   code blits the frame into the two video planes (docs/o1-rom-2.0.md 4.7).
#
#   So this is the acceptance that reads the *result*: ROM 2.0's monitor in the
#   window, both flash assets mounted, and the two planes read back off the machine
#   and compared against `frame.bin` -- the character plane byte for byte, the
#   attribute plane bit 7 (which is all the array holds).
#
#   And it is run twice, because one run cannot tell "the code drew it" from "it
#   happened to be there": with no splash mounted the stub takes its fallback, prints
#   the stock sign-on, and the frame must **not** be on the screen.
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
# The frame is **derived from the animation**, not committed (#247's W5): `frame.bin`
# was retired on 2026-10-16, and the frame the ROM is served is the one the animation
# *rests* on.  tools/research/bootanim.py is what says the asset is valid and takes
# that frame out of it.
ANIM="$REPO/firmware/rom-service/boot-animation.bin"
FRAME="$WORK/frame.bin"
SPLASH="$REPO/firmware/rom-service/screen.bin"
LUA="$HERE/o1next-bootscreen.lua"

[ -d "$ROMPATH" ] || { echo "bootscreen-check.sh: no such ROM path: $ROMPATH" >&2; exit 1; }
FRAME_OK=0
if [ -f "$ANIM" ] && python3 "$REPO/tools/research/bootanim.py" --check "$ANIM" \
        && python3 "$REPO/tools/research/bootanim.py" --resting -o "$FRAME"; then
    FRAME_OK=1
else
    echo "bootscreen-check.sh: no valid animation at $ANIM" >&2
    echo "  the frame's own two runs need it; the fallback run below does not." >&2
fi
[ -f "$SPLASH" ] || { echo "bootscreen-check.sh: no boot splash at $SPLASH" >&2; exit 1; }
[ -f "$LUA" ] || { echo "bootscreen-check.sh: no harness at $LUA" >&2; exit 1; }

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
if [ "$FRAME_OK" = 1 ]; then
    echo "  frame:   $FRAME ($(wc -c < "$FRAME" | tr -d ' ') bytes, the animation's resting frame)"
else
    echo "  frame:   <none -- no valid animation at $ANIM>"
fi
echo "  splash:  $SPLASH ($(wc -c < "$SPLASH" | tr -d ' ') bytes)"
echo

FAIL=0
verdict() {  # verdict LABEL RESULT
    if [ "$2" = 0 ]; then echo "  PASS  $1"; else echo "  FAIL  $1"; FAIL=1; fi
}

if [ "$FRAME_OK" = 1 ]; then

# --- the splash: the stub asks, the code runs, the screen is drawn ----------
echo "== the splash: the frame on the character plane and on the attribute plane"
O1_FRAME="$FRAME" O1_BOOTSPLASH="$SPLASH" O1_EXPECT=splash \
SDL_VIDEODRIVER=dummy "$MAME" "$MACHINE" -softrom "$WORK/rom2.rom" \
    -frame "$FRAME" -bootsplash "$SPLASH" \
    -video none -sound none -nothrottle -rompath "$ROMPATH" \
    -autoboot_script "$LUA" -seconds_to_run 30 > "$WORK/screen-splash.log" 2>&1 || true
grep -E '^  (PASS|FAIL)|^SCREEN:|^  \||^the frame' "$WORK/screen-splash.log" | sed 's/^/  /'
if grep -q '^SCREEN: PASS' "$WORK/screen-splash.log"; then
    verdict "the boot screen is on the machine -- monitor, stub, PRESENT(3), the code" 0
else
    verdict "the boot screen is on the machine -- monitor, stub, PRESENT(3), the code" 1
fi
echo

# --- and without it, so the frame in the planes is the code's doing ----------
echo "== no splash: the stub's fallback, and the frame is *not* on the screen"
O1_FRAME="$FRAME" O1_EXPECT=stock \
SDL_VIDEODRIVER=dummy "$MAME" "$MACHINE" -softrom "$WORK/rom2.rom" \
    -frame "$FRAME" \
    -video none -sound none -nothrottle -rompath "$ROMPATH" \
    -autoboot_script "$LUA" -seconds_to_run 30 > "$WORK/screen-stock.log" 2>&1 || true
grep -E '^  (PASS|FAIL)|^SCREEN:|^  \|' "$WORK/screen-stock.log" | sed 's/^/  /'
if grep -q '^SCREEN: PASS' "$WORK/screen-stock.log"; then
    verdict "with no splash the frame is not drawn, so the frame above is the code's" 0
else
    verdict "with no splash the frame is not drawn, so the frame above is the code's" 1
fi
echo

else
    verdict "the frame's own two runs (no boot frame mounted -- the asset is retired)" 1
    echo
fi

# --- the splash and NO frame: the screen code's own fallback (#247's W3) -----
# This is the run that needs no frame asset, so it works while the frame's is
# retired: the code runs, PRESENT(1) has nothing to answer with, and the fallback
# it has already printed is what stays on the screen.
echo "== the fallback: the screen's own two lines, and its bright/dim runs"
O1_BOOTSPLASH="$SPLASH" O1_EXPECT=fallback \
SDL_VIDEODRIVER=dummy "$MAME" "$MACHINE" -softrom "$WORK/rom2.rom" \
    -bootsplash "$SPLASH" \
    -video none -sound none -nothrottle -rompath "$ROMPATH" \
    -autoboot_script "$LUA" -seconds_to_run 30 > "$WORK/screen-fallback.log" 2>&1 || true
grep -E '^  (PASS|FAIL)|^SCREEN:|^  \|' "$WORK/screen-fallback.log" | sed 's/^/  /'
if grep -q '^SCREEN: PASS' "$WORK/screen-fallback.log"; then
    verdict "the fallback is the screen's own two lines, at its own rows and runs" 0
else
    verdict "the fallback is the screen's own two lines, at its own rows and runs" 1
fi
echo

if [ "$FAIL" = 0 ]; then
    echo "bootscreen-check.sh: all checks passed"
else
    echo "bootscreen-check.sh: FAILED -- see the logs in $WORK" >&2
fi
exit "$FAIL"
