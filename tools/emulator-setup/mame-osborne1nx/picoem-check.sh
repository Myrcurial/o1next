#!/bin/sh
# picoem-check.sh -- the picoem bridge's acceptance (#286, part of #192).
#
# WHAT IT PROVES
#   1. A firmware binary built from this tree runs inside picoem.  (The bridge
#      reports the firmware's PC and cycle count; the PC is inside the image.)
#   2. A bus cycle in `osborne1nx` reaches the firmware's GPIO, and the answer
#      comes back: the harness drives the card's window, the firmware echoes the
#      byte it latched, and the reply frame carries it back.
#   3. The result is visible in the MAME-side log -- the echoed byte and the
#      heartbeat the firmware toggles once per cycle it handles.
#   4. **The firmware answered inside the cycle budget the personality declares**
#      (#293).  Every transaction's answer time is in the bridge's log as `ans=`,
#      and the worst of them is asserted against ACB4000_CYCLE_BUDGET in
#      firmware/acb4000-scsi/acb4000.h.  `docs/emulation-testbed.md` section 7.
#
#   Items 1 and 4 are in the bridge's log and 2 and 3 in the MAME log; this script
#   requires both, because "the firmware never answered" and "the firmware never
#   started" look identical from one side alone.
#
# USAGE
#   tools/emulator-setup/mame-osborne1nx/picoem-check.sh
#
# ENVIRONMENT
#   O1_MAME        the patched `osborne1nx` binary (as softrom-check.sh finds it)
#   O1_ROMPATH     ROM path (default the repo's tools/emulator-setup/roms)
#   O1_WORK        scratch directory (default /tmp/o1next-picoem-check)
#   O1_PICOEM_BIN  the firmware flash image.  Default:
#                  firmware/picoem-smoke/build/picoem-smoke.bin, which
#                  firmware/picoem-smoke/build.sh makes.
#   O1_PICOEM_BOOTROM  picoem's roms/rp2350/bootrom-combined.bin.  Default: the
#                  documented clone at $HOME/Documents/O1NEXT/picoem-286, then
#                  $HOME/Documents/O1NEXT/picoem.
#   O1_PICOEM_BRIDGE   the bridge binary
#   O1_PICOEM_DRIVE    the I/O accesses to make (default "W30=A5,R30,W31=5A,R31")
#   O1_PICOEM_CYCLES   the bridge's phase length (default 20000).  It must exceed
#                  the declared budget, or the budget cannot be tested at all --
#                  nothing answers later than the phase's own end.
#
#   It does NOT build the firmware: that needs the Pico SDK and the Arm GNU
#   Toolchain, and a check that silently pulls 200 MB is not a check.  It says
#   what to run instead.
set -eu

HERE="$(cd "$(dirname "$0")" && pwd)"
MACHINE=osborne1nx
REPO="$(cd "$HERE/../../.." && pwd)"

[ -f "$REPO/AGENTS.md" ] || {
    echo "picoem-check.sh: this script belongs in the repo (tools/emulator-setup/mame-osborne1nx/)" >&2
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
    echo "picoem-check.sh: no $MACHINE binary." >&2
    echo "  The 'mame' on PATH has no such machine -- it is a patch." >&2
    echo "  Build one with tools/emulator-setup/mame-osborne1nx/apply.sh, or set O1_MAME." >&2
    exit 1
fi
[ -x "$MAME" ] || { echo "picoem-check.sh: not executable: $MAME" >&2; exit 1; }

ROMPATH="${O1_ROMPATH:-$REPO/tools/emulator-setup/roms}"
WORK="${O1_WORK:-/tmp/o1next-picoem-check}"
DRIVE="${O1_PICOEM_DRIVE:-W30=A5,R30,W31=5A,R31}"

# ------------------------------------------------------------- the firmware ----
FW="${O1_PICOEM_BIN:-$REPO/firmware/picoem-smoke/build/picoem-smoke.bin}"
if [ ! -f "$FW" ]; then
    echo "picoem-check.sh: no firmware image at $FW" >&2
    echo "  Build it first (needs the Pico SDK and the Arm GNU Toolchain):" >&2
    echo "    firmware/picoem-smoke/build.sh" >&2
    echo "  REQUIREMENTS.md has both tool rows." >&2
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
    echo "picoem-check.sh: no mask ROM." >&2
    echo "  It ships in picoem's own tree at roms/rp2350/bootrom-combined.bin --" >&2
    echo "  REQUIREMENTS.md has the clone and the pin.  Or set O1_PICOEM_BOOTROM." >&2
    exit 1
fi

# --------------------------------------------------------------- the bridge ----
BRIDGE="${O1_PICOEM_BRIDGE:-$REPO/tools/picoem-bridge/target/release/picoem-bridge}"
if [ ! -x "$BRIDGE" ]; then
    echo "picoem-check.sh: no bridge binary at $BRIDGE" >&2
    echo "  Build it with:  (cd tools/picoem-bridge && cargo build --release)" >&2
    exit 1
fi

# --------------------------------------------------------------- the budget ----
# The personality declares it (#293, docs/emulation-testbed.md section 7), so it
# is read out of the personality's own header rather than repeated here: a budget
# in two places is a budget that drifts.  `sed` rather than a compiler because this
# is a shell script, and a missing declaration is a hard error rather than a
# default -- a default would be the one number nobody chose.
BUDGET=$(sed -n 's/^#define[[:space:]]\{1,\}ACB4000_CYCLE_BUDGET[[:space:]]\{1,\}\([0-9]\{1,\}\)u*[[:space:]]*$/\1/p' \
             "$REPO/firmware/acb4000-scsi/acb4000.h")
if [ -z "$BUDGET" ]; then
    echo "picoem-check.sh: firmware/acb4000-scsi/acb4000.h declares no ACB4000_CYCLE_BUDGET" >&2
    echo "  The personality's declaration is what this check asserts against -- see that" >&2
    echo "  header, and docs/emulation-testbed.md section 7." >&2
    exit 1
fi

# The phase has to be longer than the budget, or the assertion is vacuous: the
# firmware cannot answer later than the phase's end, so a budget larger than the
# phase could never be exceeded.
PHASE="${O1_PICOEM_CYCLES:-20000}"
if [ "$PHASE" -le "$BUDGET" ]; then
    echo "picoem-check.sh: the phase ($PHASE cycles) does not exceed the declared budget" >&2
    echo "  ($BUDGET cycles), so the budget assertion cannot fail.  Raise O1_PICOEM_CYCLES." >&2
    exit 1
fi

mkdir -p "$WORK"
cd "$WORK"

IN_FIFO="$WORK/in"
OUT_FIFO="$WORK/out"
MAME_LOG="$WORK/mame.log"
BRIDGE_LOG="$WORK/bridge.log"
rm -f "$IN_FIFO" "$OUT_FIFO" "$MAME_LOG" "$BRIDGE_LOG"

echo "picoem bridge -- the acceptance (#286, #293)"
echo "  binary:   $MAME"
echo "  firmware: $FW"
echo "  bootrom:  $BOOTROM"
echo "  bridge:   $BRIDGE"
echo "  drive:    $DRIVE"
echo "  budget:   $BUDGET cycles (ACB4000_CYCLE_BUDGET), phase $PHASE"
echo "  work:     $WORK"
echo

# The bridge owns the chip and blocks on its FIFOs, so it is killed on every
# exit path.  `--frames` gives it a way to finish on its own as well.
"$BRIDGE" --flash "$FW" --bootrom "$BOOTROM" \
    --in "$IN_FIFO" --out "$OUT_FIFO" --frames 12 \
    --cycles "$PHASE" --assert-cycles "$BUDGET" \
    > "$BRIDGE_LOG" 2>&1 &
BRIDGE_PID=$!
trap 'kill "$BRIDGE_PID" 2>/dev/null || true; wait "$BRIDGE_PID" 2>/dev/null || true' EXIT INT TERM

# Wait for the FIFOs the bridge creates, so MAME does not start first and decide
# the bridge is absent.
n=0
while [ ! -p "$IN_FIFO" ] && [ "$n" -lt 300 ]; do
    sleep 0.1
    n=$((n + 1))
done
[ -p "$IN_FIFO" ] || { echo "picoem-check.sh: the bridge never made $IN_FIFO" >&2
                       cat "$BRIDGE_LOG" >&2; exit 1; }

SDL_VIDEODRIVER=dummy O1_PICOEM_IN="$IN_FIFO" O1_PICOEM_OUT="$OUT_FIFO" \
O1NEXT_LOG="$MAME_LOG" O1_PICOEM_REQUIRE=1 O1_PICOEM_DRIVE="$DRIVE" \
    "$MAME" "$MACHINE" -rompath "$ROMPATH" \
        -video none -sound none -nothrottle -seconds_to_run 4 \
        -autoboot_script "$HERE/o1next-picoem.lua" \
        > "$WORK/mame-stdout.log" 2>&1 || true

sleep 0.3
kill "$BRIDGE_PID" 2>/dev/null || true
wait "$BRIDGE_PID" 2>/dev/null || true
trap - EXIT INT TERM

echo "--- the machine's log ($MAME_LOG)"
grep '^picoem:' "$MAME_LOG" || echo "  (nothing)"
echo
echo "--- the bridge's log ($BRIDGE_LOG)"
grep -E 'picoem-bridge: (settled|entry|seq)' "$BRIDGE_LOG" | head -20 || true
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

echo "checks:"
want 'picoem: HELLO  status 00' "$MAME_LOG" \
     "the firmware is running in picoem (HELLO answered, status 00)"
want 'firmware pc=1000' "$MAME_LOG" \
     "the firmware's PC is inside the image's XIP window"
want 'W 30 <- A5  firmware drove A5' "$MAME_LOG" \
     "a write cycle reached the firmware and it drove the byte back"
want 'hb=1' "$MAME_LOG" \
     "the firmware toggled its heartbeat for a cycle it handled"
want 'R 30      firmware drove A5' "$MAME_LOG" \
     "a read cycle came back with the byte the firmware latched"
want 'W 31 <- 5A  firmware drove 5A' "$MAME_LOG" \
     "the register takes a second value -- it is not a stuck pin"
want 'picoem-bridge: seq' "$BRIDGE_LOG" \
     "the bridge logged the transactions it answered"

# --- the cycle budget (#293) ---------------------------------------------------
# `--assert-cycles` covers a run that finishes on its own; this script kills the
# bridge, so the assertion that always applies is the one over the log.  Every
# transaction reports the cycles the firmware took to answer (`ans=`), and the
# worst of them is the number the declared budget is about
# (docs/emulation-testbed.md section 7).
worst=$(grep -oE 'ans=[0-9]+' "$BRIDGE_LOG" | sed 's/ans=//' | sort -n | tail -1)
if [ -z "$worst" ]; then
    echo "  FAIL  the bridge reported no answer time (ans=) at all -- the firmware never answered"
    fail=1
else
    echo "  (worst answer: $worst cycles, declared budget $BUDGET)"
    if [ "$worst" -le "$BUDGET" ]; then
        echo "  PASS  every transaction answered inside the declared budget ($BUDGET cycles)"
    else
        echo "  FAIL  a transaction answered in $worst cycles, outside the budget of $BUDGET"
        fail=1
    fi
fi

echo
if [ "$fail" -eq 0 ]; then
    echo "RESULT: PASS -- a firmware binary built from this tree is running inside"
    echo "        picoem, osborne1nx's bus cycles reach its GPIO, and the answers"
    echo "        come back into the machine."
else
    echo "RESULT: FAIL -- see the logs above."
fi
exit "$fail"
