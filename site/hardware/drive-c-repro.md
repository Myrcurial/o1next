---
layout: page
title: O1NEXT Drive C Repro
subtitle: The machine's own IEEE-488 RAM disk, rebuilt on modern parts
---

**Status:** concept; blocked on the **#6** protocol.
Tracks **#84** (device) and **#6** (the protocol). Source:
`hardware/drive-c/`. Board register:
[`hardware/README.md`]({{ site.repository }}/blob/main/hardware/README.md).

## What it is

A **Drive C**, rebuilt on modern parts — no interposer, no Z80 socket, and no
reverse-engineering of an undocumented controller. It attaches to interfaces the
machine already exposes and does the one thing the IEEE-488 port was designed
for.

It is a *reproduction* rather than an adapter: the machine sees the same device on
the same bus speaking the same protocol, so period software drives it unchanged.
Look closely and you find an RP2040 where the original had a handful of TTL.

## Why this one and not the hard disks

Seven storage routes were advertised for the Osborne 1. Only one is buildable
from what this project holds:

| Route | Why not |
|---|---|
| ACT / OCC1 hard disk | Controller command set not reverse-engineered; a relocatable Z80-side port window (#8) |
| Media Distributing / Adaptec (**the MD-10**) | Same problem, different vendor (#8) |
| Trantor TSL-5/TSL-10, Helix, Corvus, OSMOS 7 | No media and no controller documentation held |
| **Drive C** | Protocol **fully observable from software alone** — `DRIVE_C.IMD` plus the ROM's own IEEE-488 implementation — and the host interface is a **documented, standard bus** |

## How it attaches

- **IEEE-488 on P3**, a 26-pin card edge (pins 25/26 unused). The PIA behind it
  is UC7 (6821) at `2900–2903`, driven through 7406 **open-collector** drivers
  with 3.3 K pull-ups — so a replacement device must **release** lines, not drive
  them high.
- **Power from P5**, the 10-pin video connector, through an EXMON-style passive
  shunt. The same shunt also yields **composite video out**, because that is
  exactly what EXMON does. It is a **mod** — passive and reversible, but a mod,
  and documented as one.
- **RP2040 + one flash chip.** Even the largest Drive C variant was not large.

## Still to confirm

- **The power budget at P5.** The EXMON shunt takes +12 V; confirm what else is
  on the connector, whether +5 V is available, and the current budget. Measure on
  a real machine — do not assume.
- **Which Drive C variant** to emulate, from the #6 command set.
- **One firmware, not two:** the same device exists as an interposer personality
  (**#22**), and it should be one implementation.

## Before the design

BrettHallen's `Osborne_1` repository carries the EXMON shunt photographs and the
connector part numbers — the only description of the video shunt we have. It
should be archived into `research/` with provenance before it moves or disappears.
