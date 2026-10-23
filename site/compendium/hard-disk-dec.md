---
layout: page
title: "The hard-disk decision: the ACB-4000"
subtitle: "Peripherals and storage · decided"
draft: "Draft &mdash; assembled from the working notes by `tools/build_book.py`. The source document is the authority; this page is a copy for reading, and it is regenerated from that source."
---

**Status: Solved.** As a decision: emulate the **Adaptec ACB-4000** SCSI-1
controller — the one inside the Mega-byte / Media Distributing **MD-10** — and
**not** the ACT 1982 unit. One personality, built as a **faithful ACB-4000 SCSI
target behind a configurable host-adapter shim**, so that the same firmware
serves any Z80 machine with an ACB-4000-class driver and not only the Osborne 1.
The build this authorises is #179; §10 carries what is still open.

This is the decision [`docs/occ1-harddisk-analysis.md`](https://github.com/Myrcurial/o1next/blob/main/docs/occ1-harddisk-analysis.md) was the groundwork for. It
answers #8's remaining checklist: the command set is documented (§4, from the
vendor's own OEM manual), the recommendation is written (§2), and the ACT's port
claim is read out of the ACT's own BIOS (§3). It is also the **formal plan** for
the personality (§9).

**The DPB is in the archive.** `0x055E` is an **offset from the MD-10 BIOS's load
address `0xD800`**, not a low-RAM address, so the per-drive type bytes sit at
`0xDD5E`, the 24-byte descriptors at `0xDD6E` and the DPB at `0xDDB6` — all
*static data inside the BIOS image*, read straight out of `HARD.COM` at file
offsets `0x998`, `0x9A8` and `0x9F0` (§7.3; [`docs/md10-system.md`](https://github.com/Myrcurial/o1next/blob/main/docs/md10-system.md) §9). What is
left is not the numbers but **who copies the static tables into a running system**
(§10 item 1).

Sources: [`research/harddisk/`](https://github.com/Myrcurial/o1next/blob/main/research/harddisk/) (the ACT disk) and [`research/adaptec/`](https://github.com/Myrcurial/o1next/blob/main/research/adaptec/) (the MD-10
software) — both extracted and disassembled in-project; and the Adaptec ACB-4000
OEM manual, archived at [`research/adaptec/acb4000/`](https://github.com/Myrcurial/o1next/blob/main/research/adaptec/acb4000/) (§4, and the archive note in
§9.1). Serves #8; overlaps #20, #27, #84.

## 1. The decision, in one sentence

**The interposer emulates an Adaptec ACB-4000 — a standard ANSI X3T9.2 SCSI-1
target — presented to the host through a small, configurable port block; the
Osborne 1 configuration of that block is the one the MD-10 driver expects.**

Two consequences worth stating up front, because they are the point:

- We are **not** emulating the MD-10's host adapter as a one-off. We are
  emulating the **controller** the MD-10 was built on, and *describing* the
  host adapter as configuration. That is what makes the personality portable
  (§5).
- Nothing here needs the Osborne 1's own floppy controller, IEEE port, or any
  other onboard device, so the personality **does not contend for a port** with
  Drive C, the printer or the RT-60A (§2). That is the opposite of the ACT route.

## 2. Why — the two candidates, measured

Both products are in the archive. Both were disassembled for this decision
(`z80dasm`, scratch listings; the reusable commands are in the sources of
[`docs/occ1-harddisk-analysis.md`](https://github.com/Myrcurial/o1next/blob/main/docs/occ1-harddisk-analysis.md)). The comparison is not close:

| | ACT (1982) | **MD-10 / Adaptec ACB-4000** |
|---|---|---|
| Host interface | **bit-banged over the IEEE-488 PIA** `2900–2903` | its **own 4-register port block**, 4-aligned relocatable base (default `30h`) |
| Protocol documented? | **No** — must be reverse-engineered from `HARDBIOS.HEX` | **Yes** — SCSI-1 command set, handshake and a sample driver, all in the OEM manual |
| Host software | a **full BIOS replacement** (17-jump table; no floppy driver at all) | driver + BIOS/BDOS/CCP overlays, installed by `HARD.COM` |
| Geometry | 5/10 MB, undocumented | **MODE SELECT descriptor** — block size, cylinders, heads, reduced-write-current, precomp, landing zone, step code |
| Port contention | shares **P3** with Drive C / printer / RT-60A | **none** — its own port block |
| Reverse engineering left | the entire protocol | *bounded*: which status bit is REQ / BSY / phase |
| Primary sources held | the driver disk only | the driver disk **and** schematic, photos, controller ROMs, two OEM manuals (§9.1) |

**Recommendation: emulate the ACB-4000.** The deciding argument is not
electrical convenience — it is that one route requires inventing a protocol and
the other requires implementing a published one. The ACT's command set lives
only in its own BIOS image; the ACB-4000's is a standard SCSI-1 CDB set that
Adaptec printed, with a worked Z80 driver, a worked format sequence and a
register map (§4).

## 3. The ACT — the ports it actually uses

#8 flagged the port claim in [`docs/occ1-harddisk-analysis.md`](https://github.com/Myrcurial/o1next/blob/main/docs/occ1-harddisk-analysis.md) — `0x2A00`
(command/data) and `0x2C01` (status) — as suspect: those addresses "are the ACIA
and video PIA, so something there is misread." The flag was right. Disassembling
`HARDBIOS.HEX` (`z80dasm`, `org 0xDF00`, `0xDF00`–`0xEB00`) settles all three
points:

1. **`0x2A00`/`0x2A01`/`0x2C01` are not the disk.** `0x2A00`/`0x2A01` are the
   console **ACIA** (`2A00` status read / control write, `2A01` RX/TX) — the
   console helpers `sub_e992h`/`sub_e99bh` read `2A00` and test **bit 1 =
   TDRE** and **bit 0 = RDRF** — and `0x2C01` is the **video PIA**.
   [`docs/o1-memory-io-map.md`](https://github.com/Myrcurial/o1next/blob/main/docs/o1-memory-io-map.md) §3 already says so; the driver confirms it.
2. **The disk rides the IEEE-488 PIA at `2900–2903`.** It is the only device
   routine in the image, it is reached from the disk path — READ (`E32A`) →
   `sub_e448h` → `E475` → `sub_e520h` → `sub_e58fh` (`E58F`) — and it works by
   `set 3,(02902h)` / `res 3,(02902h)` as a **PB3 strobe** around `ld
   a,(02900h)` / `ld (02900h),a`, with `cpl` throughout for active-low. That is
   the *same transport Drive C uses*.
3. **The "indirect `OUT (C),A`, target TBD" is the bank restore.** `C` comes
   from `[0xEF08]`, which the two bank helpers set to `0` or `1`; `OUT (C),A` is
   simply re-selecting the bank on the way out. It is not a disk port.

The ACT's `MOVCPM10/5/F.COM` are **stock Digital Research `MOVCPM.COM`** builds
(identical strings, a handful of patched bytes), *not* evidence of 5 MB / 10 MB
volume sizes — so the ACT's version list is three builds of one utility, not
three volume sizes.

**Honest residue.** The ACT board itself is unattested — no photograph or
description has been found, and the `2900–2903` conclusion is read from the
driver, not from a schematic. It does not change the decision: whether the ACT
adapter *is* the PIA or merely *mirrors* PIA-style access, its protocol is
undocumented and would have to be recovered byte by byte.

## 4. What the ACB-4000 actually is

From the OEM manual ([`research/adaptec/acb4000/500504-00_ACB-4000_OEM_Manual_Mar84.pdf`](https://github.com/Myrcurial/o1next/blob/main/research/adaptec/acb4000/500504-00_ACB-4000_OEM_Manual_Mar84.pdf)):

- **A SCSI-1 target, not a "Z80 card."** It interfaces "to a host adapter
  according to the proposed ANSI X3T9.2 Standard (SCSI)", on a 50-pin ribbon,
  single-ended, all signals low-true. It drives **two ST-506/412** drives, has a
  **1 KiB dual-ported buffer**, and **variable sector lengths 256 B – 1 KiB**
  "programmed at format time."
- **The command set** (manual Table 6-1) is the standard SCSI-1 set —
  `00` Test Unit Ready, `01` Rezero Unit, `03` Request Sense, `04` Format Unit,
  `08` Read, `0A` Write, `0B` Seek, `0F` Translate, `13`/`14` Write/Read Buffer,
  `15` Mode Select, `1A` Mode Sense, `1B` Start/Stop Unit, `1C`/`1D`
  Receive/Send Diagnostic — with a Class 01 set (Read Capacity, …) as an option.
  Commands are CDBs; completion status is a byte (bit 1 = Check condition,
  bit 2 = Equal, bit 3 = Busy).
- **The reference host adapter** (Appendix A) is a three-register model:
  `BASE` = data, `BASE+1` = control (`SELECT 40h` asserts SEL), `BASE+2` =
  status (`REQ 80h`, `I/O 40h`, `MSG 20h`, `C/D 10h`, `BUSY 08h`), with the
  controller at **ID 01**. The manual ships a **sample Z80 driver** and a
  **sample format sequence** against exactly that model.
- **Geometry is host-supplied.** `MODE SELECT` carries a descriptor list —
  block size, cylinder count, head count, reduced-write-current cylinder,
  precomp, landing zone, stepping code. That is the same field set the MD-10's
  `DRIVETBL.DAT` and its drive-table editor carry ("Enter number of cylinders /
  heads / cyl. to start reduced write current / step pulse output rate code /
  landing zone position"), so the MD-10 is a *user of* the standard descriptor,
  not a private format.
- **The fill byte is a documented feature, and it is CP/M's.** `FORMAT UNIT`
  writes a default byte (`6Ch`) **or a user-selected one**, and the manual says
  so in as many words: *"This example will assume that the format is for a CP/M
  system that requires an **E5 (HEX)** data field."* A freshly-formatted volume
  is therefore one repeated byte — which is the whole basis of the sparse blob
  (§7).
- **The controller has its own brain.** The archive holds **six 8 KiB ROM
  images** plus an Intel-HEX build ([`research/adaptec/acb4000/firmware/`](https://github.com/Myrcurial/o1next/blob/main/research/adaptec/acb4000/firmware/)), i.e.
  the ACB-4000 is a small computer running firmware, and its SCSI behaviour can
  be *read* rather than inferred. See §9.3 for how far we take that.

## 5. Portability — one personality, many Z80 machines

The ACB-4000 has **no "Z80 side."** Its host side is SCSI; what a Z80 machine
has is a **host adapter** (a SCSI initiator), and *that* is the machine-specific
part. The good news is that a host adapter is small and stereotyped — a data
register, a control register with a `SEL` bit, and a status register with
`REQ`/`I/O`/`MSG`/`C/D`/`BUSY` — and the OEM manual documents exactly that model
as its reference (§4). So the personality is built in three layers, and **only
the middle one is per-machine**:

| Layer | What it is | Machine-specific? |
|---|---|---|
| **SCSI target** | ACB-4000 command set, phases, status/sense, two LUNs, `MODE SELECT` geometry, `FORMAT` fill byte | **No** — one implementation, to spec |
| **Host-adapter shim** | the Z80-side port block: base port, register roles, status bit map | **Yes** — a *profile*, not code |
| **Backing store** | the FAT32 blob, the mailbox, `MOUNT.COM` | No |

Ship the shim with at least two profiles: **`md10`** (the Osborne 1 adapter —
base `30h`, the observed bit map, §6) and **`reference`** (the OEM Appendix A
model, §4). The first runs the period MD-10 software unchanged; the second runs
any driver written against Adaptec's documented adapter. Add profiles as
machines are found.

**This is not a new idea — it is the original's.** The MD-10's host adapter was
almost certainly a **Z80-socket device** itself (that is why it "does not tie up
existing OSBORNE ports", why it can decode its own `IN`/`OUT` ports, and why the
ad can promise it "will interface with any Z-80 computer … using CP/M, OASIS or
other system"). Our interposer is doing what the original board did; we are
simply making the host-adapter half a *description* instead of a fixed PCB, so
that the SCSI half is written once. (Inference from the ad and the port map, not
from a schematic of the MD-10 board.)

The Z80-socket form factor is the portability carrier: any machine with a
socketed 40-pin Z80 can host the interposer, and the **bus side does not vary** —
a Z80 socket is a Z80 socket, so the electrical interface is the same wherever
the board fits. What varies between machines is **logical, not electrical**:
(a) which port/register model *that machine's driver* expects, and (b) whether
the machine already decodes those addresses — and the interposer overrides them
either way. Both are configuration, so the shim is a *profile* (a table), not a
board. The original MD-10 host adapter was a PCB, but nothing about the Z80 side
of it needs to be.

## 6. The Osborne 1 shape of it (the MD-10)

From the MD-10 software ([`research/adaptec/`](https://github.com/Myrcurial/o1next/blob/main/research/adaptec/), disassembled):

- **Port base is a parameter.** `HARDBIOS.SPR` is built for base **`30h`**; the
  shipped `HD00BIOS.SPR`/`HD04BIOS.SPR` are the *same code* at base **`00h`** and
  **`04h`** — that is the "must be on a 4 port boundary" prompt — and
  `PORTCHNG.COM` is a **file patcher** (it contains no `IN`/`OUT` of its own) that
  rewrites the base. So the profile's base port is exactly the thing `PORTCHNG`
  edits.
- **Registers:** `base+0` data (also the `OUTI`/`INI` block port), `base+1`
  control, `base+2` status read / control write, `base+3` control. Status bits
  the driver polls: `01h`, `02h`, `20h`, `40h`. The probe, the transaction and
  the bit meanings are read out in [`docs/acb4000-host-adapter.md`](https://github.com/Myrcurial/o1next/blob/main/docs/acb4000-host-adapter.md) §1 — including
  that `base+2` reading `04h` is "exactly one controller on-line", and that
  `30h`–`33h` **alias onto the on-board 2-bit I/O decode** (so the adapter must
  own the bus for those ports; §2).
- **Host software:** `HARD.COM` installs; `HARDBIOS.SPR`, `HARDBDOS.SPR` and
  `HARDCCP.SPR` overlay BIOS/BDOS/CCP (the same *shape* as the ACT, but over a
  documented controller).
- **Drive letters — the boot letters.** The MD-10 advertisement is explicit:
  *"With a single hard disk installation, the MD-10 10 subsystem becomes units A
  and B with the standard drives being designated E and F. If a second MD-10 is
  installed later it becomes units C and D."* The hard disk takes `A:`/`B:`
  because the hard disk is the **boot** device — CP/M boots from `A:`. The two
  letters are the ACB-4000's **two LUNs**.
- **User areas:** the ad claims *"36 different user areas per MD-10"* — beyond
  CP/M 2.2's 32. Whether that is the driver extending user areas or just
  loose copy is a sub-issue (§9.4).
- **Memory overhead:** the ad claims *"less than 2K"* of TPA for the driver.

## 7. What we can offer — sizes, the CP/M 2.2 ceiling, and the sparse blob

**"What size disks can we offer?"** Three limits stack, and the smallest wins:

| Limit | Where it comes from | Value |
|---|---|---|
| The controller | ACB-4000: two ST-506 drives, sector 256 B – 1 KiB, **geometry is host-supplied** | two LUNs, any geometry the drive table defines |
| The driver's DPB | MD-10: `DRIVETBL.DAT` + the drive-table editor set cylinders / heads / RWC / step / landing zone | per-logical-drive size is whatever the DPB says |
| CP/M 2.2 | `DSM` is 16 bits; drives `A:`–`P:`; max file 8 MB | ≈1 GiB per drive at 16 KiB blocks; 8 MB per file |

The advertised envelope is **10 MB (MD-10), 20 MB (MD-20), "20 and 44 MB also
available."** Because the controller auto-configures to the host-supplied
geometry and we back it with a blob, **our practical limit is the driver's DPB,
not our storage** — we can offer any geometry `DRIVETBL.DAT` can describe. The
drive table's fields are read (§7.2) and so is the DPB (§7.3), so the geometry
side of that is settled and #179 has a default; what is not chased is which copy
of the tables a boot actually uses (§10 item 1).

**"How does it handle CP/M 2.2's limits on the Osborne?"**

- **16 logical drives** is CP/M's limit, not the device's — the same conclusion
  [`docs/drive-c-protocol.md`](https://github.com/Myrcurial/o1next/blob/main/docs/drive-c-protocol.md) §8.4 reached for Drive C.
- **8 MB per file** is CP/M 2.2's extent limit; the ad's "read or write a 64K
  file in less than four seconds" sits comfortably inside it.
- The O1's **stock BIOS is fixed-size with floppy-sized DPBs**, so the MD-10
  **replaces BIOS + BDOS + CCP** (`HARDBIOS/HARDBDOS/HARDCCP.SPR`) rather than
  wedging into the existing jump table. That is the mechanism by which a bigger
  DPB and more drives become possible at all.
- TPA overhead: claimed < 2 KiB. User areas: the ad claims **36** (> CP/M's 32).

**The sparse blob.** The ACB-4000's `FORMAT` writes a fill byte across the whole
drive — default `6Ch`, and `E5h` "for a CP/M system" (§4) — so a freshly
formatted, empty volume is *one repeated byte*, and a used volume is that byte
with islands of data. Two encodings, both self-describing:

- **Blank volume:** `(fill_byte, geometry)` — effectively zero bytes.
- **Truncated:** the non-fill extent, plus the fill byte and the full geometry,
  reconstituted on load.

This is the same "the size *is* the geometry" trick as the Drive C blob
([`docs/drive-c-design.md`](https://github.com/Myrcurial/o1next/blob/main/docs/drive-c-design.md) §4.2), with one addition the user's original sketch
did not need: **record the fill byte rather than assuming `0xE5`.** The
controller's default is `6Ch` and CP/M's is `E5h`, so the fill is a property of
the *volume*, not of CP/M.

One caution. CP/M writes `E5` to the **directory** eagerly but not the whole data
area ([`docs/drive-c-protocol.md`](https://github.com/Myrcurial/o1next/blob/main/docs/drive-c-protocol.md) §8.5, measured on the Drive C install), whereas
the ACB-4000's `FORMAT` is what makes the *whole* volume uniform. So a volume is
only "sparse-friendly" if it was formatted by the controller — which it will be
— and the trailing-fill length should be **measured on a formatted volume**
before the tooling trusts it.

### 7.1 What #178 found — directories, not loose files

Reading the MD-10 BIOS overlay `HARDBIOS.SPR` (the file maps to address
`0xE000 + offset`; the BIOS jump table is at `0xE100`, and its entries are
relative to that base, so `SELDSK` at `0xE1D5`):

- **It is a CP/M 2.2 filesystem.** `SELDSK` returns a **DPH**, so the volume is an
  ordinary CP/M logical drive with a **directory** — `DIR`, `PIP`, `ERA`, `STAT`
  work, and files are normal CP/M files. It is *not* a raw 10 MB blob of loose
  files.
- **Up to 16 logical drives, not two.** `SELDSK` opens with `LD A,C` / `CP 10h`
  (`0xE1D5`–`0xE1D7`) — the driver can present all of CP/M's `A:`–`P:`. The
  advertisement's "units A and B" is the shipped *default*, not a limit.
- **The geometry is data-driven, which is why there is no literal DPB.**
  `SELDSK` indexes a **per-drive type byte** at `0x055E` (one per drive; `0FFh` =
  drive absent), then a table of **24-byte per-type descriptors at `0x056E`**,
  selecting entry `type × 24`; the returned DPH sits at entry `+8`. The per-drive
  track limit lives at `0x016F`/`0x0170`. So the DPB is *built* from the drive
  table — the same reason `DRIVETBL.DAT` is editable.
- **Management is standard CP/M plus the vendor's own tools.** `MD10.COM` /
  `MD20.COM` is the drive-table editor *and* `PREP` — format with a label and a
  password, two-pass format then verify. `PORTCHNG.COM` relocates the port base.
  The companion disk carries the transfer/backup set (`AREN`, `DIRA`/`DIRS`,
  `GET`/`PUT`, `ERQ`, `FSET`, `NS`, `OSD`, `POP`, `SUBMIT`, `WSPATCH.*`).
- **The controller driver is a separate overlay, and it is port-parameterised.**
  `CNTLRCOD.OVL` — and `CNT00COD.OVL` / `CNT04COD.OVL`, the *same code* at port
  bases `30h` / `00h` / `04h` — loads at **`0x8000`**. The SCSI handshake is right
  there: poll `base+2`, write the command byte held at `0x8023` to `base+0`, then
  block-transfer with `OUTI`/`INI`. And the ACB-4000's default format fill byte
  (`6Ch`, §4) sits at `0x8024` as a lone data byte — an independent confirmation
  of the controller, found in the driver rather than the manual.
- **`DRIVETBL.DAT` is a list of drive-model entries.** This is the table
  `MD10.COM` edits and `SELDSK`'s 24-byte descriptors are built from. Its shape
  is not what its own *directory entry* says: the entry claims 128 bytes while
  the file owns nine allocation blocks and holds 16 512 bytes of live data.
  **§7.2 has the structure and the byte→field mapping.**
- **The DPB is static data in the BIOS image**, not a table built in low RAM.
  The per-drive type bytes, the 24-byte descriptors and the DPB itself are read
  out of `HARD.COM` at `0xDD5E`, `0xDD6E` and `0xDDB6` (§7.3). What is not yet
  chased is which copy a boot uses — the static one, or the drive's own copy of
  the geometry and type bytes at LBA 4 ([`docs/md10-system.md`](https://github.com/Myrcurial/o1next/blob/main/docs/md10-system.md) §3, §9.1).

### 7.2 The drive table — structure, and the byte→field mapping (#178)

**Solved**, by reading the shipped file and then running the editor that edits it.

Two things about the file's shape hide the mapping, and both are read from the
file rather than assumed:

- **`DRIVETBL.DAT` is not one 128-byte record.** Its directory entry says
  `rc = 1` (128 bytes) and even sits at extent 1, but the file owns nine
  allocation blocks and holds **16 512 bytes of live data**. A `cpmfs.py get`
  therefore returns the header and five name records and nothing else; the rest
  is reachable only by walking the block list ([`tools/research/drivetbl.py`](https://github.com/Myrcurial/o1next/blob/main/tools/research/drivetbl.py)).
- **A record is not a 7-byte name plus four parameter bytes.** The name field is
  **ten** bytes, and the four bytes are not the numeric fields at all — the
  geometry lives somewhere else entirely.

#### The file

| Offset | Length | Holds |
|---|---|---|
| `0x0000` | 13 | **Header.** `+0..1` = `13 + 11×N`, the end offset of the name table (LE); `+2` = the next free description-record index (`0x81` = 129 here); `+3` = `0x0D` = 13 — the header length, i.e. where the records start; `+4..12` = 0 |
| `0x000D` | `11×N` | **126 name records** of 11 bytes: a NUL-terminated name of up to 10 characters, then **one byte — the index of that drive's description record** |
| `13+11N` | 9 | **Sentinel** `00 "RDBAK" 00 00 00`. Its leading `0x00` is what stops the driver's name search |
| `0x0800` | `128×113` | **113 description records**, one per index 16…128, at file offset `128 × index` — so records 11–15 of the file are a gap between the two areas |
| desc. record | `+0..8` | **the nine geometry bytes** |
| | `+9..127` | the free-text description, NUL-terminated, with the stale tails of longer earlier strings left behind |

#### The nine geometry bytes — the mapping

They are **not packed**. They are the ACB-4000's own `MODE SELECT`
drive-parameter block, field for field, in the manual's order (parameter-list
offsets `0D`–`15`):

| Description record | Manual (`MODE SELECT`) | Field | Stored as |
|---|---|---|---|
| `+0..1` | `0D`–`0E` | Cylinder count | 16-bit, **little-endian** |
| `+2` | `0F` | Head count | 8-bit |
| `+3..4` | `10`–`11` | Reduced-write-current cylinder | 16-bit, LE |
| `+5..6` | `12`–`13` | Write-precompensation cylinder | 16-bit, LE |
| `+7` | `14` | Landing zone | 8-bit (signed in the editor: `Lz=+0`) |
| `+8` | `15` | Step pulse output rate code | 8-bit |

The manual's block is big-endian and the file is little-endian, so the driver
byte-swaps when it builds the descriptor. **That byte order is the whole of
it** — nothing here is packed; five fields in eight bytes was never the shape of
the thing.

Two of the fields are outside the editor: it prompts for cylinders, heads,
reduced-write-current, landing zone and step code (measured, below) and neither
displays nor writes `+5..6`. The manual puts write precompensation there and
every entry in the shipped table has it zero, so **precomp is inferred**, not
measured.

#### The name record

An 11-byte record is a NUL-terminated name of up to ten characters and then the
description index. The driver's name search compares at most ten bytes and stops
at the typed name's terminator (`LD B,9` / `DJNZ`, `0x0C04`–`0x0C12`), so **the
bytes after the name's NUL are never read by the driver**. In the shipped table
they are not consistently name text (`AT3020` is followed by `"15"`, the Seagate
entries by `"62"`, `D-720` by three unprintable bytes), so their meaning is
unresolved and, for #179, irrelevant.

Bit 7 of a name's **first** byte is a flag — the search masks it off with
`AND 7Fh`. In this table it is set on 26 entries, and every one of them is an
alias: all 26 share their description record with another name (the editor's
"Add `<S>`ynonym"), and no unflagged entry shares one.

#### How we know

**Measured**, in MAME, by running the editor itself. `MD10.COM` will not start
without an ACB-4000 answering on `30h`–`33h`, so **three** 3-byte patches were
applied ([`tools/research/md10patch.py`](https://github.com/Myrcurial/o1next/blob/main/tools/research/md10patch.py)): the overlay's init call at `0x0219`,
which is what exits the program when nothing answers; the probe at `0x15AF`; and
the branch at `0x0EE8`, which takes the loaded table to the editor's menu instead
of its "name not found" path. Nothing else in the program is touched — the
geometry code, the editor and the file I/O are the vendor's own bytes. With that,
the editor's own `<L>ist parameters` prints, for `CM5205`:

```
CM5205: Computer Memories, Inc. model CM5205
  Cyl=256, Head=2, Reduc=256, Lz=+0, Step=1, Cap=4608K
```

and the description record at index 16 is `00 01 | 02 | 00 01 | 00 00 | 00 | 01`
— 256, 2, 256, 0, 0, 1. Field for field, including the little-endian pair. The
same run fixed the rest:

- the editor's prompts run **cylinders, heads, reduced-write-current, landing
  zone, step code** — ascending record offsets 0, 2, 3, 7, 8;
- pointed at the 13-byte *header* instead of a record, the same display reads the
  header's bytes at those offsets — `Cyl=1399, Head=129, Reduc=13, Lz=+0, Step=0`
  is `77 05` / `81` / `0d 00` / `00` / `00` — an independent check of the offsets
  from the measured display;
- the loader reads 11 CP/M records (1408 bytes) into `0x3001` and sets the
  current-record offset at `0x3004` to **13** — the header length.

**Read from the primary source**: the shipped `DRIVETBL.DAT` itself, dumped by
[`tools/research/drivetbl.py`](https://github.com/Myrcurial/o1next/blob/main/tools/research/drivetbl.py). **Read from the driver**: the write side uses the
same five offsets (`LD (2719h),HL` … `LD (2721h),A`). **Cross-checked against the
manual and against the real drives**: the step codes are the manual's table
(`0` = 3 ms unbuffered, ST-506; `1` = 28 µs buffered, ST-412; `2` = 12 µs
buffered, most others) and the shipped entries obey it exactly — `ST506` → 0,
`ST412` → 1, everything else → 2; and the geometries are the drives' own:
`ST506` 153/4, `ST412` 306/4, `ST419` 306/6, `SA604` 416/4, `XT-1065` 918/7,
`XT-1140` 918/15, `XT-2085` 1224/7.

**Not obtained**: a write-back diff. In the emulated run the editor took an edit,
prompted through all five fields and returned to its menu without rewriting
`DRIVETBL.DAT` — the only bytes that changed in the image were our own patch — so
the write side is read from the code, not measured.

#### What this gives #179

A default geometry, and the table to pick it from. The editor's own template for
a new entry is the name `PYXIS13`, and that name is in the table — the vendor's
default drive. A selection from it:

| Entry | Cyl | Heads | RWC | LZ | Step | Cap | Description |
|---|---|---|---|---|---|---|---|
| **`PYXIS13`** | **321** | **4** | **132** | **0** | **2** | 11 556K | Rodime PLC model RO 202 / Ampex model Pyxis 13 |
| `ST506` | 153 | 4 | 128 | 0 | 0 | 5 508K | Seagate model ST506 — the manual's reference drive |
| `ST412` | 306 | 4 | 306 | 0 | 1 | 11 016K | Seagate model ST412 |
| `RO202E` | 640 | 4 | 0 | 0 | 2 | 23 040K | Rodime PLC model RO 202E |
| `PYXIS27` | 321 | 8 | 132 | 0 | 2 | 23 112K | Rodime PLC model RO 204 / Ampex model Pyxis 27 |

**Recommendation: `PYXIS13`.** It is what `MD10.COM` itself offers a new drive,
it lands in the MD-10's advertised 10 MB class, and period software and the
driver accept it by construction. `ST506` is worth keeping as a second profile:
it is the manual's worked example and the only step-code-0 case, so it exercises
a different code path. `Cap` is the editor's own formula,
`cylinders × heads × 18 × 512 B`, which reproduces its `Cap=4608K` for `CM5205`
exactly; the personality need not agree with it, but #179's `MODE SENSE` must
report the geometry the table holds.

The whole table — 126 entries over 113 description records — is in
`research/adaptec/MD Utilities Adaptec 4000 Controller Ver. 1.93 Osborne - MD-10
MD-20.img`; [`tools/research/drivetbl.py`](https://github.com/Myrcurial/o1next/blob/main/tools/research/drivetbl.py) prints it. The 2.01 disk carries the
same table byte-for-byte.

**A second, independent list.** `DRIVETBL.DAT` is Osborne's/MD-10's list. The
period list archived at [`research/adaptec/compatible-drives-1991-usenet.txt`](https://github.com/Myrcurial/o1next/blob/main/research/adaptec/compatible-drives-1991-usenet.txt)
(Robert Haar, `comp.sys.3b1`, Feb 1991, reposting Lenny Tropiano's 1989 table
out of the Western Digital support BBS) is the *drive manufacturers'* one, and
it is broader: Atasi, ALPS, Ampex, CMI, Disctron, Evotek, Fujitsu, IMI,
Maxtor, Microscience, Miniscribe, Mitsubishi, NEC, Newbury, Priam, Rodime,
Seagate, Sony, Tandon, Teac, Texas Instruments, Toshiba, Tulin, Vertex and
Western Digital. It also gives each drive's **sectors/track** — 17 for almost
every entry — which `DRIVETBL.DAT` does not carry at all (its capacity formula
assumes 18), and it numbers `PYXIS-13` at **320** cylinders where `DRIVETBL.DAT`
says **321**. Neither is wrong: one is the drive's own number, the other is what
the tools carry. Nothing is reconciled here; both are recorded, because the
personality (#179) may offer any geometry the driver's DPB can describe, not
only the 126 in the shipped table.

**Making a drive image.** [`tools/research/mkdrive.py`](https://github.com/Myrcurial/o1next/blob/main/tools/research/mkdrive.py) builds a blank-but-formatted
ST-506/MFM image for any geometry, byte-wise, without the 1984 tools:

```sh
tools/research/mkdrive.py --out /tmp/md10/hd.chd                  # PYXIS13
tools/research/mkdrive.py --out /tmp/md10/st412.chd --chs 306,4,17
```

It fills every sector's data field with **`6C`**, which is what the ACB-4000's
FORMAT writes by default — "completely written with 6C hex unless otherwise
specified in the format command" (`research/adaptec/acb4000/…Users_Manual_Oct85`,
§4.4.5 and the FORMAT command reference) — and passes the geometry to `chdman`,
whose `GDDD` metadata is the same record the controller keeps in the disk's ID
fields. `PREP.COM` asks for a *unique* fill byte and sends `D9` in its FORMAT
CDB, so `--fill d9` exists too. It is needed because `PREP.COM` cannot finish its
own format under MAME — the verify pass that follows it (`2F`) has no handler
([`docs/osborne1nx-machine.md`](https://github.com/Myrcurial/o1next/blob/main/docs/osborne1nx-machine.md) §5).

The drive's *own* structure — what `PREP.COM` writes once it has finished a
format — is read: it is the four-block header at LBA 0–3 read
out of the program, with the disk label and its 28-byte partition records at
LBA 0. [`docs/osborne1nx-machine.md`](https://github.com/Myrcurial/o1next/blob/main/docs/osborne1nx-machine.md) §6 has the field map and the recipe.

#### Running the editor

Four things were added to [`tools/research/`](https://github.com/Myrcurial/o1next/blob/main/tools/research/) for this, each with a header saying
what it was for: `o1raw2imd.py` (wrap an archive `.img` for MAME, which will not
open a bare raw sector image), `o1keys.lua` + `o1keys.sh` (a scripted-keystroke
harness, with a `peek` directive — that is what made the in-memory table
checkable), `md10patch.py` (patch a file inside the image, by name; the three
patches above) and `drivetbl.py` (dump the table).

### 7.3 The DPB — read out of `HARD.COM`, with its values and its mechanism (#178)

**The DPB is in the archive.**  #178's acceptance is "the DPB for each logical
drive is written down with its source offset", and both halves are now read: the
**values**, out of the file, and the **mechanism**, out of the code.

The audit that produced a negative result here read `0x055E` as a *low-RAM*
address.  It is not one.  It is an **offset from the BIOS's load address**, and
the MD-10 BIOS loads at `0xD800` ([`docs/md10-system.md`](https://github.com/Myrcurial/o1next/blob/main/docs/md10-system.md) §4), so:

| What | Address | `HARD.COM` file offset | Size |
|---|---|---|---|
| per-drive type byte table | `0xDD5E` | `0x0998` | 16 bytes |
| 24-byte per-type descriptors | `0xDD6E` | `0x09A8` | 24 × type |
| **the DPB** | `0xDDB6` | `0x09F0` | 15 bytes |

All three are **static data inside the BIOS image** — the address less the
loader's `0x0100` origin — so they are read out of the file rather than watched
at run time.  [`docs/md10-system.md`](https://github.com/Myrcurial/o1next/blob/main/docs/md10-system.md) §9 read them out and cross-checked them
against the driver's code; the values below are that reading, and this section
does not restate its §9.1.

**The DPB itself** — 15 bytes at `HARD.COM` file `0x09F0`:

```
file 0x09F0   9C F0 | 05 | 1F | 01 | 83 07 | FF 03 | FF | 00 | 00 00 | 00 00
              SPT   | BSH| BLM| EXM| DSM   | DRM   | AL0| AL1| CKS   | OFF
              F09Ch | 5  | 31 | 1  | 1923  | 1023  | FF | 00 | 0     | 0
```

**`DPB+3` is `31`** — the `BLM` read independently out of the driver's *code*
("the driver reads `DPB+3` as `BLM`").  Two readings agreeing is what makes
`0xDDB6` the DPB rather than a lookalike.

`BLM = 31` is 4096-byte blocks, so `DSM = 1923` is 7.88 MB per logical drive;
`DRM = 1023` is 1024 directory entries; `AL0 = FFh` is the eight directory
blocks; `CKS = 0` is a fixed disk, which is right.  **`SPT` reads `F09Ch` =
61 596, and that is not a sector count: it is the partition measured in 128-byte
records** — `61596 × 128 = 7 884 288 = 15399 × 512`, exactly one 15399-block
partition.  So the DPB does not merely *describe* a partition size, it **is** the
partition size, and it is the same 15399 blocks `PREP.COM` writes when it is
given a `PYXIS27` ([`docs/md10-system.md`](https://github.com/Myrcurial/o1next/blob/main/docs/md10-system.md) §3).

**One DPB, shared by every hard-disk drive.**  The three descriptors carry `DPB`
`0xDDB6`, `DIRBUF` `0xEE80` and `CSV` 0 in common; only the allocation vector
differs, at `0xDDC5`/`0xDEB6`/`0xDFA7` — exactly `0xF1` = 241 bytes apart, which
is the ALV size for `DSM = 1923`.  Two consequences, both load-bearing for #179:
every hard-disk partition is the same size in CP/M's view, and the only layout in
which the drive and the driver agree is **three 15399-block partitions on a
`PYXIS27`**.  [`docs/md10-system.md`](https://github.com/Myrcurial/o1next/blob/main/docs/md10-system.md) §9.1 has the descriptors and the arithmetic.

#### The chain, with source offsets

All offsets are file offsets into `HARDBIOS.SPR`, which maps to `0xE000 + offset`.
It is a **relocatable** image: the BIOS jump table is at file offset `0x100`
(`0xE100`) and its operands — and the routine's own internal `JP`/`CALL` targets —
are *offsets from the table*, not addresses.  That is why the table below names
`0x055E`/`0x056E`: they are the operands as written, and they resolve to
`0xDD5E`/`0xDD6E` once the BIOS is installed at `0xD800`.  Read the image
linearly and the disassembler drifts through the data and invents instructions;
[`tools/research/hardbios.py`](https://github.com/Myrcurial/o1next/blob/main/tools/research/hardbios.py) resolves them the way the loader does.

| Step | Offset | What it does |
|---|---|---|
| `SELDSK` entry | `0x11B` | jump table: operand `0x00D5` → target `0x1D5` |
| drive range | `0x1D5` | `LD A,C` / `CP 010h` / `RET NC` — drives 0–15, else NULL |
| type byte | `0x1DC`–`0x1E7` | saves the drive at `0x0180`, indexes `0x055E + drive`; `0FFh` = absent |
| descriptor | `0x1F6`–`0x203` | `type * 8`, then ×3 more, then `+ 0x056E` → `0x056E + type*24` |
| the DPH | `0x204`–`0x209` | `+ 8`, saved to `0x0555`, returned in `HL` |
| **the DPB pointer** | `0x393`–`0x39C` | in READ/WRITE: `HL = (0x0555)` — the saved DPH — `+10`, dereference → **the DPB** |
| block size | `0x39D`–`0x3A2` | `+3` into the DPB = **BLM**, `+1` = the deblocking count |
| sector size | `0x3DA`–`0x3E4` | `SRL H` / `RR L` **twice** — the 128-byte CP/M record number shifts right two, so the physical sector is **512 bytes** |

Three things follow, and they are the substance of the answer:

1. **There is a DPB per logical drive, and it is an ordinary CP/M 2.2 DPB.**  The
   driver reaches it at DPH+10 — the DPH's `DPB` field in the canonical layout
   (XLT 0–1, scratch 2–7, DIRBUF 8–9, **DPB 10–11**, CSV 12–13, ALV 14–15) — and
   then reads `DPB+3` as `BLM`.  So the descriptor points at a 15-byte DPB whose
   fields are the usual SPT/BSH/BLM/EXM/DSM/DRM/AL0/AL1/CKS/OFF.
2. **`SPT` is counted in 128-byte records, four to a physical sector.**  The
   record→sector conversion is a two-bit shift (`0x3DA`), so a 17-sector track is
   `SPT = 68`.  Whoever turns §7.2's geometry into a DPB needs that, and it is read
   from the code rather than assumed.
3. **A descriptor entry is 24 bytes with the DPH at `+8`**, so it carries eight
   bytes *before* the DPH.  What those eight hold is not determined — nothing in
   the archive reads them.

#### How the tables were found, and why the first search missed them

`tools/research/hardbios.py audit` searched for a *writer* of `0x055E`/`0x056E`,
treating them as absolute low-RAM addresses, and swept `0x0500`–`0x0700`:

```
=== writers of 0x0500-0x0700 ===
  HARDBIOS.SPR       0555@0x209 0557@0x18D 0557@0x217 0558@0x1E9
  ...
  0x055E / 0x056E writers: NONE
```

Three things follow, and together they are why the tables read as "missing":

- **The sweep found the relocatable *operands*, not the data.**  `LD BC,055E` /
  `LD DE,056E` inside the overlay are reported (`LD DE,056E` at `hardbios.spr`
  offset `0x200`); the tables they index live at `0xDD5E`/`0xDD6E`, outside the
  searched window.  A store to a BIOS-relative address is not a store to
  `0x0500`–`0x0700`.
- **The tables are not in the `.SPR` files at all.**  A byte search for the
  16-byte type run, the `01 14 00 00 27 3C` descriptor prefix and the ten-byte
  DPB prefix finds all three in `HARD.COM` and in **none** of `HARDBIOS.SPR`,
  `HARDBDOS.SPR` or `HARDCCP.SPR`.  The `.SPR` is a *different, larger* build —
  its body is `0x880` bytes against the embedded copy's `0x5C5` — the same BIOS
  at the same entry points but not the same image.  The driver's fallback table
  therefore lives only in the loader that installs it, which is why #178's audit
  of the `.SPR` files found no writer.
- **The writes the audit does find are the BIOS's own variables** — `0x0555` (the
  saved DPH), `0x0557` (a flag), `0x0558` (the saved type), i.e. `0xDD55`,
  `0xDD57`, `0xDD58`.  The two tables `SELDSK` *reads* are read-only.

Two further checks close the alternatives:

- **Not data carried by another overlay.**  If an overlay were loaded so that its
  bytes landed on the tables, the table would be there as *data*.  It is not:
  those offsets in `HARDBDOS.SPR` and `HARDCCP.SPR` are code, and neither file
  contains a per-drive type run (`00 01 02 … FF`) or a 24-byte record table.
- **Not in a system image — and it does not need to be.**  The MD utilities disk
  is a **data** disk: its system tracks (tracks 0–2, 7680 bytes) are **all
  `0xE5`**, and no part of `HARDBIOS.SPR` appears in them.  The tables arrive
  with the BIOS instead, inside `HARD.COM`, which carries a relocated copy of the
  BIOS and copies it to `0xD800` ([`docs/md10-system.md`](https://github.com/Myrcurial/o1next/blob/main/docs/md10-system.md) §4–§6) — so they are
  *installed*, not loaded from a system image.

The geometry the DPB is built from also lives **on the drive**, written by the
last `FORMAT`; the next subsection is the manual's account of that, and it is what
the personality has to reproduce.

#### Where the drive parameters live, and how they get written

The manual answers the half the archive does not cover — where the parameters go
on the drive, and how they get there.  Three commands, read from the Mar84 OEM
manual §6.3.1:

- **`MODE SELECT` (15H)** — "is used in ACB controllers to specify FORMAT parameters
  and should always precede the FORMAT command."  Byte 4 of the CDB is the byte
  count: 12 (`0Ch`) minimum, **22 (`16h`) when the drive parameter list is
  included**.  The list is the parameter list (4 bytes, format code `01`) + the
  extent descriptor list (8) + the drive parameter list.
- **`FORMAT UNIT` (04H)** — "will write from index to index all ID and data fields
  with a block size as specified by an immediately previous MODE SELECT (15H)
  command."
- **`MODE SENSE` (1AH)** — "used to interrogate the ACB-4000 device parameter table
  to determine the specific characteristics of any disk drive currently attached.
  **The attached drive must have been formatted by an ACB-4000 for this to be a
  legal command.**"

And **where** on the drive — from the ACB-4000A user manual §2.3.1, which is an
image-only scan (OCR committed beside it per [`research/README.md`](https://github.com/Myrcurial/o1next/blob/main/research/README.md)):

> During FORMAT the disk parameters provided by the MODE SELECT command will be
> encoded onto the disk.  **These parameters are written to the ID field of
> cylinder 6.**  This information is then read to the controller during the
> power-up initialization process.  Access to these parameters is also available
> using the MODE SENSE command.
>
> This scheme obsoletes the need for the host software to initialize the
> controller on power up.

§3.7 adds that at power-up the controller "will seek the drive to the last cylinder
and read the **largest block address** present.  The parameter information and
largest block address are saved on the ... Controller" — so the **capacity** is read
back at power-up as well as the geometry.

The parameters **persist on the drive**, and the manual says so three ways:

> If these parameters are not supplied the format operation will use **previously
> supplied values if available** or the default values given below.

> ...the controller being unable to read the drive information **from a drive
> already formatted** *(the `1C` blown-format error)*

> Note that it is possible to specify only the block size in a MODE SELECT.  In
> this case **the previous drive parameters are preserved**.
> *(May83 preliminary manual)*

So the geometry is written **onto the drive** by the last `FORMAT` and read back by
`MODE SENSE` — precisely the factory-assembled case, where an ACB and its drive were
paired and formatted before an end user saw either, so the drive already carries its
parameters and a later `FORMAT` without a `MODE SELECT` keeps them.  That is what
makes `MODE SENSE` (1AH) and `READ CAPACITY` (25H) a **correctness requirement** for
the personality ([`docs/acb4000-firmware.md`](https://github.com/Myrcurial/o1next/blob/main/docs/acb4000-firmware.md)), not a convenience.

The defaults, for a drive formatted with no parameter list at all — which is what an
unparameterised volume reports:

| Field | Default | Range |
|---|---|---|
| Cylinder count | **306** | 1–2048 |
| Data head count | **2** | 1–16 |
| Reduced-write-current cylinder | **150** | 0–2047 |
| Write precompensation cylinder | *ignored on the ACB-4000* (tied to RWC) | — |
| Landing zone | **0** (innermost) | 7 bits + direction bit |
| Step rate code | `00` 3.0 ms unbuffered (ST-506); `01` 28 µs buffered (ST-412); `02` 12 µs buffered | — |

#### What the manual pins, and how it relates to the DPB

The manual is about the ACB-4000, not about CP/M, so it carries no DPB.  It does
carry two of the DPB's inputs, and both bear on the one the driver holds:

- **Sectoring.**  `FORMAT` writes "**the normal 32 sectors**" of 256 bytes per track
  — **33** when the interleave is ≥ 2 — and the block size is 256, 512 or 1024 B.
  32 × 256 = **8192 bytes per track**; the driver's record→sector conversion is a
  two-bit shift (`record >> 2`), i.e. 512-byte physical sectors, 16 of them.  Either
  way a track is 8 KiB, which is **64 × 128-byte CP/M records** — the arithmetic
  behind an `SPT` field, even though the shipped DPB's `SPT` holds the *partition*
  size instead (above).  Read from the manual *and* the code, not assumed.
- **Capacity.**  `READ CAPACITY` (25H) returns "the address of the last block on the
  unit" plus the block size, in an 8-byte data field.  That is a `DSM` input the
  driver can take straight from the controller, and the first place to look before
  assuming `DSM` is computed from cylinders × heads.

Which of the two the driver actually uses at boot — the controller's report, or the
static fallback in `HARD.COM` — is the open question, and it is the same one as
"which copy of the tables" (§10 item 1).  [`docs/md10-system.md`](https://github.com/Myrcurial/o1next/blob/main/docs/md10-system.md) §3 and §9.1 have the
evidence on both sides.

#### What is left, and how to watch it

The tables and the DPB are read, so what remains is not "find the table".  It is two
narrower questions, and both are reachable on the running system:

1. **Which copy of the tables a boot uses.**  The BIOS image carries them
   (`HARD.COM` → `0xD800`), and the drive carries its own copy of the geometry and
   type bytes at LBA 4 ([`docs/md10-system.md`](https://github.com/Myrcurial/o1next/blob/main/docs/md10-system.md) §3); the two disagree in size
   ([`docs/md10-system.md`](https://github.com/Myrcurial/o1next/blob/main/docs/md10-system.md) §9.1).  Who copies one into the other is not chased.
2. **The `peek` that was going to answer it.**  #191's `peek 0x055E`/`0x056E` is now
   *reachable* — the MD-10 system boots to a prompt with three partitions
   ([`docs/md10-system.md`](https://github.com/Myrcurial/o1next/blob/main/docs/md10-system.md) §7) — so the runtime tables can be read against a running
   system rather than inferred.  The address to peek is `0xDD5E`/`0xDD6E`, not
   `0x055E`/`0x056E`.

Both routes the search left open are now closed, and neither was closed by giving
up:

1. ~~A stub ACB-4000 in MAME.~~  **Tried, and blocked** — MAME's `osborne1` decodes
   only two I/O address bits, so `30h`–`33h` alias onto the ROM-bank ports and a Lua
   stub cannot reach the adapter; it needed a MAME driver change
   ([`docs/acb4000-host-adapter.md`](https://github.com/Myrcurial/o1next/blob/main/docs/acb4000-host-adapter.md) §2).  The precedent was
   [`tools/research/drive-c-box.lua`](https://github.com/Myrcurial/o1next/blob/main/tools/research/drive-c-box.lua), a Lua model of the Drive C box, with which
   "the 1983 loader completes and PIP writes to `C:`" — the same move, for the same
   reason.  **The driver change was built: #191's `osborne1nx` machine**, which
   widens the decode to eight bits while keeping the mainboard's 2-bit alias, and
   the drive-table editor runs on it.
2. ~~A bootable MD-10 system disk.~~  **Produced, from the archive's own tools** —
   `PREP.COM` option 3 *configures an operating system onto the drive*, and the
   system it writes boots to a prompt ([`docs/md10-system.md`](https://github.com/Myrcurial/o1next/blob/main/docs/md10-system.md) §1, §7).  The *on-disk*
   half of it — the four-block header at LBA 0–3, the label at LBA 0 and the 28-byte
   partition records it carries — is read out of `PREP.COM` and reproduced on the
   emulated drive ([`docs/osborne1nx-machine.md`](https://github.com/Myrcurial/o1next/blob/main/docs/osborne1nx-machine.md) §6).

The host-adapter register protocol is read out in [`docs/acb4000-host-adapter.md`](https://github.com/Myrcurial/o1next/blob/main/docs/acb4000-host-adapter.md); §6's
open question #2 (the status bit map) is answered there — the driver polls `01h`,
`02h`, `20h`, `40h`.

[`research/harddisk/OCC1_HARDDISK.IMD`](https://github.com/Myrcurial/o1next/blob/main/research/harddisk/OCC1_HARDDISK.IMD) is a *different* controller — Australian
Computer & Telecommunications, port `00` — i.e. the RT-60A situation again: recorded
as incompatible in [`docs/occ1-harddisk-analysis.md`](https://github.com/Myrcurial/o1next/blob/main/docs/occ1-harddisk-analysis.md) §3, moved past, and not part of
this question.

## 8. Coexistence — the A/B→E/F remap and the CoPower-88

The MD-10 moves the O1's floppies from `A:`/`B:` to `E:`/`F:` (§6). Does that
hurt the CoPower-88? The honest answer is **no show-stopper, but two real
integration questions** — and neither is hardware.

1. **No port conflict.** The CoPower-88 host driver talks over its own port pair
   (`0x7E`/`0x7F` on Kaypro; the Osborne decode is still open, #5), while the
   MD-10 uses `30h–33h`. Different ports, no arbitration
   ([`docs/copower88-protocol.md`](https://github.com/Myrcurial/o1next/blob/main/docs/copower88-protocol.md)).
2. **Two things patching the BIOS.** The MD-10 *replaces* the BIOS; the
   CoPower-88 host driver *installs a BIOS wedge* and asks for a drive letter
   `A`–`P` at install time. Anything that patches the jump table has to be
   installed against the BIOS that is actually resident, so **order matters**:
   the CoPower-88 wedge must go on after the MD-10 BIOS (or be made aware of
   it). This is the same class of problem the boot disk (#28) already has to
   solve for its other drivers.
3. **Drive letters are configuration, not fate.** The CoPower-88 loader *asks*
   which host drive to use, and the Drive C precedent shows a device's letter is
   renamable ([`docs/drive-c-protocol.md`](https://github.com/Myrcurial/o1next/blob/main/docs/drive-c-protocol.md) §8.4) — so the `A:`/`B:`→`E:`/`F:` move
   is survivable, at the cost of redoing the 8088-side DOS environment.
4. **It is not MD-10-specific.** Any driver that makes the hard disk the boot
   drive renames the floppies, because CP/M boots from `A:`. The MD-10 is not
   unusually hostile here.
5. **And we own a choice.** Because we control both the personality and the boot
   disk, we *can* keep the floppies at `A:`/`B:` and put the hard disk at
   `C:`/`D:` **if** the MD-10 driver's letter assignment is reconfigurable. That
   trades vendor-faithful behaviour for CoPower-88 friendliness and should be a
   deliberate decision, not a default.

## 9. The plan

### 9.1 Archive the primary sources — first, so citations resolve

The ACB-4000 is now the chosen controller, so its primary sources belong in the
in-repo archive, with provenance rows in [`research/README.md`](https://github.com/Myrcurial/o1next/blob/main/research/README.md) (AGENTS.md). Under
[`research/adaptec/acb4000/`](https://github.com/Myrcurial/o1next/blob/main/research/adaptec/acb4000/):

| Path | What it is |
|---|---|
| `500504-00_ACB-4000_OEM_Manual_Mar84.pdf` | the OEM manual — command set, host-adapter model, sample driver, sample format |
| `400003-00A_ACB-4000A_Users_Manual_Oct85.pdf` | the ACB-4000A user manual |
| `ACB_4000_and_5000_Disk_Controllers_OEM_Manual_Preliminary_May83.pdf` | the preliminary OEM manual |
| `ACB4000A_Schematic_ARD_2025.pdf` | the board schematic |
| `firmware/` | six 8 KiB controller ROM images + an Intel-HEX build |
| `pictures/` | seven board photographs |

Source: bitsavers, `https://www.bitsavers.org/pdf/adaptec/ACB-4000/`.

### 9.2 The personality

Build the three layers of §5 in this order, each testable on its own:

1. **SCSI target** — the ACB-4000 command set, phases, `MODE SELECT` geometry,
   `FORMAT` fill byte, two LUNs. Written to the manual, machine-independent.
2. **Host-adapter shim** — ship the `md10` profile (base `30h`, the observed bit
   map) and the `reference` profile (OEM Appendix A). Profile = data, not code.
3. **Backing store** — the sparse blob (§7) behind the FAT32 library, and the
   mailbox/`MOUNT.COM` front end (§9.4).
4. **Bring-up** — run the *period* MD-10 software (`HARD.COM`, the `.SPR`
   overlays) against the personality, exactly as #84's acceptance test runs the
   period Drive C software. That is the known-good test suite, and the reason a
   "we hold the drivers" personality is worth building at all.

### 9.3 How faithful to the controller?

We hold the controller's own ROMs (§4), so a bit-exact ACB-4000 is *possible* —
run the firmware in a small emulator. **Recommendation: don't, for v1.**
Implement the documented behaviour and keep the ROMs as the **oracle** to test
against. Running the real firmware drags in the drive side (ST-506, the ACB-4000
does the sectoring and ECC) for no behavioural gain over the manual. Revisit only
if a driver turns out to depend on undocumented controller behaviour.

### 9.4 The sub-issues

| # | Sub-issue | Area | Depends on | Filed |
|---|---|---|---|---|
| 1 | **Read the MD-10 DPB and `DRIVETBL.DAT`** — pin the volume sizes and the drive-table fields | `research` | — | #178 |
| 2 | **Archive the ACB-4000 primary sources** (§9.1) — **delivered with this decision** | `research` | — | — |
| 3 | **The ACB-4000 personality** — SCSI target + `md10`/`reference` shim profiles | `firmware` | 1, 2 | #179 |
| 4 | **Hard-disk volume blob format** — sparse encoding, fill byte, geometry | `tools`/`docs` | 1 | #180 |
| 5 | **MOUNT.COM first-step menu** — personality-aware (floppy / Drive C / hard disk), plus mailbox `KIND=2` and the drive-mapping table | `software`/`docs` | 3, 4 | #181 |
| 6 | **Web-UI functional spec** — the personality registry, image library, status | `docs` | — | #182 |
| 7 | **CoPower-88 coexistence** — BIOS install order and drive-letter policy (#26, #28) | `software` | 3 | #183 |

### 9.5 What closes #8

- [x] The command sets of both products documented — the ACB-4000's from its OEM
      manual (§4); the ACT's **recorded as unobtainable** (§3), which #8 allows.
- [x] A written recommendation — the ACB-4000 (§2).
- [x] The ACT's port claim re-derived from its own BIOS and written into
      [`docs/occ1-harddisk-analysis.md`](https://github.com/Myrcurial/o1next/blob/main/docs/occ1-harddisk-analysis.md) (§3).

## 10. Open questions

1. **Which copy of the tables a boot uses.**  The DPB's values *are* in the archive
   — static data in `HARD.COM`, the type bytes and descriptors at
   `0xDD5E`/`0xDD6E` and the DPB at `0xDDB6` (§7.3, [`docs/md10-system.md`](https://github.com/Myrcurial/o1next/blob/main/docs/md10-system.md) §9) — and
   so is the system that boots ([`docs/md10-system.md`](https://github.com/Myrcurial/o1next/blob/main/docs/md10-system.md) §1).  What is not chased is
   **who copies the static tables into the running system**: the drive carries its
   own copy of the geometry and type bytes at LBA 4 ([`docs/md10-system.md`](https://github.com/Myrcurial/o1next/blob/main/docs/md10-system.md) §3), the
   BIOS image carries a fallback, and the two disagree in size
   ([`docs/md10-system.md`](https://github.com/Myrcurial/o1next/blob/main/docs/md10-system.md) §9.1).  A `peek` at `0xDD5E`/`0xDD6E` on the running
   system settles it.
2. **The MD-10 host-adapter bit map** — which observed status bit is `REQ`, which
   is `BSY`, which is phase (§6). Bounded, because the *protocol* is known; the four
   bits the driver polls are now read out in [`docs/acb4000-host-adapter.md`](https://github.com/Myrcurial/o1next/blob/main/docs/acb4000-host-adapter.md) §1
   (`01h`/`02h`/`20h`/`40h`).
3. **"36 user areas"** — a driver extension, or advertising copy?
4. **Is the MD-10's drive-letter assignment reconfigurable?** It decides whether
   we can leave the floppies at `A:`/`B:` (§8).
5. **Was the MD-10 host adapter a Z80-socket device or a port card?** §5's
   portability argument assumes the former; no photo of it has surfaced.
6. **The ACT board** — for the record only; the decision does not wait on it (§3).

## Sources

- [`research/harddisk/`](https://github.com/Myrcurial/o1next/blob/main/research/harddisk/) — the ACT software (`OCC1_HARDDISK.IMD`, `extracted/`),
  disassembled for §3.
- [`research/adaptec/`](https://github.com/Myrcurial/o1next/blob/main/research/adaptec/) — the MD-10 software (three disk images), disassembled for
  §6; and the archived ACB-4000 primary sources under [`research/adaptec/acb4000/`](https://github.com/Myrcurial/o1next/blob/main/research/adaptec/acb4000/)
  (§9.1).
- [`research/technical-articles/TPC-Issue05-1983-pp25-mega-byte-md10-hard-disk-ad.pdf`](https://github.com/Myrcurial/o1next/blob/main/research/technical-articles/TPC-Issue05-1983-pp25-mega-byte-md10-hard-disk-ad.pdf)
  (OCR at `…ocr.txt`) — the MD-10 advertisement: sizes, drive letters, user
  areas, memory overhead (§6, §7).
- [`docs/md10-system.md`](https://github.com/Myrcurial/o1next/blob/main/docs/md10-system.md) §9 — the DPB and the drive tables read out of `HARD.COM`,
  the one-DPB consequence, and the system that boots (§7.3).
- [`docs/occ1-harddisk-analysis.md`](https://github.com/Myrcurial/o1next/blob/main/docs/occ1-harddisk-analysis.md) — the product analysis this decides on top of.
- [`docs/o1-memory-io-map.md`](https://github.com/Myrcurial/o1next/blob/main/docs/o1-memory-io-map.md) §3 — the `2900`/`2A00`/`2C00` device map used in §3.
- [`docs/drive-c-protocol.md`](https://github.com/Myrcurial/o1next/blob/main/docs/drive-c-protocol.md) §8.3–§8.5, [`docs/drive-c-design.md`](https://github.com/Myrcurial/o1next/blob/main/docs/drive-c-design.md) §4.2 — the
  CP/M ceiling, the drive-letter precedent and the blob precedent (§7, §8).
- [`docs/copower88-protocol.md`](https://github.com/Myrcurial/o1next/blob/main/docs/copower88-protocol.md) — the CoPower-88 host protocol (§8).
- [`docs/virtual-peripherals-block-diagram.md`](https://github.com/Myrcurial/o1next/blob/main/docs/virtual-peripherals-block-diagram.md) §5 — the personality table this
  re-orders.
