---
layout: page
title: Complete O1 Next Generation
subtitle: The whole machine, case included
---

**Status:** concept render exists. Tracks **#49** and **#52** (Phase 5).
Source: `hardware/o1ng/`, `docs/design/`.

## What it is

The end of the road: a complete, modern-parts Osborne 1 that runs original ROMs
and original software, in a case — not a board, not an upgrade, a machine.

It comes in two form factors, and they share a power architecture:

- **FF1 — the 1:1 replacement.** The [LFF board]({{ '/hardware/lff-replacement/'
  | relative_url }}) in a stock chassis, with the original case, keyboard and
  display. This is the restoration path.
- **FF2 — the "lunchbox" portable.** An integrated machine about **8 cm thick**,
  in the Osborne 1A's own blue-and-grey industrial design: a **8" 4:3 LCD**, a
  keyboard that forms the front cover, and modern power.

## The FF2 design constraints

- **The keypad is dropped.** It duplicates the number row — two switches on the
  same matrix connections — so it earns nothing and costs space.
- **Under 250 mm wide**, so the major parts fit the most common 3D-printer bed.
- **USB-C PD, with an optional 18650 battery path.** The same power board serves
  both form factors.
- **The display is the interesting choice.** Composite keeps it period-correct
  and reuses the [video personality]({{ '/hardware/interposer/' | relative_url }});
  HDMI is cheaper and sharper. It depends on #24/#44, and the answer changes what
  the case has to carry.

## The reference designs

Not invented — borrowed from the machines that did the same job:

- **Compaq Portable III** — the canonical lunchbox: keyboard as the front cover,
  a pop-up flat display, and a rear expansion unit.
- **Dolch PAC** — the ruggedised industrial lunchbox: handle on top, flat panel
  front, expansion inside.
- **Osborne 1A** — the aesthetic target, and the whole point: grey ABS, blue
  accent stripe, blue branding, and a keyboard that docks to seal the front.

## Deliverables

- A **power board spec** — USB-C PD trigger, 5 V and 12 V regulators, and the
  optional 4S battery path.
- An **FF1 board-outline drawing** against the O1A chassis mounting holes
  (L-shaped, four screws).
- An **FF2 concept design and renders**, with enclosure dimensions, the LCD and
  keyboard selection, and a print-feasibility check against the 250 mm limit.

## Depends on

- **#49** — the reproduction this encloses.
- **#24 / #44** — the LCD input choice (composite vs HDMI).
- **#47** — the FF2 keyboard is a Cherry-MX implementation of the same matrix,
  so the [USB keyboard interface]({{ '/hardware/keyboard-interface/' |
  relative_url }}) and the built-in keyboard share their work.
