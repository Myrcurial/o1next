#!/bin/sh
# rom2-check.sh -- what ROM 2.0's HCBOOT does, measured in the machine (#247).
#
# WHY THIS EXISTS
#   rom2asm.sh proves the *assembly* is the vendor's 1.44 with new code only where
#   the guard left room.  This proves the new code *runs*: it boots the emulated
#   interposer with ROM 2.0's image in the softROM window, presses RETURN at the
#   sign-on prompt -- the monitor's HCBOOT entry, since #247 step 4 -- and reads
#   the chain back with rom2boot.lua (the CBIOS in RAM, the MD-10 BIOS in RAM, its
#   vectors patched from the CBIOS's, the bank switch, the sign-on dispatch's own
#   key bytes, the hand-over's stub and the store it makes, and -- with a drive --
#   the prompt the whole thing exists for).
#
# USAGE
#   tools/emulator-setup/mame-osborne1nx/rom2-check.sh
#
# ENVIRONMENT
#   O1_MAME         the patched `osborne1nx` binary (default: the usual trees)
#   O1_ROM2_MONITOR a ROM 2.0 monitor image to use.  Unset means build one with
#                   tools/research/rom2asm.sh first -- which takes a few minutes,
#                   because the assembly runs on an emulated Osborne 1.
#   O1_HARD         a CHD to mount, to check the boot as well as the chain: the
#                   system is read off the drive and the machine has to reach
#                   A0>.  Without it there is nothing to boot from, so the
#                   prompt is reported and not failed.
#   O1_BSH          a CP/M block shift to patch HARD.COM's DPB to before the
#                   image is built -- 5 is the shipped 4 KiB, 6 is 8 KiB.  This
#                   is the check that a non-shipped block size still boots: the
#                   DPB is rewritten with tools/research/md10dpb.py and fed to
#                   rom2image.py with --hard, and *everything else* -- the
#                   drive, the partition table, the BIOS -- is unchanged.
#   O1_PARTS        the partition sizes to patch in (default 15399,15399,15399,
#                   the shipped layout); only meaningful with O1_BSH.
#   O1_UTILS        the 2.01 utilities image HARD.COM comes off (default the
#                   repo's copy under research/adaptec/)
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
UTILS="${O1_UTILS:-$REPO/research/adaptec/Osborne Hard Disk Control Software Version 2.01 (1984).img}"
if [ -n "${O1_BSH:-}" ]; then
    PARTS="${O1_PARTS:-15399,15399,15399}"
    echo "  block size: BSH=$O1_BSH, partitions $PARTS -- patching the DPB first"
    python3 "$REPO/tools/research/md10dpb.py" --utils "$UTILS" \
        --extract "$WORK/HARD.COM" > "$WORK/md10dpb.log" 2>&1
    python3 "$REPO/tools/research/md10dpb.py" "$WORK/HARD.COM" \
        "$WORK/HARD-bsh$O1_BSH.com" --parts "$PARTS" --bsh "$O1_BSH" \
        >> "$WORK/md10dpb.log" 2>&1 || {
        echo "rom2-check.sh: the DPB patch failed -- see $WORK/md10dpb.log" >&2
        exit 1; }
    grep -E '^  DPB at|^  CP/M sees|^  ALV ' "$WORK/md10dpb.log" | sed 's/^/  /'
    python3 "$REPO/tools/research/rom2image.py" --monitor "$MONITOR" \
        --hard "$WORK/HARD-bsh$O1_BSH.com" \
        -o "$WORK/rom2.rom" --work "$WORK/rom2image" > "$WORK/rom2image.log" 2>&1
else
    python3 "$REPO/tools/research/rom2image.py" --monitor "$MONITOR" \
        -o "$WORK/rom2.rom" --work "$WORK/rom2image" > "$WORK/rom2image.log" 2>&1
fi
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

# The harness's status is the *chain*, and -- when a drive is mounted -- the
# prompt: the CBIOS, the MD-10 BIOS, the patch, the bank switch, the hand-over's
# store, the read off the drive, and then A0>, which is what the ROM is for.
# Without a drive there is no system to read, so the prompt is reported rather
# than failed; O1_HARD is what makes the boot itself part of the acceptance.
exit "$STATUS"
