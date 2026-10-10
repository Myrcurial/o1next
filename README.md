# o1nextgen

A general-purpose Z80 bus interposer for the Osborne 1, built around the
Raspberry Pi Pico 2 W (RP2350 + CYW43439 WiFi), plus the research and
reverse-engineering work it enables — and, downstream, a modern-parts
Osborne 1 reproduction (the "O1 Next Generation").

## What it does

The Osborne 1 places all peripherals in memory-mapped banks and the Z80 has a
simple, slow (4 MHz) external bus. A passive/active interposer in the Z80
socket, connected to a Pico 2, makes the machine both **observable** and
**extensible**:

| Personality | What it does | Code / issue |
|---|---|---|
| **Bus analyzer** (passive) | Cycle-accurate address/data/control capture, streamed over USB — the hardware equivalent of an emulator's machine-state view | `firmware/bus-analyzer/` #17 |
| **Peripheral synthesizer** (active) | Emulates period hardware on the same decode: RT-60A real-time clock, SCREEN-PAC 80/104-column video, IEEE-488 "Drive C" ramdisk/storage, CoPower-88 mailbox | `firmware/*` #18–#24 |
| **CPU emulation shim** | Virtual CoPower-88 (8088), so original SWP software runs on machines without the (rare) physical board | `firmware/copower88-shim/` #23 |
| **Floppy interposer** | Gotek/FlashFloppy analogue: interrupts the Shugart bus and mounts `.IMD`/`.HFE` images to either drive bay, or to "Drive C" as a persistent RAM disk | `firmware/floppy-emulator/` #20 |
| **WiFi modem** | Hayes-compatible AT command set + telnet, presented through the O1's memory-mapped 6850 ACIA registers so period comm programs work unchanged | `hardware/wifi-modem-module/` #21, #56 |
| **Virtual printer** | Centronics-mode capture on the IEEE-488 port rendered to PDF, emulating a period 9-pin Epson MX-80 | `firmware/virtual-printer/` #19 |

The image library and the printer's PDFs are served by a C64 Ultimate-style
browser UI on the Pico 2 W, with a CP/M-side utility for in-machine control; no
local mods to the O1 are required (`firmware/web-ui/`).

Electrical/mechanical constraints and the settled design decisions live in
`hardware/README.md` and `firmware/README.md`; the bus and address-space
allocation is in `docs/virtual-peripherals-block-diagram.md`.

## Beyond the interposer

- **USB keyboard adapter (#47)** — standalone RP2040 board on the P4 keyboard
  connector: plug in any USB HID keyboard, no other mods. Doubles as the
  matrix-injection firmware for the interposer's web-KVM personality (#45).
  `hardware/usb-keyboard-adapter/`
- **O1 Next Generation (#49, #52)** — modern-parts Osborne 1 reproduction running
  original ROMs and software, in two form factors: a 1:1 mainboard replacement
  for a stock chassis, and a ~8 cm thick "lunchbox" portable (O1A blue/grey
  industrial design, 8" 4:3 LCD, USB-C PD / 18650 power). `hardware/o1ng/`
- **Osborne-side software** — MOUNT.COM (#27), FATCOPY (#51), the CoPower-88
  driver (#26) and an updated boot disk (#28): `software/README.md`.

## Status

Phase 0 (research and reverse-engineering, #1) is largely complete and Phase 1
(interposer hardware, #11) has begun — a Rev A schematic exists, but **no board
has been built or tested yet**, so everything downstream of the schematic is
still design work.

Status is deliberately *not* maintained in this file; a status list here goes
stale the day after it is written. The two live sources are:

- **`docs/research-gaps.md`** — every open question, where it stands, and what is
  left to close it.
- **the GitHub issues** — the work itself, one unit per issue, with the doc that
  will carry each result named up front.

The narrative version — how the research actually went, what was surprising, and
the machines it is about — lives on the blog in `site/`.

## Repository layout

| Path | Holds |
|---|---|
| `research/` | **Sources** — the archive: manuals, schematics, ROMs, disk images and machine photographs, each with recorded provenance (`research/README.md`) |
| `docs/` | **Conclusions** — what we worked out about the Osborne 1, one document per area; index and house style in `docs/README.md` |
| `hardware/` | Device definitions and KiCad projects — interposer, floppy adapter, keyboard adapter, WiFi modem module, O1 Next Generation (`hardware/README.md`) |
| `firmware/` | On-device firmware, one folder per interposer personality (`firmware/README.md`) |
| `software/` | Osborne-side CP/M software — MOUNT.COM, FATCOPY, CoPower-88 driver, boot disk (`software/README.md`) |
| `tools/` | Disk-image pipeline (TD0 → CP/M filesystem) and host-side analysis scripts (`tools/README.md`) |
| `site/` | The project blog — Jekyll source for GitHub Pages (`site/README.md`) |

## Sources

Full per-file provenance, with source URLs and the archive's licensing note, is
in `research/README.md`. In bulk the raw material comes from bitsavers, Don
Maslin's archive, Dave Dunfield's ImageDisk archive, Brett Hallen's `Osborne_1`
repository, and the Zorba and Kaypro communities.
