---
layout: page
title: LFF replacement board
subtitle: A 1:1 mainboard for a stock chassis
---

**Status:** block-level KiCad skeleton generated. Concept.
Tracks **#49** (Phase 5). Source: `hardware/o1ng/o1ng-lff/`.

## What it is

A faithful, **1:1 replacement mainboard** for a stock Osborne 1 case — the
"large form factor" board. Same footprint, same connectors, same mounting holes,
so it drops into a machine whose original board has failed, or into a chassis
someone has kept.

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
