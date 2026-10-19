# next-integrated — the O1NEXT Integrated (the SFF board)

**Board:** `next-integrated` — the **O1NEXT Integrated**, the small-form-factor
board the project is named for. Register:
[`../README.md`](../README.md). Tracks **#49** (feasibility + build), **#52**
(case + power), **#53** (concept render: `docs/design/o1next-lunchbox-concept.*`).
**No schematic yet** — #49 is the issue that produces one.

A new PCB built from currently-available components that runs the actual
Osborne 1 ROMs and (nearly) all original software — with a Cherry MX
mechanical keyboard, the interposer's floppy/modem/printer/storage
personalities onboard, and **HDMI video out**.

**Verdict from #49: feasible, medium complexity.** The O1 is almost
entirely memory-mapped commodity MSI/LSI — no custom silicon. CPUs are a
non-issue: CMOS **Z84C00 is in current production** (the replica
deliberately uses modern CMOS silicon where the interposer interfaces
AHCT to the original NMOS part).

## What it is, in one sentence

**It is the interposer's capability designed in as firmware instead of stacked
on.** The interposer (`interposer-upgrade`) carries that capability on a board
that plugs into a real machine; this board puts it on the machine's own PCB. So
the SFF can replace the interposer and the interposer cannot replace the SFF —
the interposer is this board's **precursor**, not a competing product.

## Machine decomposition (by difficulty)

| Block | Approach | Difficulty |
|---|---|---|
| CPU + RAM + ROM | Z84C00 (new), 64 KB SRAM (replaces 16× 4116 DRAM + refresh), **ROM 2.00** in a 27C128/Flash part — the *same image* the interposer runs (#83, see below) | Trivial |
| Video | Char-gen + CRTC-class logic; **HDMI out only** — the RP2354B drives it, and this board carries **no composite driver circuitry at all** (interposer video personality reusable) | Moderate |
| Floppy | 360K half-height drive + onboard DD data separator (enables PC 360K MFM reads → FATCOPY, #51) | Moderate |
| I/O (serial/GPIB/RTC) | 6850 ACIA, IEEE-488, RTC — interposer personalities onboard | Moderate |
| Keyboard | Cherry MX matrix; O1-compatible scan encoding | Low–moderate |

## Shared power architecture (#52)

- **USB-C PD trigger board** as primary input: 15 VDC (or 19–20 V) PD →
  clean on-board +5V and +12V rails. Replaces the entire original PSU —
  and gets the RIFA caps out of the mix.
- **Battery option:** a ~15–19 V input rail suits an 18650 pack (4S).
- **Prep from USB alone (added 2026-10-14, #207):** the board must be
  preparable on the bench — Pico and library flash powered, and the flash
  programmable — from a plain USB 5 V feed, before the PD trigger, the 15 V
  rail or the chassis exists. PD negotiation is what the *finished machine*
  needs; it must not gate the step that fills the library flash. Same
  requirement on the interposer (`../interposer-upgrade/README.md`).

## It shares one ROM with the interposer

ROM 2.00 (#83) is a single image with a single layout, and it runs on **both**
paths: OEM board + interposer, and this board. On the first the interposer
**serves the ROM window from the Pico**, through a daughterboard that takes the
ROM socket, so no physical ROM part is needed at all; here the same capability is
grafted in with the board's own flash. Because the OEM board is what the
interposer was designed against, **OEM + interposer** is the one host brief and
the one test matrix. See `../interposer-upgrade/README.md` (*Tap points*) and
`docs/o1-rom-2.0.md`.

## Not a 1:1 swap, and it does not try to be

**The board goes in a real chassis or into any other design, up to the end user**,
with nothing constrained by a 1982 footprint. The interposer's capability set
(video, storage, modem, keyboard input) is thoroughly grafted in rather than
stacked on, following the original design language. One reason: integration keeps
the timing margins needed for the **clock-doubled 8 MHz "business turbo"** (#55) —
limited usefulness, but everyone will be fine with it. **Onboard library flash**
(SPI NOR, per the `interposer-upgrade` decision): a built-in diskette library with
at least the boot diskette, so the machine boots "factory" images with no SD/USB
inserted; removable media remains the bulk store.

**There is no 1:1 restoration board in the set.** A faithful OCC1/OCC1A
recreation, with the Z80 left socketed so the interposer stays the upgrade path,
is *possible* if a chassis ever needs restoring — but it is **discarded as a
deliverable** and has no directory. See *Not boards* in
[`../README.md`](../README.md).

## I/O complement (settled 2026-10-11)

The connector set is decided, and it is deliberately **not** the original
machine's complement: what is kept is kept because period hardware and software
need it, and what is dropped is dropped because a personality replaces it.

| Function | Connector | Note |
|---|---|---|
| Serial | **DB-25 (P2)** | The RS-232C port, 6850 ACIA-driven, pinout per `docs/o1-modem-serial.md` |
| IEEE-488 | **Edge connector (P3)** | The GPIB / Drive C bus, as on the original |
| Keyboard | **24-position (P4)** | The original keyboard interface, so a real O1 keyboard can be used |
| Video | **HDMI out** | Adjacent to the **RESET** and **TURBO** buttons |
| Storage | **SD / microSD slot** | The bulk removable store |
| Expansion | **USB-A #1** | **Fixed function**: memory expansion, the same role as the SD/microSD slot |
| Keyboard (USB) | **USB-A #2** | **Fixed function**: the USB keyboard |

The two USB-A ports are **fixed function** on purpose — neither is a
general-purpose host, so neither needs a hub, a driver stack, or a negotiation
story.

### Video: HDMI in, and nothing else

- **8" 1024×768 HDMI internal panel**, plus an **external HDMI port**. This is
  possible because the **RP2354B drives HDMI** directly and because that panel size
  and resolution are readily available off the shelf.
- **There is no composite driver circuitry on this board.** The discrete analogue
  chain an OEM board carries is simply not reproduced here, so this board has no
  composite output to offer at all.

### Deliberately absent

- **The MODEM port (P1) is not carried.** P1 is a TTL tap onto the same 6850 ACIA
  the RS-232 port uses, and the modem is now a **firmware personality** — so the
  physical port has nothing left to do. The DB-25 RS-232 port stays.

## The machine it becomes

**`O1NEXT Complete` is this board with the rest of the machine wrapped around
it** — the logical equivalent of the **C64 Ultimate "Crystal" edition**: an homage
that gives the end user *everything* that would have been possible in the olden
days, wrapped in a way that makes it awesome. The machine that was an absolute
fantasy in 1985 and is do-able by a hobbyist today.

Concretely: the **Dolch / Compaq Portable III idiom in O1A blue/grey industrial
design**, with the "keyboard seals the unit" aesthetic retained. ~8 cm thick: this
board + **8" 1024×768 (4:3) HDMI panel** + 18650 pack, detachable flip-up
keyboard. Optional rear "backpack" for a physical 5.25" half-height drive. The
machine is not a board and has no folder — see *Not boards* in
[`../README.md`](../README.md) and `site/hardware/o1next-complete.md`.

## Open questions

- Final video pipeline choice (discrete TTL vs small FPGA helper).
- LCD panel **part selection** — the target is a stock 8" 1024×768 HDMI panel,
  which is the easy part; mounting it is the work.
- Chassis fabrication route (sheet metal vs printed).
- Which interposer personalities are *onboard* vs *optional modules*.

## References

- `docs/design/o1next-lunchbox-concept.pdf` / `.svg` (#53)
- `docs/o1-memory-io-map.md` (the machine's whole address space)
- Issues #49 (reproduction), #52 (case/power), #51 (FATCOPY)
