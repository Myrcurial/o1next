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
| `modem/o1techman-interface-extract.pdf` (1 MB, 10 pp) | Chapter 4 "Osborne 1 Interface Design" extract of the O1 Technical Manual: §4.1 IEEE-488 (P3), §4.2 RS-232 (P2), **§4.3 MODEM (P1)**. Authoritative source for the MODEM DE-9P pinout — **TTL levels, not RS-232** — incl. pin 4 MSB, pin 5 CTS, pin 8 MCB, pin 9 RI, pin 7 +12V via 22Ω. Used by #56 (and #21/#12). **Also the P3 (IEEE-488) pinout**: §4.1.2's 26-pin edge table, §4.1.1's signal directions and §4.1.5's Centronics re-mapping, transcribed in `docs/o1-ieee488-port.md` §6 (#84). Image-only scan — OCR it, `pdftotext` returns nothing. | [kev.pulo.com.au/osborne1](https://www.kev.pulo.com.au/osborne1/documents/o1techman.pdf), captured 2026-10-09 |
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
| `TPC-Issue11-1983-pp32-osmosis-product-line-ad.pdf` (0.6 MB, 1 p) | OSMOSIS' full-page advertisement, "The Next Step Forward" — the whole product line **with product numbers**: **OSMOS 1** DD 184k/drive ($195), **1.5** ($335), **2** DS/DD 370k ($895), **3** DS/DD double-tracking 750k/1.5MB ($1050), **4** "read, write and format **over 20 other manufactures CP/M formats**" ($225), **5** the internal 80-column board ($250 — "**includes a Hard Disk interface for future plug-in expansion**", normal/inverted video, underline, ⅔ and ½ intensity), **6** telex, **7** Winchester to 42 MB, **8** instrumentation, **10** Olivetti ET121 interface; bundle OSMOS 1+4+5 for $385. Quoted in `docs/o1-upgrade-boards.md` and `docs/dd-upgrade-formats.md`. Relevant to #24, #11/#12 and #95/#30. | *The Portable Companion* #11, October 1983 — PDF p. 32 (printed 30) |
| `TPC-Issue11-1983-pp54-doubling-hard-disk-memory.pdf` (0.7 MB, 1 p) | "**Doubling hard disk memory**" by **Bob Gras** (reprinted from the OSUG newsletter, Anchorage) — patching Corvus's `CLINK2K2.ASM` so the link program works after a double-density upgrade: `DELTA EQU 500H` → `900H`, because "**more memory is required for managing the Osborne floppy drives**" under DD. The same page carries the tail of John Dilday's WordStar printer-spooler article. Quoted in `docs/dd-upgrade-formats.md` and `docs/research-gaps.md` §B1. Relevant to #95 and the hard-disk survey (gap 9). | *The Portable Companion* #11, October 1983 — PDF p. 54 (printed 52) |
| `TPC-Issue13-1984-pp26-31-reverse-video-and-9600-baud.pdf` (3.3 MB, 6 pp) | "**Reverse Video and a Faster Serial Port**" by **Thom Hogan** — changing the underline cursor to a reversed-video one, and pushing the serial port to **9600 baud**, with the schematic changes. Relevant to #24 (video) and #21 (serial/modem). Worth noting the author: the same Thom Hogan whose `AUTOCPM.ASM` is the source of the site wordmark (#97). | *The Portable Companion* #13, June/July 1984 — PDF pp. 26–31 |
| `TPC-Issue14-1984-pp43-47-drive-c-loader-and-archive-programs.pdf` (4.6 MB, 5 pp) | "**Review of New Drive C: Loader & Archive Programs**" by **Larry Walker** — a *FOGHORN* (First Osborne Group) reprint documenting the second-generation Drive C: software: `DCL.COM` (loader, replaces `DRIVEC.COM`), `DFD.SPR` ("a substitute console command processor … automatically loaded"), `DCA.COM` (Archive-Retrieve, replaces `DCARCH.COM`/`DCRET.COM`), QuickPac (`DCQ`/`DCQINS`/`DCQ.DAT`/`DCQAUT`→`AUTOST.COM`), the `DC1`/`DCN`/`DCU` command syntax, print-buffer sizes (16–128K or dynamic), retrieval timings, the BackPac battery, and the gotcha that a printer connected but switched **off** crashes the machine. Relevant to #6, #84 and #19. | *The Portable Companion* #14, November/December 1984 — PDF pp. 43–47 (printed 41–45) |
| `TPC-Issue15-1985-pp72-77-16bit-msdos-and-cpm-for-your-o1.pdf` (4.9 MB, 6 pp) | "**16-Bit MS-DOS & CP/M For Your Osborne One!**" by **Robert J. Thomson** — the **Co-Power-88**: an 8088 processor, MS-DOS / CP/M-86 / CP/M, and a 256K memory disk under regular CP/M, with the installation. Directly relevant to #23/#26 and the CoPower-88 work in `research/copower88/`. | *The Portable Companion* #15, January/February 1985 — PDF pp. 72–77 |
| `TPC-Issue15-1985-pp32-block-cursor-with-screenpac.pdf` (0.8 MB, 1 p) | Letters: **the Lovells**' fix making Hogan's block cursor work on a machine with the **SCREEN-PAC 80 fitted, without removing the piggy-back board** — the modification moves to the upgrade board's own **U2 (74HC00)** and **U23 (74HC74)**, with a capitalised warning that the pins to cut are *not* the ones in Hogan's article. Quoted in `docs/o1-memory-io-map.md` §2a. Relevant to #24. | *The Portable Companion* #15, January/February 1985 — PDF p. 32 |
| `TPC-Issue15-1985-pp52-drive-c-letters.pdf` (0.9 MB, 1 p) | Letters on **Drive C:** — a user report (a 384K unit, WordStar to the dBASE II dot prompt in six seconds, 90% less drive wear) and the reviewer's rebuttal (*"Drive C: is not a good buy for the average user"*). Quoted in `docs/drive-c-protocol.md`. Relevant to #6, #22 and #84. | *The Portable Companion* #15, January/February 1985 — PDF p. 52 |
| `TPC-Issue15-1985-pp39-nuevo-four-upgrades-ad.pdf` (0.7 MB, 1 p) | Nuevo Electronics' full-page advertisement, "**Four Nuevo Ways to Upgrade**": the 80-column board (**six cursor styles**, reverse video, horizontal scroll, optional baud generator to **19.2K**), the DD upgrade (183K), the **2 x 2** (780K, DS/DD, 128 directory entries) and the **4 x 4** (1580K, **double-sided 96 tpi drives**, auto-recognising SS SD/DD and DS 48/96 TPI, "read or write, even boot"). Quoted in `docs/dd-upgrade-formats.md` and `docs/o1-upgrade-boards.md`. Relevant to #95, #30, #24 and #21. | *The Portable Companion* #15, January/February 1985 — PDF p. 39 |
| `TPC-Issue08-1983-pp38-41-understanding-the-ieee-488-port.pdf` (2.5 MB, 4 pp) | "**Understanding the IEEE-488 port** — Scientific interfacing with the Osborne 1" by **Wayne Kogachi** and **Shahriar Kianersi**, both of **OCC**: the machine as Talker/Listener/Controller, the **15-device** bus limit, the O1's own address 0, and the **eight low-level ROM drivers** (Control Out, Status In, Go To Stand By, Take Control, Output Interface Messages, Output Device Messages, Input Device Messages, **Input Parallel Poll** — the last cutting the bus to eight devices), with the error set and the SETUP route for a printer. Written up in `docs/o1-ieee488-port.md`. Relevant to #22, #84, #19. | *The Portable Companion* #8, July 1983 — PDF pp. 38–41 (printed 36–39) |
| `TPC-Issue08-1983-pp44-49-interfacing-external-devices-joystick.pdf` (4.9 MB, 6 pp) | "**Interfacing External Devices** — add a game joystick to the Osborne 1" by **Kelly Smith** (Wizard of OsZ), part one of two: the **26-pin card-edge → DB-9** adapter cable (12-conductor ribbon, `D0`–`D4` + GND only), the Atari joystick bit map (1 north / 2 south / 4 east / 8 west / 16 fire, diagonals as sums) with the 128-character screen offsets, the **`CALL 0E154H`** ROM parallel-poll route, and `JOYSTIK.ASM` programming the **6821** at `2900`–`2903` — including **`EF08H` as the ROM/RAM bank flag** and the per-monitor-version origins `EE80`/`ED80`/`EA80`. Written up in `docs/o1-ieee488-port.md`. Relevant to #22, #84, #19. | *The Portable Companion* #8, July 1983 — PDF pp. 44–49 (printed 42–47) |
| `TPC-Issue08-1983-pp87-osbaud-baud-rate-generator.pdf` (0.8 MB, 1 p) | **Brad Baldwin**'s review of Advent Products' **"Osbaud"** baud-rate generator ($59.95, **16 DIP-switch rates** to **19200**), plus "**The CRT Connection**" — the pre-SCREEN-PAC recipe for an 80-column terminal at 9600 baud. The review gives the four solder points (*"pins 4 and 12 of the 6850 UART, pin 7 of the 74LS32, and pin 7 of the 74LS04"*), which decode to **TxCLK, Vcc and two grounds**. Written up in `docs/o1-modem-serial.md`. Relevant to #21, #24, #45. | *The Portable Companion* #8, July 1983 — PDF p. 87 (printed 85) |
| `TPC-Issue05-1983-pp25-mega-byte-md10-hard-disk-ad.pdf` (0.7 MB, 1 p) | Mega-byte Inc.'s full-page advertisement for the **MD-10** hard disk: **10 MB (formatted), 5¼", $2295**, "20 and 44 megabyte Winchesters also available". The selling points are the *architecture* — it **"does not tie up existing OSBORNE ports"** and is *"significantly faster than other winchester subsystems **which use the IEEE port**"*, so the MD-10 is **not** an IEEE-488 device (unlike Drive C or the Trantor TSL below); portability survives (*"unplug the winchester and the OSBORNE works exactly as before"*); CP/M drivers cost **under 2K** where "other systems require as much as 6K"; a **64K file reads/writes in under four seconds**; one unit takes **up to eight 44 MB subsystems**, a **network of sixteen Osbornes**, and **36 user areas**; the disk becomes **A: and B:** with the floppies moved to **E:/F:**, a second unit becoming **C:/D:**. The footnote — **"MD-10 is a registered trademark of Media Distributing"** — identifies it as the product behind `research/adaptec/` (the Media Distributing disk that ships `MD10.COM`/`MD20.COM`), so the archive's "Media Distributing / Adaptec" hard disk **is an MD-10**. **Hand-transcribed** — tesseract returns only the folio from this display-type page (see below). Quoted in `docs/research-gaps.md` §B1 and `docs/occ1-harddisk-analysis.md`. Relevant to #8 and the hard-disk survey (gap 9). | *The Portable Companion* #5, February/March 1983 — PDF p. 25 (printed 23) |
| `TPC-Issue05-1983-pp28-trantor-tsl-hard-disk-ad.pdf` (0.8 MB, 1 p) | Trantor Systems' full-page advertisement for the **TSL-5** and **TSL-10** hard disks: **5 MB $2995 / 10 MB $3395**, *"unpack your disk, **plug it into the IEEE port**, run a simple 5 minute installation procedure and you're ready for use"*, supplied *"complete with **BIOS, back-up, retrieve utilities and cable**"*. This is the Trantor line that `docs/drive-c-protocol.md` records the Drive C vendor as reselling at a discount, so the ad is the primary source for that product's interface: an **IEEE-488-attached** Winchester — the opposite architecture to the Mega-byte MD-10 on p. 25. No folio is printed on the ad page. Quoted in `docs/drive-c-protocol.md` and `docs/research-gaps.md` §B1. Relevant to #6, #22 and #84. | *The Portable Companion* #5, February/March 1983 — PDF p. 28 |
| `TPC-Issue05-1983-pp98-tra-80-100-column-video-and-winchester-ads.pdf` (0.4 MB, 1 p) | Two advertisements on one page. (1) **The Research Associates (TRA)** — "**80 and 100 column video**", a video system "as an add-on to the Osborne 1" giving **80×24 and 100×24 windows into a 128×32 format** on an external monitor, with **soft scrolling**, **reverse video and blinking**, **composite and TTL outputs**, connection *"by any Osborne 1 user. Simply plug into the **IEEE port** and into your external monitor"*, *"parallel printer connection is not forfeited"* (the printer moves to a **parallel port on the TRA**), and "a one-time, automatic disk configuration process" with vendor-supplied driver software. That is a **third 80-column implementation** alongside SCREEN-PAC and Nuevo (#24), and unlike either it reaches the monitor through the **IEEE port** while taking over the printer function. (2) **Helix / Micro Computers of New Orleans**, "**Winchesters Now Available For The Osborne 1**": a "**Z-80 adaptor** card [that] leaves external ports free and increases the speed that your information is displayed", ribbon cable disconnects for portability, **5 MB $2500 / 10 MB $3000 / 15 MB $3500**. Quoted in `docs/o1-upgrade-boards.md` (TRA) and `docs/research-gaps.md` §B1 (Helix). Relevant to #24, #19 and gap 9. | *The Portable Companion* #5, February/March 1983 — PDF p. 98 (printed 84) |
| `TPC-Issue07-1983-pp50-51-dating-your-computer-date-in-memory.pdf` (1.4 MB, 2 pp) | "**Dating your computer** — a system's date facility" by **Walter B. Novinger**: a `DATE.BAS` that asks for `MMDDYY` and stores it, a `GETDATE` BASIC subroutine that reads it back, and an `AUTOST.COM` modification (`LXI B,10` → `LXI B,13`, command string `'MBASIC DATE',0`) that makes the prompt automatic at boot. The reusable fact is the **storage location**: the date goes in the **12-byte page-zero block at `0050H–005BH`**, which the *Osborne 1 User's Guide* "Memory Allocation" chart (p. R-243) marks "**not used**" — written in both **binary** (`POKE 80,D`, `POKE 81,M`, `POKE 91,Y`) and **ASCII month name** (`82H`–`8AH`) so the reader needs no machine code. It survives a **warm start (RESET) and diskette swaps** but not power-off. Prior art for the RTC work (#18/#7) and the boot disk (#28). Quoted in `docs/rt60a-analysis.md` and `docs/o1-memory-io-map.md`. | *The Portable Companion* #7, June 1983 — PDF pp. 50–51 (printed 48–49) |
| `TPC-Issue07-1983-pp56-57-programming-the-serial-port.pdf` (0.9 MB, 2 pp) | "**Programming the serial port** — modifying the serial port for scientific test devices", signed by the **Osborne Computer Corporation System Technical Support Group**: how to change the **6850 ACIA's** data bits / stop bits / parity away from the factory **8-N-1** by patching the BIOS's serial control byte — a fully worked procedure (`MOVCPM 60 *` for a **1.3** BIOS / `MOVCPM 59 *` for **1.4**, `SAVE 39 CPM60.COM`, `DDT CPM60.COM`, **`S1FE9`** and write the code at **`1FE9H`/`1FEAH`**, then `SYSGEN`), a **"Table of 6850 control codes"** covering all 16 combinations at 1200 and 300 baud (e.g. **8-N-1 @1200 = `55H`**, **8-N-1 @300 = `56H`**, 7-E-1 @1200 = `49H`, 8-N-2 @1200 = `51H`), and a **which-BIOS-do-I-have** test (`DDT`, `DA900H`: `C3 xx E5` = 1.3, `C3 xx E1` = 1.4). Gives the exact **BIOS offset the ACIA's control register is initialised from** — a second handle on the ACIA beyond the `2A00H`/`2A01H` port pair, directly useful to the snoop/modem work (#21, #56). Quoted in `docs/o1-modem-serial.md` and `docs/o1-memory-io-map.md`. | *The Portable Companion* #7, June 1983 — PDF pp. 56–57 (printed 54–55) |

### How these extracts are made

The maintainer reads the issues and hands over the ones worth keeping, giving the
**PDF page sequence** to cut. The standing workflow:

1. Cut the pages: `pdfseparate -f A -l B ISSUE.pdf /tmp/p%03d.pdf` then
   `pdfunite /tmp/p*.pdf OUT.pdf`.
2. OCR the extract with `tools/ocr_pdf.sh OUT.pdf` — adjacent, per the convention
   above. **Wait for its `Wrote <path>` line before committing**; the file exists
   while it is still being written.
   - **If you drive `tesseract` by hand, do not render into `/tmp`.** On this
     machine it cannot open images under `/tmp` (Leptonica reports the file as
     not found) and, with `2>/dev/null`, fails *silently* — a 43-page sweep over
     `/tmp` returned nothing at all and looked like "no matches". The script is
     fine because it renders into a `mktemp -d`.
   - **A display-type page can defeat tesseract entirely.** Full-page
     advertisements set in display faces over tinted screens sometimes OCR to
     nothing but the folio — the #5 Mega-byte MD-10 ad
     (`TPC-Issue05-1983-pp25-…`) was the first. Do **not** commit an empty
     `.ocr.txt`: transcribe the page by eye into the file behind a
     `[HAND TRANSCRIPTION, not tesseract output …]` header, so the text still
     lives beside the scan and never has to be re-derived.
3. Add a row below, and write the findings into the `docs/` page they bear on
   with the extract cited.

Two things to know before cutting pages:

- **Page numbers are PDF pages, not printed pages.** Every page checked so far
  prints its own number two lower (`PDF = printed + 2`) — issues 11, 13, 14, 15,
  and now #5 p. 25 (→ 23) and #7 pp. 50 and 56 (→ 48 and 54). So an article "on
  page 26" is PDF page 26 and printed page 24 — and cutting printed 26 would miss
  the article's title page. **The offset is not uniform, though:** the #5 extract
  filed as `pp98` carries folio **84**, i.e. `+14`, so an issue can contain
  unnumbered pages. Read the folio off the page rather than assuming —
  `pdftotext -f N -l N -layout ISSUE.pdf - | tail -3` prints it, and the
  extract's own `.ocr.txt` usually ends with it.
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
| `Drive_C_Users_Manual.pdf` | Drive C user manual (IEEE-488 virtual disk drive), **second edition June 1984** | [bitsavers `bits/Osborne/Osborne1/Drive_C/`](https://bitsavers.org/bits/Osborne/Osborne1/Drive_C/) (upstream name `Drive_C_-_Users_Manual.pdf`) |
| `Drive_C_Executive_Users_Manual.pdf` | **Drive C user manual for Osborne Executive computers** — the same product on the other host: identical hardware appendix, `ECL`/`ECN`/`ECU` software under CP/M+ instead of `DCL`/`DCN`/`DCU` under CP/M 2.2, and **no `DFD.SPR`**. First edition July 1984, second printing 9/84; cover stamped PRELIMINARY, running headers "final draft". 111 pp, 12 MB, image-only (150 dpi grayscale re-encode — see the note below). Analysis: `docs/drive-c-executive.md` (#84, #6, #145) | **Jim Rayburn**, private Facebook group, posted 2024-01-06 — posts [.../2063148960719887](https://www.facebook.com/groups/690000664701397/posts/2063148960719887/) and [.../2023247321376718](https://www.facebook.com/groups/690000664701397/posts/2023247321376718/); supplied to the maintainer as `Executive_DriveC.pdf`, 2026-10-11 |
| `Drive_C_Executive_Users_Manual.ocr.txt` | OCR text layer for the above — 300 dpi `tesseract`, per the convention below | Derived in-project, 2026-10-11 |
| `DRIVE_C.IMD` | ImageDisk image of the Drive C utility disk (label comment `Drive C for the Osborne 1 computer`) | same folder — **not** imaged in-project; corrected 2026-10-10 |
| `Drive_C_disk_label.jpg` | Photo of the physical disk label | same folder (15 044 B, byte-identical) — **not** a project photo; corrected 2026-10-10 |
| `extracted/` | Files extracted from `DRIVE_C.IMD` by the project pipeline (#2) | Derived in-project |
| `disasm/` | `dcl.asm` + `dfd.asm` — z80dasm listings of the installer and the resident driver, for the protocol work (#6). Regenerate with the exact command in `docs/drive-c-protocol.md` §Disassembling | Derived in-project |

**A note on the Executive manual's size.** The owner supplied a 300 dpi scan,
42.33 MB — larger than any other single file in this tree. It is committed as a
**150 dpi re-encode** instead (12.13 MB), the same resolution as the Drive C
manual above: the document is a typewritten mono manual, and the page images
carry **no colour at all** — every pixel is neutral grey, checked across all
111 pages — so the extra resolution bought nothing but file size. All **111
pages** and the page geometry are preserved. The **300 dpi text layer** was
taken from the owner's original before the re-encode and sits beside the PDF as
`Drive_C_Executive_Users_Manual.ocr.txt`, so no text was lost. It is recorded as
a re-encode rather than as the owner's original, so the provenance stays
honest: the file here is **not** byte-for-byte what Jim Rayburn posted.

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
| `compatible-drives-1991-usenet.txt` (23 KB) | **A period list of ST-506/MFM drives**, not Osborne software: Robert L. Haar's *"List of replacement hard drives for 3b1"* (`comp.sys.3b1`, 12 Feb 1991, [TUHS Usenet archive](https://www.tuhs.org/Usenet/comp.sys.3b1/1991-February/000257.html)), which reposts Lenny Tropiano's *"ST-506 MFM Hard Drive Manufacturer listing (LONG), model #'s and specs"* (`unix-pc.general`/`comp.sys.att`/`comp.periphs`, 2 Sep 89), itself edited out of the full drive list on the Western Digital technical-support BBS. Per manufacturer: model, formatted capacity, cylinders, heads, reduced-write-current, write-precomp, encoding, transfer rate, access time and **sectors/track** — the last of which is **17** for almost every entry, where `DRIVETBL.DAT`'s capacity formula uses 18, and it gives `PYXIS-13` **320** cylinders where `DRIVETBL.DAT` says **321**. Archived because the personality should offer any ST-506/412-class drive, not only the 126 the MD-10 tools ship (`docs/harddisk-decision.md` §7.2) |

Together with `acb4000a.rom` (Maslin's archive) this identifies the controller
behind `harddisk/OCC1_HARDDISK.IMD` — issue #8.

## adaptec/md10-system/ — the MD-10 operating system (2026-10, generated in-project)

**The system the archive did not hold.** `docs/harddisk-decision.md` §7.3
concluded that nothing in the archive initialises the MD-10's low-RAM tables and
that the utilities disk carries no system image — which left #179's acceptance
("boots CP/M from the emulated hard disk") with nothing to boot. It was not
obtainable by *reading*; it is obtainable by *running*, and the vendor's own
installer produces it: `PREP.COM` option 3, "Configure operating system", writes
it to the drive. Captured off a configured drive on 2026-10-12.

| File | What it is |
|---|---|
| `lba0-15.bin` (8 KiB) | the first sixteen blocks of a configured drive: LBA 0 the disk label and its partition table, LBA 1–3 the header, LBA 4 a table, LBA 5–15 the operating system |
| `md10-os.bin` (5.6 KiB) | just the operating system — LBA 5, 11 blocks (0x1600 bytes) — what `HARD.COM`'s BIOS reads to `0xC200` and jumps into |
| `README.md` | provenance, and what each file is |

Derived in-project from `adaptec/*.img` (the `PREP.COM` that writes it) and the
2.01 utilities disk (the `HARDCCP.SPR`/`HARDBDOS.SPR` it writes); the drive it
was taken from had md5 `7fa2a3836813dabdeaaa664ea88d002e`, and
`tools/research/md10drive.py` reproduces that drive byte for byte from these two
files. The recipe, the MD-10's memory map and the boot chain are in
`docs/md10-system.md`.

## adaptec/acb4000/ — Adaptec ACB-4000 controller hardware (2026-10)

The controller itself — schematics, board photographs, the controller's own
firmware ROMs, and two OEM manuals. Archived because #8 **selected this
controller** (`docs/harddisk-decision.md`). Source:
[bitsavers `pdf/adaptec/ACB-4000/`](https://www.bitsavers.org/pdf/adaptec/ACB-4000/).

| Path | What it is |
|---|---|
| `500504-00_ACB-4000_OEM_Manual_Mar84.pdf` (9.8 MB) | OEM manual — the command set (Table 6-1), the reference host-adapter register model, a sample Z80 driver and a sample format sequence |
| `400003-00A_ACB-4000A_Users_Manual_Oct85.pdf` (7.1 MB) | ACB-4000A user manual. **Image-only scan** — `pdftotext` returns nothing. Carries **§2.3.1** (device independence / auto-configuration) and **§3.7** (power-up operation): the drive parameters are encoded onto the disk at `FORMAT`, **in the ID field of cylinder 6**, and read back at power-up — see `docs/harddisk-decision.md` §7.3 |
| `400003-00A_ACB-4000A_Users_Manual_Oct85.ocr.txt` (177 KB) | OCR text layer for the above (per the convention at the top of this file), generated 2026-10-12 at 120 dpi with `tools/ocr_pdf.sh`. Good enough to grep — §2.3.1's "ID field of cylinder 6" is legible — but the OCR mangles part numbers (`ACB-4000` renders as `ACB-4909`/`ACB-4990` in places), so read the PDF for anything load-bearing |
| `ACB_4000_and_5000_Disk_Controllers_OEM_Manual_Preliminary_May83.pdf` (2.6 MB) | preliminary OEM manual (ACB-4000 + ACB-5000) |
| `ACB4000A_Schematic_ARD_2025.pdf` (2.4 MB) | board schematic |
| `firmware/` | six 8 KiB controller ROM images + an Intel-HEX build (`ACB-4000A-rev-B.hex`) |
| `pictures/` | seven board photographs |

The `adaptec/*.img` software above is the **host** side (the MD-10 driver); this
folder is the **controller** side. The personality needs both: the host side is
what it must answer, the controller side is what it must be.

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
| `Nuevo_Electronics_DD_Upgrade_Manual.ocr.txt` (919 lines) | OCR of the manual — the BIOS 1.4→1.5 difference list (DPBs for IBM/Xerox/DEC removed, 80-column presence check, jump table at `E100h`), the 380K double-sided claim and the single/double-density system-track rules, all quoted in `docs/dd-upgrade-formats.md` | derived in-project with `tools/ocr_pdf.sh … 300` |
| `OS1NUEVO.IMD` | `Osborne 1 with DD and 80 col mods` boot disk, re-imaged 2026-10-10 with Disk-Utilities | derived in-project |
| `photos/nuevo-80-column-board.jpg` | **80-column board, `REV. D`, serial 4348** — the first hardware view of the product. Its own **NEC D780C-1** (Z80), a Nuevo **`SY6545A-1`** CRTC, 2 × `SRM2016C25` SRAM, a socketed **`CHARACTER GENERATOR`** ROM dated **6-29-84**, a 12.288 MHz oscillator, and the optional `BAUD` generator. Devices, and what they imply, in `docs/o1-upgrade-boards.md` §"The Nuevo boards themselves" (#73, #24) | **Mike Loewen**, private Facebook group, 2024-10-14 — [post](https://www.facebook.com/groups/690000664701397/posts/2260585240976257/) |
| `photos/nuevo-double-density-board.jpg` | **DD board, serial 20011** — `DAL DENS` silk, a 34-pin IDC header with a `STD DRIVE` jumper, and a discrete write-precompensation/separator chain (`74LS195A`, `SN74LS14N` ×2, `SN74LS00N` ×2, `SN74LS02N`) plus a 16-pin `9216`-family device (U1). Same analysis as above | same post |
| `photos/nuevo-80-column-and-double-density-boards.jpg` | Both boards in one frame — the shot the 2024-10-14 post is built around | same post |

The photographs are **third-party** (Mike Loewen, a private group) rather than
in-project like `pictures/`, and they are the only hardware views of either
Nuevo product — there is no Nuevo schematic in the archive. Neither board bears
on Drive C: both are host-side (video, and floppy encoding).

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

`OZROM-1E/OZROM_1E_Utilities.IMD` — the **OZROM 1E Utilities disk**, the
software half of the OZROM package, which we did not previously have. ImageDisk
1.19, label `ozrom`; 40 cyl × 10 × 256 B FM (O1 single density), 22 of 40 tracks
in use. Its CP/M directory is complete and readable: 20 files, all Micro
Management 1984, with `READ.ME`, `CRCKLIST.CRC` and the docs for `TIMER`,
`CLKPATCH`, `DVORAK` and `TD`. **Condition: partial.** 290 of the 400 sectors
read back as uniform `0xE5` and the gaps fall *inside* file bodies, so most
files are truncated or holed; the directory and a minority of complete files
(`SET.COM`, `MEMORIZE.COM`, `FK.COM`) are the recoverable part. It is a data
disk, not a system disk — the boot tracks carry a stub whose message is
"There is no CP/M system on this disk." Provenance: supplied by the project
owner as a local file (2026-10-11); the original source URL is not yet recorded,
so treat the chain of custody as open. Analysis: `docs/ozrom-1e.md` §10. Used by
#81.

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

## act-assembler/ — SORCIM ACT80, the assembler the firmware source needs (2026-10)

The Osborne firmware source in `source-code/` is written for **SORCIM's ACT**
("Assembly Code Translator"), not for any assembler we had. This is that
assembler, kept as a safety copy because `rom144.asm` reassembles with it to the
shipped ROM **byte for byte** (#203, `docs/o1-rom-source.md`).

| Path | What it is | Sourced from |
|---|---|---|
| `ACT80.COM` (13 312 B) | **SORCIM ACT80, version 3.0** — 8080/8085 + Z80. md5 `4f76a911a66ddc8e1e02a1676c232d45`. The build the 1.44 reassembly was done with. | [cpmarchives.classiccmp.org](http://cpmarchives.classiccmp.org/cpm/Software/rlee/S/SORCIM/ACT%20Cross%20Assemblers/) — `cpm/Software/rlee/S/SORCIM/ACT Cross Assemblers/` |
| `3.2/ACT80.COM` (13 312 B) | **SORCIM ACT80, version 3.2**, serial 279. md5 `cf73590466736fd1960e829b5f2221aa`. Held so the version question can be re-checked against a local file rather than the mirror: it assembles `rom144.asm` to output **byte-identical** to 3.0's. | same mirror, `cpm/Software/rlee/L/LOOSECPM/119/` — `073` and `087` hold the same bytes |
| `3.2/ACT80-eca-bundle.COM` (13 312 B) | A **third, different 3.2 build**, the one that circulated inside a third-party software bundle. md5 `88256731a9399dee68a29054865d072c`. It reports `SORCIM 808x Assembler ver 3.2` in its listing banner, but carries **no SORCIM copyright or serial line at all**, and it differs from the SORCIM 3.2 in **13 112 of 13 312 bytes** — a redistribution rather than the release, kept as evidence of how many binaries claim to be 3.2. | same mirror, `cpm/Software/rlee/D/DIGITAL RESEARCH/ECA/` (it is named `ACT80.COM` there; renamed here so both 3.2 copies can sit side by side) |
| `ACT65.COM`, `ACT68.COM`, `DOCOP65.ASM`, `DOCOP68.ASM` | The same kit's 6502 and 6800 translators and their mnemonic listings. Kept with the kit rather than dropped — they are 30 KB, and a hand-picked subset invites the question of what was left out. | same |
| `DOCOP80.ASM` (8 192 B) | **Every ACT mnemonic, in alphabetical order** — the dialect reference, and the file to diff against if a future source is rejected. | same |
| `READ.ME`, `INSTALLA.SUB` | The kit's own file list, and its `SUBMIT` script for moving the kit from B: to A:. | same |
| `IPARAMS.ACD`, `UTIL.ACD`, `ACD-EG.ASM` | ACT's `LINK` include files, and an example program using them (`LINK IPARAMS.acd`). | same |

**Versions.** The mirror holds nine copies of `ACT80.COM` in **three distinct
builds, and all three are kept here** — so the version question can be re-checked
against a local file rather than the mirror:

| Build | md5 | Copies in the mirror | In-repo |
|---|---|---|---|
| 3.0 | `4f76a911…` | `S/SORCIM/ACT Cross Assemblers/`, `M/MORROW/OUTSIDE SOFTWARE/ACT/`, `L/LOOSECPM/{079,109,262}/` | the kit above |
| 3.2, serial 279 | `cf735904…` | `L/LOOSECPM/{073,087,119}/` | `3.2/ACT80.COM` |
| 3.2, no banner | `88256731…` | `D/DIGITAL RESEARCH/ECA/` | `3.2/ACT80-eca-bundle.COM` |

**3.5e — the version `bios141.gen` names — is not in the mirror**, and it does not
need to be, because the version does not change the answer: **3.0 and the SORCIM
3.2 assemble `rom144.asm` to byte-identical output**, both re-checked against the
in-repo copies (#203). Either one reproduces the shipped ROM:

```sh
O1_ACT80=research/act-assembler/3.2/ACT80.COM tools/research/rom144-reassemble.sh
```

The third build is a caution rather than a spare. On the same disk, with the same
command, it returns to the `A>` prompt immediately and prints **nothing** — no
banner, no `no ERRORs` line, no hex file — where both SORCIM builds assemble the
source cleanly. Whatever it is (a relocation for one system size, a bundle
installer's variant, or a patched copy), it is **not a drop-in ACT80**, and it is
kept as evidence of how many different binaries claim to be version 3.2.

**Licensing:** `READ.ME` is SORCIM's own 1980 notice — *"This disk contains
software proprietary to SORCIM. It may NOT be copied other than for use by the
purchaser."* It is retained verbatim and recorded here rather than quietly
dropped. The kit has been publicly mirrored since 2011, and this copy exists to
read the firmware source the project already holds; if the terms ever need
re-examining, that file is where to start.

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
