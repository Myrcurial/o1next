---
layout: page
title: "The machines: a photographic survey"
subtitle: "Appendices &middot; reference"
draft: "Draft &mdash; assembled from the working notes by `tools/build_book.py`. The source document is the authority; this page is a copy for reading, and it is regenerated from that source."
---

Status: 14/16 examined (IMG_4856–4869). IMG_4870/4871 could not be
processed by the vision pipeline (tool rejects even after EXIF strip/
re-encode) — user to describe or retake.

## CoPower-88 8088 board (IMG_4856–4867)

- Silkscreen: **"KAYPRO-88"**, "(C) SWP 1983", "Lic. SWP Inc.",
  "COPOWER-88 REV 1.8". ⇒ The user's board is the **Kaypro variant**,
  consistent with software default port pair **0x7E (data) / 0x7F
  (status)**.
- CPU: **Fujitsu MBL8088** (NMOS 8088, ceramic DIP, 8319).
- Clock: CRYSTEK 16.000 MHz oscillator can → 8284 divides by 3 →
  **5.33 MHz 8088**.
- Boot ROM: 2732A labelled "SWP-8088" (the 8088-side monitor — the
  firmware that answers the host mailbox; a dump of this ROM would
  fully specify the protocol. Consider reading it when hardware is
  accessible — candidate for the reader hardware in #14).
- RAM daughterboard: 16 x **Mostek MK4564N-25** (64Kx1, 128 KB)
  soldered via SIP-style carrier above the main board.
- Glue visible matches 611-0003: 74LS138 x3 (RAS/CAS + port decode),
  74LS244, 74LS373/375, 74LS645, 74LS257, 74LS175, 74LS153, 74LS32,
  MC74HC374 x2, 74LS161/393/174 etc.
- **Blue DIP-package IC** marked "16-2103 8140" — per user correction this
  is a **chip, not a DIP switch**. Almost certainly an 8-bit magnitude
  comparator (74LS688-class) doing the A1-A7 port-base compare from sheet 4.
  ⇒ The host port base is **fixed by this device / its hardwired reference,
  not user-switchable**. Consistent with the Kaypro software default 0x7E/0x7F.
  TODO: confirm the exact part number + how the reference nibble is set.
- Host ribbon: IDC at board edge (to Z80 socket adapter), plus a
  second 16-pin(?) white Berg-type connector (matches "BERG PINS"
  RDX read-strobe / expansion note on sheet 4).
- Solder side (4866): single blue bodge wire, otherwise clean.

## Osborne mainboard + Z80 adapter (IMG_4868, IMG_4869)

- Mainboard marked **"24187A"** (handwritten/silk), assorted 74LS,
  socketed 6116 x2 (video RAM), WD1793? area partially visible.
- **The Z80 lives on the CoPower-88 interposer adapter**: a small PCB
  plugged into the mainboard's Z80 socket carrying
  - a plastic **Zilog Z80A, date code 8408 ⇒ NMOS** (a CMOS Z84C00
    would be marked differently; also 1984 predates common CMOS Z80s)
  - 74HCT-series glue (74HCT04 visible) and pads labelled **A4 A5 A6
    A7** — address lines broken out for the ribbon to the 8088
    board's port decode (sheet 4 A1-A7 compare feeds the blue comparator
    IC; adapter passes them down)
  - ribbon cable from adapter to the KAYPRO-88 board.
- **Level-shifting conclusion for #11**: this machine is NMOS Z80A
  (TTL-ish outputs, high input thresholds) ⇒ use 74HCT/74AHCT toward
  the Z80 bus or 74LVC245 with careful thresholds; per survey (#31)
  the safe choice remains LVC245 host-side + HCT toward host inputs.
  Still confirm the other two machines before finalizing.

## Open items (need user)

1. IMG_4870 / IMG_4871: what do they show? (They follow the CPU-area
   shots.) Please describe or retake — likely the missing piece for
   the adapter↔mainboard ribbon routing.
2. Which of the 3 machines is this (OCC1 label? board rev 24187A)?
3. Close-up of the blue comparator IC ("16-2103") to read the full part
   number and confirm the 0x7E/0x7F decode hypothesis.
4. Photos of the other two machines' Z80 areas for the NMOS/CMOS
   matrix in #29.
