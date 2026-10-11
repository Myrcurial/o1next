# The Double-Density upgrade is a multi-format controller (#95)

The DD upgrade is usually described as "twice the capacity". Its own manual
describes something else: a controller that recognises **six disk formats**,
five of them other manufacturers'.

> Thus, you'll find that you didn't just purchase double density, you purchased
> a **multi-density disk option**. Under the current release of double density,
> the following formats are all **automatically recognized by the computer**.
>
> | Format | Capacity |
> |---|---|
> | Osborne 1 single density | 92k per diskette |
> | Osborne 1 double density | 182k per diskette |
> | Xerox 820 single density | **80k** per diskette |
> | Cromemco single density | 80k per diskette |
> | IBM Personal Computer (CP/M-86 format) | 156k per diskette |
> | DEC VT-180 | 171k per diskette |
>
> — *Osborne 1 Double Density User Manual*, p. 4

That is the primary source for #95, and it **confirms the claim**: the DD
upgrade is a format capability, not just density. Note the wording is
"automatically recognized by the computer" — the recognition is in the machine,
which is what makes it testable in MAME without the hardware.

## Correction to the quoted list

oldcomputers.net gives the Xerox 820 entry as **82K**. The manual says **80k**,
and the manual is the one to follow — the page-4 list is the manufacturer's own
statement of what the option does.

The manual also records what the option deliberately does **not** handle, which
matters as much as what it does:

- **Hard-sectored diskettes** (North Star, Micropolis, Vector) — the controller
  cannot see the sector holes.
- **Non-block formats** (Apple, NEC) — no block-of-bytes structure to read.

and names the formats that were *anticipated* rather than shipped: TRS-80
Model I and III CP/M, and Zenith/Heath double density, "most likely in our user
magazine, The Portable Companion".

## Why the ROM is part of the answer

The upgrade is described as coming with the **1.4 ROM**, and the recognition is
a property of the computer rather than of the drive electronics — so the format
table should be in the 1.4/1.44 BIOS rather than in the add-on board. The 1.44
BIOS source is in the repo (`research/source-code/BIOS-144-source/rom144.asm`,
with the overlay modules `occbio*.asm`), which makes the comparison against a
1.3 source the next step: a table of geometries in 1.44 that 1.3 lacks is the
mechanism, and it would settle #95 without any hardware.

## What this means for the project

- The floppy personalities (#20, #30, #62) cannot be "an Osborne drive": they
  have to be able to *present* six geometries, which is a larger requirement than
  the issue assumed.
- The capacity figures are the acceptance target for the MAME test in #95: each
  format either reads **and** writes byte-comparably, or is recorded as failing,
  with the failure attributed to the ROM, the controller model or the image
  tooling.

## Sources

- `research/osborne1/o1doubledensityusersguide.pdf` — *Osborne 1 Double Density
  User Manual* (15 pages, image-only; OCR'd per the convention in
  `research/README.md` as `o1doubledensityusersguide.ocr.txt`).
  <https://www.kev.pulo.com.au/osborne1/documents/o1doubledensityusersguide.pdf>
- `docs/o1-memory-io-map.md` §3 (WD179x detail) — the formats already recorded
  there from the schematic side.
