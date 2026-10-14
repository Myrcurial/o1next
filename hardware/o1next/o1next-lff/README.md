# o1next-lff/ — 1:1 mainboard replacement (KiCad skeleton)

Hierarchical schematic skeleton for the **large form factor** o1next: the
faithful 1:1 replacement mainboard for a real **OCC1 or OCC1A** chassis
(see `../README.md` for the design philosophy — true to original,
socketed DIP-40 Z80, interposer is the upgrade path). **This board is
the restoration path, not the O1NEXT**: the O1NEXT is built on the SFF
board, and this one does not become one.

**This board is *only* the OEM board, recreated, with the Dual Density upgrade
built in — and that has a consequence worth stating once:** because it is a
faithful recreation rather than a new design, **LFF board + interposer ≡ OEM board
+ interposer**. Anything the interposer can do on an original machine it does
here, and anything it needs from the host it finds identically. So there is one
interposer brief, one ROM 2.00 image, and one test matrix — not two of each.

**The ROM socket is part of that fidelity, and it stays that way.** It takes a
**standard 1.44 ROM**, exactly as the OEM board does, so an LFF board on its own is
a stock machine and the restoration path boots with the stock part — no interposer
required, no new ROM required. The larger ROM is known to work in it as well. And
when the interposer *is* fitted, **the socket can be left empty**: the daughterboard
takes its place and the Pico serves the ROM window, so ROM 2.00 needs no physical
part at all. See `../../interposer/README.md` (*Tap points*) and
`docs/o1-rom-2.0.md` §4.1a.

**Status: block-level skeleton.** The hierarchy and per-sheet design
notes are the agreed decomposition; component-level capture (replacing
the note text with real circuitry) is the next step, working from
`research/osborne1/OCC1_1A2011-00_Schem_RevE.pdf` with the documented
modernizations.

## Sheets

| Sheet | Block | Key modernizations vs. original |
|---|---|---|
| `cpu_mem` | CPU + memory | Z84C00 (socketed DIP-40); **64 KB SRAM replaces 16× 4116 DRAM + refresh**; a **ROM socket that takes a standard 1.44 ROM** (see the note above — the socket is *not* modernized, so the board stays OEM-equivalent), carrying **ROM 2.00** (#83) when a part is wanted; bank decode per `docs/o1-memory-io-map.md` |
| `video` | Display | original char-gen ROM socket retained; composite out; HDMI left to the interposer |
| `floppy` | FDC | MB8877/179x-class FDC; DD data separator (PC 360K reads → FATCOPY #51); connector matches `hardware/floppy-adapter/` |
| `io` | Serial + GPIB | 6850 ACIA (P1 TTL / P2 RS-232 per `docs/o1-modem-serial.md`), 6821 PIA, CTC 60 Hz |
| `keyboard` | Keyboard | P4 connector incl. pin-19 +12V provision; matrix scan; interposer KVM injects here |
| `power` | Power | **USB-C PD trigger → +5V/+12V** replaces the entire original PSU (no RIFA caps); optional stock-connector passthrough |
| `clock` | Clock/reset | single-oscillator design (#55), 4.0 MHz, reset supervisor; **no turbo on the LFF board** (turbo is SFF-only) |

## Mechanical constraints (drive layout later)

- L-shaped board: skinny arm → left-side ports + front-left boss;
  chunky short side → front/rear right bosses. Four mounting screws
  total. Stock locations for front ports, power, internal video, floppy
  connectors (#52).

## Regenerating

`gen_lff_sch.py` generates the root + child sheets (KiCad 7 format;
open/re-save in KiCad to normalize). Add real sheets/circuitry in
KiCad proper once capture begins — the generator is scaffolding, not
the long-term source of truth.
