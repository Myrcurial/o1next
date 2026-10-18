#!/bin/sh
# picoem-guest-check.sh -- Gate A's acceptance: the *guest* reads the firmware's
# answer (#192).
#
# WHAT IT PROVES, AND HOW IT DIFFERS FROM picoem-check.sh
#   `picoem-check.sh` proves the wire: it drives the card's window *from Lua* and
#   logs what the firmware drove.  It cannot return that byte to the guest,
#   because a Lua read tap that returns data segfaults once the guest polls in a
#   tight loop (measured on MAME 0.289, tools/research/acb4000.lua GOTCHAS).
#
#   This one proves the loop closes.  The `osborne1nxp` machine hands 30h-33h to
#   a `picoem_link_device` instead of to the C++ card, and the Z80 runs a real
#   `OUT`/`IN` pair in that window:
#
#       DI / LD A,A5h / OUT (30h),A / IN A,(30h) / LD (4020h),A / HALT
#
#   The value asserted is the one the guest wrote into its *own* memory at
#   4020h.  Nothing on this side can fake that: a device that returned the wrong
#   byte, or nothing, fails.
#
#   It runs the routine on three ports (30h, 31h, 33h) because the firmware
#   decodes the full 8-bit port and MAME hands an address-map handler the offset
#   *relative to the window*, so a device that forgot to put the base back would
#   pass on 30h alone and be wrong everywhere else.  That was a real bug in this
#   device, found by exactly this test.
#
# USAGE
#   tools/emulator-setup/mame-osborne1nx/picoem-guest-check.sh
#
# ENVIRONMENT
#   O1_MAME        the patched `osborne1nx` binary (as picoem-check.sh finds it)
#   O1_ROMPATH     ROM path (default the repo's tools/emulator-setup/roms)
#   O1_WORK        scratch directory (default /tmp/o1next-picoem-guest-check)
#   O1_PICOEM_BIN  the firmware flash image (default firmware/picoem-smoke/build/)
#   O1_PICOEM_BOOTROM  picoem's roms/rp2350/bootrom-combined.bin
#   O1_PICOEM_BRIDGE   the bridge binary
#   O1_GUEST_PORTS the ports to run the routine on (default "30 31 33")
#
#   It does NOT build the firmware or the bridge: a check that silently pulls
#   200 MB is not a check.  It says what to run instead.
set -eu

HERE="$(cd "$(dirname "$0")" && pwd)"
MACHINE=osborne1nxp
REPO="$(cd "$HERE/../../.." && pwd)"

[ -f "$REPO/AGENTS.md" ] || {
    echo "picoem-guest-check.sh: this script belongs in the repo (tools/emulator-setup/mame-osborne1nx/)" >&2
    exit 1; }

# --------------------------------------------------------------- the binary ----
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
    echo "picoem-guest-check.sh: no $MACHINE binary." >&2
    echo "  The 'mame' on PATH has no such machine -- it is a patch, and this one" >&2
    echo "  needs picoem-link.patch applied as well as osborne1nx.patch." >&2
    echo "  Build one with tools/emulator-setup/mame-osborne1nx/apply.sh, or set O1_MAME." >&2
    exit 1
fi
[ -x "$MAME" ] || { echo "picoem-guest-check.sh: not executable: $MAME" >&2; exit 1; }

ROMPATH="${O1_ROMPATH:-$REPO/tools/emulator-setup/roms}"
WORK="${O1_WORK:-/tmp/o1next-picoem-guest-check}"
PORTS="${O1_GUEST_PORTS:-30 31 33}"

# ------------------------------------------------------------- the firmware ----
FW="${O1_PICOEM_BIN:-$REPO/firmware/picoem-smoke/build/picoem-smoke.bin}"
if [ ! -f "$FW" ]; then
    echo "picoem-guest-check.sh: no firmware image at $FW" >&2
    echo "  Build it first:  firmware/picoem-smoke/build.sh" >&2
    exit 1
fi

# -------------------------------------------------------------- the bootrom ----
BOOTROM="${O1_PICOEM_BOOTROM:-}"
if [ -z "$BOOTROM" ]; then
    for cand in "$HOME/Documents/O1NEXT/picoem-286/roms/rp2350/bootrom-combined.bin" \
                "$HOME/Documents/O1NEXT/picoem/roms/rp2350/bootrom-combined.bin"; do
        if [ -f "$cand" ]; then BOOTROM="$cand"; break; fi
    done
fi
if [ -z "$BOOTROM" ] || [ ! -f "$BOOTROM" ]; then
    echo "picoem-guest-check.sh: no mask ROM." >&2
    echo "  It ships in picoem's own tree at roms/rp2350/bootrom-combined.bin --" >&2
    echo "  REQUIREMENTS.md has the clone and the pin.  Or set O1_PICOEM_BOOTROM." >&2
    exit 1
fi

# --------------------------------------------------------------- the bridge ----
BRIDGE="${O1_PICOEM_BRIDGE:-$REPO/tools/picoem-bridge/target/release/picoem-bridge}"
if [ ! -x "$BRIDGE" ]; then
    echo "picoem-guest-check.sh: no bridge binary at $BRIDGE" >&2
    echo "  Build it with:  (cd tools/picoem-bridge && cargo build --release)" >&2
    exit 1
fi

mkdir -p "$WORK"
cd "$WORK"

IN_FIFO="$WORK/in"
OUT_FIFO="$WORK/out"
MAME_LOG="$WORK/mame.log"
BRIDGE_LOG="$WORK/bridge.log"
rm -f "$IN_FIFO" "$OUT_FIFO" "$MAME_LOG" "$BRIDGE_LOG"

echo "picoem guest acceptance -- the guest reads the firmware's answer (#192)"
echo "  binary:   $MAME"
echo "  firmware: $FW"
echo "  bootrom:  $BOOTROM"
echo "  bridge:   $BRIDGE"
echo "  ports:    $PORTS"
echo "  work:     $WORK"
echo

# The bridge owns the chip and blocks on its FIFOs, so it is killed on every
# exit path.  `--frames` gives it a way to finish on its own as well.
"$BRIDGE" --flash "$FW" --bootrom "$BOOTROM" \
    --in "$IN_FIFO" --out "$OUT_FIFO" --frames 16 \
    > "$BRIDGE_LOG" 2>&1 &
BRIDGE_PID=$!
trap 'kill "$BRIDGE_PID" 2>/dev/null || true; wait "$BRIDGE_PID" 2>/dev/null || true' EXIT INT TERM

n=0
while [ ! -p "$IN_FIFO" ] && [ "$n" -lt 300 ]; do
    sleep 0.1
    n=$((n + 1))
done
[ -p "$IN_FIFO" ] || { echo "picoem-guest-check.sh: the bridge never made $IN_FIFO" >&2
                       cat "$BRIDGE_LOG" >&2; exit 1; }

# One run per port, so a device that answers the wrong register is caught.
for port in $PORTS; do
    log="$WORK/mame-$port.log"
    guest="$WORK/guest-$port.log"
    rm -f "$log" "$guest"
    SDL_VIDEODRIVER=dummy O1_PICOEM_IN="$IN_FIFO" O1_PICOEM_OUT="$OUT_FIFO" \
    O1NEXT_LOG="$guest" O1_GUEST_PORT="0x$port" \
        "$MAME" "$MACHINE" -rompath "$ROMPATH" \
            -video none -sound none -nothrottle -seconds_to_run 6 \
            -autoboot_script "$HERE/o1next-picoem-guest.lua" \
            > "$log" 2>&1 || true
done

sleep 0.3
kill "$BRIDGE_PID" 2>/dev/null || true
wait "$BRIDGE_PID" 2>/dev/null || true
trap - EXIT INT TERM

echo "--- the machine's log, first port ($WORK/mame-$(echo "$PORTS" | cut -d' ' -f1).log)"
grep '^picoem:' "$WORK/mame-$(echo "$PORTS" | cut -d' ' -f1).log" || echo "  (nothing)"
echo

# ------------------------------------------------------------------ asserts ----
fail=0
want() {
    if grep -q "$1" "$2"; then
        echo "  PASS  $3"
    else
        echo "  FAIL  $3"
        fail=1
    fi
}

first="$(echo "$PORTS" | cut -d' ' -f1)"
MAME_LOG="$WORK/mame-$first.log"

echo "checks:"
want 'picoem: HELLO  status 00' "$MAME_LOG" \
     "the firmware is running in picoem (HELLO answered, status 00)"
want 'firmware pc=1000' "$MAME_LOG" \
     "the firmware's PC is inside the image's XIP window"
want 'picoem: channel' "$MAME_LOG" \
     "the osborne1nxp machine's picoem_link_device opened the channel"

for port in $PORTS; do
    want "RESULT: PASS" "$WORK/guest-$port.log" \
         "port $port: the GUEST's own IN returned the byte it drove"
    want "picoem: W $port " "$WORK/mame-$port.log" \
         "port $port: the frame carried the real 8-bit port, not the window offset"
    want "picoem: R $port " "$WORK/mame-$port.log" \
         "port $port: the read came back on the same port"
done

echo
if [ "$fail" -eq 0 ]; then
    echo "RESULT: PASS -- a Z80 program in osborne1nxp ran OUT/IN in the card's"
    echo "        window, a real RP2354B firmware answered both, and the guest"
    echo "        read the firmware's byte back out of its own memory."
else
    echo "RESULT: FAIL -- see the logs above."
fi
exit "$fail"
