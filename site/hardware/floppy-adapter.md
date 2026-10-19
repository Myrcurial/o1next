---
layout: page
title: O1NEXT Floppy Adapter
subtitle: A switchable Gotek / physical-drive daughter card
---

**Status:** design settled; **the Floppy Adapter's Rev A schematic captured**,
ready for footprint and routing review. Tracks **#62**, and the floppy interposer
personality **#20**. Source: `hardware/floppy-adapter/`,
`docs/floppy-adapter-design.md`. Board register:
[`hardware/README.md`]({{ site.repository }}/blob/main/hardware/README.md).

*This board's own Rev A / Rev B are unrelated to the interposer's Rev A / Rev B —
the letters always carry the board's name.*

## What it is

A small daughter card that lets you choose, **from a front-panel switch**, whether
the **drive A** position is served by the physical drive or by a **Gotek**
(FlashFloppy) emulator — with **drive B always present** in both modes.

It sits between the Osborne 1's floppy header and the OEM floppy cable. **Nothing
in the machine and nothing in the cable is cut.**

## Why it is not just a cable

Two prior designs exist, and this one deliberately improves on both:

- **Wayne Visser's adapter** is a **passive tap** — it puts a Gotek on the bus
  alongside the physical drives and switches nothing. Its pin and rail mapping is
  kept as the interface reference.
- **Richard Loxley's hand-wired build** proved the concept but needed a DPDT
  switch *and* a 5 V relay soldered onto the Gotek, plus hand-cut Dupont cable.
  This design moves all of that onto a PCB at the connector end.

## The interface, and the mistake worth recording

The machine uses a **Shugart-like 34-pin interface**, but with **+5 V and +12 V
routed to the drives over otherwise-unused cable pins** — there are no separate
drive power connectors, which is why the card has to tap the cable rather than
add a supply.

The pinout was first transcribed from the archived Visser adapter, then **re-read
from the Osborne 1's own schematic** (DWG 1A2011-00 Rev E, sheet 9 of 9, the P8
symbol). That second reading corrected two pins and a ground row — and one of the
corrections is the reason this card can exist at all:

> **Pins 4 and 6 are not ground.** They carry live FDC outputs — **TG43** and
> **EARLY**. The earlier transcription tied pins 2, 4, 6 and 7 to GND, which is
> harmless on a Gotek-only adapter, but this card switches the OEM cable through
> to real drives, and **clamping TG43 low would assert reduced write current
> permanently**. The card passes 4 and 6 straight through instead.

That is a good example of why the project re-reads primary sources rather than
trusting a prior adapter's transcription.

## Still to do

- Footprint and routing review, then fabrication.
- The front-panel switch wiring, which is also the point at which this card and
  the [control pod]({{ '/hardware/interposer/' | relative_url }}) have to agree on
  a physical interface.
