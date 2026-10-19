# rev0/ — the interposer's Rev 0 "test probe" (KiCad)

**Board:** the **O1NEXT Upgrade**, Rev 0 — see the register in
[`../../README.md`](../../README.md). Rev 0 is the **superseded** first revision
of the one interposer board; it is the decision record, not a product.

Minimal **snoop-only** interposer for the least-modified Osborne 1:
pass-through Z80 socket + plug, 74AHCT245 capture buffers, Pico 2 W,
USB back to the host. **Not the production interposer** — no bus
driving, no personality hardware, no stacking provisions. Its job is to
bring up the bus analyzer + trace toolchain against a real machine.

## Contents

- `rev0.kicad_pro` / `rev0.kicad_sch` — KiCad 7 project + schematic
- `gen_rev0_sch.py` — the schematic is **generated**; edit the
  generator (net assignments, symbol defs) and re-run rather than
  hand-editing large label fields, then normalize by opening/re-saving
  in KiCad. (Generated without a local KiCad install — first open in
  KiCad 7+ is the validation step; expect to re-save and assign
  footprints.)

## Circuit summary

- **J1 → J2:** 40-pin plug-to-socket pass-through (into the O1's Z80
  socket; original Z80 re-seats in J2).
- **U1–U4 (74AHCT165 PISO chain):** snapshot front end — all 32 bus
  lines (A0–15, D0–7, /MREQ, /IORQ, /RD, /WR, /M1, /RFSH, /RESET, CLK)
  latched in parallel at the SH//LD strobe, then shifted QH→SER down
  the chain into the Pico (see "Pin budget" below).
- **U5 (Pico 2 W):** 6 signal lines only — SH//LD, SCLK, SDAT, Z80_CLK,
  STROBE (bus-cycle strobe), TRIG (external trigger). Preliminary map
  in `gen_rev0_sch.py` (`PICO_NET`); firmware owns the final
  assignment.
- **J3:** dedicated 5 V input (per the settled power decision); six
  100 nF decoupling caps.
- Host link is the Pico's own micro-USB — no extra connector.

## Pin budget — resolved (decision record, 2026-10-09)

32 capture lines (16A + 8D + 8CTL) exceed the Pico 2 W's 26 exposed
GPIO (GP23–25 belong to the CYW43439). Considered and rejected: I2C/SPI
GPIO expanders (µs latency vs 250 ns T-states), a bigger MCU class
(Teensy/FPGA — abandons PIO, which is the point). Resolution:

- **Rev 0 (this board): 74AHCT165 PISO snapshot front end.** A bus
  analyzer needs one snapshot per bus cycle, not continuous sampling of
  32 lines. 4× '165 latch the full bus at the cycle strobe; PIO clocks
  32 bits into the RP2350 in ~210 ns — inside one 250 ns T-state at
  4 MHz. 6 GPIO instead of 32; also exercises the production AHCT
  logic family on a cheap board.
- **The interposer's Rev A and Rev B (one board): RP2354B.** The 80-pad package has
  **48 GPIO** — full 32-line capture *plus* the drive-mode transceivers
  every personality needs, no muxing. WiFi is the onboard ESP32 on UART0,
  not a radio module. The Pico 2 W module constraint applies only to the
  Rev 0 probe.
- Fallback if the '165 chain misbehaves at bring-up: minimal 26-line
  set (A0–15, D0–7, /MREQ, /RD, CLK + one gate) — viable because all
  O1 peripherals are memory-mapped and refresh is distinguishable
  (/MREQ low, /RD high) without a dedicated /RFSH pin.

## Bring-up goals

1. Power-up smoke: buffers isolated, no contention (probe is
   listen-only by construction).
2. Analyzer firmware first light: CLK-synchronous PIO capture of the
   idle/boot bus, streamed to `tools/trace-analyzer/`.
3. **CoPower-88 monitor-ROM recovery attempt:** with the CoPower board
   installed, watch the host boot/read the 8088 mailbox path — the
   analyzer sees every byte the Z80 reads, so ROM content exercised at
   runtime may be recoverable passively (research-gaps #4 without
   desoldering).
4. Validate O1A P1/P4 physical assumptions (#47, #57 class) from
   observed traffic.
