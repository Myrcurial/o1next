---
layout: page
title: Complete O1 Next Generation
subtitle: The whole machine, case included
---

**Status:** concept render exists. Tracks **#49** and **#52** (Phase 5), plus
**#125** (the Osborne 3). Source: `hardware/o1ng/`, `docs/design/`.

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

## The Osborne 3

FF1 and FF2 are both Osborne 1s. The **Osborne 3** is not: it is the third
machine, and the one the line never got right.

The name is real. The **Osborne 3** was the last computer Osborne Computer
Corporation shipped — announced October 1984, on sale spring 1985, $2,995 — and
the only IBM-compatible they ever built. It is also the machine where Osborne
stopped being Osborne:

- **It was not their design.** Licensed from **Morrow Designs** and almost
  identical to the **Morrow Pivot**, so it wore Morrow's industrial design rather
  than the Osborne 1's blue-and-grey.
- **It abandoned their software** — MS-DOS 2.11, not CP/M.
- **Its screen was the known failure.** Price forced a **16-line** display
  instead of 25, and like all early non-backlit LCDs it was "difficult to read
  without perfect lighting". One owner reports wearing a miner's headlamp to use
  it.
- **Nothing adjusted.** "Neither the screen or keyboard position is adjustable."
- OCC went bankrupt again in early 1986; the assets were sold, and no schematics
  were ever published.

That is the **counter-example to the whole project**. The Osborne 1 is open and
documented, which is why it is still reproducible forty years on. The Osborne 3
was a licensed rebadge, and it died with its vendor.

So this is our Osborne 3 — the one OCC should have built (**#125**). Four design
commitments:

1. **Retain the OCC aesthetic rather than dark grey.** Grey ABS, blue accent
   stripe, blue branding: the Osborne 1A's language, not the rebadged box the
   real Osborne 3 shipped in.
2. **A usable screen.** A panel you can read in a normally-lit room — 80×25, not
   the 16-line compromise, and backlit.
3. **A detachable keyboard.** It docks over the front and seals the unit, as the
   Osborne 1's does. Nothing about the machine's ergonomics is fixed by a hinge.
4. **Open and reproducible.** Schematics, firmware and case files published, so
   anyone can build one. The opposite of a licensed rebadge.

It shares the USB-C PD power architecture with FF1 and FF2, and sits downstream of
both: #49 is the reproduction it is deliberately *not*, and #52 supplies the case
and power work.

*(The Osborne 3 history above comes from its entry at oldcomputers.net and the
Osborne Computer Corporation article on Wikipedia; both agree on the Morrow
licensing and the 16-line display.)*

## Deliverables

- A **power board spec** — USB-C PD trigger, 5 V and 12 V regulators, and the
  optional 4S battery path.
- An **FF1 board-outline drawing** against the O1A chassis mounting holes
  (L-shaped, four screws).
- An **FF2 concept design and renders**, with enclosure dimensions, the LCD and
  keyboard selection, and a print-feasibility check against the 250 mm limit.
- An **Osborne 3 design brief** — the four commitments above, plus the panel and
  keyboard selection and the publishing route for the schematics and case files.

## Depends on

- **#49** — the reproduction this encloses.
- **#24 / #44** — the LCD input choice (composite vs HDMI).
- **#47** — the FF2 keyboard is a Cherry-MX implementation of the same matrix,
  so the [USB keyboard interface]({{ '/hardware/keyboard-interface/' |
  relative_url }}) and the built-in keyboard share their work.
- **#125** — the Osborne 3: the four commitments above, and the open-publishing
  plan.
