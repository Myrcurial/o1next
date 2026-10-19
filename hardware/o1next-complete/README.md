# o1next-complete — O1NEXT Complete (the machine)

**Hardware, but not a board.** `o1next-complete` is the **machine**: the
`next-integrated` board with the rest of the machine wrapped around it. Register:
[`../README.md`](../README.md). Tracks **#49** (Phase 5), **#52** (case + power),
**#53** (the concept render), **#125** (the Osborne 3 history) and **#128** (the
specification).

## What it is made of

| Piece | Where it stands |
|---|---|
| **Chassis CAD** — the enclosure in the Dolch / Compaq Portable III idiom, O1A blue/grey, "keyboard seals the unit", ~8 cm thick | `docs/design/o1next-lunchbox-concept.*` (#53) |
| **Print STLs** — the printable parts of the chassis and the keyboard mounting | *to produce* (#52) |
| **Assembly BOM** — everything that goes in: the board, the 8" panel, the 18650 pack, the keyboard, the fasteners | *to produce* (#52) |
| **The keyboard PCB** — a custom USB keyboard, **QMK-compatible**, in the **Osborne 1 layout** | [`keyboard/`](keyboard/) |
| **The board inside it** | [`../next-integrated/`](../next-integrated/) — the O1NEXT Integrated (SFF) board |

## The machine, in the maintainer's words

> The O1NEXT is the SFF board with the rest of the machine wrapped around it — the
> logical equivalent of the C64 Ultimate "Crystal" edition: an homage that gives
> the end user *everything* that would have been possible in the olden days.

Concretely: an **8" 1024×768 (4:3) HDMI panel**, a **4S 18650 pack**, a detachable
flip-up keyboard, and an optional rear "backpack" for a physical 5.25" half-height
drive. The board's own I/O complement and power architecture are
[`../next-integrated/README.md`](../next-integrated/README.md)'s.

## Status

**No schematic of its own — it is CAD and a BOM, not a PCB.** There is nothing for
`tools/check_schematics.py` to check here; the keyboard PCB will have one of its
own (`keyboard/`), and the board inside the machine is `next-integrated`.
