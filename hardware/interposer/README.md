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
- **ROM 2.00 (#83)** — the monitor ROM's replacement: CP/M 2.2 resident, booting
  to `A>` with no disk. The interposer's **main-ROM socket tap** is what makes it
  possible on a real machine (see *Tap points* below); the same image is what the
  SFF board runs
- Web KVM console (#45): video snoop + keyboard matrix poke

## Tap points (three, and all of them socket leads)

The interposer sits in the Z80 socket, so it already has the bus. Two further
socket lead-sets give it the two things the bus alone cannot supply — the font,
and the ROM window.

| # | Socket | What the tap gives | Serves |
|---|---|---|---|
| 1 | **Z80, 40-pin DIP** (the interposer's own seat) | every bus cycle — address, data, `MREQ`/`IORQ`/`RD`/`WR`/`M1`, `RFSH`, `CLK`; sampled synchronously via PIO | everything: capture, drive, and every personality |
| 2 | **Main ROM, UD11, 24-pin** *(added 2026-10-13)* | the ROM window itself. A daughterboard takes the socket — **DIP pins down, ribbon up** — and the Pico **serves the ROM**, so **no physical ROM part is needed** and the banking is a firmware register | **ROM 2.00 (#83)**: a banked ROM window, one image, on any OEM-faithful mainboard |
| 3 | **Char-gen ROM, UA15, 24-pin** | the font (read-only, `ScreenPac`-style) — the ROM is permanently selected, so the tap reads whatever is fitted | video personality (#24), font capture (#44) |

Tap 2 is what collapses #83's two routes into one. Note what it does *not* need:
a 24-pin 2732 socket carries no `A12`, no `A13` and no write strobe, so a *part* in
that socket could never exceed 4 KB — but when the Pico serves the window the
address lines past `A11` are irrelevant, because the bank is which 4 KB the
firmware chooses to present. That is why the interposer path needs **no new part
and no programmer**, and why ROM 2.00 is updatable in flash. **There is no ROM 2.00
part at all** — not a 27128, not a 2764, not in any form — because there is no board
without an interposer to design one for.

**The host board does not matter, and that is worth stating once:** an existing
**OEM board + interposer** is the same thing as an **LFF board + interposer**,
because the LFF board is a faithful recreation of *just* the OEM board with the
Dual Density upgrade built in (`../o1ng/o1ng-lff/README.md`). So there is no
separate LFF path to design, document or test for — one brief covers both.

## Electrical definition (settled decisions)

- **CPU interface:** standard Z80 DIP40 socket + socket-safe pin header;
  4 MHz bus sampled synchronously via PIO.
- **ROM interface (added 2026-10-13):** a second socket lead-set to the **main
  ROM socket (UD11)**, by way of a daughterboard (DIP pins down, ribbon up). The
  Pico then **serves the ROM window** and the bank is a firmware register, so
  ROM 2.00 (#83) needs no physical ROM part at all — see *Tap points*.
- **Level shifting:** 74AHCT (or 74HCT) both directions — all O1s are
  NMOS Z80s; AHCT/HCT matches NMOS I/O thresholds. (Decision
  2026-10-09, research-gaps #2; supersedes "74LVC245-class".)
- **Power:** own dedicated 5 VDC feed from a rail near the Z80 socket,
  sized for Pico 2 W WiFi bursts (~300 mA+). (Decision 2026-10-09.)
- **Power, standalone (added 2026-10-14, #207):** the Pico 2 W and the W25Q
  library flash share one 5 V net, and that net must be reachable **from USB
  alone** — the board runs, and the flash is programmable, with the interposer
  out of the machine and no host supply connected. This rules out the case
  where the Pico is USB-powered and the flash is fed from the machine's rail:
  the library could not be filled. Filling the onboard library, then installing
  the board, is the intended bench sequence. The SFF board carries the same
  requirement (`../o1ng/README.md`).
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
  - **HSTX is fixed to GP12–19** on RP2350 → **HDMI** there. A VGA
    resistor DAC would need the same range, so the two are mutually
    exclusive; **HDMI is the choice** and VGA is not pursued.
  - **Status/LED bank moves to the ESP32** (charlieplexed or I²C
    expander); SD on SPI (4-bit SDIO-via-PIO deferred); I²C pair
    reserved for front-panel OLED/encoder/expansion.
  - The Rev A 595/165 fabric carries over wholesale and remains the
    pressure-relief valve for any slow line.
- Ribbon-cable header to the front-panel UI pod (`../front-panel-ui/`),
  which also carries the second-keyboard USB-A path (see
  `../front-panel-ui/`).
- Two socket lead-sets beyond the Z80 seat, both now first-class rather than
  optional: **UD11** (main ROM, via a DIP-down/ribbon-up daughterboard — the Pico
  serves the window) and **UA15** (char-gen, font capture). Pinout confirmations:
  mainboard schematic §4a for UA15, `docs/o1-memory-io-map.md` §2 for the ROM
  window (research-gaps #3). The daughterboard's signal list is #12's.

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
