---
layout: page
title: SFF integrated board
subtitle: One board, no interposer, the whole machine
---

**Status:** concept.
Tracks **#49** (Phase 5). Source: `hardware/o1ng/`.

## What it is

The **SFF board** — the foundation of the O1 Next Generation. A **fully integrated
board**: everything the [interposer]({{ '/hardware/interposer/' | relative_url }})
does, designed in as firmware rather than plugged in.

**It is not a 1:1 swap, and it does not try to be.** The
[LFF board]({{ '/hardware/lff-replacement/' | relative_url }}) is the board that
drops into a real chassis. This one can go into a real chassis **or** into any
other design — up to the end user. Nothing about it is constrained by a 1982
footprint.

**The [O1NG]({{ '/hardware/o1ng-complete/' | relative_url }}) is this board with
the rest of the machine wrapped around it.**

## Why build it at all, if the interposer exists

Because they answer different questions:

- The **LFF board** preserves a machine. It is the repair and restoration path,
  and it keeps the interposer as the upgrade.
- The **SFF board** is the *new* machine. It can be smaller, cheaper, and faster
  than an Osborne 1 with an interposer in it, and it does not need a 40-year-old
  CPU socket to work.

## What it adds over the original

- **Turbo-capable** — an 8 MHz clock, which is the "2× business turbo" the WiFi
  modem's baud buffering exists to exploit.
- **Onboard flash library**, so it boots from internal storage with no card.
- **USB-C PD power**, shared with the [complete O1 Next Generation]({{
  '/hardware/o1ng-complete/' | relative_url }}).
- The interposer's personalities **as firmware**, not as a second board.

## What it keeps

Original ROMs and original software, unchanged. The whole project's thesis is
augmentation rather than replacement, and this board is the strictest test of it:
if period software cannot tell it apart from an Osborne 1, it is finished.

## Still to do

Everything, past the concept. The block diagram comes first, then the same
footprint discipline the LFF board uses.
