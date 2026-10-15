#!/bin/sh
# softrom-check.sh -- the softROM window's two-way acceptance (#247).
#
# WHY THIS EXISTS
#   Step 1 of #247 is the banked-ROM device: the interposer serves the whole
#   8 KB ROM window (0000-1FFF) from an image file, and with no image mounted it
#   serves the machine's own 1.44 -- so an image-less machine is a stock machine
#   (docs/o1-rom-2.0.md section 4.1b).  Two things have to be true, and only one
#   of them can be seen from a boot:
#
#     1. **The window really is the device's.**  Page 1 (1000-1FFF) has to be the
#        payload, and a boot comparison cannot tell you that: the stock monitor
#        never reads page 1, so a softROM that failed to take over the page would
#        boot identically and silently.  o1next-softrom.lua reads the window back
#        and compares all 8192 bytes against what the device says it should be.
#
#     2. **The boot is identical.**  With no image mounted the machine must boot
#        identically to `osborne1`, and with rom2image.py's 7681-byte image
#        mounted it must boot identically *too* -- because that image's monitor is
#        still the stock 1.44.  That second one is the pass/fail that proves the
#        plumbing before any monitor code exists.
#
#   Both halves are one command, and it exits non-zero if either fails.
#
# USAGE
#   tools/emulator-setup/mame-osborne1nx/softrom-check.sh
#
# ENVIRONMENT
#   O1_MAME     the patched `osborne1nx` binary.  Default: beside this script
#               (a staged machine), then the usual build trees.  `mame` on PATH
#               has no such machine -- it is a patch, see README.md.
#   O1_ROMPATH  ROM path (default the repo's tools/emulator-setup/roms)
#   O1_WORK     scratch directory (default /tmp/o1next-softrom-check).  MAME
#               writes cfg/ and snap/ into the current directory and writes back
#               into a floppy image in place, so the floppy is copied here first.
set -eu

HERE="$(cd "$(dirname "$0")" && pwd)"
MACHINE=osborne1nx
REPO="$(cd "$HERE/../../.." && pwd)"

[ -f "$REPO/AGENTS.md" ] || {
    echo "softrom-check.sh: this script belongs in the repo (tools/emulator-setup/mame-osborne1nx/)" >&2
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
if [ -z "$MAME" ]; then
    echo "softrom-check.sh: no $MACHINE binary." >&2
    echo "  The 'mame' on PATH has no such machine -- it is a patch." >&2
    echo "  Build one with tools/emulator-setup/mame-osborne1nx/apply.sh, or set O1_MAME." >&2
    exit 1
fi

ROMPATH="${O1_ROMPATH:-$REPO/tools/emulator-setup/roms}"
WORK="${O1_WORK:-/tmp/o1next-softrom-check}"
MONITOR="$REPO/research/roms/os1-144.rom"
FLOPPY="$REPO/tools/emulator-setup/floppies/52-blank.imd"
WINDOW_LUA="$HERE/o1next-softrom.lua"
BOOT_LUA="$REPO/tools/research/mame-boot-probe.lua"

[ -x "$MAME" ] || { echo "softrom-check.sh: not executable: $MAME" >&2; exit 1; }
[ -d "$ROMPATH" ] || { echo "softrom-check.sh: no such ROM path: $ROMPATH" >&2; exit 1; }
[ -f "$MONITOR" ] || { echo "softrom-check.sh: no stock monitor at $MONITOR" >&2; exit 1; }
[ -f "$FLOPPY" ] || { echo "softrom-check.sh: no boot disk at $FLOPPY" >&2; exit 1; }

mkdir -p "$WORK"
cd "$WORK"

echo "osborne1nx softROM window -- the two-way acceptance (#247)"
echo "  binary:  $MAME"
echo "  rompath: $ROMPATH"
echo "  work:    $WORK"
echo

# rom2image.py's image: 4096 monitor + 3585 payload = 7681 of the 8192-byte
# window, and its monitor is still the stock 1.44 (docs/o1-rom-2.0.md 2.3).
"$REPO/tools/research/rom2image.py" -o "$WORK/rom2.rom" > "$WORK/rom2image.log" 2>&1
echo "image: $(wc -c < "$WORK/rom2.rom" | tr -d ' ') bytes, from rom2image.py ($WORK/rom2image.log)"
echo

# MAME writes back into a floppy image as it runs, so it gets a copy.
cp "$FLOPPY" "$WORK/boot.imd"

FAIL=0
verdict() {  # verdict LABEL RESULT
    if [ "$2" = 0 ]; then echo "  PASS  $1"; else echo "  FAIL  $1"; FAIL=1; fi
}


# --- 1. the window, three ways ----------------------------------------------
# `-softrom` is this device's own machine option, named after its tag.
window() {   # window LABEL LOG [IMAGE]
    label="$1"; log="$2"; image="${3:-}"
    if [ -n "$image" ]; then
        O1_SOFTROM_MONITOR="$MONITOR" O1_SOFTROM_IMAGE="$image" \
        SDL_VIDEODRIVER=dummy "$MAME" "$MACHINE" -softrom "$image" \
            -video none -sound none -nothrottle -rompath "$ROMPATH" \
            -autoboot_script "$WINDOW_LUA" -seconds_to_run 2 > "$log" 2>&1 || true
    else
        O1_SOFTROM_MONITOR="$MONITOR" \
        SDL_VIDEODRIVER=dummy "$MAME" "$MACHINE" \
            -video none -sound none -nothrottle -rompath "$ROMPATH" \
            -autoboot_script "$WINDOW_LUA" -seconds_to_run 2 > "$log" 2>&1 || true
    fi
    echo "== window: $label"
    grep -E '^  page 0|^  page 1|^SOFTROM:' "$log" | sed 's/^/  /'
    if grep -q '^SOFTROM: PASS' "$log"; then verdict "window: $label" 0; else verdict "window: $label" 1; fi
    echo
}

window "no image -- the monitor, mirrored"           "$WORK/window-none.log"
window "a 4 KB image -- the stock part, mirrored"    "$WORK/window-4k.log"   "$MONITOR"
window "the 7681-byte image -- two pages"            "$WORK/window-rom2.log" "$WORK/rom2.rom"

# --- 2. the boot, three ways ------------------------------------------------
# The stock machine is in the same binary, so all three runs are comparable
# byte for byte; the MACHINE line is the only thing that differs.
boot() {     # boot LABEL LOG [IMAGE]
    label="$1"; log="$2"; image="${3:-}"
    if [ -n "$image" ]; then
        O1_MACHINE="$MACHINE" O1_IMAGE="$image" \
        SDL_VIDEODRIVER=dummy "$MAME" "$MACHINE" -flop1 "$WORK/boot.imd" -softrom "$image" \
            -video none -sound none -nothrottle -rompath "$ROMPATH" \
            -autoboot_script "$BOOT_LUA" -seconds_to_run 120 > "$log" 2>&1 || true
    else
        O1_MACHINE="$MACHINE" O1_IMAGE="<none>" \
        SDL_VIDEODRIVER=dummy "$MAME" "$MACHINE" -flop1 "$WORK/boot.imd" \
            -video none -sound none -nothrottle -rompath "$ROMPATH" \
            -autoboot_script "$BOOT_LUA" -seconds_to_run 120 > "$log" 2>&1 || true
    fi
    echo "== boot: $label -- $(grep -E '^BANNER|^PROMPT|^RESULT' "$log" | tr '\n' ' ')"
}

boot "osborne1 (the stock machine)"        "$WORK/boot-stock.log"
boot "osborne1nx, no image"                "$WORK/boot-none.log"
boot "osborne1nx -softrom rom2.rom"        "$WORK/boot-rom2.log" "$WORK/rom2.rom"

echo
# `grep -v '^MACHINE'` drops the machine name and the image path -- the runs are
# otherwise expected to be identical, screen dump included.  (Plain `sh`: the
# comparisons go through files, not process substitution.)
grep -v '^MACHINE' "$WORK/boot-stock.log" > "$WORK/boot-stock.txt"
for pair in "boot-none.log:no image" "boot-rom2.log:the 7681-byte image"; do
    log="${pair%%:*}"; label="${pair#*:}"
    grep -v '^MACHINE' "$WORK/$log" > "$WORK/$log.txt"
    if diff "$WORK/boot-stock.txt" "$WORK/$log.txt" > "$WORK/$log.diff" 2>&1; then
        verdict "boot: osborne1nx with $label is identical to osborne1" 0
    else
        verdict "boot: osborne1nx with $label is identical to osborne1" 1
        sed 's/^/        /' "$WORK/$log.diff" | head -20
    fi
done

echo
if [ "$FAIL" = 0 ]; then
    echo "softrom-check.sh: all checks passed"
else
    echo "softrom-check.sh: FAILED -- see the logs in $WORK" >&2
fi
exit "$FAIL"
