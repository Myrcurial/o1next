# o1ng-lff/ — 1:1 mainboard replacement (KiCad skeleton)

Hierarchical schematic skeleton for the **large form factor** o1ng: the
faithful 1:1 replacement mainboard for a real **OCC1 or OCC1A** chassis
(see `../README.md` for the design philosophy — true to original,
socketed DIP-40 Z80, interposer is the upgrade path). **This board is
the restoration path, not the O1NG**: the O1NG is built on the SFF
board, and this one does not become one.

**This board is *only* the OEM board, recreated, with the Dual Density upgrade
built in — and that has a consequence worth stating once:** because it is a
faithful recreation rather than a new design, **LFF board + interposer ≡ OEM board
+ interposer**. Anything the interposer can do on an original machine it does
here, and anything it needs from the host (the ROM socket lead-set for ROM 2.00
above all) it finds identically. So there is one interposer brief, one ROM 2.00
image, and one test matrix — not two of each.

**Status: block-level skeleton.** The hierarchy and per-sheet design
notes are the agreed decomposition; component-level capture (replacing
the note text with real circuitry) is the next step, working from
`research/osborne1/OCC1_1A2011-00_Schem_RevE.pdf` with the documented
modernizations.

## Sheets

| Sheet | Block | Key modernizations vs. original |
|---|---|---|
| `cpu_mem` | CPU + memory | Z84C00 (socketed DIP-40); **64 KB SRAM replaces 16× 4116 DRAM + refresh**; 27C128/Flash BIOS carrying **ROM 2.00** (#83) — the same image the interposer runs; bank decode per `docs/o1-memory-io-map.md`. **How the ROM socket is wired is deliberately *not* modernized here**: the host side must stay OEM-equivalent (see the note above), so the banking lines come from the interposer's ROM tap on this board exactly as they do on an original |
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
