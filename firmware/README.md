# firmware/

Firmware deliverables for the o1nextgen project, one folder per
component. Three target platforms: **RP2350** (Pico 2 W on the
interposer), **ESP32** (WiFi modem, shared between the severable module
and the interposer-onboard option), and **RP2040** (keyboard matrix
injection, shared between the standalone adapter and the KVM/second-
keyboard path).

See `software/` for code that runs on the Osborne itself (CP/M) and
`tools/` for host-side utilities.

## Components

| Folder | Platform | Component | Issues | Difficulty |
|---|---|---|---|---|
| `bus-analyzer/` | RP2350 | Passive cycle-accurate bus capture → USB/WiFi; includes the shared memory-map snoop/poke engine all personalities build on | #17 | Hard (timing-critical) |
| `rt60a-rtc/` | RP2350 | RT-60A real-time clock register emulation | #18, #37 | Easy |
| `virtual-printer/` | RP2350 | Virtual Epson MX-80: Centronics-on-IEEE-488 capture → on-device 9-pin raster → PDF (with tractor-feed page edges) over HTTP | #19 | Medium |
| `floppy-emulator/` | RP2350 | MFM flux interposer + `.IMD`/`.HFE` image library ("Drive C" RAM disk option) | #20 | Hardest |
| `drive-c-gpib/` | RP2350 | Drive C IEEE-488 ramdisk/storage device personality, incl. the **TurboPac** variant (Drive C as cache in front of a Trantor hard disk) | #22, #6 | Medium |
| `acb4000-scsi/` | RP2350 | Adaptec ACB-4000 SCSI-1 target (the MD-10's controller) — portable: one SCSI personality + a configurable host-adapter shim serves any Z80 machine with an ACB-4000-class driver | #8 | Medium |
| `screenpac-video/` | RP2350 | SCREEN-PAC 80/104-col video + **HDMI out**; char-gen socket tap, reads installed font ROM at init | #24, #44 | Medium-hard |
| `kvm-console/` | RP2350 + RP2040 | Web KVM: video snoop (reuses screenpac-video) + keyboard matrix injection (reuses keyboard-matrix) | #45 | Medium (composition) |
| `copower88-shim/` | RP2350 | Virtual CoPower-88: 8088 emulation + host mailbox protocol so SWP software runs without the physical board | #23, #3-#5 | Hardest; sequence last |
| `web-ui/` | RP2350 | C64 Ultimate-style HTTP interface: image library, modem, printer PDFs, status, control | #16, #27 | Medium |
| `zimodem-fork/` | ESP32 | Zimodem fork: Hayes/telnet baseline + SSH + double-sided baud-rate buffer | #21, #56 | Medium (fork-and-extend) |
| `keyboard-matrix/` | RP2040 | TinyUSB HID host → 8×8 matrix injection; shared by the standalone adapter, KVM, and front-panel USB port | #47, #45, #14 | Easy-medium |
| `rom-ident/` | RP2350 (host-testable) | Identify the fitted ROM at boot by CRC32 (table generated from `docs/o1-rom-variants.md`) and gate the personalities on it: refuses Drive C / printer under OZROM 1E, degrades video to a warning | #86 | Gate + table done and tested; the socket read needs a board |

## Project rule

**If we hold the drivers for a piece of period hardware, we plan a
personality for it.** Existing drivers mean zero Osborne-side software
work and a known-good test suite — these personalities are pure win.
(Current examples: Drive C, the ACB-4000/MD-10 hard disk, RT-60A.)

## Cross-cutting constraints

- **Radio jitter:** CYW43 activity adds jitter — bus capture and MFM
  flux emulation run pinned to core1/PIO with WiFi IRQs fenced off, or
  WiFi is gated during capture/flux windows.
- **One modem codebase:** the ESP32 Zimodem fork serves both the
  severable module and (leaning) an interposer-onboard ESP32; see
  `hardware/interposer/README.md` for the decision record.
- **Level shifting** is a hardware concern (74AHCT/HCT) — firmware
  assumes clean 3.3 V logic at the RP2350 pins.
