# wifi-modem-module — the O1NEXT WiFi COMM PAC (ESP32 Zimodem fork)

**Board:** the **O1NEXT WiFi COMM PAC** — the project's **third deliverable**.
See the register in [`../README.md`](../README.md). It closely models the
original Osborne 1 COMM PAC 300-baud modem and lives in the left-hand floppy
storage pocket, taking power and signal from the MODEM (P1) 9-pin port. The PCB
also hosts ~10 indicator LEDs, a piezo speaker, the aux power port for the USB
Keyboard Adapter, and a USB-C port for programming or powering the ESP32.

Hayes-compatible WiFi modem for the Osborne 1, designed as a **severable
module**: usable standalone on the MODEM (P1) port, or as part of the
interposer (where the RP2354B personality #21 does the same job via
memory-map snooping instead).

Tracks: #56 (extension of #21). Physical interface documented by #57.

## Definition

- **Base:** Zimodem fork targeting **ESP32** (not ESP8266) — the ESP32
  build already carries the SSH client (`INCLUDE_SSH`), SD shell, FTP,
  SLIP/PPP; ESP8266 lacks the headroom.
- **New O1-specific work on top:**
  1. **SSH as first-class transport** — keys, host verification, session
     management via the web UI; `ssh` from the O1 into a modern host.
  2. **Baud-rate buffering/correction** — decouple O1-side ACIA rate
     from the far-end link rate; makes the 2× business turbo (#55)
     usable and quietly corrects the factory 600/2400 → 650/2600 quirk.

## Host interface — MODEM port (P1, DE-9P)

**TTL levels, not RS-232** — the port feeds straight into the 6850 ACIA
(status `2A00H` / data `2A01H`), bypassing the RS-232 level shifters.

- 1 GND · 2 TXD (TTL) · 3 NC · 4 MSB (open-collector) · 5 CTS ·
  6 RXD (**bipolar input**, −0.5…−10 V = 1) · 7 +12V via R21 22Ω ·
  8 MCB (TTL, low = suppress output) · 9 RI (TTL)
- **Asymmetric levels:** TXD/MCB/RI are plain TTL, but **RXD is bipolar**
  (LM1458 + 1N5231B zener front-end) — the module must swing
  TX-toward-O1 **negative** for a clean mark. Needs in-hardware
  validation; a small charge-pump or transistor level stage is expected.
- On-board P1 header carries DE-9 pin numbers straight through
  (schematic sheet 7); 2×5 IDC orientation to be confirmed on a real
  board (same validation class as #47's P4).

## Power

+12V available on DE-9 pin 7 (via R21) — same power trick as the
keyboard adapter; on-board regulator to 3.3 V for the ESP32. **The port
carrying power is what makes the severable module possible at all**: it
hangs on the front of the machine and feeds itself, with no case opened
and no separate supply.

- **The current budget is deliberately deferred** (decision 2026-10-10,
  #56): don't derive it until a board is close enough to need the answer.
  The expected resolution is cheap — a bulk capacitor local to the module
  absorbs the WiFi transmit transients and R21 only has to supply the
  *average*. A series resistor is a sustained-current limit, so it and a
  transient reservoir do not actually fight each other.
- **R21 is shared, and that is an opportunity rather than a tension.** The same
  22 Ω resistor feeds **P4 pin 19** through jumper J6 *and* **P1 pin 7**. Because
  **P1 is externally accessible while P4's path needs J6 bridged**, a USB
  keyboard adapter (#47) fitted alongside this module can take its +12 V from the
  **modem port** through a 9-pin passthrough — **no case opening at all**. Both
  loads share R21 either way; what changes is which connector feeds them. Revisit
  the budget with the numbers above, not separately.

## Enclosure

The module ships with STLs for a **"COMM PAC-look" case** that fits in
the **left floppy storage pocket** — period-authentic Osborne
industrial design so it reads as original kit, not a modern dongle.
Deliverables: `case/*.stl` (top/bottom shells, LED light-pipe window)
alongside the PCB. Case design should accommodate the DE-9P pigtail and
leave the pocket usable with the keyboard closed.

## References

- `docs/o1-modem-serial.md` (authoritative pinout + levels)
- `docs/o1-memory-io-map.md` §"6850 ACIA detail"
- Upstream: https://github.com/bozimmerman/Zimodem
