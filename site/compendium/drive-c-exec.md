---
layout: page
title: "The Drive C's Executive variant"
subtitle: "Peripherals and storage"
draft: "Draft &mdash; assembled from the working notes by `tools/build_book.py`. The source document is the authority; this page is a copy for reading, and it is regenerated from that source."
---

**Status:** Read, compared and archived. The Executive manual turns out to be a
**direct port** of the Osborne 1 manual we already held, and the diff is small
enough to state exactly. It resolves several items `drive-c-protocol.md` §10 had
listed as open — most importantly by showing that §10's `DFD.SPR` item was the
wrong question (§4) — and it confirms that the *hardware* is a single design for
both machines (§1).

**Source:** [`research/drive_c/Drive_C_Executive_Users_Manual.pdf`](https://github.com/Myrcurial/o1nextgen/blob/main/research/drive_c/Drive_C_Executive_Users_Manual.pdf), OCR layer at
`Drive_C_Executive_Users_Manual.ocr.txt`. Drive C:, 1690 65th Street, Emeryville
CA. First edition July 1984, second printing 9/84; © 1984 *Drive C:, a joint
venture*. 111 pages, image-only scan, OCR'd at 300 dpi per the
[`research/README.md`](https://github.com/Myrcurial/o1nextgen/blob/main/research/README.md) convention. The Osborne 1 manual already in the archive is
`Drive_C_Users_Manual.pdf` — **second edition, June 1984**, same publisher.

One bibliographic note worth recording: the cover is stamped **PRELIMINARY**,
while every running header in the body reads "(final draft)". The PDF is a
draft/review copy, not a production print. Its *content* is nevertheless
complete — the appendices are all present and internally consistent (§3).

## 1. The headline: the hardware is one design

§6-2 (Executive) and §7-2 (Osborne 1) are the same appendix. Verbatim, apart
from one line:

| Specification | Osborne 1 manual §7-2 | Executive manual §6-2 |
|---|---|---|
| Dimensions | 5.6 × 5.9 × 1.0 in (14 × 15 × 2.5 cm) | identical |
| Weight | 1 lb (0.45 kg) | identical |
| Shipping weight | 3 lb (1.4 kg) | identical |
| Operating temperature | +5 to +60 °C (+40 to +140 °F) | identical |
| Storage temperature | −20 to +100 °C (−5 to +212 °F) | identical |
| **Power** | 11 to 14.5 VDC at 0.3 A max (**2.5 W nominal, 384K unit**) | identical |
| **Source** | "the **O1** EXT. VIDEO connector" | "the **Executive** EXT. VIDEO connector" |
| Latency | none (solid state, no moving parts) | identical |
| Max data throughput | 55,000 B/s (445,000 b/s) | identical |
| Random-sector access | ≈40 µs (software access time) | identical |
| Load a 32K `.COM` and run it | 1.1 s max | **1.0 s max** |

The only substantive differences are the connector the unit draws power from and
a 0.1 s better load time on the Executive — which is a host difference, not a
Drive C one.

**This is the useful result for #84.** The Drive C is not two products; it is
one box with two software personalities. The [`docs/drive-c-protocol.md`](https://github.com/Myrcurial/o1nextgen/blob/main/docs/drive-c-protocol.md) contract
is therefore the contract for *both*, and a replacement built to it serves
either machine. It also means the P3 work in [`docs/o1-ieee488-port.md`](https://github.com/Myrcurial/o1nextgen/blob/main/docs/o1-ieee488-port.md) §6
transfers wholesale — the Executive's port is the same port.

The power figure is worth quoting precisely because it is the one number a
reproduction has to beat: **2.5 W nominal** for the 384K unit, from a 11–14.5 V
rail. A Pico plus flash plus SRAM is far inside that.

## 2. The software is not the same

The two manuals describe the same product in the same words, so the diff is
clean. Everything below is a real difference:

| | Osborne 1 | Executive |
|---|---|---|
| Host operating system | CP/M 2.2 | **CP/M+** (CP/M Plus), OCC BIOS 1.0/1.1 |
| Loader | `DCL.COM` | **`ECL`** |
| Rename the unit | `DCN.COM` | **`ECN.COM`** |
| Utility program | `DCU.COM` | **`ECU.COM`** |
| QuickPac installer | `DCQINS.COM` | **`ECQINS`** |
| CCP replacement | **`DFD.SPR`** — 3K (192K) / 4K (384K) | **none** |
| Utility options | `S` space, **`O` optimize**, buffer, no-menu, `E` erase | `S` space, **`I` install/un-install**, buffer, **`D` file delete**, no-menu, `E` erase |
| System utilities appendix | COPY, SETUP, SYSGEN, **MOVCPM** | COPY, **COPYSYS**, SETUP |
| Floppy orientation | left / right | **upper / lower** (the Executive stacks its drives) |
| ZCPR appendix | §7-8 | absent |
| CP/M tutorial section | Section 4 | absent |
| Useful storage capacity | 187 KB / 376 KB | **190 KB / 380 KB** |
| TPA RAM, no print buffer | 1152 B | **768 B** |
| TPA RAM, with print buffer | 2176 B | **786 B** |
| TPA RAM, with TurboPac | 3172 B | **1024 B** |
| Disk overhead, 384K unit | 8K min, 20K with options | **4K min, 16K with options** |

Two of these are large enough to be worth stating plainly.

**The Executive runs CP/M+, and that is why the driver differs at all.** CP/M+
is a different system with a different BIOS and a different memory map, so the
Executive's loader has to patch a different host. Everything the loader does is
host-side; none of it touches the wire.

**The Executive variant has no `DFD.SPR`, and uses a fraction of the TPA RAM.**
Both follow from the first point, and §4 explains why.

## 3. The CP/M parameters are identical — and the capacity figures reconcile

§6-3 (Executive, headed "CP/M**+** PARAMETERS") and §7-3 (Osborne 1, "CP/M
PARAMETERS") carry the same table, with the same numbers:

| Parameter | 192K unit | 384K unit | TurboPac |
|---|---|---|---|
| Block size | 1K | **2K** | 8K (modifiable) |
| Directory entries | 64 | **128** | 512 per logical drive |
| Directory space | 2048 B | **4096 B** | 16384 B per drive |
| Logical sectors | 1536 | 3072 | varies |
| Reserved tracks | 0 | 6 | 12 |
| Logical sectors / track | 2 | 32 | — |
| Bytes per sector | 128 | 256 | — |

**The 384K column is our reverse-engineered DPB, field for field.** Block size
2K is `BSH = 4`; 128 directory entries is `DRM = 127`; 4096 bytes of directory
is `AL0 = C0h` (two 2K blocks). And the capacity falls out exactly:
`DSM = 191` means **192 blocks of 2K = 384 KB total**, of which the directory
takes 2, leaving **190 blocks = 380 KB usable** — the Executive's own figure.

That in turn explains why the two manuals quote *different* "useful" capacities
for the same unit, which had looked like a documentation error:

| | 192K unit | 384K unit |
|---|---:|---:|
| Raw capacity | 192 KB | 384 KB |
| less the directory | −2 KB | −4 KB |
| **= Executive's "useful"** | **190 KB** | **380 KB** |
| less `DFD.SPR` | −3 KB | −4 KB |
| **= Osborne 1's "useful"** | **187 KB** | **376 KB** |

Both books are right. The Osborne 1 figure is *net of the CCP replacement the
Osborne 1 needs and the Executive does not* — which is a neat independent
confirmation of §4.


## 4. `DFD.SPR` — what it is, and why §10's item 4 was the wrong question

`drive-c-protocol.md` §10 item 4 asked for a code-aware disassembly of
`DFD.SPR`, framing it as "the resident command layer" that calls the transport.
**That framing was the error, and the document half-knew it already**: its own
appendix table quotes the vendor describing `DFD.SPR` as "**a substitute console
command processor (CCP)**" that is "**automatically loaded**", and the
[`research/README.md`](https://github.com/Myrcurial/o1nextgen/blob/main/research/README.md) row for the *FOGHORN* review says the same. But §10 item 4
was written as though the transport lived there, so the two statements sat
unreconciled.

The Osborne 1 manual settles it, in the vendor's own words and in more detail
than the review had:

> The `DFD.SPR` file is absolutely necessary to Drive C operation. It's located
> in **user area 15**. DO NOT ATTEMPT TO ERASE `DFD.SPR` FROM USER AREA 15. This
> file is loaded each time you type `^C` and each time a program exits to CP/M.
> … The Drive C software automatically loads the `DFD.SPR` file **to replace the
> O1 Digital Research CCP** which would normally be loaded from the drive A:
> floppy disk after each `^C`.

So the picture is:

- **`DCL.COM` is the loader and carries the transport** — this we had right. It
  announces itself as `DRIVEC version 2.08`, carries `DCN version 2.07` inside
  it, and creates `DCN.COM` on the unit when it runs.
- **`DFD.SPR` is the command processor** that CP/M reloads on every warm boot in
  place of `CCP.COM`. It is a *CP/M program*, not device firmware — which is
  exactly why its committed listing "sweeps through zero blocks": it is a CCP
  image, not a driver.
- **It must be present on logical drive `A:` during initial installation**, and
  thereafter lives on the unit in user area 15. Its name "has no significance,
  but `DCL` always checks for its existence each time `DCL` is run."
- **It costs 3K on a 192K unit and 4K on a 384K unit** — a number the review did
  not give, and the one that makes §3's capacity arithmetic close.

**Why the Executive has none of this.** The Executive runs CP/M+, whose CCP is
a different animal; the O1's trick of substituting a custom CCP on warm boot has
no counterpart there. That is the whole reason the Executive variant is 4K
lighter on the unit and uses 384 fewer bytes of TPA without a print buffer
(768 vs 1152), and 1390 fewer with one (786 vs 2176).

**What this changes for #84.** It *removes* an item from the work list rather
than adding one. A replacement does not need to reimplement `DFD.SPR`: it
inherits it. The CCP that ships with the product already talks to whatever
driver is installed, so a box that satisfies `drive-c-protocol.md` §7 gets the
command layer for free. The disassembly we were going to do would have
characterised a CCP, not a device.

## 5. The disk and RAM budget, from the manuals

§7-4 (Osborne 1) and §6-4 (Executive) give the unit's overhead directly. This is
the passage that answers whether a **fixed print buffer** costs RAM-disk space —
it does:

| | Osborne 1 | | Executive | |
|---|---:|---|---:|---:|
| Function | 192K | 384K | 192K | 384K |
| Directory space | 2K | 4K | 2K | 4K |
| `DFD.SPR` | 3K | 4K | — | — |
| `DCN.COM` / `ECN.COM` | 1K opt | 2K opt | 1K opt | 2K opt |
| `DCU.COM` / `ECU.COM` | 10K opt | 10K opt | 10K opt | 10K opt |
| **minimum** | **5K** | **8K** | **2K** | **4K** |
| **with options** | **16K** | **20K** | **13K** | **16K** |

`DCL.COM` also creates a second system file the disk-space table does not list —
the manual's screen illustration shows `DCLOADED.SYS` and `DRIVEC.SYS` on the
unit, and notes that `DRIVEC.SYS` is "a SYSTEM file and will not be displayed by
DIR. To check for the `DRIVEC.SYS` file, use XDIR or STAT." (Those two names come
from a poor OCR of a screen dump, so treat the spelling as provisional; what is
solid is that there are two, they are hidden system files, and `DCL` creates
them.)

**RAM.** The O1 needs **1152 bytes** of the 64K, plus **1024** more if the print
buffer is installed — and the buffer's RAM "is not used unless you install the
Buffer at the time you run `DCL.COM`". The manual even names the consequence:
applications that use all of the TPA (it cites DeskTop Accountant) may need the
print buffer removed to load.

**Print buffer, in the unit's own memory:**

- Fixed Buffer Capacity: user-selectable **16K to 128K in 16K steps**.
- Dynamic Buffer Capacity: up to the maximum space available on the unit.
- TurboPac spool buffer: **128K fixed on the 384K unit, not installed on the
  192K unit**.

That last line is the 192K/384K TurboPac split, and it is also the explanation
for the print buffer's disk cost: a fixed buffer is carved out of the RAM disk,
so a 384K unit running TurboPac is **256K cache + 128K fixed print buffer** —
which is precisely what the Osborne 1 manual says in its feature list.


## 6. The printer connector is P3, re-presented — and it checks our pinout

Both manuals carry the same appendix (§7-5 / §6-5) giving the cable from the
unit's **PRINTER/HARD DISK/8088** connector to a Centronics printer. That
connector is a **26-pin card edge** — the same edge as P3 — and its pin
assignments match our transcribed P3 table ([`docs/o1-ieee488-port.md`](https://github.com/Myrcurial/o1nextgen/blob/main/docs/o1-ieee488-port.md) §6, §6.2)
**line for line**:

| Drive C 26-pin edge | Signal (manual) | Our P3 table | Centronics |
|---|---|---|---|
| 1, 3, 5, 7 | data bits 0–3 | `DIO1`–`DIO4` (odd pins) | 2, 3, 4, 5 |
| 2, 4, 6, 8 | data bits 4–7 | `DIO5`–`DIO8` (even pins) | 6, 7, 8, 9 |
| 11 | Output Strobe | `DAV` | 1 |
| 13 | **NRFD** | `NRFD` | (12, PE — must be cut) |
| 15 | Printer Busy | **`NDAC`** | 11 |
| 19 | SRQ | `SRQ` | 13 (SLCT OUT) |
| 12, 14, 16, 18, 20, 22, 23, 24 | ground | the same eight grounds | 19–30 |

Four things this buys us:

- **The interleave is confirmed by a second, independent source.** Odd pins are
  data bits 0–3, even pins are 4–7 — the vendor's own cable table, not just
  Figure 4.1.2.
- **The ground set is confirmed exactly** — pins 12, 14, 16, 18, 20, 22, 23, 24,
  the same eight our table lists.
- **The dual-purpose pin 15 is confirmed.** It is `NDAC` on the bus and *Printer
  Busy* in the printer personality — precisely the "one pin, two meanings"
  constraint [`docs/o1-ieee488-port.md`](https://github.com/Myrcurial/o1nextgen/blob/main/docs/o1-ieee488-port.md) §6.2 already recorded, now corroborated
  by the product that has to live with it.
- **The Drive C watches pin 13 (`NRFD`).** The manual is emphatic that a cable
  carrying Centronics pin 12 (Paper Error) to pin 13 "will interfere with normal
  Drive C operation if connected and MUST be removed". So the box must leave
  `NRFD` harmless as well as `NDAC` — a constraint for
  [`docs/drive-c-design.md`](https://github.com/Myrcurial/o1nextgen/blob/main/docs/drive-c-design.md) §2.3.

**One discrepancy, recorded rather than smoothed over:** our P3 table has pin 10
as `REN` (`CB2`), while the Drive C's cable table lists pin 10 as **ground**
(tied to Centronics pin 30). Either the Drive C's cable grounds a line it does
not need, or the two connectors are not bit-identical on that pin. It does not
affect anything a replacement has to do — `REN` is unused by every personality
we care about — but the two tables disagree and that should be noted rather than
assumed away.

## 7. What the Executive manual does *not* have

Worth listing, because absence is evidence about how the product was maintained:

- **No `DFD.SPR`**, and no equivalent. CP/M+ needs no CCP substitution (§4).
- **No ZCPR appendix.** The O1 manual's §7-8 covers running ZCPR with Drive C;
  the Executive's appendix list stops at §6-6.
- **No CP/M tutorial.** The O1 manual's Section 4 teaches CP/M; the Executive
  manual renumbers everything up by one and drops it, so its Section 4 is the
  RAM-disk/print-buffer/utility section.
- **No MOVCPM rule.** The O1's §7-1 warns that `MOVCPM` "must be run BEFORE
  running the Drive C Loader, `DCL.COM`" or it reports a "Synchronization
  Error". The Executive's §6-1 has no equivalent — CP/M+ is configured with
  `SETUP`, and `GENCPM`-style rebuilding is a different mechanism.
- **No fourth system utility is named.** The Executive's §6-1 opens "There are
  four programs supplied with your Executive" and then documents three: COPY,
  COPYSYS and SETUP. The O1's §7-1 names all four of its own (COPY, SETUP,
  SYSGEN, MOVCPM). Whether the Executive's fourth was dropped from the draft or
  simply never written is not determinable from this copy.


## 8. What this changes

**For #84, the Executive variant is not a second design to build.** It is the
same box with a different loader, and the contract in [`docs/drive-c-protocol.md`](https://github.com/Myrcurial/o1nextgen/blob/main/docs/drive-c-protocol.md)
is the contract for both. The reproduction target does not change.

**It removes work rather than adding it.** The `DFD.SPR` disassembly that
`drive-c-protocol.md` §10 item 4 was carrying is no longer needed: `DFD.SPR` is
a CCP, it ships with the product, and a replacement inherits it (§4).

**It closes the fixed-print-buffer question.** A fixed buffer is carved out of
the unit's RAM disk, and the manuals give the budget table (§5). The 384K
TurboPac split — 256K cache + 128K fixed print buffer — is stated outright.

**It corroborates the P3 pinout from a second vendor document** (§6), including
the interleave, the ground set and the dual-purpose pin 15.

**It supplies the mechanical, electrical and performance envelope** (§1): 5.6 ×
5.9 × 1.0 in, 1 lb, 11–14.5 VDC at 0.3 A max and **2.5 W nominal** for the 384K
unit, 55,000 B/s throughput, ≈40 µs random-sector access. Those are now targets
rather than unknowns in [`docs/drive-c-design.md`](https://github.com/Myrcurial/o1nextgen/blob/main/docs/drive-c-design.md).

### What is still open

1. **How the box resolves banks 0–2** (`drive-c-protocol.md` §10 item 2) —
   unchanged by any of this, still the sharpest question, still not a blocker.
2. **Bus loading** (`drive-c-design.md` §7 item 2) — unchanged.
3. **The Executive driver software.** The manual tells us what the Executive's
   loader is called (`ECL`) and what it does, but we do not have it. If one
   surfaces, the interesting comparison is *why the Executive driver needs 768
   bytes of TPA where the Osborne 1's needs 1152* — the answer is in how each
   patches its host, and it would tell us how much of the driver is host
   adaptation versus device work.
4. **`DCLOADED.SYS` and `DRIVEC.SYS`** (§5) — two hidden system files that
   `DCL` creates on the unit and the disk-space table does not itemise. Their
   names come from a poor OCR of a screen illustration, so even the spelling is
   provisional.
5. **Pin 10** (§6) — `REN` in our P3 table, ground in the Drive C's cable table.

## Sources

- [`research/drive_c/Drive_C_Executive_Users_Manual.pdf`](https://github.com/Myrcurial/o1nextgen/blob/main/research/drive_c/Drive_C_Executive_Users_Manual.pdf) and
  `Drive_C_Executive_Users_Manual.ocr.txt` — the Executive manual. First edition
  July 1984, second printing 9/84; © 1984 Drive C:, a joint venture. 111 pages,
  image-only; OCR'd at 300 dpi per the [`research/README.md`](https://github.com/Myrcurial/o1nextgen/blob/main/research/README.md) convention.
  Owner-supplied local file, 2026-10-11; source URL not yet recorded.
- [`research/drive_c/Drive_C_Users_Manual.pdf`](https://github.com/Myrcurial/o1nextgen/blob/main/research/drive_c/Drive_C_Users_Manual.pdf) and `…ocr.txt` — the Osborne 1
  manual, second edition June 1984. The source of §4, §5 and most of §3.
- [`docs/drive-c-protocol.md`](https://github.com/Myrcurial/o1nextgen/blob/main/docs/drive-c-protocol.md) §5 (the frame), §8 (the DPB and the ceiling), §10
  (open questions this closes or leaves).
- [`docs/o1-ieee488-port.md`](https://github.com/Myrcurial/o1nextgen/blob/main/docs/o1-ieee488-port.md) §6/§6.2 — the P3 pinout §6 corroborates.
- [`research/drive_c/extracted/dcl.com`](https://github.com/Myrcurial/o1nextgen/blob/main/research/drive_c/extracted/dcl.com) — `DRIVEC version 2.08`, `DCN version
  2.07`, and the `DFD     SPR` / `DCN     COM` / `DCU     COM` name literals
  quoted in §4.
