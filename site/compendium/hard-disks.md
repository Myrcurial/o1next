---
layout: page
title: "The hard-disk products"
subtitle: "Peripherals and storage"
draft: "Draft &mdash; assembled from the working notes by `tools/build_book.py`. The source document is the authority; this page is a copy for reading, and it is regenerated from that source."
---

**Status: the decision is taken** — emulate the **Adaptec ACB-4000**, not the
ACT. See [`docs/harddisk-decision.md`](https://github.com/Myrcurial/o1nextgen/blob/main/docs/harddisk-decision.md). This doc remains the product analysis.

Source: research/harddisk/OCC1_HARDDISK.IMD (Osborne 1 SSDD, FM 10x256).
Extracted to research/harddisk/extracted/ via disk-analyse + cpmtools
(`osb1sssd`).

## What this is

The Osborne 1 hard disk product from **Australian Computer &
Telecommunications (ACT), (c) 1982** (string in BOOTHd.COM). This is the
"winchester style" interface — and, significantly for us, it is one of
the known **Z80-interposer** designs: the host-side hardware plugged
into the Osborne's Z80 socket.

## Two products, not one

The archive drop (#71) added a **second, unrelated** Osborne 1 hard-disk product,
so "the OCC1 hard disk" is a family, not a single thing:

| | ACT (this doc) | Media Distributing / Adaptec (**the MD-10**) |
|---|---|---|
| Source | [`research/harddisk/OCC1_HARDDISK.IMD`](https://github.com/Myrcurial/o1nextgen/blob/main/research/harddisk/OCC1_HARDDISK.IMD) | `research/adaptec/*.img` |
| Vendor string | `AUSTRALIAN COMPUTER & TELECOMMUNICATIONS  COPYRIGHT (C) 1982` | `Copyright (c) September 1983, Media Distributing` |
| Versions | `Version 31.05.82`, `Version 9-02-81` | `HARD version 1.93`, `PORTCHNG version 1.92`, `PREP version 1.93` |
| Controller | its own; prompts `Enter disk controller address (` | Adaptec ACB-4000; prompts `Enter starting port address in hex` / `must be on a 4 port boundary` |
| BIOS | `HARDBIOS.HEX`, overlaid by `LOADBIOS.COM` | `HARDBIOS.SPR`, `HARDBDOS.SPR`, `HARDCCP.SPR`, `HD00BIOS.SPR`, `HD04BIOS.SPR` |
| Other utilities | `MOVCPM10/5/F`, `DISKEDIT`, `DISKTEST`, `RESTORE`, `SAVEFILE` | `MD10.COM`, `MD20.COM`, `PREP.COM`, `DRIVETBL.DAT`, `PORTCHNG.COM` |

**The second product is identified: it is the Mega-byte MD-10.** Mega-byte Inc.'s
advertisement in *The Portable Companion* #5 (February/March 1983, PDF p. 25;
[`research/technical-articles/TPC-Issue05-1983-pp25-mega-byte-md10-hard-disk-ad.pdf`](https://github.com/Myrcurial/o1nextgen/blob/main/research/technical-articles/TPC-Issue05-1983-pp25-mega-byte-md10-hard-disk-ad.pdf))
sells the **MD-10** — 10 MB formatted for $2295, "20 and 44 megabyte Winchesters
also available" — and its footnote reads *"MD-10 is a registered trademark of
**Media Distributing**."* The disk in [`research/adaptec/`](https://github.com/Myrcurial/o1nextgen/blob/main/research/adaptec/) is copyright Media
Distributing (September 1983) and ships `MD10.COM`/`MD20.COM`, matching the 10
and 20 MB models, so the "Adaptec" disk is **MD-10 software**. Two details from
the ad bear on the interface question below: the MD-10 "does not tie up existing
OSBORNE ports" and is "significantly faster than other winchester subsystems
**which use the IEEE port**" — so it is **not** an IEEE-488 device, consistent
with a controller that claims its own addresses (hence `PORTCHNG.COM`) rather
than borrowing the serial/video ports. Its own parts list — "drive controller,
case, power supply, cabling, **Z-80 interface**" — points at the same class of
host attachment as the ACT unit: a **Z80-socket or dedicated-port** design, not
the IEEE bus.

Both are **port-relocatable** controllers: the ACT disk asks for a "disk
controller address", the Adaptec disk for a "starting port address … on a 4 port
boundary", and it ships `PORTCHNG.COM` to change it. That is consistent with the
rest of the O1, whose I/O decode only looks at the low address lines.

It also means the port claim in "Hardware interface" below should be re-derived
rather than trusted: `0x2A00` and `0x2C01` are the serial ACIA and the video PIA
on this machine, so either the ACT adapter is mapped elsewhere or that
disassembly read the wrong operand.

So there are **three** routes to more storage than 2 × 182 KB — the two hard disks
here, and Drive C ([`docs/drive-c-protocol.md`](https://github.com/Myrcurial/o1nextgen/blob/main/docs/drive-c-protocol.md)) — and only Drive C is buildable
without unobtainable hardware (#84).

## Files

| File | Role |
|---|---|
| HARDBIOS.HEX | Intel HEX of a full replacement BIOS, loads at 0xDF00-0xEB00 (17-jump BIOS entry table at 0xDF00) |
| LOADBIOS.COM | Overlays HARDBIOS.HEX onto the running BIOS ("Your BIOS has been overlayed"; validates 17 JMPs, checksums, warm-boot vector) |
| BOOTHd.COM | Hard-disk boot ("ERROR DURING BOOTING TO HARD DISK") |
| MOVCPM10/5/F.COM | MOVCPM variants (10MB / 5MB / full? volume sizing) for relocating CP/M under the new BIOS |
| DISKEDIT.COM, DISKTEST.COM | Winchester utilities |
| RESTORE.COM, SAVEFILE.COM | Backup/restore to floppy |
| AUTOST.COM, SYSGEN.COM, PIP.COM, XDIR.COM | Standard |

## Hardware interface (from HARDBIOS.HEX disassembly) — **corrected**

The register claim below was re-derived by disassembling `HARDBIOS.HEX`
(`z80dasm`, `org 0xDF00`, 0xDF00–0xEB00). The original reading was wrong; see
[`docs/harddisk-decision.md`](https://github.com/Myrcurial/o1nextgen/blob/main/docs/harddisk-decision.md) §3.

- Same Osborne bank discipline as Drive C: **OUT (0x00) = bank 2 (IO),
  OUT (0x01) = bank 1 (RAM)**, DI/EI bracketed (subroutines at 0xEA6A /
  0xEA75 wrap all IO accesses).
- **The disk transport is the IEEE-488 PIA at `2900–2903`**, bit-banged:
  `set 3,(02902h)` / `res 3,(02902h)` is a **PB3 strobe** around
  `ld a,(02900h)` (read) and `ld (02900h),a` (write), with `cpl` for
  active-low. It is the only device routine in the image, reached from the
  disk path READ (`E32A`) → `sub_e448h` → `E475` → `sub_e520h` → `sub_e58fh`
  (`E58F`).
- **`0x2A00`/`0x2C01` are not the disk.** `0x2A00`/`0x2A01` are the console
  **ACIA** (`0x2A00` status read / control write, `0x2A01` RX/TX — the console
  helpers `sub_e992h`/`sub_e99bh` test bit 1 = TDRE, bit 0 = RDRF) and `0x2C01`
  is the **video PIA** ([`docs/o1-memory-io-map.md`](https://github.com/Myrcurial/o1nextgen/blob/main/docs/o1-memory-io-map.md) §3). The image contains **no
  floppy-controller references at all**: it is a hard-disk-only BIOS.
- The "indirect `OUT (C),A`, target TBD" is resolved: `C` comes from
  `[0xEF08]`, which the bank helpers set to `0` or `1` — it is the **bank
  restore** on exit, not a disk port.
- The BIOS preserves a full register environment (pushes IX/IY/HL/DE/
  BC/AF, switches to a private stack at 0xEFC1) around hard-disk calls
  — it hooks deep into the 17-entry BIOS jump table as a full BIOS
  replacement, not just a disk-driver wedge.

## Comparison with Drive C

| | Drive C (RAM disk) | ACT hard disk |
|---|---|---|
| Physical interface | IEEE-488 port (6821 PIA bit-bang @ 0x2900-0x2903) | IEEE-488 PIA @ 0x2900-0x2903, bit-banged (PB3 strobe) |
| Host code | Driver wedge (DCL/DFD.SPR) | Full BIOS replacement @ 0xDF00 |
| Boot | QUICKPAC autoload from floppy | BOOTHd.COM + SYSGEN to winchester |

## Implications for the interposer project

1. **The ACT product validates the whole interposer concept on this
   exact machine** — a Z80-socket interposer was a shipping commercial
   Osborne 1 peripheral in 1982.
2. Its transport is the **same PIA bit-bang as Drive C** (`2900–2903`), so an
   ACT personality would reuse that machinery — but its command protocol is
   undocumented and would have to be reverse-engineered from `HARDBIOS.HEX`
   ([`docs/harddisk-decision.md`](https://github.com/Myrcurial/o1nextgen/blob/main/docs/harddisk-decision.md) §3).
3. The mass-storage decision is **made**: emulate the Adaptec ACB-4000 (the
   controller inside the Media Distributing **MD-10**), not the ACT. See
   [`docs/harddisk-decision.md`](https://github.com/Myrcurial/o1nextgen/blob/main/docs/harddisk-decision.md) for the reasoning and the plan.

## Open questions

The ACT-specific questions are **closed or superseded** — the ACT is not being
emulated ([`docs/harddisk-decision.md`](https://github.com/Myrcurial/o1nextgen/blob/main/docs/harddisk-decision.md) §3):

1. ~~Which ACT product exactly?~~ **Superseded.** `MOVCPM10/5/F.COM` are stock
   Digital Research `MOVCPM.COM` builds, not volume sizes.
2. ~~Command set at 0x2A00~~ — **resolved as not the disk.** The transport is the
   `2900–2903` PIA and its protocol is undocumented.
3. ~~The `OUT (C)` target port at 0xEF08~~ — **resolved**: the bank restore.
4. Whether any ACT hardware photos/schematics survive online — still unattested,
   and now only of archival interest.
5. ~~Re-derive the port claim~~ — **done** (above; `harddisk-decision.md` §3).
6. **The MD-10 / ACB-4000's** remaining questions — the DPB, the host-adapter bit
   map, the drive letters, "36 user areas" — are in [`docs/harddisk-decision.md`](https://github.com/Myrcurial/o1nextgen/blob/main/docs/harddisk-decision.md)
   §10.
