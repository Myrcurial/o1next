# hardware/

Hardware device definitions for the o1next project. **One folder per board, and
the folder name is the board's name** — each folder holds that board's interface
spec, design decisions and (eventually) its KiCad project. Status ranges from
"concept definition" to "ready for schematic entry" — no PCB layouts exist yet
(Phase 1, issue #11).

## The board register

**This table is the one place the boards are named.** One row per physical board:
the **shortform** (which is also its folder), the name it is described by, where
it lives, what tracks it, where it stands, and the name
`tools/check_schematics.py` knows it by. Every other file in `hardware/` defers
here rather than restating a board's name or state, and `tools/check_boards.py`
fails if this table, the netlist checker and `site/hardware/` disagree. The names
are the maintainer's, from the 2026-10-19 board list on #308.

| Shortform | Board | Home | Tracking issues | State | Schematic |
|---|---|---|---|---|---|
| `floppy-adapter` | O1NEXT Floppy Adapter | `hardware/floppy-adapter/` | #62, #20, #95 | Floppy Adapter's Rev A schematic captured; no PCB. **Deliverable 1** — processor-less; adds a Gotek as a third drive on any O1, with nothing cut | `floppy-adapter` |
| `keyboard-adapter` | O1NEXT USB Keyboard Adapter | `hardware/keyboard-adapter/` | #47 | Reference design; spec validation pending. **No schematic yet** (#47). **Deliverable 2** | — |
| `wifi-comm-pac` | O1NEXT WiFi COMM PAC | `hardware/wifi-comm-pac/` | #56, #21, #57 | Concept; P1/DE-9 pinout and levels documented. **No schematic yet** (#56). **Deliverable 3** | — |
| `drive-c-repro` | O1NEXT Drive C Repro | `hardware/drive-c-repro/` | #84, #6 | Concept; blocked on the #6 command set. **No schematic yet** (#84). **Deliverable 4** | — |
| `interposer-upgrade` | O1NEXT Upgrade — the interposer, **one unit in four parts** | `hardware/interposer-upgrade/` | #11, #12, #13, #15, #83, #259, #297, #303, #304 | Rev A engineering-sample schematic generated; Rev B is a pin map and has **no schematic yet** (#259). **Deliverable 5** — it subsumes the three boards above it | `interposer-upgrade-reva`, `interposer-upgrade-rev0` |
| `next-integrated` | O1NEXT Integrated — the SFF board | `hardware/next-integrated/` | #49 | Concept. **No schematic yet** (#49). **Deliverable 6** — the board the project is named for | — |

### `interposer-upgrade` is one unit in four parts

One delivery, four parts. Only the first has a KiCad project today:

| Part | Home |
|---|---|
| the interposer board itself — `Rev 0` → `Rev A` → `Rev B` | `hardware/interposer-upgrade/` |
| the **UI pod** — the ribbon-cabled faceplate (#14) | `hardware/interposer-upgrade/ui-pod/` |
| the **ROM socket tap** — the UD11 daughterboard the Pico serves the ROM window through | *no directory yet* — the signal list is #12's |
| the **character ROM socket tap** — UA15, the font | *no directory yet* |

### Not boards

- **`O1NEXT Complete` — the machine.** Deliverable 7: the `next-integrated` board
  with a case, an 8" panel, an 18650 pack and a keyboard. It is not a board, so it
  has no row above and no folder of its own — its description is
  `site/hardware/o1next-complete.md` and the render is
  `docs/design/o1next-lunchbox-concept.*` (#52, #53).
- **An LFF (large form factor) 1:1 mainboard — possible, not planned.** A faithful
  OCC1/OCC1A mainboard recreation, with the Z80 left socketed so the interposer
  stays the upgrade path, is *possible* if a chassis ever needs restoring. It was
  sketched once — cpu_mem / video / floppy / io / keyboard / power / clock, L-shaped
  with four mounting screws, in the git history — and it is **discarded as a
  deliverable** (maintainer, 2026-10-19): no directory, no schematic, nothing to
  build, nothing to check. #49 is where it would start if it were ever wanted.

**Not ours:** board names, and `Rev A`/`Rev B` hits, under `research/` or
describing an early Osborne 1 ROM, refer to other people's hardware. They are not
project boards — see the vocabulary note below.

**Delivery order:** `floppy-adapter` → `keyboard-adapter` → `wifi-comm-pac` →
`drive-c-repro` → `interposer-upgrade` → `next-integrated` → `O1NEXT Complete`.

## How the boards relate

- The **four standalone boards** hang off ports the machine already exposes — the
  floppy header, P4, P1/DE-9, and P3 + P5. None needs the interposer, none changes
  the BIOS, and nothing in the machine or its cables is cut.
- **`interposer-upgrade`** (the O1NEXT Upgrade) is the board on the Z80 bus, and it
  is **one unit in four parts** (the board, the UI pod, and the two ROM socket
  taps). It **can act as any one of the first three boards** and offers every
  personality, so if you have it you don't need them. On a real machine it also
  serves the ROM window, so no ROM part is needed at all.
- **`next-integrated`** (the O1NEXT Integrated, the SFF board) is that same
  capability **designed in as firmware rather than stacked on**. That makes the
  interposer the **precursor of the SFF, not a separate product from it**: the SFF
  can replace the interposer, and the interposer cannot replace the SFF.
- **`O1NEXT Complete`** is the `next-integrated` board with the machine wrapped
  around it.
- **The LFF 1:1 mainboard is not in this set.** It remains *possible* (see *Not
  boards*), and if it were ever built it would sit *under* the interposer exactly
  as an OEM board does — **LFF + interposer ≡ OEM + interposer** — which is why it
  has no ROM path and no test matrix of its own.

## One vocabulary for the names and the revision letters

- **The shortform is the board's name.** `floppy-adapter`, `keyboard-adapter`,
  `wifi-comm-pac`, `drive-c-repro`, `interposer-upgrade`, `next-integrated` — the
  folder, the site URL (`/hardware/<shortform>/`) and the netlist checker all use
  it. The longer forms (`O1NEXT Upgrade` and friends) are how a board is *described*
  to a reader, and they are the site's page titles. Nothing else is a name.
- **In `hardware/`, an unqualified `Rev 0` / `Rev A` / `Rev B` is
  `interposer-upgrade`'s** — the interposer's own revisions. **Rev 0** is the probe
  (superseded), **Rev A** the engineering sample, **Rev B** the production
  revision. The interposer is **one board**: Rev B is not a second product, it is
  Rev A's instrument *plus* the live-cycle engine (74AHCT688 + `/WAIT`) on the same
  board, with `/BUSRQ` mastering kept. That is the collapse **#259** decided; #13
  and #15 are absorbed by it.
- **Everywhere else the owner is named**: the **Floppy Adapter's** Rev A/Rev B (an
  unrelated board — `docs/floppy-adapter-design.md`); the **Osborne 1 monitor ROM's
  rev B** (a 1979 ROM, not a board — `docs/o1-rom-read-from-machine.md`);
  **gusmanb/logicanalyzer's Rev A** (someone else's board —
  `docs/interposer-survey.md`).
- **A document about exactly one board binds the letters for itself**, and says so
  at the top: `docs/floppy-adapter-design.md` and the ROM documents each carry a
  one-line vocabulary note, and that note is what makes their unqualified `Rev A` /
  `rev B` unambiguous. A file that has no such note must qualify.
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
  open. Required for the interposer and the `next-integrated` board; every
  standalone board is bench-preparable for the same reason.
- **Stacking:** the interposer must coexist with SCREEN-PAC and
  CoPower-88 interposers on the fully-loaded host machine.
- **Socket taps: three.** The Z80 seat (the bus), the **main ROM socket UD11** (the
  ROM window — the Pico serves it, added 2026-10-13 for ROM 2.00 / #83) and the
  **char-gen socket UA15** (the font). A 24-pin 2732 socket carries no `A12`, no
  `A13` and no write strobe, so a *part* in it can never exceed 4 KB — but when the
  Pico serves the window those lines are irrelevant, because the bank is which 4 KB
  the firmware presents. The UD11 and UA15 taps are two of the four parts of
  `interposer-upgrade`.
- **One ROM 2.00, and on a real machine no ROM part at all.** The same image runs
  on OEM board + interposer and on the `next-integrated` board (with the socket
  empty and the Pico serving the window). Because the OEM board is the reference
  the interposer was designed against, **OEM + interposer** is the one host brief
  and the one test matrix — and a 1:1 LFF recreation, if one is ever made, would be
  equivalent. See `interposer-upgrade/README.md` and `docs/o1-rom-2.0.md`.
- **MODEM port (P1) is TTL, not RS-232** — but its RXD is a bipolar
  input; the modem module must swing TX-toward-O1 negative for a clean
  mark. See `docs/o1-modem-serial.md`.
- **P4 keyboard connector:** pin 19 = +12V via jumper J6 + R21 — usable
  to power small adapter boards (see `keyboard-adapter/`).
- **A board is named once, in the register above.** The shortform is the name; a
  folder is not a separate identity. A board with no folder says so there, with the
  issue that will give it one.

## Conventions

Each board folder is named for its **shortform** and contains a `README.md` with
that board's name, a pointer to the register above, purpose, host interfaces,
electrical/mechanical constraints, open questions, and links to the tracking issues
and supporting docs. KiCad projects land in the same folders as
`<board>.kicad_pro` — and every folder with a `.kicad_sch` is covered by
`tools/check_schematics.py` (the register's `Schematic` column is that tool's board
name).
