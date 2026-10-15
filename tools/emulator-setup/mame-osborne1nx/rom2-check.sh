#!/bin/sh
# rom2-check.sh -- what ROM 2.0's HCBOOT does, measured in the machine (#247).
#
# WHY THIS EXISTS
#   rom2asm.sh proves the *assembly* is the vendor's 1.44 with new code only where
#   the guard left room.  This proves the new code *runs*: it boots the emulated
#   interposer with ROM 2.0's image in the softROM window, presses ESC at the
#   sign-on prompt -- the monitor's HCBOOT entry -- and reads the chain back with
#   rom2boot.lua (the CBIOS in RAM, the MD-10 BIOS in RAM, its vectors patched
#   from the CBIOS's, the bank switch, and the system read off the drive).
#
# USAGE
#   tools/emulator-setup/mame-osborne1nx/rom2-check.sh
#
# ENVIRONMENT
#   O1_MAME         the patched `osborne1nx` binary (default: the usual trees)
#   O1_ROM2_MONITOR a ROM 2.0 monitor image to use.  Unset means build one with
#                   tools/research/rom2asm.sh first -- which takes a few minutes,
#                   because the assembly runs on an emulated Osborne 1.
#   O1_HARD         a CHD to mount, to also check the read off the drive
#   O1_ROMPATH      ROM path (default the repo's tools/emulator-setup/roms)
#   O1_WORK         scratch directory (default /tmp/o1next-rom2-check)
set -eu

HERE="$(cd "$(dirname "$0")" && pwd)"
MACHINE=osborne1nx
REPO="$(cd "$HERE/../../.." && pwd)"

[ -f "$REPO/AGENTS.md" ] || {
    echo "rom2-check.sh: this script belongs in the repo (tools/emulator-setup/mame-osborne1nx/)" >&2
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
    echo "rom2-check.sh: no $MACHINE binary -- build one with apply.sh, or set O1_MAME" >&2
    exit 1; }
[ -x "$MAME" ] || { echo "rom2-check.sh: not executable: $MAME" >&2; exit 1; }

ROMPATH="${O1_ROMPATH:-$REPO/tools/emulator-setup/roms}"
WORK="${O1_WORK:-/tmp/o1next-rom2-check}"
[ -d "$ROMPATH" ] || { echo "rom2-check.sh: no such ROM path: $ROMPATH" >&2; exit 1; }
mkdir -p "$WORK"
cd "$WORK"

# The monitor: given, or built here (which is the slow part, so it is said).
MONITOR="${O1_ROM2_MONITOR:-}"
if [ -z "$MONITOR" ]; then
    echo "== no O1_ROM2_MONITOR; assembling ROM 2.0's monitor (a few minutes) =="
    MONITOR="$WORK/rom2-monitor.rom"
    "$REPO/tools/research/rom2asm.sh" -o "$MONITOR" "$WORK/rom2asm"
fi
[ -f "$MONITOR" ] || { echo "rom2-check.sh: no such monitor: $MONITOR" >&2; exit 1; }

echo "== the image: the monitor plus rom2image.py's payload =="
python3 "$REPO/tools/research/rom2image.py" --monitor "$MONITOR" \
    -o "$WORK/rom2.rom" --work "$WORK/rom2image" > "$WORK/rom2image.log" 2>&1
grep -E '^  ok  monitor|^wrote' "$WORK/rom2image.log"

# MAME writes back into a CHD as it runs, so the drive is a copy too.
DRIVE=""
if [ -n "${O1_HARD:-}" ]; then
    [ -f "$O1_HARD" ] || { echo "rom2-check.sh: no such hard disk: $O1_HARD" >&2; exit 1; }
    DRIVE="$WORK/hd.chd"
    cp "$O1_HARD" "$DRIVE"
fi

echo "== the machine =="
echo "  binary:  $MAME"
echo "  monitor: $MONITOR"
echo "  drive:   ${DRIVE:-<none -- the chain is checked without one>}"
echo

if [ -n "$DRIVE" ]; then
    O1_ROM2_DRIVE=1 SDL_VIDEODRIVER=dummy "$MAME" "$MACHINE" \
        -softrom "$WORK/rom2.rom" -harddisk "$DRIVE" \
        -video none -sound none -nothrottle -rompath "$ROMPATH" \
        -autoboot_script "$HERE/rom2boot.lua" -seconds_to_run 60
    STATUS=$?
else
    SDL_VIDEODRIVER=dummy "$MAME" "$MACHINE" \
        -softrom "$WORK/rom2.rom" \
        -video none -sound none -nothrottle -rompath "$ROMPATH" \
        -autoboot_script "$HERE/rom2boot.lua" -seconds_to_run 60
    STATUS=$?
fi

# The harness's status is about the *chain* -- the CBIOS, the MD-10 BIOS, the
# patch, the bank switch, the read off the drive.  Whether the machine then
# reaches A0> is reported in its output and is not what this exits on: the chain
# is what the ROM is responsible for.
exit "$STATUS"
