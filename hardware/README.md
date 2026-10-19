# hardware/

Hardware device definitions for the o1next project. Each subfolder is one
physical device contemplated in the GitHub issues, holding its interface spec,
design decisions, and (eventually) KiCad design files. Status ranges from
"concept definition" to "ready for schematic entry" — no PCB layouts exist yet
(Phase 1, issue #11).

## The board register

**This table is the one place the boards are named.** One row per physical board:
the name the maintainer gave it, where it lives, what tracks it, where it stands,
and the name `tools/check_schematics.py` knows it by. Every other file in
`hardware/` defers here rather than restating a board's name or state, and
`tools/check_boards.py` fails if this table, the netlist checker and
`site/hardware/` disagree. The canonical names are the maintainer's, from the
2026-10-19 board list on #308.

| Board | Home | Tracking issues | State | Schematic |
|---|---|---|---|---|
| **O1NEXT Floppy Adapter** | `hardware/floppy-adapter/` | #62, #20, #95 | Floppy Adapter's Rev A schematic captured; no PCB. **Deliverable 1** — processor-less; adds a Gotek as a third drive on any O1, with nothing cut | `floppy-adapter` |
| **O1NEXT USB Keyboard Adapter** | `hardware/usb-keyboard-adapter/` | #47 | Reference design; spec validation pending. **No schematic yet** (#47). **Deliverable 2** | — |
| **O1NEXT WiFi COMM PAC** | `hardware/wifi-modem-module/` | #56, #21, #57 | Concept; P1/DE-9 pinout and levels documented. **No schematic yet** (#56). **Deliverable 3** | — |
| **O1NEXT Drive C Repro** | `hardware/drive-c/` | #84, #6 | Concept; blocked on the #6 command set. **No schematic yet** (#84). **Deliverable 4** | — |
| **O1NEXT Upgrade** — the interposer | `hardware/interposer/` | #11, #12, #13, #15, #83, #259, #297, #303, #304 | Rev A engineering-sample schematic generated; Rev B is a pin map and has **no schematic yet** (#259). **Deliverable 5** — it subsumes the three boards above it | `reva`, `rev0` |
| **O1NEXT Integrated** — the SFF board | *no directory yet* — #49 makes it | #49 | Concept. **No schematic yet** (#49). **Deliverable 6** — the board the project is named for, and it has no home in the tree yet | — |
| **LFF board** | `hardware/o1next/o1next-lff/` | #49, #52, #53, #55 | Block-level KiCad skeleton. **Won't build** (maintainer, 2026-10-19) — the restoration path, not the O1NEXT. The stub idea is kept | `lff` |
| **O1NEXT Complete** — the machine | *no directory of its own* — it is a machine, not a board (#49) | #49, #52, #53 | Concept render exists. **No schematic** — it is not a board (#49). **Deliverable 7** — the SFF board with case, screen, battery and keyboard | — |

**Not a board of its own:** `hardware/front-panel-ui/` (#14) is the **interface
pod of the O1NEXT Upgrade** — the ribbon-cabled faceplate carrying SD/USB, HDMI,
the OLED, the modem LED bank and the second-keyboard USB-A path. The maintainer's
board description places it inside the interposer, so it is a sub-board of the
Upgrade and not a separate product.

**Not ours:** board names, and `Rev A`/`Rev B` hits, under `research/` or
describing an early Osborne 1 ROM, refer to other people's hardware. They are not
project boards — see the vocabulary note below.

**Delivery order:** Floppy Adapter → USB Keyboard Adapter → WiFi COMM PAC →
Drive C Repro → O1NEXT Upgrade → O1NEXT Integrated → O1NEXT Complete.

## How the boards relate

- The **four standalone devices** hang off ports the machine already exposes —
  the floppy header, P4, P1/DE-9, and P3 + P5. None needs the interposer, none
  changes the BIOS, and nothing in the machine or its cables is cut.
- The **O1NEXT Upgrade** (the interposer) is the board on the Z80 bus. It **can
  act as any one of the first three boards** and offers every personality, so if
  you have it you don't need them. On a real machine it also serves the ROM
  window, so no ROM part is needed at all.
- The **O1NEXT Integrated** (the SFF board) is that same capability **designed in
  as firmware rather than stacked on**. That makes the interposer the **precursor
  of the SFF, not a separate product from it**: the SFF can replace the
  interposer, and the interposer cannot replace the SFF.
- The **LFF board** is the restoration path — a faithful recreation of *just* the
  OEM board, so **LFF + interposer ≡ OEM + interposer** and the interposer stays
  the upgrade. It will not be built.
- The **O1NEXT Complete** is the SFF board with the machine wrapped around it.

## One vocabulary for the revision letters

`Rev 0` / `Rev A` / `Rev B` named four unrelated things in this tree. They no
longer do:

- **In `hardware/`, an unqualified `Rev 0` / `Rev A` / `Rev B` is the O1NEXT
  Upgrade's** — the interposer's own revisions. **Rev 0** is the probe
  (superseded), **Rev A** the engineering sample, **Rev B** the production
  revision. The interposer is **one board**: Rev B is not a second product, it is
  Rev A's instrument *plus* the live-cycle engine (74AHCT688 + `/WAIT`) on the
  same board, with `/BUSRQ` mastering kept. That is the collapse **#259** decided;
  #13 and #15 are absorbed by it.
- **Everywhere else the owner is named**: the **Floppy Adapter's** Rev A/Rev B
  (an unrelated board — `docs/floppy-adapter-design.md`); the **Osborne 1 monitor
  ROM's rev B** (a 1979 ROM, not a board — `docs/o1-rom-read-from-machine.md`);
  **gusmanb/logicanalyzer's Rev A** (someone else's board —
  `docs/interposer-survey.md`).
- **A document about exactly one board binds the letters for itself**, and says so
  at the top: `docs/floppy-adapter-design.md` and the ROM documents each carry a
  one-line vocabulary note, and that note is what makes their unqualified
  `Rev A` / `rev B` unambiguous. A file that has no such note must qualify.
- **LFF and SFF are form factors, not revisions** — they never use letters.

## Cross-cutting decisions (settled)

- **Level shifting:** 74AHCT/74HCT for anything touching the Z80 bus —
  all O1s are NMOS Z80s (research-gaps #2, resolved 2026-10-09).
- **Interposer power:** dedicated 5 VDC feed near the Z80 socket, sized
  for RP2354B WiFi bursts (~300 mA+).
- **Standalone USB power (added 2026-10-14, #207):** one 5 V net carries the
  RP2354B **and** the library flash, and that net is reachable from USB alone
  — so the board runs, and its flash is programmable, with no host machine, no
  Z80 socket and no chassis supply. Preparing a board (fill the library, then
  install it) is a bench procedure, not something that needs a donor machine
  open. Required for the interposer and the O1NEXT Integrated board; every
  standalone device is bench-preparable for the same reason.
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
  the Pico serving the window) and the O1NEXT Integrated board. Because the LFF
  board is a faithful recreation of *just* the OEM board with DD built in, **LFF +
  interposer ≡ OEM + interposer** — one interposer brief, one ROM image, one test
  matrix. An LFF board on its own still takes a standard 1.44 ROM, so the
  restoration path boots stock. See `interposer/README.md` and
  `docs/o1-rom-2.0.md`.
- **MODEM port (P1) is TTL, not RS-232** — but its RXD is a bipolar
  input; the modem module must swing TX-toward-O1 negative for a clean
  mark. See `docs/o1-modem-serial.md`.
- **P4 keyboard connector:** pin 19 = +12V via jumper J6 + R21 — usable
  to power small adapter boards (see `usb-keyboard-adapter/`).
- **A board is named once, in the register above.** The register's name is the
  board's name; a folder is a home, not a name. A board with no folder says so
  there, with the issue that will give it one.

## Conventions

Each device folder contains a `README.md` with: its board's **canonical name**,
a pointer to the register above, purpose, host interfaces,
electrical/mechanical constraints, open questions, and links
to the tracking issues and supporting docs. KiCad projects land in the
same folders as `<device>.kicad_pro` when design begins — and every folder with
a `.kicad_sch` is covered by `tools/check_schematics.py` (the register's
`Schematic` column is that tool's board name).
