#!/bin/sh
# romservice-check.sh -- the ROM service's door and page 1 (#247; rewritten for
# #278, 2026-10-17).
#
# WHY THIS EXISTS
#   Step 8 of #247 is the boot screen, and its first piece is the interposer's side
#   of it: the ROM asks for things through a bank-2 register pair, and the page
#   that pair selects is what it is served.  So this checks the whole transaction
#   -- and the address it happens at, which is the one thing in that contract this
#   machine can settle.
#
#   Four things have to be true, and only one of them can be seen from a boot:
#
#     1. **The door answers.**  ECHO, INFO, NOP, an unknown opcode, and the
#        abandon-a-pending-reply rule -- the mailbox protocol's transaction
#        (docs/mailbox-protocol.md 3), on a bank-2 register pair.
#     2. **Page 1 is the payload.**  `PRESENT(0)` is the one content id left: the
#        frame's two halves and the screen's own code retired with the ROM-side
#        frame path (#278), so the three ids that used to select them answer 09h
#        and leave page 1 alone.
#     3. **The address.**  The protocol proposed 2300h/2301h; this machine says no,
#        and says why: the onboard selects check two address bits, so 0x2301 is the
#        floppy's track register as well as the keyboard's row 0
#        (docs/o1-mainboard-schematic.md 7a), and a reply ANDed with a track
#        register reading 0x00 is "not ready" for ever.  The door lives at 2800h,
#        the part of o1-memory-io-map.md 7's recommended block that nothing
#        selects, and the harness measures the difference.
#     4. **The asset is valid**, which is all the ROM side can ask of the boot
#        screen: the animation is the RP2354B's to play, and `bootanim.py --check`
#        is the format test (the container's own sum, its geometry and flags, and
#        every frame's own trailer).
#
#   All four are one command, and it exits non-zero if any fails.
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
# The boot screen's asset, and the one thing this side of the ROM can say about it:
# that it is *valid*.  There is no frame to serve and no screen code to serve any
# more (#278) -- the RP2354B plays the animation, and the monitor draws its own
# fallback out of its own tail -- so the animation is checked for its format and
# for nothing else.  `frame.bin` was retired on 2026-10-16 and `screen.bin` with
# the frame path; neither is mounted, and neither is derived.
ANIM="$REPO/firmware/rom-service/boot-animation.bin"
LUA="$HERE/o1next-romservice.lua"

[ -x "$MAME" ] || { echo "romservice-check.sh: not executable: $MAME" >&2; exit 1; }
[ -d "$ROMPATH" ] || { echo "romservice-check.sh: no such ROM path: $ROMPATH" >&2; exit 1; }
[ -f "$MONITOR" ] || { echo "romservice-check.sh: no stock monitor at $MONITOR" >&2; exit 1; }
[ -f "$ANIM" ] || { echo "romservice-check.sh: no boot animation at $ANIM" >&2; exit 1; }
[ -f "$LUA" ] || { echo "romservice-check.sh: no harness at $LUA" >&2; exit 1; }

mkdir -p "$WORK"
cd "$WORK"

echo "osborne1nx ROM service -- the door, page 1 and the address (#247)"
echo "  binary:  $MAME"
echo "  rompath: $ROMPATH"
echo "  work:    $WORK"
echo

# rom2image.py's image: 4096 monitor + 3599 payload = 7695 of the 8192-byte
# window, so page 1 is the payload and page 0 the stock monitor.
"$REPO/tools/research/rom2image.py" -o "$WORK/rom2.rom" > "$WORK/rom2image.log" 2>&1
echo "image: $(wc -c < "$WORK/rom2.rom" | tr -d ' ') bytes, from rom2image.py ($WORK/rom2image.log)"
echo "animation: $(wc -c < "$ANIM" | tr -d ' ') bytes, firmware/rom-service/boot-animation.bin"
echo "assets:    none mounted -- there are none left to mount (#278)"
echo

FAIL=0
verdict() {  # verdict LABEL RESULT
    if [ "$2" = 0 ]; then echo "  PASS  $1"; else echo "  FAIL  $1"; fi
    if [ "$2" != 0 ]; then FAIL=1; fi
}

# --- the asset, as a verdict --------------------------------------------------
# **This is the ROM-side acceptance.**  The animation is not the ROM's to draw --
# the RP2354B blits it in -- so nothing on this side looks at the animation's
# *content*.  What it can say, and all it can say, is that the asset is **valid**:
# the container's own sum, its declared geometry and flags, and every frame's own
# trailer, which is the test a machine would run before drawing one.
echo "== the asset is valid, which is all the ROM side can ask of it"
if python3 "$REPO/tools/research/bootanim.py" --check "$ANIM" > "$WORK/bootanim.log" 2>&1; then
    sed 's/^/  /' "$WORK/bootanim.log"
    verdict "the animation is a valid asset -- container sum, geometry, flags, every frame" 0
else
    sed 's/^/  /' "$WORK/bootanim.log"
    verdict "the animation is a valid asset -- container sum, geometry, flags, every frame" 1
fi
echo

# --- the door, page 1, and the address ---------------------------------------
# `-softrom` is the window device's own machine option, named after its tag
# (softrom.h).  Nothing else is mounted: the frame and screen-code slots retired
# with the frame path (#278), so the run is the window and the door.
echo "== the door, page 1, and the address the machine settles"
O1_SOFTROM_IMAGE="$WORK/rom2.rom" O1_SOFTROM_MONITOR="$MONITOR" \
SDL_VIDEODRIVER=dummy "$MAME" "$MACHINE" -softrom "$WORK/rom2.rom" \
    -video none -sound none -nothrottle -rompath "$ROMPATH" \
    -autoboot_script "$LUA" -seconds_to_run 2 > "$WORK/svc.log" 2>&1 || true
grep -E '^  (PASS|FAIL)|^ROMSERVICE:|^  INFO:|^  (floppy|contract)' "$WORK/svc.log" | sed 's/^/  /'
if grep -q '^ROMSERVICE: PASS' "$WORK/svc.log"; then
    verdict "the door answers, page 1 is the payload, and the address is measured" 0
else
    verdict "the door answers, page 1 is the payload, and the address is measured" 1
fi
echo

if [ "$FAIL" = 0 ]; then
    echo "romservice-check.sh: all checks passed"
else
    echo "romservice-check.sh: FAILED -- see the logs in $WORK" >&2
fi
exit "$FAIL"
