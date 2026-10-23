# hardware/

Hardware for the o1next project. **One folder per board, and the folder name is the
board's name** — the *shortform*. Each folder carries that board's spec, its
decisions and its KiCad project.

**No PCB layout exists yet** (Phase 1, #11); three boards have a schematic, three do
not, and the `State` column below is the per-board answer.

## The board register

**This is the one place the boards are named.** `tools/check_boards.py` fails if
this table, `tools/check_schematics.py` and `site/hardware/` stop agreeing. Paths
are relative to this directory, and a board's home is always
`hardware/<shortform>/`.

| Shortform | Board | Home | Tracking issues | State | Schematic |
|---|---|---|---|---|---|
| `floppy-adapter` | O1NEXT Floppy Adapter | `floppy-adapter/` | #62, #20, #95 | Rev A schematic complete and decided (solid-state switch, 2-pin panel lead) — **ready for PCB floorplan + routing** | `floppy-adapter` |
| `keyboard-adapter` | O1NEXT USB Keyboard Adapter | `keyboard-adapter/` | #47 | Reference design; **no schematic yet** (#47) | — |
| `wifi-comm-pac` | O1NEXT WiFi COMM PAC | `wifi-comm-pac/` | #56, #21, #57, #324, #325 | Rev A schematic captured; no PCB | `wifi-comm-pac` |
| `drive-c-repro` | O1NEXT Drive C Repro | `drive-c-repro/` | #84, #6 | Concept; **no schematic yet** (#84) | — |
| `interposer-upgrade` | O1NEXT Upgrade | `interposer-upgrade/` | #11, #12, #13, #15, #83, #259, #297, #303, #304 | Rev A engineering-sample schematic; Rev B is a pin map, **no schematic yet** (#259) | `interposer-upgrade-reva`, `interposer-upgrade-rev0` |
| `next-integrated` | O1NEXT Integrated (the SFF board) | `next-integrated/` | #49 | Concept; **no schematic yet** (#49) | — |

Delivery order: `floppy-adapter` → `keyboard-adapter` → `wifi-comm-pac` →
`drive-c-repro` → `interposer-upgrade` → `next-integrated` → `O1NEXT Complete`.

### `interposer-upgrade` is one board in four sections

Routed and separated by **mouse bites**, so it is assembled in **one pass** with a
single board-handling requirement. The two ROM taps are **air connected**: snapped
off, a tap sits in the machine's ROM socket, so its nets return through a pair of
header pin assemblies wired back-to-back.

| Part | Home |
|---|---|
| the interposer board — the main section | `interposer-upgrade/` |
| the UI pod (#14) — snap-off | `interposer-upgrade/ui-pod/` |
| the ROM socket tap (UD11) — snap-off | `interposer-upgrade/rom-tap/` |
| the char-gen ROM socket tap (UA15) — snap-off | `interposer-upgrade/chargen-tap/` |

## Not boards

| Shortform | What it is | Home | Tracking issues | State | Schematic |
|---|---|---|---|---|---|
| `o1next-complete` | O1NEXT Complete — **the machine** | `o1next-complete/` | #49, #52, #53, #125, #128 | Hardware: chassis CAD, print STLs and an assembly BOM, and the machine's own keyboard PCB (QMK-compatible, Cherry MX, Osborne 1 layout) is incidental to it. **No schematic** — it is CAD, not a PCB (#52) | — |
| — | an LFF (large form factor) 1:1 mainboard | *no directory* | #49 | **Possible, not planned** (2026-10-19): a faithful OCC1/OCC1A recreation with the Z80 socketed so the interposer stays the upgrade path. Nothing to build, nothing to check | — |

**Not ours:** `Rev A`/`Rev B` hits under `research/`, and the early Osborne 1 ROM's
`rev B`, are other people's hardware — see the vocabulary below.

## The relationship, and the vocabulary

- **The interposer is the SFF board's precursor, not a competitor.** It carries the
  same capability on a board that plugs into a real machine; `next-integrated`
  designs it in as firmware. So the SFF can replace the interposer, and not the
  reverse. The interposer **can also act as any one of the first three boards** —
  have it and you don't need them.
- **`O1NEXT Complete`** is the `next-integrated` board with the machine wrapped
  around it. **The LFF 1:1 mainboard is not in the set** — if it were ever built it
  would sit *under* the interposer exactly as an OEM board does, which is why it has
  no ROM path and no test matrix of its own.
- **In `hardware/`, `Rev 0` / `Rev A` / `Rev B` are `interposer-upgrade`'s**: Rev 0
  the probe (superseded), Rev A the engineering sample, Rev B the production
  revision. **Rev B is a revision, not a second product** — #259 absorbed #13/#15,
  and Rev B keeps Rev A's whole instrument.
- **Everywhere else the owner is named**: the **Floppy Adapter's** Rev A/B; the
  **Osborne 1 monitor ROM's rev B** (a 1979 ROM, not a board);
  **gusmanb/logicanalyzer's Rev A**. A document about one board may bind the letters
  for itself in a note at the top. **LFF and SFF are form factors, never letters.**

## Cross-cutting decisions (settled)

- **Level shifting:** 74AHCT/74HCT for anything touching the Z80 bus — all O1s are
  NMOS Z80s (research-gaps #2, 2026-10-09).
- **Power:** the interposer takes its own 5 VDC feed near the Z80 socket, sized for
  RP2354B WiFi bursts (~300 mA+).
- **Bench-prep from USB alone (#207, 2026-10-14):** one 5 V net carries the RP2354B
  and the library flash and is reachable from USB alone, so a board runs and its
  flash is programmable with no host machine, no Z80 socket and no chassis supply.
  Required on `interposer-upgrade` and `next-integrated`, and true of every
  standalone board.
- **Stacking:** the interposer must coexist with SCREEN-PAC and CoPower-88
  interposers on a fully-loaded machine.
- **Socket taps: three.** The Z80 seat, the **main ROM socket UD11** (the window the
  Pico serves) and the **char-gen socket UA15** (the font). A 24-pin 2732 socket
  carries no `A12`/`A13` and no write strobe, so a *part* in it can never exceed
  4 KB — irrelevant when the Pico serves the window, because the bank is which 4 KB
  the firmware presents. The UD11 and UA15 taps are two of the four sections above.
- **One ROM 2.00, and on a real machine no ROM part at all** (#83). One image runs
  on OEM board + interposer and on `next-integrated`. Because the OEM board is the
  reference the interposer was designed against, **OEM + interposer** is the one
  host brief and the one test matrix.
- **MODEM port (P1) is TTL, not RS-232**, and its RXD is bipolar — the modem must
  swing TX-toward-O1 negative for a clean mark (`docs/o1-modem-serial.md`). Its
  **+12.6 V on pin 7 sits behind the machine's 22 Ω (R21)**, which the keyboard
  branch through J6 shares, so the port **is current limited by that resistor** —
  and the sheet's own default is a **1/4 W** part, which caps it at **~107 mA**
  continuous (2.35 V dropped; 150 mA would be 0.495 W, a 1/2 W part at its
  rating). Burst power comes off bulk capacitance (`wifi-comm-pac/README.md`).
- **The two +12 V feeds are not alike, and that decides how the boxes are powered**
  (#354, #356). P1's pin 7 is behind `R21`; the **monitor jack (P5) is not limited
  at all** — it is the PSU rail, so the Astec AC8151's **2.02 A** is the only
  limit, against a load of one 5" CRT (~1.0–1.2 A steady, ~2 A inrush), two floppy
  motors that never run together, and small mainboard supplies. The wiring that
  settles:

  | Box | Wired to |
  |---|---|
  | `wifi-comm-pac` | `P1` & `P7`, **or** `P1` & `drive-c-repro`'s 5 V out |
  | `drive-c-repro` | `P3` & `P7` (the OEM configuration) |
  | `keyboard-adapter` | `P4` & 5 V out from `wifi-comm-pac` **or** `drive-c-repro` |

  With both boxes installed they **cross-feed 5 V** — their two 5 V connectors are
  wired together — rather than stacking a connector at P7, so **each board's 5 V
  port must be diode-OR'd against its own buck output** or the two converters drive
  one node and back-feed each other. Two pieces of hardware follow: a **front-panel
  connector on the `wifi-comm-pac`**, and a **small adapter routing the +12 V from
  P7 to it**.
- **P4 keyboard connector:** pin 19 = +12 V via jumper J6 + R21 — usable to power
  small adapter boards (`keyboard-adapter/`).

## Conventions

A board folder is named for its shortform and holds a `README.md` naming that board
and pointing at this register, plus its interfaces, constraints, open questions and
issue links. KiCad projects land there as `<board>.kicad_pro`, and every folder with
a `.kicad_sch` is covered by `tools/check_schematics.py`.
