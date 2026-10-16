#!/bin/sh
# romservice-check.sh -- the ROM service's door and page 1's selector (#247).
#
# WHY THIS EXISTS
#   Step 8 of #247 is the boot screen, and its first piece is the interposer's
#   side of it: the ROM asks for the boot frame's halves through a bank-2
#   register pair, and page 1 of the ROM window is the payload *or* one of those
#   halves (docs/rom-pico-protocol.md 4 and 5).  Until now the window served the
#   payload and nothing else, so this checks the whole transaction the ROM's
#   screen code will drive -- and the address it happens at, which is the one
#   thing in that contract this machine can settle.
#
#   Five things have to be true, and only one of them can be seen from a boot:
#
#     1. **The door answers.**  ECHO, INFO, NOP, an unknown opcode, and the
#        abandon-a-pending-reply rule -- the mailbox protocol's transaction
#        (docs/mailbox-protocol.md 3), on a bank-2 register pair.
#     2. **Page 1 is the selector's.**  PRESENT(0) the payload, PRESENT(1) the
#        frame's character half, PRESENT(2) its attribute half, PRESENT(3) the
#        boot splash -- the code the monitor's stub copies to RAM at 4000h and
#        enters -- and each half's own O1NEXT + 16-bit-sum trailer at its own
#        0FF8h, in place, which is what the ROM checks before it blits.
#     3. **A missing asset is a case, not a crash.**  With no frame mounted, or
#        an erased one, or a corrupt one, PRESENT(1) answers 09h and page 1 keeps
#        the payload; with no splash mounted, PRESENT(3) does the same.  The door
#        does *not* validate the frame: that check is the ROM's, and missing,
#        erased and corrupt are one case (docs/rom-pico-protocol.md 6).
#     4. **A wrong-sized asset is refused, loudly.**  A frame is two 4096-byte
#        halves and the splash is one 4096-byte page, so each slot refuses
#        anything else rather than serving half of it as if it were whole.
#     5. **The address.**  The protocol proposed 2300h/2301h; this machine says
#        no, and says why: the onboard selects check two address bits, so 0x2301
#        is the floppy's track register as well as the keyboard's row 0
#        (docs/o1-mainboard-schematic.md 7a), and a reply ANDed with a track
#        register reading 0x00 is "not ready" for ever.  The door lives at
#        2800h, the part of o1-memory-io-map.md 7's recommended block that
#        nothing selects, and the harness measures the difference.
#
#   All five are one command, and it exits non-zero if any fails.
#
# USAGE
#   tools/emulator-setup/mame-osborne1nx/romservice-check.sh
#
# ENVIRONMENT
#   O1_MAME     the patched `osborne1nx` binary.  Default: beside this script
#               (a staged machine), then the usual build trees.  `mame` on PATH
#               has no such machine -- it is a patch, see README.md.
#   O1_ROMPATH  ROM path (default the repo's tools/emulator-setup/roms)
#   O1_WORK     scratch directory (default /tmp/o1next-romservice-check)
set -eu

HERE="$(cd "$(dirname "$0")" && pwd)"
MACHINE=osborne1nx
REPO="$(cd "$HERE/../../.." && pwd)"

[ -f "$REPO/AGENTS.md" ] || {
    echo "romservice-check.sh: this script belongs in the repo (tools/emulator-setup/mame-osborne1nx/)" >&2
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
    echo "romservice-check.sh: no $MACHINE binary." >&2
    echo "  The 'mame' on PATH has no such machine -- it is a patch." >&2
    echo "  Build one with tools/emulator-setup/mame-osborne1nx/apply.sh, or set O1_MAME." >&2
    exit 1
fi

ROMPATH="${O1_ROMPATH:-$REPO/tools/emulator-setup/roms}"
WORK="${O1_WORK:-/tmp/o1next-romservice-check}"
MONITOR="$REPO/research/roms/os1-144.rom"
FRAME="$REPO/firmware/rom-service/frame.bin"
SPLASH="$REPO/firmware/rom-service/screen.bin"
LUA="$HERE/o1next-romservice.lua"

[ -x "$MAME" ] || { echo "romservice-check.sh: not executable: $MAME" >&2; exit 1; }
[ -d "$ROMPATH" ] || { echo "romservice-check.sh: no such ROM path: $ROMPATH" >&2; exit 1; }
[ -f "$MONITOR" ] || { echo "romservice-check.sh: no stock monitor at $MONITOR" >&2; exit 1; }
[ -f "$FRAME" ] || { echo "romservice-check.sh: no boot frame at $FRAME" >&2; exit 1; }
[ -f "$SPLASH" ] || { echo "romservice-check.sh: no boot splash at $SPLASH" >&2; exit 1; }
[ -f "$LUA" ] || { echo "romservice-check.sh: no harness at $LUA" >&2; exit 1; }

mkdir -p "$WORK"
cd "$WORK"

echo "osborne1nx ROM service -- the door, the selector and the address (#247)"
echo "  binary:  $MAME"
echo "  rompath: $ROMPATH"
echo "  work:    $WORK"
echo

# rom2image.py's image: 4096 monitor + 3599 payload = 7695 of the 8192-byte
# window, so page 1 is the payload and page 0 the stock monitor.
"$REPO/tools/research/rom2image.py" -o "$WORK/rom2.rom" > "$WORK/rom2image.log" 2>&1
echo "image: $(wc -c < "$WORK/rom2.rom" | tr -d ' ') bytes, from rom2image.py ($WORK/rom2image.log)"
echo "frame: $(wc -c < "$FRAME" | tr -d ' ') bytes, firmware/rom-service/frame.bin"
echo "splash: $(wc -c < "$SPLASH" | tr -d ' ') bytes, firmware/rom-service/screen.bin"

# The frame's variants, built here rather than committed: a corrupt frame (one
# byte flipped in each half, so each half's own sum no longer matches) and an
# erased one (all 0xFF, which is what erased flash answers).  The splash's
# variant is a half-page, which its slot has to refuse.
cp "$FRAME" "$WORK/frame.bin"
cp "$FRAME" "$WORK/frame-corrupt.bin"
printf '\000' | dd of="$WORK/frame-corrupt.bin" bs=1 seek=291 conv=notrunc 2>/dev/null
printf '\000' | dd of="$WORK/frame-corrupt.bin" bs=1 seek=4387 conv=notrunc 2>/dev/null
dd if=/dev/zero bs=8192 count=1 2>/dev/null | tr '\000' '\377' > "$WORK/frame-erased.bin"
dd if="$FRAME" of="$WORK/frame-short.bin" bs=4096 count=1 2>/dev/null
cp "$SPLASH" "$WORK/screen.bin"
dd if="$SPLASH" of="$WORK/screen-short.bin" bs=2048 count=1 2>/dev/null
echo

FAIL=0
verdict() {  # verdict LABEL RESULT
    if [ "$2" = 0 ]; then echo "  PASS  $1"; else echo "  FAIL  $1"; FAIL=1; fi
}

# --- the door, the selector, and the address --------------------------------
# `-softrom`, `-frame` and `-bootsplash` are each device's own machine option,
# named after its tag (softrom.h).  The harness is told what was mounted so it can
# check the served bytes against the files *and* INFO's two flags against what was
# really there -- so the four combinations are the four combinations.
service() {  # service LABEL LOG [FRAME] [SPLASH]
    label="$1"; log="$2"; frame="${3:-}"; splash="${4:-}"
    set -- "$MACHINE" -softrom "$WORK/rom2.rom" \
        -video none -sound none -nothrottle -rompath "$ROMPATH" \
        -autoboot_script "$LUA" -seconds_to_run 2
    if [ -n "$frame" ]; then set -- "$@" -frame "$frame"; fi
    if [ -n "$splash" ]; then set -- "$@" -bootsplash "$splash"; fi
    O1_SOFTROM_IMAGE="$WORK/rom2.rom" O1_SOFTROM_MONITOR="$MONITOR" \
    O1_FRAME="$frame" O1_BOOTSPLASH="$splash" \
    SDL_VIDEODRIVER=dummy "$MAME" "$@" > "$log" 2>&1 || true
    echo "== $label"
    grep -E '^  (PASS|FAIL)|^ROMSERVICE:|^  (chars|attrs) trailer|^  splash trailer|^  INFO:|^  (floppy|contract)' \
        "$log" | sed 's/^/  /'
    if grep -q '^ROMSERVICE: PASS' "$log"; then verdict "$label" 0; else verdict "$label" 1; fi
    echo
}

# The four combinations of the two assets, so each of INFO's flags is seen set
# and clear, and the two bad frames on top of that.
service "the real frame and the real splash -- both flags"    "$WORK/svc-both.log"    "$WORK/frame.bin" "$WORK/screen.bin"
service "the real frame, no splash -- bit 0 alone"            "$WORK/svc-frame.log"   "$WORK/frame.bin"
service "no frame, the real splash -- bit 1 alone"            "$WORK/svc-splash.log"  ""                "$WORK/screen.bin"
service "neither -- both answer 09h and page 1 stays"         "$WORK/svc-none.log"
service "a corrupt frame, the real splash"                    "$WORK/svc-corrupt.log" "$WORK/frame-corrupt.bin" "$WORK/screen.bin"
service "an erased frame, the real splash"                    "$WORK/svc-erased.log"  "$WORK/frame-erased.bin"  "$WORK/screen.bin"

# The two halves the ROM will actually be served have to carry good trailers, or
# the screen never comes up: that is the assertion the harness cannot make on a
# corrupt frame and this is where it is made on a good one.
if [ "$(grep -c 'trailer ok' "$WORK/svc-both.log")" = 2 ]; then
    verdict "the real frame's two trailers both check out" 0
else
    verdict "the real frame's two trailers both check out" 1
    grep 'trailer' "$WORK/svc-both.log" | sed 's/^/        /'
fi
for f in svc-corrupt svc-erased; do
    if [ "$(grep -c 'trailer BAD' "$WORK/$f.log")" = 2 ]; then
        verdict "$f: both halves fail the trailer, and that is the ROM's check" 0
    else
        verdict "$f: both halves fail the trailer" 1
        grep 'trailer' "$WORK/$f.log" | sed 's/^/        /'
    fi
done

# --- a wrong-sized frame is refused ----------------------------------------
echo "== a 4096-byte frame -- half a frame is not a frame"
O1_SOFTROM_IMAGE="$WORK/rom2.rom" O1_SOFTROM_MONITOR="$MONITOR" \
SDL_VIDEODRIVER=dummy "$MAME" "$MACHINE" -softrom "$WORK/rom2.rom" \
    -frame "$WORK/frame-short.bin" \
    -video none -sound none -nothrottle -rompath "$ROMPATH" \
    -autoboot_script "$LUA" -seconds_to_run 1 > "$WORK/svc-short.log" 2>&1 || true
grep -i 'frame is two 4096-byte halves' "$WORK/svc-short.log" | sed 's/^/  /'
if grep -q 'a frame is two 4096-byte halves: 4096 bytes, not 8192' "$WORK/svc-short.log"; then
    verdict "a 4096-byte frame is refused, with the reason" 0
else
    verdict "a 4096-byte frame is refused, with the reason" 1
fi
echo

# --- and a wrong-sized splash, the same way ---------------------------------
echo "== a 2048-byte splash -- one page is not two, and half a page is not one"
O1_SOFTROM_IMAGE="$WORK/rom2.rom" O1_SOFTROM_MONITOR="$MONITOR" \
SDL_VIDEODRIVER=dummy "$MAME" "$MACHINE" -softrom "$WORK/rom2.rom" \
    -bootsplash "$WORK/screen-short.bin" \
    -video none -sound none -nothrottle -rompath "$ROMPATH" \
    -autoboot_script "$LUA" -seconds_to_run 1 > "$WORK/svc-splash-short.log" 2>&1 || true
grep -i 'boot splash is one 4096-byte window page' "$WORK/svc-splash-short.log" | sed 's/^/  /'
if grep -q 'the boot splash is one 4096-byte window page: 2048 bytes, not 4096' "$WORK/svc-splash-short.log"; then
    verdict "a 2048-byte splash is refused, with the reason" 0
else
    verdict "a 2048-byte splash is refused, with the reason" 1
fi
echo

if [ "$FAIL" = 0 ]; then
    echo "romservice-check.sh: all checks passed"
else
    echo "romservice-check.sh: FAILED -- see the logs in $WORK" >&2
fi
exit "$FAIL"
