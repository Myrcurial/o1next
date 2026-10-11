---
layout: page
title: "The floppy subsystem and its formats"
subtitle: "Interfaces"
draft: "Draft &mdash; assembled from the working notes by `tools/build_book.py`. The source document is the authority; this page is a copy for reading, and it is regenerated from that source."
---

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

## Why the ROM is part of the answer — and the answer

The upgrade is described as coming with the **1.4 ROM**, and the recognition is
a property of the computer rather than of the drive electronics. The 1.44 BIOS
source and the overlay CBIOS modules are in the repo
([`research/source-code/BIOS-144-source/`](https://github.com/Myrcurial/o1nextgen/blob/main/research/source-code/BIOS-144-source/)), and reading them settles #95 without
hardware. The mechanism is **two cooperating parts, and neither is the monitor
ROM alone**:

1. **The monitor ROM senses the disk.** `SENDEN` (jump-table entry `0130`,
   `SENSE_DISK_DENSITY`) tries both densities and issues a WD179x **READ
   ADDRESS** (`RADR`) on track 0. The address mark the controller finds *is* the
   disk's geometry: it yields the density (FM/MFM), the sector length and the
   sectors per track. There is no format table in the monitor ROM — the geometry
   comes off the disk. `SAVTYP` is set to a code of `density (bit 0) | sector
   length (bits 2–3)`, where the length field is `0`=128, `1`=256, `2`=512,
   `3`=1024 bytes.
2. **The DD CBIOS carries the DPB table.** `occbio95.asm` defines a table of
   Disk Parameter Blocks, and `occbio45.asm` (`GDEN`) converts the sensed
   physical sector count into a count of 128-byte *logical* sectors
   (×1/×2/×4/×8 for 128/256/512/1024) and searches the table for the entry whose
   sectors-per-track **and** type code both match. On a match it installs that
   DPB and its sector-skew translation table.

**The table is the smoking gun** (`occbio95.asm` / `occbio15.asm`, the names are
the manufacturer's own):

| Entry | Type code | Sectors/track | Block | Dir | boottrk | `DSM` formula | = capacity | Manual's figure |
|---|---|---|---|---|---|---|---|---|
| **Osborne DD** (`DSKD1`) | `0Ch` = MFM, 1024 B | 40 (=8×5) | 1 K | 64 | 3 | `((40−3)*8*5)/8` = 185 | 185 K | 182 k |
| **Osborne SD** (`DSKS1`) | `5` = FM, 256 B | 20 (=2×10) | 2 K | 64 | 3 | `((40−3)*2*10)/16` = 46 | 46 blk × 2 K = 92 K | 92 k |
| **Xerox** (`XEROX`) | `1` = FM, 128 B | 18 (=1×18) | 1 K | 32 | 3 | `((40−3)*1*18)/8` = 83 | 83 K | 80 k |
| **IBM** (`IBM`) | `8` = MFM, 512 B | 32 (=4×8) | 1 K | 64 | 1 | `((40−1)*4*8)/8` = 156 | 156 K | 156 k |
| **DEC** (`DEC`) | `8` = MFM, 512 B | 36 (=4×9) | 1 K | 64 | 2 | `((40−2)*4*9)/8` = 171 | 171 K | 171 k |

`NUMDPB = 5`. **The capacities match the manual's list exactly** — IBM 156 k and
DEC 171 k to the kilobyte — which is what makes this the answer rather than a
guess. The manual lists **six** formats and the table has **five** entries
because **Cromemco shares the Xerox geometry** (both 5.25" single-density,
80 k), so one DPB serves both names.

Each entry also carries a **sector-skew translation table** (`XTAB` in
`occbio95.asm`): Osborne DD is 1:1, Osborne SD is 2-to-1, Xerox is 5-to-1, IBM
is 1:1, DEC is 2-to-1. "Mostly DPB + FDC parameter tables", as #30's text put
it — confirmed, and the *skew* is the part that would be missed by a
geometry-only description.

So the DD upgrade's multi-format claim is a **CBIOS DPB+skew table selected by a
monitor-ROM density/sector probe** — recognition in the computer, exactly as the
manual says, with the *filesystem* parameters living on the diskette's own CBIOS
rather than in the ROM. That also explains the G2 answer (#30): a "G2 format set"
is more entries in the same table.


## What this means for the project

- The floppy personalities (#20, #30, #62) cannot be "an Osborne drive": they
  have to be able to *present* six geometries, which is a larger requirement than
  the issue assumed.
- The capacity figures are the acceptance target for the MAME test in #95: each
  format either reads **and** writes byte-comparably, or is recorded as failing,
  with the failure attributed to the ROM, the controller model or the image
  tooling.

## A second vendor made the same claim, and a bigger one: Nuevo

OCC is not the only multi-format claim of the period. Nuevo's four-way product
line, advertised in *The Portable Companion* #15 (Jan/Feb 1985, PDF p. 39),
escalates from density to format:

| Nuevo product | Price | Claim |
|---|---|---|
| Double Density Upgrade | $150 | "a full **183K** of data storage per disk" — and *"upgradable to double-sided double density"* |
| 2 x 2 Upgrade (780K) | $595 | double-sided double density, "nearly **400K each**", *"Format compatible with the new ACC Vixen"*, **128 directory entries** |
| 4 x 4 Upgrade (1580K) | $745 | "both drives are replaced with **double-sided 96 track-per-inch drives**" |

The 4 x 4 text is the important one:

> This system will **automatically recognize single-sided disks that are either
> single or double density and double-sided disks that are either 48 TPI or 96
> TPI**. You can **read or write, even boot**, any of these discs automatically.
> Directory Capacity 256 File Names.

So Nuevo claims four formats beyond the six in OCC's DD table — 96 TPI, both
densities, both sidednesses — and claims to **boot** them. Two things make that
credible rather than just advertising:

- **The stock O1 interface already carries what it needs.** P8 pin 4 is **TG43**,
  the drive's write-current-reduce input for 96 tpi media, and pin 32 is **SIDE
  SELECT** — both documented in [`docs/floppy-adapter-design.md`](https://github.com/Myrcurial/o1nextgen/blob/main/docs/floppy-adapter-design.md) from the schematic
  and the OEM cable. The controller is not the limit; the drives and the format
  table are.
- **The format table is the CBIOS's job, and Nuevo replaces it.** The installers
  on `OS1NUEVO.IMD` are DDT patches inserting `BIOS15.OBJ` at `1F00` and
  `BIOS15BM.OBJ` at `29E0` ([`docs/o1-upgrade-boards.md`](https://github.com/Myrcurial/o1nextgen/blob/main/docs/o1-upgrade-boards.md)), and the advertised
  directory capacities — 128 and 256 entries — are disk parameter block values,
  exactly what such a patch changes. The 2 x 2 and 4 x 4 prices include **new
  drives**, so the media capability is hardware and the *recognition* is the
  BIOS's.

**Consequence for #95 and #30:** the multi-format requirement is not an OCC
quirk. Two vendors shipped it, with overlapping but different format lists, and
the O1's own floppy connector carries the signals for both. A floppy personality
(#20) has to be able to present more geometries than the six in the OCC table.

## Nuevo's own BIOS 1.4 → 1.5 list: the formats are **disk parameter blocks**

Nuevo's DD manual has a passage that settles the mechanism behind all of this.
Its BIOS 1.5 differs from the factory BIOS 1.4 in ways it enumerates itself:

> 2) For BIOS Version 1.5 the **disk parameter blocks for IBM, Xerox and DEC
> formats have been removed** to provide space for code to allow **auto
> configuration at boot time via NEWSETUP.COM**. Space remains for two more DPB's
> to be inserted.
>
> 4) BIOS Version 1.5 **checks for the presence of the Nuevo 80 Column Upgrade**.
> If not present, the configuration routine for the 80 Column Upgrade will be
> skipped. Thus, the Version 1.5 BIOS will boot and run correctly on machines that
> don't have the Nuevo 80 Column Upgrade.
>
> 6) The jump table configuration and the jump table start address (**E100h**) is
> the same in BIOS Version 1.5 as in BIOS Version 1.4.
> — *Nuevo Double Density Upgrade Manual*, "differences between the two BIOS
> versions" (OCR: [`research/nuevo/Nuevo_Electronics_DD_Upgrade_Manual.ocr.txt`](https://github.com/Myrcurial/o1nextgen/blob/main/research/nuevo/Nuevo_Electronics_DD_Upgrade_Manual.ocr.txt))

Five things follow, and the first two correct an assumption worth recording:

- **"BIOS 1.4" and "BIOS 1.5" here are the *CBIOS on the system tracks*, not the
  monitor ROM.** Nuevo's installers load `BIOS15.OBJ` at `1F00` and
  `BIOS15BM.OBJ` at `29E0` ([`docs/o1-upgrade-boards.md`](https://github.com/Myrcurial/o1nextgen/blob/main/docs/o1-upgrade-boards.md)), and the manual compares
  1.5 against *"Version 1.4, the most recent **factory** version"* — so the DPB
  table it describes lives in the bootable CBIOS image, and *that* is the file to
  read for #95, not the 4 KiB monitor ROM.
- **The monitor ROM contains no literal DPBs, and the factory BIOS does not need
  them.** A structural scan of all four ROMs the project holds — factory 1.4, 1.43,
  1.44 and Nuevo 1.51 — finds **zero** CP/M DPB-shaped structures. The reason is in
  the 1.44 source: the loader *"will load single or double density and any number
  of sectors per track or bytes per sector"*, and `SENSE THE DENSITY` **probes** —
  it reads an address mark at one density, flips the density bit, and retries, with
  a second pass after a home command (`rom144.asm` lines 3666–3712). Geometry is
  discovered by trying, not by table lookup.
- **Nuevo is not a superset of the factory BIOS.** Nuevo *removed* IBM, Xerox and
  DEC to make room for its own code and re-added formats through
  **auto-configuration at boot via NEWSETUP.COM**. Two vendors, two mechanisms,
  overlapping lists — the same conclusion as above, now with the reason.
- **"Space remains for two more DPB's to be inserted"** — the table is extensible,
  which is how the 2 x 2 and 4 x 4 geometries fit into the same scheme.
- **Nuevo's BIOS checks for its own video board's presence** and skips the
  80-column configuration if it is absent — the same *pattern* as the SCREEN-PAC's
  `2400H` flag ([`docs/o1-upgrade-boards.md`](https://github.com/Myrcurial/o1nextgen/blob/main/docs/o1-upgrade-boards.md)), and the reason its 1.5 ROM still
  boots on a machine with no Nuevo hardware. The jump table sits at **E100h**,
  unchanged from 1.4, which is the region the SCREEN-PAC's width variable
  (`E1A5H`, [`docs/o1-memory-io-map.md`](https://github.com/Myrcurial/o1nextgen/blob/main/docs/o1-memory-io-map.md) §2a) lives in.

## A third vendor sold the format list itself: Osmosis OSMOS 4

Osmosis advertised the capability as a **standalone product**, in *The Portable
Companion* #11 (October 1983), PDF p. 32 = printed p. 30:

> **OSMOS 4** — Disk Formatting & Conversion: Allowing your Osborne to **read,
> write and format over 20 other manufactures CP/M formats**. $225

That is the strongest form of the claim in the archive: not a capability bundled
into a density upgrade (OCC), and not a side effect of a BIOS rewrite (Nuevo), but
a **$225 product sold on its own**, priced *above* the $195 double-density board
it was usually bought with. The same page bundles them — "**OSMOS 1, 4 AND 5 ALL
FOR $385**", $670 separately — which is a fair measure of how much of the value
was seen to be in *formats* rather than in *density*.

Its density line, for the record: **OSMOS 1** 184k per drive on existing drives
($195), **OSMOS 1.5** single-sided DD now, 370k later with new drives ($335),
**OSMOS 2** double-sided DD, 370k ($895), **OSMOS 3** double-sided DD **double
tracking**, 750k per drive, "an incredible 1.5MB" ($1050). The full product table
is in [`docs/o1-upgrade-boards.md`](https://github.com/Myrcurial/o1nextgen/blob/main/docs/o1-upgrade-boards.md).

**The tally is four independent format mechanisms:** OCC's DPB table, Nuevo's
boot-time auto-configuration, Osmosis's separate conversion program, and the
factory BIOS's density/sector probing. A floppy personality (#20) that knows only
the stock geometry fails on any of them.

## What the DD upgrade costs in memory: the Corvus link program

A user note in *The Portable Companion* #11 (October 1983), PDF p. 54 = printed
p. 52 — "**Doubling hard disk memory**" by Bob Gras, reprinted from the OSUG
newsletter (Anchorage) — is a patch to Corvus's link program, and it says plainly
why it is needed:

> If you had a single-density Osborne computer, but now have a double-density and
> are using the Corvus hard disk drives, this one is for you. … With the new double
> density system, **more memory is required for managing the Osborne floppy
> drives**, so this value has to be reset to accommodate the double density version
> of the Osborne.

The value is a CP/M offset in `CLINK2K2.ASM` (the source for the `CLINK2` program
that links the machine to the Corvus drive):

```
IF NOT (ABOVE)      ;
DELTA  EQU  500H    ; OFFSET FROM STANDARD CP/M *
```

and the fix is to "type a **900H** in place of the **500H**", then assemble and
link with `ASM.COM` and `LOAD.COM` (the article points at the Osborne manual's
assembly instructions, pp. 253–255 of the "Rev: 2/28/82" edition). So the constant
grows by `400H` — 1 KB — between the single- and double-density versions of the
same machine, and the author's stated reason is the DD system's larger floppy-
management code. **The DD upgrade is not memory-neutral**, which matters for
anything that assumes a fixed TPA base, and it is the kind of third-party
consequence the DD documentation itself does not mention (#95).

## The acceptance test, run in MAME (#95)

The manual's claim is a capability, and the capability is testable without
hardware because the recognition is in the computer. The test: **boot ROM 1.4+ with
a DD CBIOS, put a disk in drive B, move files on and off it, and read the result
back byte-for-byte.**

### Tooling

Two small stdlib helpers were added for this ([`tools/research/`](https://github.com/Myrcurial/o1nextgen/blob/main/tools/research/)):

- **`imdmake.py`** — writes a blank Osborne 1 disk in ImageDisk form (the writer
  half of `imdinfo.py`): `--dd` = 250 kbit MFM, 40×5×1024; `--sd` = 250 kbit FM,
  40×10×256, filled with `0xE5`. It emits the `IMD 1.x:` version line first,
  because `disk-analyse` refuses a file that does not start with one.
- **`o1disk-copy.sh` + `o1disk-copy.lua`** — boot a disk in `-flop1`, put another
  in `-flop2`, wait for `A>`, type a CP/M command, and report the screen. It is
  the keyboard-injecting counterpart to `mame-boot-probe.sh`.

### Results (measured)

| Test | Command | Result |
|---|---|---|
| **ROM 1.4+ boots DD** | `mame osborne1 -bios ver14/ver143/ver144` on `52-blank.imd` | **all three boot to `A>`** |
| **Content onto B:** | `PIP B:=A:MBASIC.COM` | B: image gains `MBASIC.COM`, **byte-identical** to A:'s (24320 B) |
| **Content off B:** | `PIP A:BACK.COM=B:MBASIC.COM` | A: image gains `BACK.COM`, **byte-identical** — full round trip |
| **Foreign density read** | DD system in A:, **Osborne SD** disk in B:, `DIR B:` | **lists B:'s files** — the DD CBIOS auto-recognised the single-density disk |

The last row is the important one for this issue: it exercises the real
mechanism end to end. The monitor ROM's `SENDEN` read the SD disk's address
marks (FM, 256-byte sectors, 20/track), the DD CBIOS matched `DPBS1`, and `DIR`
read a foreign-density directory. **Osborne SD is one of the manual's six
formats, confirmed on the emulated machine.**

### A MAME gotcha worth writing down

**`os.exit(0)` in the Lua script silently discards guest disk writes.** MAME
flushes a modified image when the device is torn down at a *clean* shutdown;
`os.exit()` skips that. A `SAVE 1 HELLO.TXT` under `os.exit()` left the image
byte-identical; the same command with the script simply ending (MAME running on
to `-seconds_to_run`) persisted. `o1disk-copy.lua` therefore does **not** call
`os.exit()` — the opposite of `mame-boot-probe.lua`, which only reads.

### What the test does *not* yet cover

- **The other four formats** (Xerox 820, Cromemco, IBM CP/M-86, DEC VT-180) —
  we hold no images for them, so the DPB-table proof above stands on the source
  rather than on a run. The way to close it is to synthesise an image per DPB
  entry with `imdmake.py` (or `disk-analyse`) and `DIR` it; that is the next
  unit of work, and it is cheap now that the geometries are known.
- **Real hardware** — see below.

## IMD → HFE for the real machine

`disk-analyse` converts both ways, and the round trip is lossless on the raw
sector data:

```bash
disk-analyse blank-dd.imd blank-dd.hfe      # write to a Gotek/HxC
disk-analyse blank-dd.hfe blank-dd-back.imd # read it back
tools/research/imdinfo.py --raw a.raw blank-dd.imd
tools/research/imdinfo.py --raw b.raw blank-dd-back.imd
cmp a.raw b.raw                             # identical
```

Measured: a `--dd` blank and the `52-blank.imd` system disk both convert to HFE
(2 039 296 bytes each), and IMD→HFE→IMD reproduces the raw sector image exactly.
`disk-analyse`'s HFE output is what a hardware floppy emulator wants, so the
images built and validated above are directly testable on a real Osborne 1.



- [`research/osborne1/o1doubledensityusersguide.pdf`](https://github.com/Myrcurial/o1nextgen/blob/main/research/osborne1/o1doubledensityusersguide.pdf) — *Osborne 1 Double Density
  User Manual* (15 pages, image-only; OCR'd per the convention in
  [`research/README.md`](https://github.com/Myrcurial/o1nextgen/blob/main/research/README.md) as `o1doubledensityusersguide.ocr.txt`).
  <https://www.kev.pulo.com.au/osborne1/documents/o1doubledensityusersguide.pdf>
- [`docs/o1-memory-io-map.md`](https://github.com/Myrcurial/o1nextgen/blob/main/docs/o1-memory-io-map.md) §3 (WD179x detail) — the formats already recorded
  there from the schematic side.
