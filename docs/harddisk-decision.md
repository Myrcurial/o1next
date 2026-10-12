# Osborne 1 hard disk — the controller decision, and the plan (#8)

**Status: decided.** Emulate the **Adaptec ACB-4000** SCSI-1 controller — the one
inside the Mega-byte / Media Distributing **MD-10** — and **not** the ACT 1982
unit. One personality, built as a **faithful ACB-4000 SCSI target behind a
configurable host-adapter shim**, so that the same firmware serves any Z80
machine with an ACB-4000-class driver and not only the Osborne 1.

This is the decision `docs/occ1-harddisk-analysis.md` was the groundwork for. It
answers #8's remaining checklist: the command set is documented (§4, from the
vendor's own OEM manual), the recommendation is written (§2), and the port claim
is corrected (§3). It is also the **formal plan** for the personality (§9).

Sources: `research/harddisk/` (the ACT disk) and `research/adaptec/` (the MD-10
software) — both extracted and disassembled in-project; and the Adaptec ACB-4000
OEM manual, archived at `research/adaptec/acb4000/` (§4, and the archive note in
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
`docs/occ1-harddisk-analysis.md`). The comparison is not close:

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

## 3. The ACT, corrected

`docs/occ1-harddisk-analysis.md` recorded the ACT adapter's registers as
`0x2A00` (command/data) and `0x2C01` (status), and #8 flagged that those
addresses "are the ACIA and video PIA, so something there is misread." The
disassembly says the flag was right. Three corrections:

1. **`0x2A00`/`0x2A01`/`0x2C01` are not the disk.** `0x2A00`/`0x2A01` are the
   console **ACIA** (`2A00` status read / control write, `2A01` RX/TX) — the
   console helpers `sub_e992h`/`sub_e99bh` read `2A00` and test **bit 1 =
   TDRE** and **bit 0 = RDRF** — and `0x2C01` is the **video PIA**.
   `docs/o1-memory-io-map.md` §3 already says so; the driver confirms it.
2. **The disk rides the IEEE-488 PIA at `2900–2903`.** It is the only device
   routine in the image, it is reached from the disk path — READ (`E32A`) →
   `sub_e448h` → `E475` → `sub_e520h` → `sub_e58fh` (`E58F`) — and it works by
   `set 3,(02902h)` / `res 3,(02902h)` as a **PB3 strobe** around `ld
   a,(02900h)` / `ld (02900h),a`, with `cpl` throughout for active-low. That is
   the *same transport Drive C uses*.
3. **The "indirect `OUT (C),A`, target TBD" is the bank restore.** `C` comes
   from `[0xEF08]`, which the two bank helpers set to `0` or `1`; `OUT (C),A` is
   simply re-selecting the bank on the way out. It is not a disk port.

One further correction, for the record: the ACT's `MOVCPM10/5/F.COM` are **stock
Digital Research `MOVCPM.COM`** builds (identical strings, a handful of patched
bytes), *not* evidence of 5 MB / 10 MB volume sizes. The analysis doc's "MOVCPM
variants (10MB / 5MB … volume sizing)" should be read as "stock MOVCPM, three
builds."

**Honest residue.** The ACT board itself is unattested — no photograph or
description has been found, and the `2900–2903` conclusion is read from the
driver, not from a schematic. It does not change the decision: whether the ACT
adapter *is* the PIA or merely *mirrors* PIA-style access, its protocol is
undocumented and would have to be recovered byte by byte.

## 4. What the ACB-4000 actually is

From the OEM manual (`research/adaptec/acb4000/500504-00_ACB-4000_OEM_Manual_Mar84.pdf`):

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
  images** plus an Intel-HEX build (`research/adaptec/acb4000/firmware/`), i.e.
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

The Z80-socket form factor is itself the portability carrier: any machine with a
socketed 40-pin Z80 can host the interposer. The limits to be honest about are
(a) a non-Osborne machine needs a shim profile that matches *its* driver, and
(b) the interposer must snoop *that* machine's bus — the SCSI layer does not
change, the plumbing around it does.

## 6. The Osborne 1 shape of it (the MD-10)

From the MD-10 software (`research/adaptec/`, disassembled):

- **Port base is a parameter.** `HARDBIOS.SPR` is built for base **`30h`**; the
  shipped `HD00BIOS.SPR`/`HD04BIOS.SPR` are the *same code* at base **`00h`** and
  **`04h`** — that is the "must be on a 4 port boundary" prompt — and
  `PORTCHNG.COM` is a **file patcher** (it contains no `IN`/`OUT` of its own) that
  rewrites the base. So the profile's base port is exactly the thing `PORTCHNG`
  edits.
- **Registers:** `base+0` data (also the `OUTI`/`INI` block port), `base+1`
  control, `base+2` status read / control write, `base+3` control. Status bits
  the driver polls: `01h`, `02h`, `20h`, `40h`.
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
DPB itself is *not yet read* (§9.4, item 1); it is the one number this
decision still owes.

**"How does it handle CP/M 2.2's limits on the Osborne?"**

- **16 logical drives** is CP/M's limit, not the device's — the same conclusion
  `docs/drive-c-protocol.md` §8.4 reached for Drive C.
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
(`docs/drive-c-design.md` §4.2), with one addition the user's original sketch
did not need: **record the fill byte rather than assuming `0xE5`.** The
controller's default is `6Ch` and CP/M's is `E5h`, so the fill is a property of
the *volume*, not of CP/M.

One caution. CP/M writes `E5` to the **directory** eagerly but not the whole data
area (`docs/drive-c-protocol.md` §8.5, measured on the Drive C install), whereas
the ACB-4000's `FORMAT` is what makes the *whole* volume uniform. So a volume is
only "sparse-friendly" if it was formatted by the controller — which it will be
— and the trailing-fill length should be **measured on a formatted volume**
before the tooling trusts it.

## 8. Coexistence — the A/B→E/F remap and the CoPower-88

The MD-10 moves the O1's floppies from `A:`/`B:` to `E:`/`F:` (§6). Does that
hurt the CoPower-88? The honest answer is **no show-stopper, but two real
integration questions** — and neither is hardware.

1. **No port conflict.** The CoPower-88 host driver talks over its own port pair
   (`0x7E`/`0x7F` on Kaypro; the Osborne decode is still open, #5), while the
   MD-10 uses `30h–33h`. Different ports, no arbitration
   (`docs/copower88-protocol.md`).
2. **Two things patching the BIOS.** The MD-10 *replaces* the BIOS; the
   CoPower-88 host driver *installs a BIOS wedge* and asks for a drive letter
   `A`–`P` at install time. Anything that patches the jump table has to be
   installed against the BIOS that is actually resident, so **order matters**:
   the CoPower-88 wedge must go on after the MD-10 BIOS (or be made aware of
   it). This is the same class of problem the boot disk (#28) already has to
   solve for its other drivers.
3. **Drive letters are configuration, not fate.** The CoPower-88 loader *asks*
   which host drive to use, and the Drive C precedent shows a device's letter is
   renamable (`docs/drive-c-protocol.md` §8.4) — so the `A:`/`B:`→`E:`/`F:` move
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
in-repo archive, with provenance rows in `research/README.md` (AGENTS.md). Under
`research/adaptec/acb4000/`:

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
- [x] The port-claim correction applied to `docs/occ1-harddisk-analysis.md` (§3).

## 10. Open questions

1. **The MD-10 DPB** — the volume size the driver installs (§7, §9.4 item 1).
2. **The MD-10 host-adapter bit map** — which observed status bit is `REQ`, which
   is `BSY`, which is phase (§6). Bounded, because the *protocol* is known.
3. **"36 user areas"** — a driver extension, or advertising copy?
4. **Is the MD-10's drive-letter assignment reconfigurable?** It decides whether
   we can leave the floppies at `A:`/`B:` (§8).
5. **Was the MD-10 host adapter a Z80-socket device or a port card?** §5's
   portability argument assumes the former; no photo of it has surfaced.
6. **The ACT board** — for the record only; the decision does not wait on it (§3).

## Sources

- `research/harddisk/` — the ACT software (`OCC1_HARDDISK.IMD`, `extracted/`),
  disassembled for §3.
- `research/adaptec/` — the MD-10 software (three disk images), disassembled for
  §6; and the archived ACB-4000 primary sources under `research/adaptec/acb4000/`
  (§9.1).
- `research/technical-articles/TPC-Issue05-1983-pp25-mega-byte-md10-hard-disk-ad.pdf`
  (OCR at `…ocr.txt`) — the MD-10 advertisement: sizes, drive letters, user
  areas, memory overhead (§6, §7).
- `docs/occ1-harddisk-analysis.md` — the product analysis this decides on top of.
- `docs/o1-memory-io-map.md` §3 — the `2900`/`2A00`/`2C00` device map used in §3.
- `docs/drive-c-protocol.md` §8.3–§8.5, `docs/drive-c-design.md` §4.2 — the
  CP/M ceiling, the drive-letter precedent and the blob precedent (§7, §8).
- `docs/copower88-protocol.md` — the CoPower-88 host protocol (§8).
- `docs/virtual-peripherals-block-diagram.md` §5 — the personality table this
  re-orders.
