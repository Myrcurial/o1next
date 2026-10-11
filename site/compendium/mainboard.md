---
layout: page
title: "Mainboard and the schematic set"
subtitle: "The machine"
draft: "Draft &mdash; assembled from the working notes by `tools/build_book.py`. The source document is the authority; this page is a copy for reading, and it is regenerated from that source."
---

[`research/osborne1/OCC1_1A2011-00_Schem_RevE.pdf`](https://github.com/Myrcurial/o1nextgen/blob/main/research/osborne1/OCC1_1A2011-00_Schem_RevE.pdf) is the primary source for
the O1's logic board. Until now it was read by eye, page by page, in a PDF
viewer: the scan is dense, the PDF's own text layer is unusable, and the 12
pages are actually **two different drawing sets**, which is easy to get wrong.
This document is the map of that archive item: what is in it, how to read it,
and what has been extracted from it so far.

## 1. What the file actually contains

12 pages. Each page is a single 1-bit JBIG2 scan at roughly 600 dpi
(6582 × 5137 px on a 785 × 610 pt sheet) — genuinely high quality; every pin
number is legible at native resolution.

Each page *also* carries a text layer, but it is an early-1990s OCR pass and is
garbage: the disc-controller sheet's title reads `J'U~ I 'IIS IO/OO-tOOnl`.
Ignore it. (It is left in the PDF; the fresh pass in §3 is the one to search.)

The 12 pages are **two drawing sets**:

| Pages | Drawing | Rev | Sheets |
|---|---|---|---|
| 1–3 | **DISK ELECTRONICS**, DWG 1A3004-00/01 | C | 1–3 of 3 |
| 4–12 | **MAIN PC BOARD**, DWG 1A2011-00 | E | 1–9 of 9 |

This distinction matters. The disk-electronics set (1A3004) is the *drive's
own* board — read amplifier, data separator, write driver, head connectors.
The mainboard set (1A2011) is the machine this project extends. Notes in this
repo have cited "DWG 1A3004" for mainboard facts, including the floppy
connector pinout; that citation is wrong (§5).

[`research/README.md`](https://github.com/Myrcurial/o1nextgen/blob/main/research/README.md) describes the split as "sheets 1–3 are the disk analog
board (DWG 1A3004), sheet 4+ the main logic board" — correct in outline; the
exact drawing numbers and sheet counts are as tabulated above.

## 2. Sheet index

Titles are the drawing's own title-block text (sheet 1 of the mainboard set
has no block title; its function is read off the circuit).

| PDF page | Drawing / sheet | Function | Devices read off the sheet |
|---|---|---|---|
| 1 | 1A3004 1/3 | Disk read electronics: head pre-amp and peak detection, ALC, head connectors P1/P2 | U9, U10, U15, U16, U18, U19, U20 |
| 2 | 1A3004 2/3 | Disk data separator: index/sector, read data, drive connector P2 | U8, U12–U22 |
| 3 | 1A3004 3/3 | Disk write driver, erase, motor control, ±12 V/+5 V rails | U1, U2, U3, U6, U11, U12, U13 |
| 4 | 1A2011 1/9 | CPU clock (4 MHz), reset, data buffers, power entry | UD11, UD13, UE3, UE20, UC7, **UC11 = 74LS161** clock counter, UA6, UA8, J5, P6 (battery) |
| 5 | 1A2011 2/9 | Address decode, ROM/RAM/I-O select, WAIT generation | UC1, UC2, UD1, UD2, UD3, UD9, UD12, UE3, Q1/Q2 (reset timing) |
| 6 | 1A2011 3/9 | **CPU**: Z80-A, monitor EPROM, address latches | **UC11 = Z80-A**, **UD11 = 2732**, UD4, UD6–UD10, UE6, UE10, UE11, UA4 |
| 7 | 1A2011 4/9 | **RAM** array, address multiplex/buffer, **character generator ROM and its serialiser** | **UA15 = 2716** char-gen ROM and **UA14 = 74166** pixel serialiser (§4a), **UA18 = 74LS273** character latch (drives UA15 `A0–A6`), UA17/UA18 and the UA23–UA48 array (2114/2112 static RAMs per sheet 1's parts list), UE13–UE15 (74LS244), UE16–UE18 (74LS153), UD16 (74LS374) |
| 8 | 1A2011 5/9 | **VIDEO**: PIA, scan counters, video timing, brightness/contrast | **UC15 = 6821**, **UD17/UD18 = 74LS161** scan-line counters (preset from PIA `PB0–PB3`, outputs `SCAN0–SCAN3` → UA15 on sheet 4/9), UC16–UC21 (74166/74165), UA11–UA13, UB14/UB15 (74LS161), UE20–UE24 (7406), R40 (brightness), R44 (contrast). **UA14, UA15 and UA18 are on sheet 4/9, not here** — §4a. The rest of this row is still the first pass (§3) |
| 9 | 1A2011 6/9 | IEEE-488 interface (P3): PIA + open-collector bus drivers | **UC7 = 6821**, UD1 (74LS30), UD5 (74LS32), UD6/UD8–UD11 (7406), UE6/UE10 (74LS04), RN7/RN11–RN16 (3.3 K pull-ups) |
| 10 | 1A2011 7/9 | **SERIAL I/O**: ACIA + RS-232 level shifting, modem and CRT connectors | **UC4 = 6850**, **UC3 = 74LS161 baud divider at C3**, **UB3 = 74LS04**, UD4 (LM3900 ×3, modem status comparators) — §4b; UC14 (6551), UD1, UE1 (555), UE2 (1488), UE3 (1489), P1 (MODEM), P2 (9"/12" RS-232 CRT) |
| 11 | 1A2011 8/9 | **KEYBOARD**: row/column matrix, column drivers | UE12 (81LS95), UE13/UE14 (74LS05), RN10 (1.5 K), P4 (KEYBOARD) |
| 12 | 1A2011 9/9 | **DISC CONTROLLER** + the 34-pin floppy header | **UB7 = MB8877**, U7, U8, U9, U10 (7408/7406), U15 (74LS161), UD6 (74LS74), RN2 (150 Ω terminator), **P8** |

Sheets 4–12 are numbered 1–9 of 9 in their title blocks; the mainboard set is
complete in this scan.

> **Read the device lists at native resolution before citing them.** The
> *functions* in the last column are reliable; the part numbers came from a
> whole-sheet pass and at least two are known wrong (§3). `UC11` in particular
> appears twice — as the Z80 (sheet 3/9, verified at 600 dpi) and as a 74LS161
> (sheet 1/9, overview pass); only one can be right.

## 3. How to read a sheet

Whole-sheet views are useless — scale a 6582 px sheet onto a screen and the pin
numbers vanish. Read it one region at a time at native resolution. Two tools:

```
# browse: an overview plus a grid of native-resolution tiles for every sheet
tools/schematic_atlas.sh research/osborne1/OCC1_1A2011-00_Schem_RevE.pdf
#   -> build/atlas/index.md          tile map: page -> tile -> pixel box
#   -> build/atlas/sheet-05/r1c0.png native-res tiles you can just open

# then re-render any region exactly, once the index says where it is
tools/schematic_render.sh research/osborne1/OCC1_1A2011-00_Schem_RevE.pdf /tmp/s \
    --sheet 5 --dpi 600 --crop 2600 1250 1450 1050
```

[`tools/schematic_atlas.sh`](https://github.com/Myrcurial/o1nextgen/blob/main/tools/schematic_atlas.sh) writes into `build/atlas/` — gitignored, because the
atlas is regenerable and the *coordinates* are the durable part. Its index maps
every tile to the pixel box it covers, so a region found by eye once can be
re-rendered exactly later. `--info` on the render tool prints the sheet size in
pixels at a given dpi. Both need poppler (`brew install poppler`), which
[`tools/ocr_pdf.sh`](https://github.com/Myrcurial/o1nextgen/blob/main/tools/ocr_pdf.sh) already depends on.

**Read part numbers at native resolution, never from an overview.** At 300 dpi
`LS00` and `LS08` are indistinguishable, and so are `LS138` and `LS139`. The
first pass over this scan was done from whole-sheet views and got both of those
wrong on sheet 2: at 600 dpi it plainly reads **`UC1 LS00`** (quad NAND) and
**`UB1 LS139`** (dual 2-to-4 decoder — its pin numbers 15/14/13 for
enable/A/B and 12/11/10/9 for Y0–Y3 are exactly the second half of a '139).
The §2 device lists came from that first pass: treat the *functions* as
reliable and the part numbers as needing a native-resolution check before
anything is built on them. One conflict is already visible in them — `UC11`
is listed as both the Z80 (sheet 3/9, read at 600 dpi, and it matches a
standard DIP-40) and a 74LS161 (sheet 1/9, overview pass). The Z80 is the
verified one.

[`research/osborne1/OCC1_1A2011-00_Schem_RevE.ocr.txt`](https://github.com/Myrcurial/o1nextgen/blob/main/research/osborne1/OCC1_1A2011-00_Schem_RevE.ocr.txt) is a fresh OCR pass (per
the [`research/README.md`](https://github.com/Myrcurial/o1nextgen/blob/main/research/README.md) OCR convention) so the scan is greppable for component
references. It is useful for *finding* things — "which sheet has the MB8877?" —
and not trustworthy for pin-level detail. Everything in §4 and §5 was read by
eye at 600–1200 dpi instead.

[`research/osborne1/OCC1_1A2011-00_Schem_RevE.ocr.txt`](https://github.com/Myrcurial/o1nextgen/blob/main/research/osborne1/OCC1_1A2011-00_Schem_RevE.ocr.txt) is a fresh OCR pass (per
the [`research/README.md`](https://github.com/Myrcurial/o1nextgen/blob/main/research/README.md) OCR convention) so the scan is greppable for component
references. It is useful for *finding* things — "which sheet has the MB8877?" —
and not trustworthy for pin-level detail. Everything in §4 and §5 was read by
eye at 600–1200 dpi instead.

## 4. Extracted: the Z80 socket (UC11) is a standard Z80 DIP-40

Read from sheet 3 of 9 (PDF page 6) at 600 dpi. The symbol is drawn as
**UC11, Z80-A**.

| Pin | Signal | Pin | Signal | Pin | Signal | Pin | Signal |
|---|---|---|---|---|---|---|---|
| 1 | A11 | 11 | +5 V | 21 | RD | 31 | A1 |
| 2 | A12 | 12 | D2 | 22 | WR | 32 | A2 |
| 3 | A13 | 13 | D7 | 23 | BUSAK | 33 | A3 |
| 4 | A14 | 14 | D0 | 24 | WAIT | 34 | A4 |
| 5 | A15 | 15 | D1 | 25 | BUSRQ | 35 | A5 |
| 6 | CLK | 16 | INT | 26 | RESET | 36 | A6 |
| 7 | D4 | 17 | NMI | 27 | M1 | 37 | A7 |
| 8 | D3 | 18 | HALT | 28 | RFSH | 38 | A8 |
| 9 | D5 | 19 | MREQ | 29 | GND | 39 | A9 |
| 10 | D6 | 20 | IORQ | 30 | A0 | 40 | A10 |

Read directly off the sheet: A1 = 31 … A10 = 40, A11 = 1 … A15 = 5, A0 = 30,
D0 = 14, D1 = 15, D2 = 12, D3 = 8, MREQ = 19, RFSH = 28, IORQ = 20, WR = 22,
M1 = 27, RD = 21, +5 V = 11, GND = 29, BUSRQ = 25, NMI = 17. The unread rows
are the standard Zilog DIP-40 pinout, consistent with every pin that was read.

**This closes the Z80 half of [`docs/research-gaps.md`](https://github.com/Myrcurial/o1nextgen/blob/main/docs/research-gaps.md) gap #3 from the primary
source.** The O1's socket is wired as a plain Z80 DIP-40, so any board that
mates with it can use the datasheet pinout — which is what
[`tools/check_schematics.py`](https://github.com/Myrcurial/o1nextgen/blob/main/tools/check_schematics.py) asserts and what the interposer generators were
corrected to use (#62). It also corroborates that fix: the generators had the
pin table off by one across all 40 pins and were corrected to +5 V = 11 /
GND = 29 / A0 = 30 from the databook — the sheet says exactly that.

**Correction — both halves of that paragraph were wrong.** It read *"the
char-gen socket (UA15) half of gap #3 is still open. UA15 is a 74S244 on sheet
5 of 9."* UA15 is neither a 74S244 nor on sheet 5, and that mis-direction is
why #24's second tap point sat unresolved. UA15 is the **2716
character-generator ROM on sheet 4 of 9** (PDF page 7, title block `RAM`).
Read it at 1200 dpi — §4a.

## 4a. Extracted: the character-generator ROM socket (UA15) — gap #3 closed

Found at 600 dpi on sheet 4 of 9 (PDF page 7), read at 1200 dpi. The socket is
`UA15`, silkscreened **2716**, drawn with the address pins on the left and the
data pins on the right. The pinout is the **standard Intel 2716**, pin for pin:

| Pin | Signal | Where it comes from / goes |
|---|---|---|
| 1–8 | A7–A0 | `A0–A6` = character code (7 bits, 128 chars) from **UA18 (74LS273)**; `A7` = `SCAN0` |
| 9, 10, 11, 13–17 | O0–O7 | the pixel row, to the parallel inputs of **UA14 (74166)** |
| 12 | GND | **bussed with pins 18 and 20, then to ground** |
| 18 | `/CE` | **grounded** — the ROM is permanently selected |
| 19 | A10 | `SCAN3` |
| 20 | `/OE` | **grounded** — the ROM always drives its outputs |
| 21 | (A11 on a 2732) | **strapped to +5 V** |
| 22 | A9 | `SCAN2` |
| 23 | A8 | `SCAN1` |
| 24 | Vcc | +5 V |

### Address map

`SCAN0–SCAN3` arrive as labelled nets (`5C1 — SCANn`): they are the outputs of
the scan-line counters **UD17/UD18 (74LS161) on sheet 5 of 9**, which the video
PIA `UC15` presets from `PB0–PB3`. With `A7 = SCAN0` and the character code on
`A0–A6`, the address is

```
address = (scan << 7) | char       scan = {SCAN3,SCAN2,SCAN1,SCAN0}
        = 128 characters x 16 scan rows = 2048 bytes = exactly one 2716
```

The displayed cell is 8 wide x 10 high (24 rows x 10 = the 240-line video all
three MAME drivers produce), so scan rows 10–15 of every character are stored
but never shown.

### Output path — the assumed one was wrong too

`O0–O7` do **not** leave the sheet as eight parallel `CHAR0–CHAR7` lines. They
drive the parallel inputs of **UA14 (74166)**, an 8-bit shift register on the
same sheet, which serialises the pixel row and exports it as the single net
`VIDEO → 5D4` to the video sheet. UA14 is clocked by `DOT CLK` (from sheet 1/9)
and its `SI` and `/CE` are wired together — the usual trick that shifts in 1s
as the inter-character blank. The video sheet's own `4D1 → VIDEO` reference
(sheet 4, zone D1 — where UA14 sits) corroborates the direction.

This matters to #24: the char-gen socket is a **font source, not a pixel bus**.
Reading the font through the tap is enough — the pixels are re-rendered from
shadow VRAM.

### What the strapping means for a tap

`/CE` (18) and `/OE` (20) are **hard-grounded on the mainboard**, so the ROM is
always selected and always driving `O0–O7`. A socket tap may buffer and *read*
those pins freely, but it cannot tristate the ROM to inject its own font
without intercepting pins 18 and 20 between socket and ROM. Any future
"supply your own font" mode needs that interception, and the pin-21 strap held
at +5 V (the socket is wired 2732-style, so a 4 KiB part would fit physically).

## 4b. Extracted: the ACIA's clock and the baud divider (sheet 7 of 9)

Read from sheet 7 of 9 (PDF page 10) at 600–1200 dpi, prompted by two sources
that describe the same modification from opposite ends — *The Portable
Companion* #13 (Hogan, from inside OCC) and the Technical Manual's own Figure
4.4.

**The 6850 (UC4) pin numbers as drawn.** The symbol omits Vcc/Vss (pins 12 and
1), which is this schematic's house style — every symbol drops its power pins:

| Pin | Signal | Pin | Signal | Pin | Signal | Pin | Signal |
|---|---|---|---|---|---|---|---|
| 2 | RXDATA | 5 | RTS | 8 | CS2 | 11 | RS |
| 3 | RX (clock) | 6 | TXDATA | 9 | CS1 | 13 | R/W |
| 4 | TX (clock) | 7 | IRQ | 10 | CS0 | 14 | E |
| 23 | DCD | 24 | CTS | 15–22 | D7…D0 | 12 / 1 | Vcc / Vss |

**The clock is strapped.** Pins **3 and 4 are wired together** under a bracket
labelled `CLK` — the ACIA runs both halves from one clock — and that net is
driven by **UC3's `QD` (pin 11)**.

**UC3 is a preset-load counter, not a plain divider.** It is a 74LS161 at board
position **C3**, clocked (`CK`, pin 2) from a `4USEC`/`2USEC` tap off the video
counter through jumper **J1**, with **`RCO` (pin 15) inverted by UB3 (74LS04)
into `/LD` (pin 9)** — the classic preset-load ÷N. `/CLR` (pin 1) is tied to
+5 V and the preset inputs carry the divisor as solder-select pads. So the stock
19.2 kHz ACIA clock is `(250 or 500 kHz) ÷ 13`, and the 6850's own ÷16/÷64 gives
300/1200 — or 600/2400 with J1 out.

**It agrees with the Technical Manual pin for pin.** Figure 4.4, "Baud Rate
Hardware Modification" (manual p. 22 = **PDF page 36**; the manual's +14 offset
holds, [`docs/o1-chargen-graphics.md`](https://github.com/Myrcurial/o1nextgen/blob/main/docs/o1-chargen-graphics.md)), draws the same LS161/LS163 at C3 and
documents the factory's faster-rate modification: **pin 2 moved** between a
*"FOR 9600/2400 BAUD"* and a *"FOR 4800/1200 BAUD"* pad, jumpers **J2** and
**J3**, **J1** marked **"DON'T CARE"**, and the caption box

```
300/1200 NO MOD - J1 IN
600/2400 NO MOD - J1 OUT
1200/4800 MOD W/O PIN 2 (J1 = X)
2400/9600 MOD W/PIN 2 (J1 = X)
```

bracketed *"SPEED SELECTED W/IN 6850"*. The consequence for the serial work is
in [`docs/o1-modem-serial.md`](https://github.com/Myrcurial/o1nextgen/blob/main/docs/o1-modem-serial.md); the register-level view is in
[`docs/o1-memory-io-map.md`](https://github.com/Myrcurial/o1nextgen/blob/main/docs/o1-memory-io-map.md) §"6850 ACIA detail".

The same corner of the board is also where a third-party product attaches:
Advent Products' **Osbaud** solders to the ACIA's clock and supply pins (4 and
12) and two ground pins, and substitutes the clock outright —
[`docs/o1-modem-serial.md`](https://github.com/Myrcurial/o1nextgen/blob/main/docs/o1-modem-serial.md).

## 5. Extracted: the P8 34-pin floppy connector — and a correction

Read from sheet 9 of 9 (PDF page 12, DISC CONTROLLER) at 600–1200 dpi. Every
pin label on the P8 symbol was read individually:

| Pin | Signal | Pin | Signal | Pin | Signal | Pin | Signal |
|---|---|---|---|---|---|---|---|
| 1 | GND | 10 | DRV SEL 1 | 19 | GND | 28 | WRT PROT |
| 2 | GND | 11 | +12 V | 20 | STEP | 29 | GND |
| 3 | GND | 12 | DRV SEL 2 | 21 | +5 V | 30 | READ |
| **4** | **TG43** | 13 | +12 V | 22 | WRT DATA | 31 | GND |
| 5 | GND | 14 | *(not drawn)* | 23 | +5 V | 32 | SIDE SEL |
| **6** | **EARLY** | 15 | +12 V | 24 | WRT GATE | 33 | GND |
| 7 | *(not drawn)* | 16 | CLOCK (4 MHz) | 25 | +5 V | 34 | LATE |
| 8 | INDEX | 17 | +12 V | 26 | TRACK 00 | | |
| 9 | GND | 18 | DIR | 27 | GND | | |

**Pins 4 and 6 are not ground.** Pin 4 is **TG43** and pin 6 is **EARLY**; both
are driven by the FDC (UB7) through 7406 open-collector buffers (U9/U10) and
routed to the connector. Pins 7 and 14 are not drawn on P8 at all.

This contradicted [`docs/floppy-adapter-design.md`](https://github.com/Myrcurial/o1nextgen/blob/main/docs/floppy-adapter-design.md) §2, which listed
`1,2,3,4,5,6,7,9,19,27,29,31,33` as GND "per DWG 1A3004". Two things were
wrong with that:

- **The citation.** DWG 1A3004 is the *disk electronics* drawing (§1). P8 is on
  the mainboard drawing, 1A2011-00 sheet 9. The right source was being
  overlooked and the wrong one cited.
- **The content.** The transcription that went into the generator and the doc
  came from the archived Wayne Visser adapter
  ([`research/osborne1/floppy-adapter/FloppyAdapter.sch`](https://github.com/Myrcurial/o1nextgen/blob/main/research/osborne1/floppy-adapter/FloppyAdapter.sch)), which ties pins
  4, 6 and 7 to GND. That is safe for a passive Gotek-only adapter — a 7406
  open-collector output pulled low is not damaged and a Gotek ignores TG43 and
  EARLY — but it is not what the machine does, and this adapter switches the
  OEM cable through to the physical drives, so it must not clamp two live
  signals.

**Fixed** in [`hardware/floppy-adapter/gen_floppy_adapter_sch.py`](https://github.com/Myrcurial/o1nextgen/blob/main/hardware/floppy-adapter/gen_floppy_adapter_sch.py): pins 4 and 6
are now `FLP_TG43` / `FLP_EARLY` and pass straight through J1 → J2 like every
other signal. Grounding TG43 is not merely untidy: it is the FDC's track > 43
output, which is the drive's *write-current-reduce* input on 96 tpi drives, so
clamping it low would assert reduced write current permanently.

### The 2-versus-7 discrepancy (harmless, recorded for completeness)

DWG 1A3004 sheet 1 shows connector **P2** — the drive end of the same ribbon
cable — with `GND = 1,3,5,7,9,19,27,29,31,33` and `CASE = 32`, i.e. **pin 7**
grounded and pin 2 not listed. Mainboard P8 shows **pin 2** grounded and pin 7
not drawn. The digits were checked at 1200 dpi against the `27`/`29`/`31`/`33`
glyphs in the same font to rule out a misread, so the two drawings really do
disagree.

It does not matter electrically: neither pin carries a driven signal on the O1
(every signal the interface has is accounted for on other pins), so both are
safe to tie to ground. The adapter ties both, which is correct whichever
drawing is right.

## 6. Running it as a machine

A scan cannot be "run": there is no vector netlist in it, only pixels, so there
is nothing to hand to a simulator. Reading a schematic and *executing* the
machine it documents are two different jobs. The machine itself, however, runs
very well — and it is the better oracle anyway, because it exercises the design
rather than our reading of it.

MAME has an `osborne1` driver, and this machine already has everything needed:

- MAME (`brew install mame`)
- the O1 ROMs in `~/Documents/Osborne1/roms/`, including
  `3a10082-00rev-e.ud11` — the **Rev E** monitor ROM, i.e. the same board
  revision as this schematic (`ROM_DEFAULT_BIOS("ver144")` in MAME's driver)
- a headless harness in the sibling project:
  <https://github.com/Myrcurial/o1prsnt/tree/main/utilities/headless-testing-harness>

That harness is a small Lua library MAME runs via `-autoboot_script`. It
injects keystrokes through MAME's natural-keyboard device and reads the
**screen straight out of video RAM at `0xF000`** (128 bytes/row × 32 rows), so a
test asserts on what the machine is *displaying*. Run it with:

```
cd .../headless-testing-harness
O1_ROMPATH=/tmp/o1roms O1_RUNDIR=/tmp \
  ./run-test.sh mytest.lua ~/Documents/Osborne1/floppies/<image>.imd 90
```

`O1_RUNDIR` keeps MAME's `cfg/`/`snap/` litter out of the repo. `O1_ROMPATH`
must point at a directory laid out the way MAME expects — `rompath/osborne1/`
or `rompath/osborne1.zip` — not a directory of loose ROM files:

```
mkdir -p /tmp/o1roms/osborne1 && cp ~/Documents/Osborne1/roms/* /tmp/o1roms/osborne1/
```

**Verified working, 2026-10-10.** A three-line script (`H.boot_cpm()`,
`H.dump()`, `H.finish()`) booted CP/M headless and reached `A>` in 9 emulated
seconds with this on screen, read out of VRAM:

```
PIP     .COM   8k        Disk A:  1K blocks
SETUP   .COM   6k        Size=  185K, 13 Files, Used=  140K, Space=   45K
SYSGEN  .COM   2k        A>
XDIR    .COM   3k        Loading CP/M
XREF    .COM   7k        Extended Directory version 3.5
```

With `-nothrottle` the 4 MHz Z80 runs at ~20–25× real time, and because MAME
counts *emulated* seconds the timings a test measures are valid 4 MHz Z80
timings. That is what makes this useful for #29: it is a machine-level oracle
for the memory map, the I/O decode and bus timing, available before any
hardware exists.

## 7. Cross-checks against the running machine

The emulator is not just a way to run the O1; it independently confirms parts
of the extraction. MAME's driver
(`src/mame/osborne/osborne1.cpp`) encodes the hardware, and the running machine
agrees with [`docs/o1-memory-io-map.md`](https://github.com/Myrcurial/o1nextgen/blob/main/docs/o1-memory-io-map.md):

- **Banks.** Driver memory map: `0x0000–0x3fff` a ROM view whose low half is the
  4 KB monitor ROM `.mirror(0x1000)` and whose `0x2000–0x2fff` window is the I/O
  area `.mirror(0x1000)`; `0xf000–0xffff` an attribute-RAM view. That is exactly
  §2 of the map doc (ROM 0000–0FFF mirrored into 1000–1FFF, I/O 2000–2FFF
  mirrored into 3000–3FFF, video at F000).
- **Bank switching.** Driver I/O map is `map.global_mask(0x03)` with a single
  `0x00–0x03` write handler, dispatching exactly as §4 of the map doc says:
  0 → select ROM+I/O bank, 1 → back to main RAM, 2 → map attribute RAM at F000,
  3 → unmap it. The doc's four I/O writes are the four driver cases.
- **I/O decode.** The driver's window tests — floppy `(off & 0x900) == 0x100`,
  IEEE-488 `(off & 0x900) == 0x900`, keyboard `(off & 0xa00) == 0x200`,
  serial `(off & 0xa00) == 0xa00`, video PIA `(off & 0xc00) == 0xc00`,
  ScreenPac `(off & 0xc00) == 0x400` — match the doc's `2100/2900/2200/2A00/2C00`
  bases and show the decode is *partial*: peripherals alias widely and their
  outputs are ANDed together when more than one responds, which is why the doc
  calls it a "memory-mapped I/O window" rather than a decoded bus.
- **Floppy controller variant (gap #11).** The doc says "Fujitsu MB8877 ≡
  WD1793 (UB7)". MAME's driver carries the same uncertainty as a source
  comment: *"Schematics specify a WD1793 floppy controller, but we're using the
  Fujitsu equivalent MB8877 here. Is it known that the original machines used
  one or [the other]?"* Two independent readings of the same drawing, same
  conclusion — the schematic's symbol is a WD1793-compatible part, the fitted
  chip may be either.
- **Rev E alignment.** The BIOS MAME loads by default for this machine is
  `3a10082-00rev-e.ud11` (BIOS 1.44), the Rev E monitor ROM — so the emulator,
  the archived ROM and this schematic are the same board revision.

### 7a. Asking the machine directly — [`tools/check_o1_map.sh`](https://github.com/Myrcurial/o1nextgen/blob/main/tools/check_o1_map.sh)

Reading the driver is still reading someone else's model of the hardware.
[`tools/check_o1_map.sh`](https://github.com/Myrcurial/o1nextgen/blob/main/tools/check_o1_map.sh) boots the machine headlessly and interrogates it over
its own bus, then asserts what [`docs/o1-memory-io-map.md`](https://github.com/Myrcurial/o1nextgen/blob/main/docs/o1-memory-io-map.md) claims. RAM is told
from ROM by writing back the complement of the byte that was there and restoring
it — a RAM cell follows, a ROM cell does not. Eleven checks, all passing:

```
$ tools/check_o1_map.sh
program space: mask=0xFFFF width=8   io space: mask=0x0003 width=8
booted to A> after 9.0 emulated seconds
PASS  B1    CP/M reaches the A> prompt in the emulated machine
PASS  C1    0xF000 behaves as RAM (video RAM is in the RAM bank)
PASS  C2    0x4000-0xEFFF is RAM (176/176 pages)
PASS  C3    I/O write to port 0x00 selects the ROM bank
PASS  C4    I/O write to port 0x01 selects the RAM bank
PASS  C5    the data byte on a bank-switch write is ignored
PASS  C6    I/O ports 0x04/0x05 alias 0x00/0x01 (only A0/A1 decoded)
PASS  C10   the selected bank is re-derived on instruction fetch, not latched
PASS  C7    I/O port 0x02 maps the 1-bit bank-3 plane over 0xF000
PASS  C8    ROM at 0x0000-0x0FFF mirrors 0x1000-0x1FFF
PASS  C9    nominally-dead bank-2 addresses alias real devices (sloppy decode)
== 11 passed, 0 failed ==
```

The page maps it prints are §2 of the map doc in machine form: in bank 2,
ROM across `0000-1FFF`, devices across `2000-3FFF`, RAM from `4000` up; in
bank 1, RAM across all 64K. Four things it established that the documents do
not currently say:

- **The bank latch is real but does not persist.** `OUT (1),A` puts the machine
  in the RAM bank immediately, and 10 ms of emulated time later it is back in
  the ROM bank — the bank is re-derived on every instruction fetch from the
  M1/IRQACK flip-flops, and the video PIA interrupts at 60 Hz. The map doc §4
  says the selection is "qualified by M1 and IRQ-acknowledge conditions"; this
  is what that means in practice, and it is why a naive peek at `0x0000` while
  CP/M runs returns ROM bytes. Interposer logic that assumes a static bank state
  is wrong.
- **The I/O space decodes two address bits** (`io space: mask=0x0003`), so all
  256 Z80 I/O ports are `0x00-0x03` repeated 64 times — the map doc's "only the
  two low address bits are decoded", measured.
- **The ROM is live while CP/M runs.** Sampling the Z80's PC during a working
  `DIR` finds it inside the ROM (`0x0377-0x0387`, `0x0EF7-0x0EFC`) as well as in
  RAM, so the ROM is paged in and out during normal operation; "the ROM is only
  used at boot" is not true.
- **Bank-2 aliasing is measurable, not theoretical.** `0x2500` reads the floppy
  register that `0x2100` reads, `0x2601` the keyboard row that `0x2201` reads,
  `0x2c04` the video PIA port that `0x2c00` reads. Addresses that decode to two
  devices at once return the AND of both — `0x2301` is keyboard *and* floppy,
  `0x2f00` is video PIA *and* serial ACIA.

## 8. Can the schematic be turned into something runnable?

**Automatically, no — and that is a property of the file, not of effort.** Every
page is a single 1-bit JBIG2 raster at 600 dpi:

```
$ pdfimages -list research/osborne1/OCC1_1A2011-00_Schem_RevE.pdf
page   num  type   width height color comp bpc  enc  x-ppi y-ppi size
   5     0 image    6582  5137  gray    1   1  jbig2  600   600 69.1K
   6     0 image    6592  5150  gray    1   1  jbig2  600   600 86.2K
   ...
```

No vector data at all — no lines, no symbols, no netlist, nothing to walk. The
only text object is a `HiddenHorzOCR` layer from an early-1990s pass that
renders a sheet title as `J'U~ I 'IIS IO/OO-tOOnl`. Whatever "extraction" means
here, it starts from pixels.

**Re-OCRing the labels does not work either.** Tesseract on native-resolution
tiles mangles exactly the tokens that matter — `UC1 LS139` came back as
`uct LSiss`, `LS32` as `L$3e2`, `LS00` as `tS0e` — and a 1200 dpi pass returned
nothing usable at all. A harvested label index would mislead more than it
helped, so the reading stays manual and §3 is about making that fast and
accurate.

**The honest route to a netlist is manual capture**, and the only part worth
capturing is the discrete glue. Most of these sheets are Z80, DRAM, FDCs and
PIAs whose behaviour is already known; the unknowns are the small-scale logic —
above all the **wait-state generator on sheet 2/9** (`UC1`, `UC2`, `UD1`–`UD3`,
`UD9`, `UD12`, `UB1`, `UB7`, `UB12`, `UE1`–`UE3`, `UA4`, `UA5`, Q1/Q2), which is
what MAME does *not* model and what issue #29 needs. Capturing that one sheet
into KiCad gets ERC and netlist checking from the tooling `hardware/` already
has; capturing it into Verilog additionally lets it be *run*.

**What "run it as a machine" can mean, in order of fidelity:**

| Approach | Status | What it validates |
|---|---|---|
| MAME, booting CP/M headless | works (§6) | the machine, behaviourally |
| [`tools/check_o1_map.sh`](https://github.com/Myrcurial/o1nextgen/blob/main/tools/check_o1_map.sh) asserting the documented map | works (§7a) | our *reading* of the map, against the machine |
| Hand-captured glue logic as Verilog, simulated | not started | the schematic itself — the wait states MAME omits |
| The above, driven by bus traces logged from MAME | not started | the same, against real Z80 traffic |
| Whole-board gate-level simulation | not sensible | MAME already is the machine |

The last two rows are a design, not a wish: MAME's Lua can log every read and
write through an address space, so a captured decode/wait model can be driven
with real traffic and its chip-select and `WAIT` outputs compared against what
the machine actually did. A disagreement is then either a misreading of the
schematic or a MAME shortcut, and both are worth knowing. It is a multi-hour
careful job, and doing it badly would produce a wrong document — the failure
mode this whole exercise exists to avoid.

## 9. What is not extracted yet

- **What the `CHAR0–CHAR7` nets carry.** They cross to the video sheet carrying
  a `4C1` reference (sheet 4, zone C1 — the RAM array), so they are *not* the
  char-gen ROM's outputs (§4a). Presumably the character-code bus out of video
  RAM; not yet read.
- **What UC16–UC21 do on the video sheet.** The pixel row is serialised by UA14
  on sheet 4 (§4a), so the six shift registers §2 lists on sheet 5 need a
  second look before #24 relies on the phrase "character shifters".
- **Sheet 4 (1A2011 1/9) parts list.** That sheet carries the board's
  REF/DESCRIPTION table. It is partly legible in the scan and is the fastest
  route to a full IC inventory.
- **Per-sheet component inventories** for sheets 4, 5 and 8, which §2 lists
  only from a first pass — see the part-number caution in §3. (Sheet 7's serial
  area is now read at pin level — §4b.)
- **The wait-state generator (sheet 2/9)** as a captured, simulatable model
  (§8).
- **A net-level extraction** of the whole board — not achievable from this scan
  without manual capture.
