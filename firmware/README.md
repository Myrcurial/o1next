# firmware/

Firmware deliverables for the o1next project, one folder per
component. Three target platforms: **RP2354B** (the
interposer), **ESP32** (WiFi modem, shared between the severable module
and the interposer-onboard option), and **RP2040** (keyboard matrix
injection, shared between the standalone adapter and the KVM/second-
keyboard path).

See `software/` for code that runs on the Osborne itself (CP/M) and
`tools/` for host-side utilities.

## Components

| Folder | Platform | Component | Issues | Difficulty |
|---|---|---|---|---|
| `bus-analyzer/` | RP2354B | Passive cycle-accurate bus capture → USB/WiFi; includes the shared memory-map snoop/poke engine all personalities build on | #17 | Hard (timing-critical) |
| `rt60a-rtc/` | RP2354B | RT-60A real-time clock register emulation | #18, #37 | Easy |
| `virtual-printer/` | RP2354B | Virtual Epson MX-80: Centronics-on-IEEE-488 capture → on-device 9-pin raster → PDF (with tractor-feed page edges) over HTTP | #19 | Medium |
| `floppy-emulator/` | RP2354B | MFM flux interposer + `.IMD`/`.HFE` image library ("Drive C" RAM disk option) | #20 | Hardest |
| `drive-c-gpib/` | RP2354B | Drive C IEEE-488 ramdisk/storage device personality, incl. the **TurboPac** variant (Drive C as cache in front of a Trantor hard disk) | #22, #6 | Medium |
| `acb4000-scsi/` | RP2354B | Adaptec ACB-4000 SCSI-1 target (the MD-10's controller) — portable: one SCSI personality + a configurable host-adapter shim serves any Z80 machine with an ACB-4000-class driver | #8, #179 | Medium — target, shim and store built and host-tested (`run_tests.sh`, CI); the FAT32 store (#180) and the end-to-end acceptance are open |
| `screenpac-video/` | RP2354B | SCREEN-PAC 80/104-col video + **HDMI out**; char-gen socket tap, reads installed font ROM at init | #24, #44 | Medium-hard |
| `kvm-console/` | RP2354B + RP2040 | Web KVM: video snoop (reuses screenpac-video) + keyboard matrix injection (reuses keyboard-matrix) | #45 | Medium (composition) |
| `copower88-shim/` | RP2354B | Virtual CoPower-88: 8088 emulation + host mailbox protocol so SWP software runs without the physical board | #23, #3-#5 | Hardest; sequence last |
| `web-ui/` | RP2354B | C64 Ultimate-style HTTP interface: image library, modem, printer PDFs, status, control | #16, #27 | Medium |
| `zimodem-fork/` | ESP32 | Zimodem fork: Hayes/telnet baseline + SSH + double-sided baud-rate buffer | #21, #56 | Medium (fork-and-extend) |
| `keyboard-matrix/` | RP2040 | TinyUSB HID host → 8×8 matrix injection; shared by the standalone adapter, KVM, and front-panel USB port | #47, #45, #14 | Easy-medium |
| `rom-ident/` | RP2354B (host-testable) | Identify the fitted ROM at boot by CRC32 (table generated from `docs/o1-rom-variants.md`) and gate the personalities on it: refuses Drive C / printer under OZROM 1E, degrades video to a warning | #86 | Gate + table done and tested; the socket read needs a board |
| `rom-service/` | RP2354B | The ROM↔interposer channel: the **ROM-service** command class (`PRESENT`, `INFO`) on **two doors** — userland I/O `0E7h`/`0EBh`, and the ROM's own bank-2 pair `2800h`/`2801h` (**not** `2300h`/`2301h`, which is the floppy's track register and the keyboard's row 0) — and the boot screen in the RP2354B's own flash: `boot-animation.bin`, the animation the **RP2354B plays itself** | #247, #277, #278 | Easy-medium — the C module is **not written yet**, and that is this folder's work (#284); the contract is `docs/rom-pico-protocol.md`. The animation is not generated in-repo, and `bootanim.py --check` is its format check. The ROM-side frame path — `PRESENT(1)`/`(2)`/`(3)`, and the committed `frame.bin` and `screen.bin` — was retired 2026-10-16/17 (#278) |
| `library/` | RP2354B (host-testable) | The **image library**, the **mailbox engine** and the **media layer**: three media (external SPI flash + one microSD + one USB stick) merged into one namespace, the `floppy/`/`disk/`/`printer/` layout, the kind and size rules, the mount table, the protocol's opcode dispatch for both doors, **FatFS R0.15 vendored** and the block-device seam beneath it | #283, #285, #192; serves #20, #27, #181, #182 | **Built and host-tested** (`run_tests.sh`, CI) — no board, no SDK; the library and protocol run over a directory tree *and* over three real FAT volumes the suite formats itself. The board's transports (SPI to the NOR flash, microSD, USB MSC) and the NOR FTL are the follow-up to #285 |

## Project rule

**If we hold the drivers for a piece of period hardware, we plan a
personality for it.** Existing drivers mean zero Osborne-side software
work and a known-good test suite — these personalities are pure win.
(Current examples: Drive C, the ACB-4000/MD-10 hard disk, RT-60A.)

## Cross-cutting constraints

- **Radio jitter — and why it is no longer the interposer's problem.** The
  interposer used to carry a **radio-bearing module**, whose CYW43439 sat
  alongside the MCU and added jitter to bus capture and MFM flux emulation.
  **That is no
  longer the design**: the board carries the bare **RP2354B** part — which is where
  the firmware and the boot screen's assets live — and the radio is an **ESP32 on UART0**
  (GP38/39). So the jitter source has moved *off* the bus-critical chip entirely,
  which is strictly better for every personality. The rule becomes a **link**
  rule rather than a fencing rule: the ESP32 is never asked for anything inside a
  capture or flux window, and the UART link is the only thing crossing between
  them. (Corrected 2026-10-15: this section named the module's radio part, which
  is a module we no longer fit.)
- **One modem codebase:** the ESP32 Zimodem fork serves both the severable module
  and the interposer's onboard ESP32. **The variant is not yet chosen** — C3, C5
  (dual band) or S3/S3A (SSH headroom) — and the decision needs the modem's own
  requirements written down first; see #21, #56 and
  `hardware/interposer/README.md`.
- **Level shifting** is a hardware concern (74AHCT/HCT) — firmware
  assumes clean 3.3 V logic at the RP2354B pins.
