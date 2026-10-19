---
layout: page
title: LFF board (won't build)
subtitle: A 1:1 mainboard for an OCC1 or OCC1A chassis
---

**Status:** block-level KiCad skeleton generated. **Won't build** — decided by the
maintainer on 2026-10-19; the stub is kept for the record. Concept.
Tracks **#49** (Phase 5). Source: `hardware/o1next/o1next-lff/`. Board register:
[`hardware/README.md`]({{ site.repository }}/blob/main/hardware/README.md).

## What it is

A faithful, **1:1 replacement mainboard** for a real **OCC1 or OCC1A** chassis —
the "large form factor" board. Same footprint, same connectors, same mounting
holes, so it drops into a machine whose original board has failed, or into a
chassis someone has kept. **It works for either machine**: the OCC1 and the OCC1A
share an architecture, so one board covers both.

## This is the restoration path, not the O1NEXT

There are two boards in this part of the project, and this is the one that
preserves an existing machine. The [SFF board]({{
'/hardware/sff-integrated/' | relative_url }}) is the integrated one, and the
[O1NEXT]({{ '/hardware/o1next-complete/' | relative_url }}) is **the SFF board with
the rest of the machine wrapped around it**. This board does not become an O1NEXT,
and it is not meant to.

## The design rule that makes it work

**The Z80 stays socketed, in a DIP-40 socket.**

That is the whole point. It means the [bus interposer]({{
'/hardware/interposer/' | relative_url }}) remains the upgrade path on the new
board exactly as it is on the original — you keep the machine's own CPU, and the
interposer still plugs in between. The replacement board does not try to
supersede the project's own architecture; it inherits it.

## What it keeps

- Original ROMs and original software — this is a reproduction, not a
  reimplementation.
- The full original I/O map, so period peripherals work unchanged.
- Socketed parts where the original had them, which is also what makes repair
  possible.

## What it changes

Only the things that have to change: obsolete and unobtainable parts are
substituted with modern equivalents at the same electrical interface. The
[memory and I/O map]({{ site.repository }}/blob/main/docs/o1-memory-io-map.md)
and the [schematic index]({{
site.repository }}/blob/main/docs/o1-mainboard-schematic.md) are the contract it
is built against.

## Still to do

- Footprint and mechanical verification against the Rev E schematic set and a
  real chassis.
- The bill of materials, part by part, with each substitution justified.
- Routing.
