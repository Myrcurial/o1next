# reva/ — the interposer's Rev A engineering sample: active interposer (KiCad)

**Board:** the **O1NEXT Upgrade**, Rev A — see the register in
[`../../README.md`](../../README.md). Rev A is the **engineering sample** of the
one interposer board (`Rev 0` → `Rev A` → `Rev B`); it is not a product separate
from Rev B.

The board that replaces the Rev 0 probe concept (see `../rev0/` —
superseded, kept for the decision record): parts-acquisition time for a
passive probe was within a day or two of an engineering sample of the
real thing, so we go straight to **active**.

**Almost all SMD, two-off build.** Pull the original Z80, drop the
interposer in its socket. The point of this board: *the development
partner (the AI) controls the hardware* — full memory read/write and
code injection into a running machine over USB/WiFi.

## Architecture

- **J1:** 40-pin plug into the O1's Z80 socket.
- **U1 (Z84C00, SMT 44-pin):** the machine's CPU lives on the
  interposer. Bus mastering: assert /BUSRQ, wait /BUSAK, the Z80 floats
  and the RP2354B owns the bus.
- **Drive path (slow-tolerant by design):** 4× 74AHCT595 (U3/U4/U5/U15)
  — address A0–15, control /MREQ//IORQ//RD//WR//M1//RFSH, and
  system-control bits (D_/RESET, D_/INT, D_/NMI, D_/WAIT, D_/BUSRQ).
  While bus-mastering the Z80 is stopped, so serial loading is fine.
- **Data drive:** U9 74AHCT245, A-side straight from Pico GP8–15,
  /OE = /OE_DATA. (A read-modify turnaround needs a real transceiver,
  not a 595.)
- **Tri-state onto shared lines:** U11 74AHCT244 drives /RESET, /INT,
  /NMI, /WAIT, /BUSRQ under /OE_SYSCTL (the motherboard also drives
  /RESET).
- **Capture path:** 3× 74AHCT165 (U6–U8) — address echo, data-in — the
  analyzer front end from Rev 0, retained for passive capture while the
  Z84C00 runs.
- **U2 (RP2354B):** brains. USB to the host is the part's own connector.
- **U12 (ESP32-C3 castellated module):** WiFi — UART bridge to the
  RP2354B (GP16/17); runs the Zimodem fork later
  (`firmware/zimodem-fork/`), AT-bridge firmware initially.
- **U13 (W25Q 64 Mb SPI flash):** the built-in diskette library
  (boot diskette at minimum).
- **Power:** J2 dedicated 5 V in; U14 LDO makes 3V3 for the ESP32/flash
  (the part's own regulator is not sized for the C3's TX bursts).

## What this enables (firmware roadmap hooks)

1. Passive bus analyzer (165 chain) — bring-up milestone 1.
2. Memory read/write while halted (/BUSRQ mastering) — inspect any
   address, dump ROMs (yes, including the CoPower-88 monitor ROM:
   mastering reads it directly, no runtime-inference needed —
   research-gaps #4 fully resolved).
3. **Code injection + execute:** write a payload to RAM, release
   /BUSRQ, reset or steer the Z80 into it. Remote software development
   against real hardware.
4. Later personalities (Rev B) reuse the same drive/capture fabric.

## Which Z80 signals are timing-critical (and which aren't)

The partitioning rule: **while bus-mastering (/BUSAK held), everything
is slow** — the Z80 is stopped and the RP2354B sets the pace, so
shift registers suffice for all drive. Speed is only needed for
*live* observation/response while the CPU runs at 4 MHz (250 ns
T-states).

| Signal(s) | Path | Why |
|---|---|---|
| **CLK** | Direct GPIO (GP27) | PIO timing reference for synchronous capture; nothing may add latency |
| **/MREQ, /IORQ** | Direct GPIO (GP22/GP26) *and* captured in the 165 | Raw edges needed for strobe/trigger generation mid-cycle; PIO watches these to fire SR_LOAD at the right T-state |
| /RD, /WR, /M1, /RFSH | 165 snapshot (Rev A ES) | Only needed *as sampled at the strobe*, not as raw edges, for a passive analyzer |
| A0–15, D0–7 (capture) | 165 snapshot | Same: per-cycle snapshot, clocked out in ~210 ns |
| Address/control **drive** | 595 chain | Only ever driven while mastering (CPU stopped) — slow is fine |
| Data **drive** | 74AHCT245, direct GPIO | Read-modify turnaround wants a real transceiver even when slow; keeps write timing clean against DRAM refresh windows |
| /BUSRQ (out), /BUSAK (in) | 595 bit / GPIO | Bus grant handshake tolerates multi-cycle latency by spec |
| /RESET, /INT, /NMI, /WAIT (drive) | 595 bits → 244 tri-state | Asserted-and-held signals; even edge-triggered NMI only needs >1 clock pulse width, trivially met |
| Status/LEDs, flash, ESP32 UART | GPIO/SPI | Not bus-timing |

**Rev B lookahead (now fully mapped in `../revb/README.md`):** the
*personalities* change the answer — responding to a live bus cycle
needs /MREQ, /IORQ, /RD, /WR, /M1 direct to PIO plus the data 245 on
fast OE. The address-decode problem is solved **without** direct
address pins: 74AHCT688 window comparator (595-programmable) + /WAIT
cycle stretching. **Rev B is the production revision of this same
board, not a second product** (#259), and it keeps the whole Rev A
instrument: the 595/165/244/245 fabric and `/BUSRQ` mastering.

## Known placeholders (fix during KiCad capture review)

- **U1 pin numbers are DIP-logical placeholders** — assign the real
  QFP/PLCC-44 (PEG/VSC) pinout at footprint assignment. Flagged in the
  symbol comment too.
- No DRAM refresh while bus-mastering: firmware must keep holds short
  or issue refresh cycles (document in `firmware/bus-analyzer/`).
- Decoupling caps are schematic-token (12× 100 nF); place per IC.
- Generated, not yet opened in KiCad: first open/re-save in KiCad 7+
  is the validation step.

## Regenerating

`python3 gen_reva_sch.py` — edit net tables (`SR_OUT`, `SR_IN`,
`PICO_NET`) and re-run; then normalize in KiCad.
