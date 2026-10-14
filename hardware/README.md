# hardware/

Hardware device definitions for the o1nextgen project. Each subfolder is
one physical device contemplated in the GitHub issues, holding its
interface spec, design decisions, and (eventually) KiCad design files.
Status ranges from "concept definition" to "ready for schematic entry" —
no PCB layouts exist yet (Phase 1, issue #11).

## Devices

| Folder | Device | Issues | Status |
|---|---|---|---|
| `interposer/` | Z80 bus interposer — the core board. **Rev A engineering sample** (`interposer/reva/`, 2-off, SMD): active interposer w/ SMT Z84C00, /BUSRQ bus mastering (memory R/W + code injection), Pico 2 + ESP32-C3, W25Q library flash; **three socket taps** — Z80, **main ROM UD11** (the Pico serves the ROM window, so no ROM part is needed — ROM 2.00), char-gen UA15. Rev 0 passive probe superseded (kept for record) | #11, #12, #13, #15, #83 | Rev A ES schematic generated, ready for KiCad capture review + routing. The UD11 tap and its daughterboard are new and belong in #12's interface spec |
| `front-panel-ui/` | Front panel faceplate & UI pod — SD/USB storage, **HDMI out**, OLED, FlashFloppy-style controls, modem LED bank | #14 | Concept |
| `usb-keyboard-adapter/` | Standalone RP2040 USB-HID → P4 keyboard adapter ("jam a USB keyboard into an O1"); two power variants: internal +12V (J6) or external powered-hub for no-open-case use | #47 | Reference design defined; spec validation pending |
| `wifi-modem-module/` | Severable WiFi modem (ESP32 Zimodem fork: telnet + SSH, baud buffering) for the MODEM (P1) TTL port; ships with COMM PAC-look case STLs for the left storage pocket | #56, #21, #57 | Concept; P1/DE-9 pinout + levels documented |
| `drive-c/` | Standalone Drive C reproduction — IEEE-488 on **P3**, RP2040 + flash, powered off the **P5** video shunt (which also yields composite video). No interposer, no Z80 socket; the same firmware doubles as the #22 personality | #84, #6 | Concept; blocked on the #6 command set |
| `floppy-adapter/` | Switchable Gotek/physical-drive daughter card on the mainboard floppy connector — both physical drives *or* Gotek-as-drive-A + physical B, remote switch, switched Gotek 5 V; no cable cutting | #62, #20, #95 | Rev A schematic captured (`floppy-adapter.kicad_sch`); open questions settled (design doc §8); ready for footprint/routing review |
| `o1ng/` | O1 Next Generation — **two boards, one machine**. **LFF board**: a 1:1 mainboard replacement for a real **OCC1 or OCC1A** chassis (socketed DIP-40 Z80, interposer as upgrade path; KiCad skeleton in `o1ng/o1ng-lff/`) — the restoration path, *not* the O1NG. **SFF board**: fully integrated, deliberately *not* a 1:1 swap, usable in a real chassis or any other design. **The O1NG is the SFF board with the machine wrapped around it** (~8 cm, 8 MHz turbo-capable, onboard flash library, USB-C PD) | #49, #52, #53, #55 | LFF schematic skeleton generated; concept render exists |

## Cross-cutting decisions (settled)

- **Level shifting:** 74AHCT/74HCT for anything touching the Z80 bus —
  all O1s are NMOS Z80s (research-gaps #2, resolved 2026-10-09).
- **Interposer power:** dedicated 5 VDC feed near the Z80 socket, sized
  for Pico 2 W WiFi bursts (~300 mA+).
- **Standalone USB power (added 2026-10-14, #207):** one 5 V net carries the
  Pico 2 W **and** the library flash, and that net is reachable from USB alone
  — so the board runs, and its flash is programmable, with no host machine, no
  Z80 socket and no chassis supply. Preparing a board (fill the library, then
  install it) is a bench procedure, not something that needs a donor machine
  open. Required for the interposer **and** the SFF board (`o1ng/`).
- **Stacking:** the interposer must coexist with SCREEN-PAC and
  CoPower-88 interposers on the fully-loaded host machine.
- **Socket taps: three.** The Z80 seat (the bus), the **main ROM socket UD11** (the
  ROM window — the Pico serves it, added 2026-10-13 for ROM 2.00 / #83) and the
  **char-gen socket UA15** (the font). A 24-pin 2732 socket carries no `A12`, no
  `A13` and no write strobe, so a *part* in it can never exceed 4 KB — but when the
  Pico serves the window those lines are irrelevant, because the bank is which 4 KB
  the firmware presents.
- **One ROM 2.00, and on a real machine no ROM part at all.** The same image runs
  on OEM board + interposer, LFF board + interposer (both with the socket empty and
  the Pico serving the window) and the SFF board. Because the LFF board is a
  faithful recreation of *just* the OEM board with DD built in, **LFF + interposer ≡
  OEM + interposer** — one interposer brief, one ROM image, one test matrix. An LFF
  board on its own still takes a standard 1.44 ROM, so the restoration path boots
  stock. See `interposer/README.md` and `docs/o1-rom-2.0.md`.
- **MODEM port (P1) is TTL, not RS-232** — but its RXD is a bipolar
  input; the modem module must swing TX-toward-O1 negative for a clean
  mark. See `docs/o1-modem-serial.md`.
- **P4 keyboard connector:** pin 19 = +12V via jumper J6 + R21 — usable
  to power small adapter boards (see `usb-keyboard-adapter/`).

## Conventions

Each device folder contains a `README.md` with: purpose, host
interfaces, electrical/mechanical constraints, open questions, and links
to the tracking issues and supporting docs. KiCad projects land in the
same folders as `<device>.kicad_pro` when design begins.
