# interposer — Z80 bus interposer (core board)

The centerpiece of the project: a board that sits between the Osborne 1's
Z80 and its socket, carrying a Raspberry Pi Pico 2 W (RP2350 + CYW43439).

Tracks: #11 (Phase 1 hardware design), #12 (electrical/mechanical
interface spec), #13 (Rev A schematic + PCB), #15 (Rev B SMD).

## Personalities hosted (firmware, Phase 2 #16)

- Passive bus analyzer (#17) — cycle-accurate capture → USB/WiFi
- RT-60A RTC emulation (#18)
- Virtual MX-80 printer, IEEE-488 Centronics capture → PDF (#19)
- Floppy interposer + image library (#20)
- WiFi modem via 6850 ACIA snoop (#21)
- Drive C / IEEE-488 storage device (#22)
- Virtual CoPower-88 8088 emulation shim (#23)
- SCREEN-PAC 80/104-column video + HDMI (#24; taps the char-gen socket
  UA15, reads whatever font ROM is installed — #44)
- Web KVM console (#45): video snoop + keyboard matrix poke

## Electrical definition (settled decisions)

- **CPU interface:** standard Z80 DIP40 socket + socket-safe pin header;
  4 MHz bus sampled synchronously via PIO.
- **Level shifting:** 74AHCT (or 74HCT) both directions — all O1s are
  NMOS Z80s; AHCT/HCT matches NMOS I/O thresholds. (Decision
  2026-10-09, research-gaps #2; supersedes "74LVC245-class".)
- **Power:** own dedicated 5 VDC feed from a rail near the Z80 socket,
  sized for Pico 2 W WiFi bursts (~300 mA+). (Decision 2026-10-09.)
- **Modes:** passive-tap vs active-drive switching; mode jumpers.
- **Stacking:** must coexist with SCREEN-PAC and CoPower-88 interposers
  on the fully-loaded machine; pass-through height matters.

## Modem: personality vs. onboard ESP32 (decision to make)

Two ways to deliver the WiFi modem (#21/#56) from the interposer:

- **(a) Pure firmware personality:** the Pico 2 W's CYW43439 provides
  WiFi; the modem is a Zimodem-style reimplementation on the Pico SDK /
  lwIP, snooping/driving the memory-mapped 6850 ACIA. Fewer parts, but
  SSH is not realistic on the Pico 2 W and the radio shares the RP2350
  with timing-critical PIO work (WiFi IRQ fencing needed).
- **(b) Onboard ESP32 adjacent to the Pico 2 W:** the interposer
  carries the same ESP32 module as the severable modem
  (`../wifi-modem-module/`), running the Zimodem fork with SSH +
  baud buffering; the Pico 2 W just bridges ACIA traffic to it. More
  BOM, but SSH works today, the modem firmware is shared with the
  severable module, and RP2350 timing stays clean.

Current leaning: **(b)** — one modem firmware codebase across both
devices, SSH capability, and cleaner real-time behavior. Confirm
before Rev A schematic (#13).

## Onboard storage: built-in diskette library

**Decision: include onboard library flash in addition to removable
media.** SD/USB (via the front-panel pod) is the bulk store, but the
interposer should carry enough onboard flash to hold a **built-in
library — at minimum the boot diskette** — so the machine is useful
with no card or stick inserted (and the O1NG can boot
"factory" images out of the box).

- Option A: SPI NOR flash (W25Q-class, 16–64 MB) — trivially enough for
  dozens of O1 images (a DD image is ~400 KB); cheap, easy.
- Option B: eMMC or a second SD — overkill; not needed at O1 image
  sizes.
- Leaning: **A** — a handful of SOIC-8 flash chips' worth of library is
  effectively free. Exact sizing settled with #20's image format.

## Mechanical / revision plan (revised 2026-10-09)

- **Rev 0 "test probe"** — **superseded** (kept in `rev0/` for the
  decision record, incl. the '165 snapshot front end that Rev A
  inherits). Parts lead time for a passive probe was within days of an
  engineering sample of the active board, so the passive step is
  skipped.
- **Rev A engineering sample (`reva/`, 2-off, almost all SMD):**
  active interposer — SMT Z84C00 on board (pull the original CPU, drop
  the interposer in), /BUSRQ bus mastering, 595/165 shift-register
  drive+capture fabric, Pico 2 module + castellated ESP32-C3 for WiFi,
  W25Q library flash. Design goal: **the dev partner controls the
  hardware** — memory R/W, ROM dumping (incl. the CoPower-88 monitor
  ROM, resolving research-gaps #4 by direct read), code injection +
  execute. See `reva/README.md`.
- Rev A production (#13): incorporates ES errata.
- **Rev B (#15) — a separate product, not a revision:** Rev A is the
  mastering/debug instrument; Rev B is the **live-cycle personality
  engine**. Full RP2350B pin allocation in `revb/README.md`. The
  enabling decisions:
  - **Zero direct address pins:** a 74AHCT688 window comparator
    (595-programmable match) + **/WAIT cycle stretching** — the
    period-correct slow-peripheral mechanism — replaces 16 direct
    address lines with 2 (ADDR_HIT, /WAIT drive).
  - Timing-critical direct set is only: D0–7, /MREQ, /IORQ, /RD, /WR,
    /M1, CLK, DATA_OE/DIR — 13 pins.
  - **HSTX is fixed to GP12–19** on RP2350 → HDMI there, either/or
    with VGA on the same range.
  - **Status/LED bank moves to the ESP32** (charlieplexed or I²C
    expander); SD on SPI (4-bit SDIO-via-PIO deferred); I²C pair
    reserved for front-panel OLED/encoder/expansion.
  - The Rev A 595/165 fabric carries over wholesale and remains the
    pressure-relief valve for any slow line.
- Ribbon-cable header to the front-panel UI pod (`../front-panel-ui/`),
  which also carries the second-keyboard USB-A path (see
  `../front-panel-ui/`).
- Optional second tap: 24-pin char-gen socket (UA15) for the video
  personality — pinout confirmation from ScreenPac install pages +
  mainboard schematic (research-gaps #3).

## Open questions

- Exact free I/O decode windows — resolved in `docs/o1-memory-io-map.md`;
  verify chosen peripheral port bases against it.
- /RFSH refresh-cycle filtering strategy for traces.
- Physical 2×5 IDC orientation for the modem P1 connection (same
  validation class as the P4 keyboard pinout).

## References

- `docs/o1-memory-io-map.md`, `docs/interposer-survey.md`,
  `docs/virtual-peripherals-block-diagram.md`, `docs/research-gaps.md`
- Host machine photos: `research/pictures/`
