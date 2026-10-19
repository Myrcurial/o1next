# picoem-fabric — the interposer's shift fabric, driven (#304, part of #192)

**Status: the firmware runs, the fabric answers, and one thing blocks it — picoem cannot
see GP30 or GP31.** Measured 2026-10-19, `--fabric-test` passes everything except the
latch, and the latch is not the firmware's fault.

## What it is

The first firmware that touches the *board* rather than only the bus. It programs the
**74AHCT595**'s match value for the **74AHCT688** — so `ADDR_HIT` means "a cycle landed in
my window" — and then, on every cycle it takes, reads the address back out of the
**74AHCT165** and drives the port onto the data bus.

Both, and not the window alone: the 688 compares `A8–15`, so its window is a 256-byte
*page*, and on a Z80 I/O cycle `A8–15` is the accumulator (or `B`), not the port. The
window cannot tell one register from another; the 165 has to.
`tools/picoem-bridge/src/fabric.rs` has the argument and the unit tests.

## Build and run

```sh
firmware/picoem-fabric/build.sh

tools/picoem-bridge/target/release/picoem-bridge \
    --flash firmware/picoem-fabric/build/picoem-fabric.bin \
    --bootrom "$HOME/Documents/O1NEXT/picoem-286/roms/rp2350/bootrom-combined.bin" \
    --fabric-test --hb-pin 22
```

`--hb-pin 22` because a *personality*'s liveness signal is **`/WAIT`**: asserted when it
takes the cycle, released when the answer is on the bus. The smoke firmware borrows GP26
for its heartbeat instead, which is why the pin is a parameter and not a constant.

## What it proves, and what it measured

| | |
|---|---|
| the window | 8 `SR_SCK` edges and a latch, with `/OE_ADDR` asserted |
| the snapshot | two registers, two answers — `30` and `31` — so the **165** is doing the work |
| the pacing | **56 `SR_SCK` edges seen** against a floor of 48, so no level was held for less than a quantum |
| **the cost** | **`/WAIT` asserted at 64 cycles, released at 14 976** — a 24-bit snapshot is 234 quanta |

That last row is the number **#303** needs: a snapshot per I/O cycle is not free, and it is
now a measurement rather than a worry.

## The pacing rule, which is the emulator's

The bridge steps the emulated chip one **quantum** at a time (64 cycles, picoem's
`DEFAULT_STEP_QUANTUM`) and observes the fabric once per step, so a level held for *less*
than a quantum can be missed entirely — the model would see the net level and never the
clock edge. `pace()` holds every level for at least one quantum, which is 2.3 MHz at
150 MHz and comfortably inside the 74AHCT parts' own limits.

And it is **measured rather than asserted**: the bridge's own edge count is checked against
the floor a 24-bit snapshot must produce, so a firmware that went too fast fails the check
instead of working sometimes.

## What is blocked, and on what

**picoem masks GP30 and GP31 away.** It re-uses the **RP2040's** SIO
(`crates/rp2040-emu/src/bus/sio.rs`: `PIN_MASK = 0x3FFF_FFFF` — thirty bits, because an
RP2040 has thirty GPIOs), so every SIO write *and* read drops bits 30 and 31. Rev B's
`SR_RCK` is GP30 and `/OE_ADDR` is GP31: **two of the five fabric pins.**

So the firmware shifts its window in and picoem never sees the latch — `--fabric-test`
counts all 8 `SR_SCK` edges and reports `0 latch(es)`, and the diagnostic names the mask
rather than leaving it to be inferred. The fix is **one line** in picoem (the mask, for the
RP2350 path), and because that pin lives in the fork's patch series it means a new patch
and a re-pin. `docs/emulation-testbed.md` §4.2 **P9** has the measurement.

## Not here

- **The `/WAIT` stretch itself.** The firmware asserts and releases it; nothing measures
  the Z80 side, because the bridge models the bus and not the timing (§6).
- **A personality.** This is the fabric — what a personality needs before it can know
  *which register* a cycle is for.
- **PIO.** The fabric is bit-banged from GPIO, as Rev B's pin map implies; a PIO path is
  the personality's business, not the fabric's.
