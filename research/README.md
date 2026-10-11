# Research archive — sources and safety copies

This directory is the project's **research archive**: the documentation,
disk images, and photographs that the reverse-engineering and design work
under `docs/` and the GitHub issues depend on.

**These files are reserved as safety copies of the documentation necessary
to complete this project.** They are committed in-repo on purpose: upstream
archives move, go offline, or drop files, and this project cannot finish
without these specific documents. If an upstream link dies, the in-repo
copy is authoritative. Please do not "clean up" large PDFs or disk images
from this tree — their presence here is the point.

Where each item was sourced is recorded below, so provenance is preserved
alongside the copies.

**OCR convention:** most of the scans here have no text layer. When a
document is OCR'd for research, the text is committed **adjacent to the
PDF** as `<filename>.ocr.txt` (e.g.
`drive_c/Drive_C_Users_Manual.ocr.txt`) so it never has to be
regenerated. Regenerate with `tools/ocr_pdf.sh` if a better pass is
needed.

## osborne1/ — Osborne 1 mainboard documentation

| File | What it is | Sourced from |
|---|---|---|
| `2F00153-01_Osborne1TechnicalManual_1982.pdf` (19 MB) | Osborne 1 Technical Manual, 1982. No text layer — image-only scan. Theory of operations, banking, I/O, video, disk, keyboard. | [bitsavers](https://bitsavers.trailing-edge.com/pdf/osborne/osborne1/2F00153-01_Osborne1TechnicalManual_1982.pdf) |
| `OCC1_1A2011-00_Schem_RevE.pdf` (1.2 MB) | **Two drawing sets in one 12-page scan.** Pages 1–3: DISK ELECTRONICS, DWG 1A3004-00/01 Rev C (sheets 1–3 of 3 — the *drive's* own board). Pages 4–12: MAIN PC BOARD, DWG 1A2011-00 Rev E (sheets 1–9 of 9). 600 dpi bilevel; the embedded text layer is a useless early-90s OCR pass. Indexed, and the Z80 socket and P8 floppy pinouts extracted, in `docs/o1-mainboard-schematic.md` (#62). | [bitsavers](https://bitsavers.org/pdf/osborne/osborne1/OCC1_1A2011-00_Schem_RevE.pdf) (also mirrored as `Osborne_1_Schematics_1A2011-00_Rev_E.pdf` on RetroTechCollection/Internet Archive) |
| `OCC1_1A2011-00_Schem_RevE.ocr.txt` | OCR text layer for the above (per the convention below), generated 2026-10-10 at 400 dpi. Good enough to grep for component references; **not** reliable for pin-level detail — read sheets visually with `tools/schematic_render.sh`. | — |
| `keyboard/osborne_keyboard_pinout.html` + `keyboard/PROVENANCE.md` | Verbatim capture of the pinouts.ru Osborne 1 keyboard page: P4 pinout (incl. pin 19 = +12V via J6+R21) and the full key matrix map. Used by #45/#47. | [pinouts.ru](https://old.pinouts.ru/InputCables/osborne_keyboard_pinout.shtml), captured 2026-10-08 (provenance in the folder) |
| `floppy-adapter/` (README, LICENSE, `.sch`, `.kicad_pcb`, PROVENANCE.md) | Snapshot of WayneVisser's Osborne1FloppyAdapter KiCad project — passive Gotek adapter documenting the O1's "Shugart-like" floppy interface (power over the cable's unused pins). Used by #20/#49. | [github.com/WayneVisser/Osborne1FloppyAdapter](https://github.com/WayneVisser/Osborne1FloppyAdapter), captured 2026-10-09 (provenance in the folder) |
| `modem/o1techman-interface-extract.pdf` (1 MB, 10 pp) | Chapter 4 "Osborne 1 Interface Design" extract of the O1 Technical Manual: §4.1 IEEE-488 (P3), §4.2 RS-232 (P2), **§4.3 MODEM (P1)**. Authoritative source for the MODEM DE-9P pinout — **TTL levels, not RS-232** — incl. pin 4 MSB, pin 5 CTS, pin 8 MCB, pin 9 RI, pin 7 +12V via 22Ω. Used by #56 (and #21/#12). | [kev.pulo.com.au/osborne1](https://www.kev.pulo.com.au/osborne1/documents/o1techman.pdf), captured 2026-10-09 |
| `o1doubledensityusersguide.pdf` (2.2 MB, 15 pp) | *Osborne 1 Double Density User Manual*. The DD option's own manual, and the primary source for what it actually does: it is a **multi-density** option that recognises six formats, not just a denser one. §"formats automatically recognized" is quoted in `docs/dd-upgrade-formats.md` (#95). Image-only scan; OCR'd 2026-10-10 at 300 dpi as `o1doubledensityusersguide.ocr.txt`. | [kev.pulo.com.au/osborne1](https://www.kev.pulo.com.au/osborne1/documents/o1doubledensityusersguide.pdf), supplied by the maintainer 2026-10-10 |

Basis for `docs/o1-memory-io-map.md` (#40) and
`docs/o1-mainboard-schematic.md` (#62). Both scans are image-only; extraction
is manual — OCR for text pages, and for schematics a native-resolution region
render (`tools/schematic_render.sh`) read by eye. The mainboard map is
independently cross-checked against the running machine in MAME; see
`docs/o1-mainboard-schematic.md` §7 (#64).

## inspired-by/ — adjacent projects

`inspired-by/README.md` — other Osborne 1 reinventions (MAME cyberdeck,
Raspberry Pi brain transplant, Loxley's Gotek mod): what they did, and
what we take from each. Contrast defines the project: **we keep the
original machine intact**.

## mx80/ — Epson MX-80 printer references

| File | What it is | Sourced from |
|---|---|---|
| `mx80/Epson_MX-80_Operations_Manual.pdf` | Epson MX-80 operation manual; Appendix 4 (PDF p. 97+) has the character-font tables (6×9 matrix) and ESC code reference. | [Internet Archive / manualsbase](https://dn790002.ca.archive.org/0/items/manualsbase-id-381505/381505.pdf), captured 2026-10-09 |
| `mx80/EPSON_MX-80_Fonts_v1.0.zip` + `mx80/fonts/` | Michael Walden's MX-80 font pack (CC BY-NC-SA 4.0). Convenience cross-check; see the folder README for the double-strike/2×-width caveat. | [mw.rat.bz/MX-80](https://mw.rat.bz/MX-80/), captured 2026-10-09 |

Also: `drive_c/Drive_C_Users_Manual.ocr.txt` — OCR text layer for the
image-only Drive C manual scan (generated 2026-10-09 per the OCR
convention above; source of the TurboPac details used by
`firmware/drive-c-gpib/`).

References for the virtual Epson MX-80 printer personality (#19).

## screenpac/ — OCC ScreenPac (80- and 104-column upgrade)

| File | What it is | Sourced from |
|---|---|---|
| `2F00040_service_2ndEd_1983.pdf` (12 MB) | Osborne Field Service Manual, 2nd Edition, 1983. Covers the ScreenPac upgrade (Z80 + char-gen socket taps, dual-port video RAM). §6.12 documents the ScreenPac IC-harness fly-lead solder connections (used by `firmware/screenpac-video/`). | [bitsavers](https://bitsavers.trailing-edge.com/pdf/osborne/2F00040-00_Service2ndEdition_1983.pdf) |
| `2F00040_service_2ndEd_1983.ocr.txt` | OCR text layer (per the convention above), generated 2026-10-09 | — |
| `o1screenpacusersguide.pdf` (2.3 MB, 20 pp) | *Osborne 1 SCREEN-PAC User Guide*. **The primary source for what the upgrade does**, and it is more than a wider window: p. 13 (PDF p. 17) gives the three software-selectable widths (52 / 80 / 104), horizontal scrolling in **32-column blocks**, and the **presence flag at `2400H` bank 2** that lets software detect the board. Quoted in `docs/mame-emulation.md` §2 and `docs/o1-memory-io-map.md` §2a/§3 (#73, #24). | [kev.pulo.com.au/osborne1](https://www.kev.pulo.com.au/osborne1/documents/o1screenpacusersguide.pdf), supplied by the maintainer 2026-10-10 |

The ScreenPac is the mechanical/electrical template for the interposer and
for the video-output (HDMI) personality (#24, #9 photos).

## technical-articles/ — extracts from Osborne-era magazines

**Only the pages that matter are kept, cut from the original and OCR'd.** The
full issues are not in the repo: they are 50–60 MB scans each, they are on the
Internet Archive (<https://archive.org/details/theportablecompanion>) and on the
maintainer's own backup, and keeping whole magazines for a few pages of schematics
is not worth the repo weight. Each extract names the issue and the pages it was
cut from, so it can be checked against the original.

| Extract | What it is | Cut from |
|---|---|---|
| `TPC-Issue13-1984-pp26-31-reverse-video-and-9600-baud.pdf` (3.3 MB, 6 pp) | "**Reverse Video and a Faster Serial Port**" by **Thom Hogan** — changing the underline cursor to a reversed-video one, and pushing the serial port to **9600 baud**, with the schematic changes. Relevant to #24 (video) and #21 (serial/modem). Worth noting the author: the same Thom Hogan whose `AUTOCPM.ASM` is the source of the site wordmark (#97). | *The Portable Companion* #13, June/July 1984 — PDF pp. 26–31 |
| `TPC-Issue15-1985-pp72-77-16bit-msdos-and-cpm-for-your-o1.pdf` (4.9 MB, 6 pp) | "**16-Bit MS-DOS & CP/M For Your Osborne One!**" by **Robert J. Thomson** — the **Co-Power-88**: an 8088 processor, MS-DOS / CP/M-86 / CP/M, and a 256K memory disk under regular CP/M, with the installation. Directly relevant to #23/#26 and the CoPower-88 work in `research/copower88/`. | *The Portable Companion* #15, January/February 1985 — PDF pp. 72–77 |

### How these extracts are made

The maintainer reads the issues and hands over the ones worth keeping, giving the
**PDF page sequence** to cut. The standing workflow:

1. Cut the pages: `pdfseparate -f A -l B ISSUE.pdf /tmp/p%03d.pdf` then
   `pdfunite /tmp/p*.pdf OUT.pdf`.
2. OCR the extract with `tools/ocr_pdf.sh OUT.pdf` — adjacent, per the convention
   above. **Wait for its `Wrote <path>` line before committing**; the file exists
   while it is still being written.
3. Add a row below, and write the findings into the `docs/` page they bear on
   with the extract cited.

Two things to know before cutting pages:

- **Page numbers are PDF pages, not printed pages.** Both issues checked so far
  print their own numbers two lower (`PDF = printed + 2`), so an article "on page
  26" is PDF page 26 and printed page 24 — and cutting printed 26 would miss the
  article's title page. Confirm with `pdftotext -f N -l N -layout ISSUE.pdf - |
  tail -3`, which prints the page's own folio.
- **Provenance for every article from *The Portable Companion* is the same
  collection**: <https://archive.org/details/theportablecompanion>. Rows
  therefore cite the issue and the page range rather than a per-file URL.

The **full issues are not kept in the repo** — 50–60 MB each, and they live on
the Internet Archive and on the maintainer's own backup. Only the extracts are
committed, and they are cut from files outside the repo (the maintainer's
`~/Documents` tree), never from a copy inside it.

## copower88/ — SWP CoPower-88 (Z80-coprocessor board being reverse-engineered)

| Path | What it is | Sourced from |
|---|---|---|
| `zorba/Co-Power-88guide.pdf`, `zorba/Co-Power-88advert.pdf`, `zorba/611-0003-1..4.pdf` | SWP CoPower-88 user guide, advertisement, and SWP technical document scans (Zorba-flavored set) | [zorba.z80.de](http://zorba.z80.de/files/swp/) — the Zorba Portable Computer archive site |
| `zorba/*.td0`, `kaypro/*.td0` | TeleDisk images of CoPower-88 CP/M-86 / DOS boot disks (Zorba and Kaypro versions) | zorba.z80.de (exact path not recorded in repo history) |
| `zorba/extracted/`, `kaypro/extracted_cpm/`, `*/disasm/` | CP/M files extracted from those images by the project pipeline (#2), and disassemblies of the CoPower RAM-disk/DOS drivers | Derived in-project — not external sources |
| `swp/Copower_User_guide.pdf`, `swp/Swp_ad.jpg` | Fuller CoPower-88 user guide (4.7 MB, not the Zorba set) and an SWP advert scan | [kayprojournal.com `Swp_copower_88`](https://kayprojournal.com/index.php/Swp_copower_88) — `File:Copower User guide.pdf`, `File:Swp ad.jpg` |
| `swp/1600px-73356_8088_card.jpg`, `swp/1600px-73356_mem_card.jpg`, `swp/866px-73356_cpu_card.jpg` | Board photographs of the CoPower-88 8088 card, memory card and CPU card — held as MediaWiki thumbnails (1600 px / 866 px) of `File:73356 8088 card.jpg`, `File:73356 mem card.jpg`, `File:73356 cpu card.jpg` | Same page: [kayprojournal.com `Swp_copower_88`](https://kayprojournal.com/index.php/Swp_copower_88) |

The whole `swp/` set is from that one page. Confirmed 2026-10-10 by querying the
wiki's API (`list=allimages` and `prop=images&titles=Swp copower 88`) and matching
all five `File:` names exactly — not by reading the rendered page text. The wiki
also carries `File:Copower sch 1..4.pdf`, a second copy of the SWP schematics we
hold from zorba.z80.de.

Basis for #3/#4/#5 (CoPower-88 protocol analysis). The board's own 8088 ROM is
`roms/swp-p88.rom` — see `roms/` below and #70.

## drive_c/ — Drive C (IEEE-488 ramdisk, #6)

| Path | What it is | Sourced from |
|---|---|---|
| `Drive_C_Users_Manual.pdf` | Drive C user manual (IEEE-488 virtual disk drive) | [bitsavers `bits/Osborne/Osborne1/Drive_C/`](https://bitsavers.org/bits/Osborne/Osborne1/Drive_C/) (upstream name `Drive_C_-_Users_Manual.pdf`) |
| `DRIVE_C.IMD` | ImageDisk image of the Drive C utility disk (label comment `Drive C for the Osborne 1 computer`) | same folder — **not** imaged in-project; corrected 2026-10-10 |
| `Drive_C_disk_label.jpg` | Photo of the physical disk label | same folder (15 044 B, byte-identical) — **not** a project photo; corrected 2026-10-10 |
| `extracted/` | Files extracted from `DRIVE_C.IMD` by the project pipeline (#2) | Derived in-project |
| `disasm/` | `dcl.asm` + `dfd.asm` — z80dasm listings of the installer and the resident driver, for the protocol work (#6). Regenerate with the exact command in `docs/drive-c-protocol.md` §Disassembling | Derived in-project |

## rtc/ — RT-60A real-time clock (#7)

| Path | What it is | Sourced from |
|---|---|---|
| `RT-60A_Manual.pdf` | RT-60A RTC manual (JG Communications) | [bitsavers `bits/Osborne/Osborne1/Osborne_1_Real_Time_Clock/`](https://bitsavers.org/bits/Osborne/Osborne1/Osborne_1_Real_Time_Clock/) (upstream name `RT-60A_Real_Time_Clock_Manual_-_Osborne_1.pdf`) |
| `RT-60A.TD0` | TeleDisk image of the RT-60A utility disk — **a damaged dump** (27 no-id sectors); filesystem extraction fails, see `tools/README.md` | same folder |

## harddisk/ — ACT/OCC1 hard disk (#8)

| Path | What it is | Sourced from |
|---|---|---|
| `OCC1_HARDDISK.IMD` | ImageDisk image of the OCC1 hard-disk system disk (label comment `act-osborne / hard disk software / rev 2`) | [bitsavers `bits/Osborne/Osborne1/_floppy_images/`](https://bitsavers.org/bits/Osborne/Osborne1/_floppy_images/) — **not** imaged in-project; corrected 2026-10-10 |
| `extracted/` | Files extracted from the image, incl. `hardbios.hex` | Derived in-project |

## adaptec/ — Adaptec ACB-4000 hard-disk software (2026-10)

Raw Osborne 1 SSSD floppy images (102 400 B = 40 tracks × 10 sectors × 256 B,
**no IMD header**) each with a photo of the disk's label. Source: Internet
Archive, [`md-utilities-adaptec-4000-controller-ver.-1.93-osborne`](https://archive.org/details/md-utilities-adaptec-4000-controller-ver.-1.93-osborne).

| File | What it is |
|---|---|
| `MD Utilities Adaptec 4000 Controller Ver. 1.93 Osborne.img` | Adaptec ACB-4000 utilities |
| `MD Utilities Adaptec 4000 Controller Ver. 1.93 Osborne - MD-10 MD-20.img` | Same, for the MD-10/MD-20 drive pair |
| `Osborne Hard Disk Control Software Version 2.01 (1984).img` | Osborne's own hard-disk control software |

Together with `acb4000a.rom` (Maslin's archive) this identifies the controller
behind `harddisk/OCC1_HARDDISK.IMD` — issue #8.

## diagnostics/ — Osborne 1 confidence tests (2026-10)

| File | Label comment |
|---|---|
| `DIAG_2.04.IMD` | `2.04 / diagnostics` |
| `OCC1_DIAG_2.1.IMD` | `occ diag / ver 2.1 / 12/31/84` |

Source: [bitsavers `bits/Osborne/Osborne1/_floppy_images/`](https://bitsavers.org/bits/Osborne/Osborne1/_floppy_images/).
These are the known-good boot images the validation matrix (#29) needs.

## nuevo/ — Nuevo Electronics double-density upgrade (2026-10)

| File | What it is | Sourced from |
|---|---|---|
| `Nuevo_Electronics_DD_Upgrade_Manual.pdf` (13 MB) | DD upgrade manual | [bitsavers `bits/Osborne/Osborne1/`](https://bitsavers.org/bits/Osborne/Osborne1/) (13 810 755 B, exact match) |
| `OS1NUEVO.IMD` | `Osborne 1 with DD and 80 col mods` boot disk, re-imaged 2026-10-10 with Disk-Utilities | derived in-project |

> **Removed 2026-10-10: `NUEVO151.BIN`.** It was a byte-identical duplicate of
> `tools/emulator-setup/roms/monrom-rev1.51-12.ud11` — same 4096 bytes, SHA-256
> `aec8f5be127fdff5d30cae0b7f45ee48d13a8c1d5745a262b944b9ba67778906`, CRC32
> `298da402` — verified with `cmp` before deletion. It carried no provenance of
> its own, so the tracked emulator-set copy, which has a recorded source, is the
> one we keep. The BIOS strings are unchanged by this: `COPYRIGHT 1983, OSBORNE
> COMPUTER CORP. / COPYRIGHT 1984, NUEVO ELECTRONICS CORP.`

Nuevo shipped **two** products — a DD upgrade and an 80-column board — and
neither matches Osborne's own implementation of that function; see #73.

`OS1NUEVO.IMD` **is** the Nuevo 80-column system disk: its system area carries
`CBIOS vers 1.5` and the text *"THIS IS AN EIGHTY (80) COLUMN DISPLAY FOR THE
OSBORNE ONE"*. It does **not** currently boot under MAME — it prints the CBIOS
banner and stops (measured over 260 emulated seconds; the pristine upstream copy
behaves the same), which blocks validating the Nuevo video path in the emulator.
See #79 and `docs/mame-emulation.md` §4.

## osmosis/ — Osmosis Computer upgrades (2026-10)

Source: [bitsavers `bits/Osborne/Osborne1/Osmosis_Upgrades/`](https://bitsavers.org/bits/Osborne/Osborne1/Osmosis_Upgrades/) — all seven files byte-for-byte identical.

`Osmosis_CPM_Disk_Emulator.pdf`, `Osmosis_80_Column_Board.pdf`,
`Osmosis_SSDD_Upgrade.pdf`, `OSMO-EMU.TD0`, `OSMOS-DD.TD0`, plus two disk-label
photos. Osmosis likewise shipped two products (a CPM disk emulator and an
80-column board). **The 1983 CPM Disk Emulation System is direct prior art for
this project** — see #73 and `inspired-by/`.

## gotek/FF/ — working Gotek configuration (2026-10)

`FF.CFG` + `IMG.CFG` — the project's own Gotek configuration for the O1:
`interface = shugart`, `pin02`/`pin34` = `nc`, and an `IMG.CFG` default of
40 cylinders × 1 head × 16 × 128 B, FM, 125 kbit/s — i.e. O1 SSSD. Captured
from the physical Gotek, so these are primary sources, not downloads.
Used by #62 and #20.

## roms/ — ROM images (2026-10)

Canonical inventory, CRC32s and the third-party ROM survey are tracked in #70.
Files here come from two sources:

- `os1-143.rom`, `os1-144.rom`, `os1-vid8.rom`, `os1vid80.rom`, `swp-p88.rom` — [Don Maslin's ROM archive](http://www.retroarchive.org/maslin/disks/roms/) on retroarchive.org
- `OZROM-1E/OZROM_1E.BIN`, `OZROM-1E/OZROM_1E_Manual.pdf`, `OCC1_ScreenPac_RevA.BIN` — [github.com/BrettHallen/Osborne_1](https://github.com/BrettHallen/Osborne_1) `ROM/`

`swp-p88.rom` is **8088 code, not Z80**: the SWP co-processor board's own ROM.
The board and interposer card are common to every host machine (only the driver
varies), so this is the 8088-side firmware of the CoPower-88 family — #3/#4/#5.

`OZROM-1E/OZROM_1E_Manual.ocr.txt` — OCR text layer for the OZROM manual
(image-only scan; generated 2026-10-10 at 300 dpi with `tesseract`, per the OCR
convention above). Good enough to grep for the technical appendices — which is
how the IEEE-488 removal and the 3 KB video window were found (#81) — but not
reliable for exact code or pin detail.

## shipped-software/ — the shipped application library (2026-10)

Fourteen ImageDisk images of the disks that shipped with (or were published
for) the Osborne 1. The ImageDisk label comment is quoted because it is the
disk's own identity. Source: **Dave Dunfield's ImageDisk archive**
(`dunfield.classiccmp.org`, which rotates its directory to discourage deep
links) — `d/osborne1.zip` and `d/o1ddsys.zip`, byte-identical to these copies.

| File | Label comment |
|---|---|
| `O1CPM.IMD` | `Osborne-1 CP/M System Disk / Double Density` |
| `O1CBMB.IMD` | `Osborne 1 - CBASIC/MBASIC / Double Density` |
| `O1SCALC.IMD` | `Osborne 1 - SuperCalc 1.12 / Double Density` |
| `O1WSMM.IMD` | `Osborne 1 - WordStar/MailMerge 2.26 / Double Density` |
| `OS1SYSD.IMD` | `CP/M-2.2 system disk for Osborne 1 w/ DD drives / SSDD 1024 byte sector` |
| `OS1SYSS.IMD` | `CP/M 2.2 System Disk for Osborne 1 / SSSD 256 byte sector` |
| `OS1BASIC.IMD` | `CP/M 2.2 Basic Disk for Osborne 1` |
| `OS1DBASE.IMD` | `dBase II for the Osborne 1 on sysgened disk` |
| `OS1DIAS.IMD` | `CP/M 2.2 Diagnostics Disk for Osborne 1` |
| `OS1MCAL.IMD` | `CP/M 2.2 Mocro-Call Disk for Osborne 1 (Communications)` |
| `OS1MDM7.IMD` | `Modem 740 communications for Osborne 1` |
| `OS1UTLS.IMD` | `CP/M 2.2 Utilities Disk for Osborne 1` |
| `OS1XUTLS.IMD` | `Extended utilities for Osborne 1 w/ 80 column video card` |
| `OS1WRDST.IMD` | `CP/M 2.2 WordStar 3.0 Disk for Osborne 1` |

The corpus for the image library (#20), the updated boot disk (#28) and the
validation matrix (#29). Dunfield also publishes a 2005 single-density set
(`O1CPMS.IMD`, `O1CPMU.IMD`, …) which is deliberately **not** copied here.

## source-code/ — Osborne's own firmware source (2026-10)

| Path | What it is | Sourced from |
|---|---|---|
| `BIOS-144-source/` (18 files) | **The original Osborne ROM source**: `rom144.asm` (DOUBLE DENSITY ROM REV 1.44, Roger W. Chapman, 2/4/1983), `occbio05..95.asm` (OCC CBIOS Rev 1.41), `occram15/25.asm`, `occtxt6.ast` (ACT80 assembler equates), `bios141.gen`, `release.txt`, `tran.txt`. Basis for #72. | [github.com/BrettHallen/Osborne_1](https://github.com/BrettHallen/Osborne_1) `ROM/Source_Code_v144/` (all 18 file sizes match) |
| `OCCCBIOS.IMD`, `OCCROM.IMD`, `OCCUTIL.IMD`, `OSBIOSSR.IMD`, `OSBROM.IMD`, `OSROM13.IMD`, `OSUTLSRC.IMD` | OCC engineering **source disks** (1981–82): CBIOS, ROM rev B, utility programs, ROM 1.3. The ImageDisk comments carry the OCC part numbers (`4d2007-00 occbi00a.asm`, `rev b 9/12/81`). | bitsavers |

**Licensing:** `release.txt` is Osborne's 1985 letter permitting the First
Osborne Group to reprint the schematics and the BIOS listing, on condition that
any money goes to the non-profit FOG and that the trademark/copyright notices
are retained. FOG is long defunct and this material is already public in
several places — this copy came from a public GitHub repository. The notice is
retained verbatim; if the terms ever need re-examination, that is the file.

## pictures/ — machine photographs

`IMG_4856.jpeg` … `IMG_4871.jpeg` — disassembly/mainboard/upgrade-board
photos of the project's own machines (mainboard, double-density upgrade,
ScreenPac, CoPower-88). Taken in-project for #9; these are primary sources,
not copies. Further photo sets are tracked in #39.

## Provenance

The two long-standing **provenance gaps are closed**: the Drive C manual and
the RT-60A manual/TD0 both come from bitsavers'
[`bits/Osborne/Osborne1/`](https://bitsavers.org/bits/Osborne/Osborne1/)
(`Drive_C/` and `Osborne_1_Real_Time_Clock/`), as does `OCC1_HARDDISK.IMD` and
the two diagnostic disks (`_floppy_images/`). Four rows that had been recorded
as in-project work or as unknown URLs were corrected on 2026-10-10.

**Both remaining TODOs are closed (2026-10-10, #74):**

- `copower88/swp/` — kayprojournal.com's
  [`Swp copower 88`](https://kayprojournal.com/index.php/Swp_copower_88) page; all
  five files matched by `File:` name through the wiki API (CoPower-88 table above).
- `nuevo/NUEVO151.BIN` — removed as a byte-identical duplicate of the tracked
  `tools/emulator-setup/roms/monrom-rev1.51-12.ud11` (nuevo/ table above).

No provenance TODOs remain.
