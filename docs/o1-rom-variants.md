# Osborne 1 ROM variants — canonical inventory

**Issue:** #70. **Status:** first pass — the stock and third-party images we
hold are identified by CRC32 and cross-referenced against MAME; the open
questions at the end are the work that remains.

The machine has two ROM sockets in play:

| Socket | Package | Size | Role |
|---|---|---|---|
| UD11 | 2732 (24-pin) | 4 KiB | Monitor / BIOS — the Z80 code that boots the machine |
| UA15 | 2716 (24-pin) | 2 KiB | Character generator (the 6×9 font the video logic reads) |

Both were replaced or re-programmed by the third-party upgrade vendors, so
"the Osborne 1 ROM" is really a family. This document is the map.

## Method

Every image is identified by **CRC32 over the raw bytes** plus size. CRC32 is
what MAME's ROM definitions and the archive indices both publish, so it is the
only key that cross-references cleanly. Two independent sources agreeing on a
CRC is treated as positive identification; a CRC agreeing under two different
*names* is treated as a finding, not an error.

## Stock monitor ROM (UD11, 4 KiB)

| Rev | Our copy | CRC32 | MAME name | MAME BIOS slot |
|---|---|---|---|---|
| A (1981) | — | — | `osba.bin` | `vera` — **NO_DUMP** |
| 1.2 | — | — | `osb12.bin` | `ver12` — **NO_DUMP** |
| 1.2.1 | — | — | `osb121.bin` | `ver121` — **NO_DUMP** |
| 1.3 | — | — | `osb13.bin` | `ver13` — **NO_DUMP** (source disk held: `research/source-code/OSROM13.IMD`) |
| 1.4 | `tools/emulator-setup/roms/rev1.40.ud11` | `3d966335` | `rev1.40.ud11` | `ver14` |
| 1.43 | `research/roms/os1-143.rom` | `91a48e3c` | `rev1.43.ud11` | `ver143` |
| 1.44 | `research/roms/os1-144.rom` | `c0596b14` | `3a10082-00rev-e.ud11` | `ver144` |

Corroboration: BrettHallen's `ROM/OCC1_v140.BIN`, `OCC1_v143.BIN` and
`OCC1_v144.BIN` are byte-identical to the three we hold (same CRCs), and
`research/source-code/BIOS-144-source/rom144.asm` is the original ACT80 source
for 1.44 (#72).

Two things worth noting:

- **MAME's "ver144" is the part `3a10082-00` Rev E**, not a file named
  "1.44". The revision and the part number are two names for one image.
- **BIOS A, 1.2, 1.2.1 and 1.3 have never been dumped** (MAME carries them as
  `NO_DUMP` placeholders). We hold the **ROM 1.3 source disk**, so 1.3 is
  potentially reconstructible — but **not for us**: we build from the 1.44
  source, which is in-repo and now proven to reassemble to the shipped part
  (#203). Reconstructing 1.3 would fill an *upstream* gap, so it is filed as a
  side quest, **#205**, and nothing in this project depends on it.

## Character generator (UA15, 2 KiB)

There are **two distinct images** in circulation, and which one a machine has
tracks the BIOS revision:

| Image | CRC32 | Paired with | Our copies |
|---|---|---|---|
| Early | `5297c109` | BIOS A … 1.4 | `tools/emulator-setup/roms/char.ua15` |
| Late | `6c1eab0d` | BIOS 1.43, 1.44, and every ScreenPac / Nuevo machine | `research/roms/os1-vid8.rom`, `research/roms/os1vid80.rom`, `research/roms/OCC1_ScreenPac_RevA.BIN` |

MAME's driver carries the early image five times, once per BIOS slot 0–4, with
the comment *"this is CHRROM from v1.4 BIOS MB"*, and the late image for slots
5 and 6 (1.43 / 1.44). That is the evidence for the pairing, and it is the
"early font / late font" distinction that #44 asks about — **both variants are
now captured in this repo.**

The socket itself (UA15, on mainboard sheet 4 of 9 — see
`o1-mainboard-schematic.md` §4a) is wired **2732-style**: pin 21 is strapped to
+5 V, and `/CE` (18) and `/OE` (20) are grounded. Both variants are 2 KiB 2716s,
so either drops straight in with no strapping change, and whichever is fitted
is what a socket tap reads.

### How the font is stored

The layout is **not** glyph-contiguous, and it is not obvious from the dump — it
took MAME's driver to settle it (`src/mame/osborne/osborne1.cpp`):

```
u8 const gfx = m_p_chargen[(ra << 7) | (chr & 0x7f)];
```

so the byte for scanline `ra` of character `chr` is at `rom[ra * 128 + chr]`:
all 128 characters' row 0 are contiguous, then all of row 1, and so on. Ten rows
× 128 characters = **1280 bytes**, and the remaining 768 bytes of the 2 KiB are
`0xFF`. Each row is one byte, **bit 7 = leftmost pixel**, and the cell is 8×10.

(Guessing this cost an hour: reading it as 128 glyphs of 16 bytes, or as 8 bytes
per glyph, produces plausible-looking noise and no recognisable letters. The
driver had it in one line.)

That layout matters to the video personality (#24): a socket tap reads the font
as `rom[ra * 128 + chr]`, and the Nuevo ROM adds an underline by forcing row 9
to `0xFF` when bit 7 of the character code is set.

### The two fonts really are different — 93 glyphs of 128

Comparing the two images glyph by glyph (`tools/romfont.py` decodes both):

| | Differing characters |
|---|---|
| 0x00–0x1F graphics set | **0 of 32** — byte-identical |
| 0x20–0x7E printable ASCII | **90 of 95** |
| 0x7F and the rest | 3 |

Only three printable characters are shared: space, the apostrophe and the
backtick. So this is not a tweak — the late font is a different typeface, and the
graphics set was carried over unchanged. That settles the open question below,
and it means "which font is fitted" is a visible difference, not a subtle one.

### Finding: one late image, five names

The bytes `6c1eab0d` appear under five different names across three sources:

| Source | Name |
|---|---|
| Maslin's archive | `os1-vid8.rom` |
| Maslin's archive | `os1vid80.rom` |
| BrettHallen | `OCC1_char.BIN` |
| BrettHallen | `OCC1_ScreenPac_RevA.BIN` ("Screen Pac BIOS Rev. A") |
| MAME | `7a3007-00.ud15` and `character_generator_6-29-84.14` |

So the stock late character generator, the ScreenPac's 2 KiB ROM and the
Nuevo-era date-stamped character generator are **the same 2 KiB image**. The
ScreenPac's 80/104-column capability therefore does not live in this ROM, and
MAME models the ScreenPac as a *clone of `osborne1` with no ROM differences at
all* (`osborne1sp` is a `COMP` of `osborne1`, while `osborne1nv` is a separate
machine with its own ROMs). That matches the picture that the Nuevo 80-column
implementation is a different design from the OCC one.

## Third-party ROMs

| ROM | Size | CRC32 | Our copy | What it is |
|---|---|---|---|---|
| Micro Management **OZROM 1E** | 4 KiB | `ba1f6131` | `research/roms/OZROM-1E/OZROM_1E.BIN` | Third-party replacement monitor ROM, © 1984 Micro Management. Strings: `OZROM 1E #00187`, `(c) 1984 Micro Management`, `Slip disk in drive and press RETURN.` Manual in the same folder. |
| Nuevo Electronics **Rev 1.51** | 4 KiB | `298da402` | `tools/emulator-setup/roms/monrom-rev1.51-12.ud11` | Nuevo's replacement monitor ROM. Strings: `OSBORNE 1 COMPUTER`, `ROM Rev 1.51`, `COPYRIGHT 1983, OSBORNE COMPUTER CORP.`, `COPYRIGHT 1984, NUEVO ELECTRONICS CORP.` — i.e. an OCC ROM with Nuevo's DD/video patches. MAME name: `monrom-rev1.51-12.ud11`. |
| **SWP co-processor** | 4 KiB | `948556db` | `research/roms/swp-p88.rom` | The SWP co-processor board's own ROM. **This is 8088 code, not Z80** (`8C C8 8E D8` = `MOV AX,CS` / `MOV DS,AX`), and it carries the WD179x disk-BIOS error table (`Clock Error`, `Late DMA`, `ID CRC Error`, … `Type C to CANCEL`, `R to RETRY`, `I to IGNORE error`). Maslin's index describes it as "SWP Plus-88 card for Kaypro 2/4/10". The board and interposer card are common to every host machine and only the driver varies, so this is the 8088-side firmware of the CoPower-88 family — #3/#4/#5. |
| OCC 1.44 + OZROM combined | 8 KiB | `edc31846` | *not copied* | BrettHallen's 2764 image for the 2732→2764 daughterboard, holding OCC 1.44 and OZROM 1E with A12 selecting between them. Recorded here for completeness. |

## Personality-relevant properties

Some interposer personalities are only compatible with some of these ROMs, so the
firmware needs to know more than the CRC. The facts below are what the
personality gate is built on (#86). Each is recorded with its evidence, because
two of them were inference until the bytes were read.

| ROM | IEEE-488 driver | Video window | Evidence |
|---|---|---|---|
| OCC 1.4, 1.43 | **present** | 4 KiB (`F000-FFFF`) | `013F-0156` holds eight `JP` vectors (`c3 36 09 …`), and the printer entry points `0187-0190` are `JP`s. Byte-identical between 1.4 and 1.43 |
| OCC 1.44 | **present** | 4 KiB | Same structure with shifted targets (`c3 49 09 …`), and the implementation is in source we hold: `rom144.asm` `;IEEE-488 INTERFACE.` line 2606 (`o1-rom-source.md`) |
| OZROM 1E | **removed** | **3 KiB** (`F000-FBFF`) | Manual (`OZROM_1E_Manual.ocr.txt`), verbatim: *"The OZROM 1E does not support the IEEE-488 functions"*; *"013F-0156 WERE IEEE-488 ROUTINES / CALLING THESE FORMER JUMPS RESULTS IN A CONTROLLED SYSTEM CRASH (NO DAMAGE TO DISK DATA)"*; *"IEEE-488 AS IOBYTE DEVICE 3 NOW NULL DEVICE"*. Confirmed in the bytes: `013F-0156` is `ef f3 00 f7 …` — not jumps — and `0187-0190` is `f6 ff c9 f6 ff c9 af c9 c9 c9` = `OR 0FFH; RET` ×2 then `XOR A; RET; RET`, exactly the documented printer stubs. Video: *"only 3K of RAM is used for the video (F000-FBFF hex) since the last 1K is used for the redefinable keyboard and extra function keys"* |
| Nuevo 1.51 | **present, routines unverified** | unknown | The vector block is intact (`013F-0156` = eight `JP`s, `0187-0190` = `JP`s), so Nuevo kept the entry points — but nothing shows the routines behind them are unpatched. Not usable for Drive C until read (#86) |
| OCC 1.44 + OZROM (8 KiB) | depends on A12 | — | Daughterboard image; which half is live is a hardware strap, so a probe cannot tell from the CRC alone |

Three consequences, all of which the gate encodes:

1. **Drive C (#6, #22, #84) and the virtual printer (#19) both need the IEEE-488
   driver**, so both are refused under OZROM 1E. The printer is the less obvious
   of the two: the ROM's printer entry points `0187-0190` are precisely what
   OZROM stubs out.
2. **The video personality (#24) must cope with a 3 KiB window** under OZROM 1E,
   where `FC00-FFFF` belongs to OZROM's keyboard features.
3. **An unknown ROM must not be assumed good.** BIOS A/1.2/1.2.1/1.3 have never
   been dumped, so a machine fitted with one is unidentifiable — the gate refuses
   rather than guesses.

## MAME cross-reference

MAME carries three Osborne 1 machines; the relationship between them is itself
evidence about the upgrade boards:

| MAME machine | Year | Parent | ROM set |
|---|---|---|---|
| `osborne1` | 1981 | — | BIOS A/1.2/1.2.1/1.3 (NO_DUMP) + 1.4 + 1.43 + 1.44, chargen early + late |
| `osborne1sp` "Osborne-1 with SCREEN-PAC" | 1983 | `osborne1` | **no ROM differences** — a clone, so the ScreenPac is modelled as hardware only |
| `osborne1nv` "Osborne-1 (Nuevo Video)" | 1984 | `osborne1` | `monrom-rev1.51-12.ud11` + `7a3007-00.ud15` + `character_generator_6-29-84.14` — its own BIOS and chargen |

`tools/check_o1_map.sh` already selects a driver from the boot image's
`52-`/`80-`/`104-` prefix (`osborne1` / `osborne1nv` / `osborne1sp`), so this
table is also the map from video mode to ROM set.

## Open questions

1. ~~**Do the two character generators actually differ in the font?**~~ **Answered
   — yes, substantially.** 93 of 128 glyphs differ, and the 32 graphics characters
   are byte-identical (see "The two fonts really are different" above). Only
   space, apostrophe and backtick are shared. `tools/romfont.py` decodes either
   image to a font, so the comparison can be repeated.
2. **What is BrettHallen's "Screen Pac BIOS Rev. A"?** It is byte-identical to
   the stock late character generator, so the label may be wrong — or the
   ScreenPac genuinely ships an unmodified char-gen and does its 80-column work
   entirely in hardware. Settle against the ScreenPac install and service pages
   (`research/screenpac/`, `research/osborne1/`). Affects #24.
3. **ROM 1.3 can probably be reconstructed — as a side quest (#205).** We hold
   the 1.3 source disk (`research/source-code/OSROM13.IMD`, comment `rom 1.3,
   cbios .3 osborne source 12/16/81`) while MAME carries 1.3 as `NO_DUMP`.
   Reassembling it with the now in-repo ACT80 (`research/act-assembler/`) would
   fill a real gap upstream, and would also give us BIOS A / 1.2 / 1.2.1 if
   those sources exist on the other source disks. **The project itself has no
   use for it** — everything we build is built from the 1.44 source — so this is
   filed as a side quest rather than as work in the #72 tree.
4. **Confirm `swp-p88.rom` is host-independent.** The working assumption is
   that the co-processor board and interposer are common and only the host
   driver differs, which makes this the CoPower-88 ROM rather than a
   Kaypro-only artefact. A disassembly would confirm it and simultaneously
   yield the host mailbox protocol — #3/#4/#5.

## Provenance

- Stock monitor ROMs `os1-143.rom`, `os1-144.rom`, and the character generators
  `os1-vid8.rom` / `os1vid80.rom` — [Don Maslin's ROM archive](http://www.retroarchive.org/maslin/disks/roms/) on retroarchive.org.
- `OZROM-1E/*`, `OCC1_ScreenPac_RevA.BIN` — [github.com/BrettHallen/Osborne_1](https://github.com/BrettHallen/Osborne_1) `ROM/` (the OZROM manual is his cleaned-up copy).
- `tools/emulator-setup/roms/*` — the MAME `osborne1` / `osborne1nv` ROM sets, matching the CRCs MAME's driver publishes.
- ROM 1.44 source — `github.com/BrettHallen/Osborne_1` `ROM/Source_Code_v144/`; the OCC engineering source disks are from bitsavers.
- Cross-reference data — MAME `src/mame/osborne/osborne1.cpp` (`ROM_START( osborne1 )`, `ROM_START( osborne1nv )`, and the `COMP()` lines).

See `research/README.md` for the per-file archive provenance, and #74 for the
two images whose source is still unrecorded.

