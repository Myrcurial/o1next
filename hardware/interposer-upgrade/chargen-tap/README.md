# chargen-tap — the UA15 character ROM socket tap

**Part 4 of 4 of `interposer-upgrade`** — and a **snap-off section of the
interposer PCB**, not a board of its own. The unit's README is
[`../README.md`](../README.md); the register is [`../../README.md`](../../README.md).

## What it is

The **character ROM socket tap** (tap 3 of the three in the unit's *Tap points*
table): a lead-set into the 24-pin **UA15** socket, giving the Pico the **font**.
It is **read-only by necessity** — the ROM's `/CE` and `/OE` are grounded on the
mainboard, so the part is permanently selected and always driving — and it reads
whatever font ROM is fitted.

It serves the **video personality** (#24) and **font capture** (#44), and it is
what lets a ScreenPac-style 80/104-column personality use the machine's own
character generator rather than its own.

## How it connects: the air connect

Snapped off, this tap sits in the machine's char-gen socket, which is nowhere near
the Z80 — so its nets **leave the PCB and come back through a pair of header pin
assemblies, wired back-to-back**. The ROM-chip nets are *air connected* across that
pair instead of being routed on the board. Same mechanism as the UD11 tap
([`../rom-tap/README.md`](../rom-tap/README.md)), and it is what keeps the
interposer a single panel.

## Status

**No schematic of its own** — it is a section of the interposer's schematic, so it
is covered by whatever `rev0/`, `reva/` and `revb/` become, not by a file here.
Pinout confirmations: the mainboard schematic §4a (`docs/o1-mainboard-schematic.md`).
