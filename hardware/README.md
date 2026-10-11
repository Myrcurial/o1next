# hardware/

Hardware device definitions for the o1nextgen project. Each subfolder is
one physical device contemplated in the GitHub issues, holding its
interface spec, design decisions, and (eventually) KiCad design files.
Status ranges from "concept definition" to "ready for schematic entry" —
no PCB layouts exist yet (Phase 1, issue #11).

## Devices

| Folder | Device | Issues | Status |
|---|---|---|---|
| `interposer/` | Z80 bus interposer — the core board. **Rev A engineering sample** (`interposer/reva/`, 2-off, SMD): active interposer w/ SMT Z84C00, /BUSRQ bus mastering (memory R/W + code injection), Pico 2 + ESP32-C3, W25Q library flash. Rev 0 passive probe superseded (kept for record) | #11, #12, #13, #15 | Rev A ES schematic generated, ready for KiCad capture review + routing |
| `front-panel-ui/` | Front panel faceplate & UI pod — SD/USB storage, VGA/HDMI out, OLED, FlashFloppy-style controls, modem LED bank | #14 | Concept |
| `usb-keyboard-adapter/` | Standalone RP2040 USB-HID → P4 keyboard adapter ("jam a USB keyboard into an O1"); two power variants: internal +12V (J6) or external powered-hub for no-open-case use | #47 | Reference design defined; spec validation pending |
| `wifi-modem-module/` | Severable WiFi modem (ESP32 Zimodem fork: telnet + SSH, baud buffering) for the MODEM (P1) TTL port; ships with COMM PAC-look case STLs for the left storage pocket | #56, #21, #57 | Concept; P1/DE-9 pinout + levels documented |
| `drive-c-adapter/` | Standalone Drive C replacement — IEEE-488 on **P3**, RP2040 + flash, powered off the **P5** video shunt (which also yields composite video). No interposer, no Z80 socket; the same firmware doubles as the #22 personality | #84, #6 | Concept; blocked on the #6 command set |
| `floppy-adapter/` | Switchable Gotek/physical-drive daughter card on the mainboard floppy connector — both physical drives *or* Gotek-as-drive-A + physical B, remote switch, switched Gotek 5 V; no cable cutting | #62, #20, #95 | Rev A schematic captured (`floppy-adapter.kicad_sch`); open questions settled (design doc §8); ready for footprint/routing review |
| `o1ng/` | O1 Next Generation — modern-parts Osborne 1 reproduction: faithful 1:1 replacement mainboard (socketed DIP-40 Z80, interposer as upgrade path; block-level KiCad skeleton in `o1ng/o1ng-lff/`) + fully integrated "lunchbox" portable (8 MHz turbo-capable, onboard flash library), shared USB-C PD power architecture | #49, #52, #53, #55 | LFF schematic skeleton generated; concept render exists |

## Cross-cutting decisions (settled)

- **Level shifting:** 74AHCT/74HCT for anything touching the Z80 bus —
  all O1s are NMOS Z80s (research-gaps #2, resolved 2026-10-09).
- **Interposer power:** dedicated 5 VDC feed near the Z80 socket, sized
  for Pico 2 W WiFi bursts (~300 mA+).
- **Stacking:** the interposer must coexist with SCREEN-PAC and
  CoPower-88 interposers on the fully-loaded host machine.
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
