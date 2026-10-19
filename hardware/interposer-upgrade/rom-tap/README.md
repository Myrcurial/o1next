# rom-tap — the UD11 main-ROM socket tap

**Part 3 of 4 of `interposer-upgrade`** — and a **snap-off section of the
interposer PCB**, not a board of its own. The unit's README is
[`../README.md`](../README.md); the register is [`../../README.md`](../../README.md).

## What it is

The **main ROM socket tap** (tap 2 of the three in the unit's *Tap points* table):
a daughterboard that takes the 24-pin **UD11** socket — **DIP pins down, ribbon
up** — and lets the Pico **serve the ROM window**, so no physical ROM part is
needed and the banking is a firmware register. That is what makes **ROM 2.00**
(#83) possible on an OEM-faithful machine.

A 24-pin 2732 socket carries no `A12`, no `A13` and no write strobe, so a *part*
in it could never exceed 4 KB — but when the Pico serves the window those lines
are irrelevant, because the bank is which 4 KB the firmware presents.

## How it connects: the air connect

Snapped off, this tap sits in the machine's ROM socket, which is nowhere near the
Z80 — so its nets **leave the PCB and come back through a pair of header pin
assemblies, wired back-to-back**. The ROM-chip nets are *air connected* across that
pair instead of being routed on the board. Same mechanism as the DIP-down /
ribbon-up daughterboard in the unit's README, and it is what keeps the interposer a
single panel.

## Status

**No schematic of its own** — it is a section of the interposer's schematic, so it
is covered by whatever `rev0/`, `reva/` and `revb/` become, not by a file here.
**The signal list is #12's** (the electrical/mechanical interface spec), and the
pinout confirmations are in `docs/o1-memory-io-map.md` §2 (the ROM window).
