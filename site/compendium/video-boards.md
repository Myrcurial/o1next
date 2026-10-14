---
layout: page
title: "80-column boards: SCREEN-PAC to TRA"
subtitle: "Peripherals and storage · partially solved"
draft: "Draft &mdash; assembled from the working notes by `tools/build_book.py`. The source document is the authority; this page is a copy for reading, and it is regenerated from that source."
---

Nuevo Electronics and Osmosis each shipped **two** Osborne 1 upgrades — a
double-density board and an 80-column video board — and **neither follows the
pattern OCC used for the same two functions**. That matters twice over: it is
prior art for this project's interposer, and it means a video personality (#24)
cannot assume the ScreenPac's interface.

This doc covers the **video** side. The DD side is in
[`docs/dd-upgrade-formats.md`](https://github.com/Myrcurial/o1next/blob/main/docs/dd-upgrade-formats.md) and [`docs/research-gaps.md`](https://github.com/Myrcurial/o1next/blob/main/docs/research-gaps.md) gap #11.

> **Scope note: "Executive" means a different machine.** In Osborne's world the
> Osborne **Executive** is the O2-class machine, not a variant of the 1. Upgrades,
> software and advertisements aimed at it are therefore **out of scope here** and
> must not be folded into Osborne 1 conclusions — for example the $595
> double-sided-drive upgrade advertised in *The Portable Companion* #14, PDF p. 47,
> which is an Executive product. The three machines this project cares about are
> the Osborne 1, the Osborne 1 with OCC's own upgrades, and clones of them
> ([`docs/research-gaps.md`](https://github.com/Myrcurial/o1next/blob/main/docs/research-gaps.md) gap 12).

## The three implementations at a glance

| | OCC **SCREEN-PAC** (1983) | **Nuevo** (1984) | **Osmosis** (1983) |
|---|---|---|---|
| What it is | add-on board, hardware only | replacement monitor ROM + patched CBIOS + own char-gen | **Z80 interposer board** + supplied monitor ROM |
| How it attaches | board inside the machine (`2F00040` service manual §6.12) | swap the monitor ROM; patch the CBIOS with DDT | **Z80 moves onto the board, board into the Z80 socket** |
| ROM change | **none** — MAME models `osborne1sp` as a clone | Nuevo **1.51** monitor ROM + BIOS 1.5 objects | supplied ROM marked **"Osborne 1.44 GM"** |
| Widths | **52 / 80 / 104** | 80 | 80 (and back to 52) |
| Selected by | **BIOS variable** — poke `E1A5H`, call `E4E5H` | patched CBIOS entry (`02C9` → `JP 02D4`) | **escape sequences** — `ESC 8` / `ESC 5` / `ESC F` |
| Detected by software | `2400H` bank 2, **bit 2 LOW** | — | — |
| Horizontal scroll | 32-column blocks | — | — |
| Character generator | stock late | **its own** (adds underline via row 9) | stock 1.44 |

Sources for each row are quoted below. "—" means the material in the archive
does not say; it is not a claim that the feature is absent. A **fourth**
implementation, The Research Associates' TRA board, is not in the archive at all
— it is covered separately below from its advertisement.

## OCC SCREEN-PAC — hardware only, driven by the stock BIOS

The one that needs no ROM: [`docs/o1-memory-io-map.md`](https://github.com/Myrcurial/o1next/blob/main/docs/o1-memory-io-map.md) §2a has the full
statement. The parts that make it the odd one out are that the **stock BIOS
already contains the width-switching routine** (`E1A5H` / `E4E5H`), that the
board announces itself at **`2400H` in bank 2**, and that the SCREEN-PAC's own
2 KiB ROM is *the same image as the stock late character generator*
([`docs/o1-rom-variants.md`](https://github.com/Myrcurial/o1next/blob/main/docs/o1-rom-variants.md)) — so the capability genuinely is not in a ROM.

## The Research Associates (TRA) — 80/100 columns, over the IEEE port

A **fourth** 80-column answer, and the only one that reaches the screen through a
*different connector*. An advertisement in *The Portable Companion* #5
(February/March 1983, PDF p. 98 = printed 84; extract
[`research/technical-articles/TPC-Issue05-1983-pp98-tra-80-100-column-video-and-winchester-ads.pdf`](https://github.com/Myrcurial/o1next/blob/main/research/technical-articles/TPC-Issue05-1983-pp98-tra-80-100-column-video-and-winchester-ads.pdf))
announces "**80 and 100 column video**" from **The Research Associates** (Forest
Hill, Dunstable, Massachusetts) as "an add-on to the Osborne 1", providing:

- an **80×24 window** and a **100×24 window** "into a 128 character by 32 line
  video format" — the same 128-wide buffer this project already models
  ([`docs/o1-memory-io-map.md`](https://github.com/Myrcurial/o1next/blob/main/docs/o1-memory-io-map.md) §2a), so TRA widens the *window* exactly as the
  others do;
- **soft scrolling**, **reverse video and blinking**, **composite and TTL video
  monitor outputs**;
- connection "by any Osborne 1 user. **Simply plug into the IEEE port** and into
  your external monitor";
- "**parallel printer connection is not forfeited**" — the printer moves to a
  **parallel port on the TRA**;
- "a one-time, automatic disk configuration process", with the **driver software
  supplied by the vendor**.

Two things make it worth recording. First, **the interface is the IEEE port**,
not the video bus — so a video personality (#24) cannot assume an 80-column
upgrade lives on the video side of the machine, and the IEEE port becomes
contended between a video device, Drive C (#6/#84), the RT-60A (#18) and Trantor
storage. Second, its **on-board printer port** is the same "duplicated port"
pattern as the Drive C panel ([`docs/drive-c-protocol.md`](https://github.com/Myrcurial/o1next/blob/main/docs/drive-c-protocol.md)): the add-on
*re-presents* an existing connector. Neither its width-switching mechanism (no
ROM or BIOS patch is mentioned — a driver plus a disk configuration step) nor its
presence detection is documented in the ad, and **unlike SCREEN-PAC and Nuevo it
is not in the archive**: the ad is all we hold.

## Nuevo — a new monitor ROM, and a CBIOS patched on disk

Nuevo's video upgrade is **software**, and the archive holds the installer. The
system disk [`research/nuevo/OS1NUEVO.IMD`](https://github.com/Myrcurial/o1next/blob/main/research/nuevo/OS1NUEVO.IMD) (Osborne DD: 40 tracks × 5 × 1024 B,
250 kbps MFM) contains 19 files, and two of them are the installers — not SUBMIT
scripts despite the extension, but **DDT patch scripts** run through `XSUB`:

```
$ cpmcp -f osborne1 OS1NUEVO.IMD 0:SYS-80C.SUB -
B:XSUB
B:DDT B:MOVCPM.COM      ; patch the CP/M system image in memory
IBIOS15.OBJ             ; insert Nuevo's BIOS 1.5 object
R1F00                   ; ...at 1F00
IBIOS15BM.OBJ           ; and the second module
R29E0                   ; ...at 29E0
S2C9                    ; set the byte at 02C9
C3                      ;   to C3 (JP)
D4                      ;    D4 02 = JP 02D4  <- the 80-column hook
02
.
FA10,A17,00             ; clear the width/variable block
G0
SAVE 43 MOVE-CPM.COM    ; 43 pages = the new system
MOVE-CPM 59 *           ; write it to the system tracks
```

So the Nuevo mechanism is: **patch `02C9` to jump into new code at `02D4`,
carrying a replacement BIOS (1.5) and its variables.** `SYS-DDEN.SUB` is the
same script with the DD patches added — four sites set to `64` (100 decimal, the
width value used for the wide display elsewhere) — plus an `ERA AUTOST.COM`.

Two more files patch an application rather than the system:

```
$ cat DB23PTCH.SUB
XSUB
DDT B:DBASE.COM
S130 / 01        ; patch dBASE's screen handling
S154 / 50        ; 50 hex = 80 columns
S395A / C9       ; RET
G0
SAVE 70 B:DBASE.COM
```

**That is byte-for-byte the same three-byte patch Osmosis's manual gives for
dBASE** (below). Two independent vendors arrived at the same fix, because what
needs patching is dBASE's assumptions, not the board.

Plus the ROM side: Nuevo **1.51** is an OCC ROM carrying Nuevo's copyright and
patches ([`docs/o1-rom-variants.md`](https://github.com/Myrcurial/o1next/blob/main/docs/o1-rom-variants.md)), and the Nuevo char-gen differs from stock —
it forces row 9 to `0xFF` when bit 7 of the character code is set, which is the
underline attribute made real in the font.

### The Nuevo product line, from its own advertising

*The Portable Companion* #15 (Jan/Feb 1985, PDF p. 39) advertises four upgrades,
and the 80-column one is not just a wider window:

> **80 COLUMN UPGRADE** — Increase your screen size to a full 80 columns (& still
> be able to scroll horizontally if you choose). Excellent resolution, with a
> **choice of six cursor styles and reverse video capability** for easy viewing.
> Optional **baud rate generator provides 16 baud rates from 50 to 19.2K baud**.
> $250.00 (add $30 for the optional baud rate generator)

Three things worth taking from that:

- **"Six cursor styles"** — Nuevo's video board treats the cursor as a *feature*,
  which is the same circuit the block-cursor modifications (#24) were chasing on
  the stock machine and on the SCREEN-PAC. A personality that renders only the O1's
  underline cursor is rendering the worst of the available options.
- **Horizontal scroll in 80 columns** — the same window-sliding behaviour the
  SCREEN-PAC gives, here described as a user choice rather than a side effect.
- **A baud generator to 19.2K** — well beyond the 9600 Hogan's modification
  reaches on the stock board ([`docs/o1-memory-io-map.md`](https://github.com/Myrcurial/o1next/blob/main/docs/o1-memory-io-map.md) §2a), and an *option*
  rather than a cut track. It is the other end of #21's range.

The disk products from the same advertisement are in [`docs/dd-upgrade-formats.md`](https://github.com/Myrcurial/o1next/blob/main/docs/dd-upgrade-formats.md).

### The Nuevo boards themselves (2024 photo drop)

No Nuevo schematic is in the archive, so both products have only ever been known
through their software. Two field photographs change that: they are the **first
hardware views of either Nuevo board**. Source: **Mike Loewen**, private Facebook
group, 2024-10-14
([post](https://www.facebook.com/groups/690000664701397/posts/2260585240976257/));
archived as [`research/nuevo/photos/`](https://github.com/Myrcurial/o1next/blob/main/research/nuevo/photos/).

**80-column board** — silk `NUEVO ELECTRONICS CORPORATION © 1984`,
`80 COLUMN UPGRADE REV. D`, **serial 4348**. It is not a video tap; it is a
**self-contained video subsystem**:

| Device | What it is |
|---|---|
| **NEC D780C-1** (PI9455-138) | a Z80 — the board has its own CPU |
| **Nuevo `SY6545A-1`** (8325) | a 6545/6845-class CRTC, so the board makes its own video timing |
| `SRM2016C25` ×2 | 2 K × 8 SRAM — about 4 KB of video RAM |
| socketed **`CHARACTER GENERATOR`** ROM, `88332 SINGAPORE`, dated **6-29-84** | the board's own font, under a Nuevo printed label |
| `NYMPH 12.288 NMP122` | 12.288 MHz oscillator (dot clock) |
| `74S157` ×3, `74LS194A`, `74LS161B`, `74LS273`, `74LS374B` ×2, `74LS166`, `74LS174`, `74LS86B`, `74LS74A`, `74LS20`, `74LS10`, `74LS02` ×2, `74LS00`, `7406` ×2 | glue: multiplexers, counters, shift registers, latches, drivers |
| `VR1`, `Y2` | video-level trimmer, crystal |
| `J1`–`J6`, **`J9`–`J12`** | configuration jumper blocks |
| `P2`, `P3` (10-way edge fingers), `P4` | host/display interface |
| `BAUD` section, 14-pin `P2111-2` | the **optional** baud-rate generator the advertisement prices at +$30 |

Two consequences, and both *corroborate* what the software already said:

- **The 80-column mode is a second video system, not a wider window.** Its own
  CPU, CRTC, video RAM and font are why the advertisement can sell "six cursor
  styles" and horizontal scroll as *features* — those are properties of a real
  CRTC. It is also why [`docs/o1-rom-variants.md`](https://github.com/Myrcurial/o1next/blob/main/docs/o1-rom-variants.md) §"one late image, five names"
  concludes Nuevo's 80-column design is not the OCC one: the SCREEN-PAC widens
  the *existing* video path, Nuevo builds another one.
- **The socketed `CHARACTER GENERATOR` chip is dated 6-29-84** — the date in
  MAME's `character_generator_6-29-84.14`, the Nuevo-era char-gen already tracked
  in [`docs/o1-rom-variants.md`](https://github.com/Myrcurial/o1next/blob/main/docs/o1-rom-variants.md). So the font the board carries is an image the
  project holds, not an unknown ROM.

**Double-density board** — silk `NUEVO ELECTRONICS CORPORATION © 1984 MADE IN
USA`, `DAL DENS` (dual density), **serial 20011**. This one is an *encoding*
board, not a controller:

| Device | What it is |
|---|---|
| `STD DRIVE` silk; `J1`/`J2`; 34-pin IDC header (pins 1–34) | the drive-cable side of the interface (the O1's own 34-pin floppy header is `P8`) |
| `WRITE PRE COMP` silk; `74LS195A` (U4), `SN74LS14N` ×2 (U3, U5), `SN74LS00N` ×2 (U2, U6), `SN74LS02N` (U7) | a discrete **write-precompensation delay line** (shift register + Schmitt inverters), and the **data separator** |
| U1, 16-pin DIP marked `VD9216 / CA00 / 8402` | unresolved. `9216` is the number Standard Microsystems uses for its **FDC9216 floppy data separator**, which would make U1 the separator and put the precompensation in the LS chain — but the marking needs a higher-magnification re-read before either reading is asserted |
| `RN1`, `RN2`; `P4` | resistor networks; 4-pin power |

The likely division of labour — that the DD upgrade supplies the **MFM data
separator and write precompensation** the stock machine lacks, and leaves the
controller alone — fits the rest of the archive: the controller is `MB8877` ≡
`WD1793` on the mainboard, and the separator is a *separate board on the drive
side* rather than part of it ([`docs/o1-mainboard-schematic.md`](https://github.com/Myrcurial/o1next/blob/main/docs/o1-mainboard-schematic.md) §2, sheets 9/9 and
2/3, U8 and U12–U22). **That is an inference, not a finding** — Nuevo's own
installation instructions are the missing piece.

**Does any of this bear on Drive C?** No, and it is worth saying plainly. Both
boards are host-side — video, and floppy encoding — while Drive C is an IEEE-488
peripheral that draws power from the EXT. VIDEO connector and speaks over the
GPIB port ([`docs/drive-c-protocol.md`](https://github.com/Myrcurial/o1next/blob/main/docs/drive-c-protocol.md)). The photo drop is recorded here because
it is the first hardware view of either Nuevo product, not because it changes the
Drive C contract.

### The 80-column board's own feature list, from the shipped software

`OS1NUEVO.IMD` also carries **`AUTOST.COM`** — a two-instruction CP/M program
(`LD C,9` / `CALL 5`, print a string, exit) whose string is the product's own
feature list. It is the **autostart banner**: the 80-column installer keeps it
(`SYS-80C.SUB`) and the DD-only installer *erases* it (`SYS-DDEN.SUB`), so it
ships only with the video product. The same file is on the disk twice, as
`AUTOST.COM` and `AUTOST.BAK`, byte-identical.

> **THIS IS AN EIGHTY (80) COLUMN DISPLAY FOR THE OSBORNE ONE.**
>
> FEATURES:
> (1) EIGHTY COLUMN STANDARD DISPLAY.
> (2) PROGRAMMABLE BAUD RATE GENERATOR (16 RATES, 50 TO 19.2K BAUD).
> (3) FULL SCREEN REVERSE VIDEO CAPABILITY (JUMPER SELECT).
> (4) CURSOR PROGRAMMABLE AS UNDERLINE OR REVERSE VIDEO BLOCK.
> (5) CURSOR PROGRAMMABLE FOR FAST, SLOW, OR NO BLINK.
> (6) REVERSE VIDEO BLOCK CAPABILITY (INSTEAD OF UNDERLINE; JUMPER SELECT).
> (7) COMPOSITE VIDEO OUTPUT FOR EXTERNAL MONITOR (NO MORE ADAPTERS).
> (8) SIMPLE USER INSTALLATION.
> — `AUTOST.COM`, [`research/nuevo/OS1NUEVO.IMD`](https://github.com/Myrcurial/o1next/blob/main/research/nuevo/OS1NUEVO.IMD) (extracted with
> `cpmcp -T raw -f osborne1`; the manual's BIOS 1.4→1.5 list item 3 is the
> "autostart command space", so the file name is the feature)

This is the product describing itself, and it splits **hardware** from
**software** cleanly. Only item **(1)** is the CBIOS patch. Items (2)–(7) are
properties of the board's own circuitry: the CRTC gives the programmable cursor
(4, 5), the `J1`–`J6` / `J9`–`J12` jumper blocks give the reverse-video options
(3, 6), the `BAUD` section and 14-pin `P2111-2` header give (2), and the board's
own video output gives (7). That is what "a second video system, not a wider
window" means in practice — and it is why the advertisement can sell cursor
styles and horizontal scroll as *features* while the software delivers exactly one
of the eight.

## Osmosis — a Z80 interposer with an escape-sequence interface

Osmosis's 80-column board is the one that matters most to this project, because
of *how it attaches*. From [`research/osmosis/Osmosis_80_Column_Board.pdf`](https://github.com/Myrcurial/o1next/blob/main/research/osmosis/Osmosis_80_Column_Board.pdf) §3:

> Locate the monitor ROM (fig 2.1). This ROM can be carefully removed … Now take
> the ROM we supplied … Fit the ROM we supplied (marked **Osborne 1.44 GM**) …
> Locate the Z80 processor … Remove the 40 pin Z80 … **Fit the Z80 into the blue
> 40 way header on the Osmosis 80 column board** … Fit the Osmosis 80 column
> board onto the Osborne PCB by inserting the 40 pins … into the socket on the
> Osborne PCB from which you have just [removed the Z80].

**The CPU is moved onto the board and the board takes the CPU's socket.** That is
a Z80 bus interposer — the same technique this project's interposer uses
(#11/#12) — which is why #73 calls Osmosis direct prior art. It is also why the
board can be ROM-based: it ships its own monitor ROM.

Its interface is a **terminal's**, not the BIOS's. From §4, the applications
guide:

> B3. Press escape (ESC), 8 and return. The screen should now be showing a full
> 80 columns. … B5. Try pressing escape (ESC), 5 and return to take you back to
> 52 columns.

and, for software:

> B7. … The board will react to a command such as: `10 PRINT CHR$(27)+"8"`

So Osmosis switches width with **escape sequences** (`ESC 8` = 80 columns,
`ESC 5` = 52, `ESC F` = auto-CR/LF) — the shape of a real terminal's control
codes, reachable from BASIC, rather than a memory variable. The manual also notes
that the board "has been well proven in Europe".

The manual's own dBASE instructions are the same patch Nuevo's disk applies:

> (c) Enter S130 (ret) … Enter 01 (ret) … (e) Enter S154 (ret) … Enter 50 (ret)
> … (g) Enter S395A (ret) … Enter C9 (ret)

### The escape-sequence set (Appendix E)

Appendix E is the *complete* control interface — every code is `ESC` plus one
character. It is a display-type table that tesseract renders as noise (the
`.ocr.txt` interleaves the columns), so it is **hand-transcribed from the PDF**
here. `*` in the first column is the manual's own mark for "unique to the OS/5
80-column OSBORNE 1":

| OS/5 only | ASCII | Hex | Dec | Effect |
|:--:|---|---:|---:|---|
| ✱ | `-` | 2C | 44 | sets chars to inverse |
| ✱ | `,` | 2D | 45 | sets chars to normal |
| | `(` | 28 | 40 | sets full intensity |
| | `)` | 29 | 41 | sets half intensity |
| ✱ | `*` | 2A | 42 | sets 3/4 intensity |
| ✱ | `+` | 2B | 43 | sets 1/4 intensity |
| ✱ | `.` | 2E | 46 | normal character set |
| ✱ | `/` | 2F | 47 | alternate character set |
| ✱ | `0` | 30 | 48 | select default 24-line screen with up/down 48-line scroll |
| ✱ | `1` | 31 | 49 | reserved |
| ✱ | `2` | 32 | 50 | reserved *(hand-annotated "NO scroll")* |
| ✱ | `3` | 33 | 51 | reserved *(hand-annotated "scroll 9 lines only")* |
| ✱ | `4` | 34 | 52 | reserved |
| ✱ | `5` | 35 | 53 | **display 52 characters** |
| ✱ | `8` | 38 | 56 | **display 80 characters** |
| ✱ | `C` | 43 | 67 | reserved |
| | `E` | 45 | 69 | insert a line |
| ✱ | `F` | 46 | 70 | enable 80-column auto-CR/LF |
| | `G` | 47 | 71 | end graphics |
| ✱ | `H` | 48 | 72 | disable 80-column auto-CR/LF |
| ✱ | `I` | 49 † | 73 † | invert screen |
| ✱ | `N` | 4E † | 78 † | normal screen |
| | `R` | 52 | 82 † | deletes a line |
| | `S` | 53 | 83 † | insert a character |
| | `T` | 54 | 84 † | deletes to end of line |
| ✱ | `U` | 55 | 85 † | reserved |
| ✱ | `V` | 56 | 86 † | reserved |
| ✱ | `W` | 57 | 87 † | deletes char at cursor |
| ✱ | `X` | 58 | 88 † | reserved |
| ✱ | `Y` | 59 | 89 † | sets 60 Hz operation |
| ✱ | `Z` | 5A | 90 † | sets 50 Hz operation |
| ✱ | `?` | — | — | reserved *(unreadable in the original)* |
| | `g` | 67 | 103 † | start graphics |
| | `l` | 6C | 108 | start underline |
| | `m` | 6D | 109 | stop underline |

Two things about the source table are worth recording rather than smoothing over:

- **† the `Dec` column is damaged.** From `R` (52H) to `Z` (5A) the original
  prints `8-` — the page edge cuts the column — and it prints `183` for `g` where
  67H is 103. The values marked † are the correct decimal for the hex shown, not
  a reading of the original.
- **One row disagrees with itself.** The ASCII column prints `I` (invert screen)
  and `N` (normal screen); the Hex and Dec columns print `61H`/`97` and
  `62H`/`98`, which are `a` and `b`. Every other row's three columns agree, and
  the table is otherwise in ascending hex order — `49H`/`4EH` would sit exactly
  where `61H`/`62H` are printed, so the *hex* is the likelier typo. That is
  inference from the ordering, not a reading, and **which byte the board decodes
  is not settled by this manual**; treat `ESC I` / `ESC N` as the intent and
  verify against the board.

Note what the `*` marks mean: `(`, `)`, `E`, `G`, `R`, `S` and `T` are *not*
board-unique — they are codes a standard system already reacts to. The manual's
closing warning about them is the detection story, and it is covered in "How
software finds the board" below.

### The whole Osmosis product line, from their own advertising

*The Portable Companion* #11 (October 1983), PDF p. 32 = printed p. 30, is a
full-page OSMOSIS advertisement — "The Next Step Forward" — and it gives the
boards **product numbers**, which the manual we hold does not:

| Product | What it is | Price |
|---|---|---|
| **OSMOS 1** | Double Density, "184k per drive using existing drives", "fully compatible with all Osborne software" — "Install it yourself and save $165 on Osborne's charge" | $195 |
| **OSMOS 1.5** | single-sided double density now on existing drives, upgradable to 370k per drive later with new drives | $335 |
| **OSMOS 2** | double-sided double density, 370k per drive | $895 |
| **OSMOS 3** | double-sided double density **double tracking**, 750k per drive, "an incredible 1.5MB of portability" | $1050 |
| **OSMOS 4** | disk formatting and conversion — "read, write and format **over 20 other manufactures CP/M formats**" | $225 |
| **OSMOS 5** | **the internal 80-column board** — this section's subject | $250 |
| **OSMOS 6** | telex: prepare telexes in WordStar, timed send, "automatic transmission/reception in background while running any standard CP/M software", log and queue | $1195 |
| **OSMOS 7** | Winchester disks, 5¼ / 10½ / 15¾ / 21 MByte units, "a 42 Megabyte max capacity" | $2475–$3650 |
| **OSMOS 8** | instrumentation — analog/digital, digital/analog, digital/digital cards | — |
| **OSMOS 10** | Olivetti ET121 to Osborne RS-232 KSR interface, 2K print buffer | $500 |

with a bundle — "**OSMOS 1, 4 AND 5 ALL FOR $385**" against $670 separately,
"offer extended by popular demand until December 31, 1983" — and a house claim
that matters for the interposer work:

> All OSMOSIS upgrades are **plug-in. There is no soldering or cutting.** Our
> products are supplied as kits for existing units and require no modifications to
> the Osborne computer. No specialized knowledge is required.

That is the design philosophy this project's interposer adopts, and the opposite
of the SCREEN-PAC's soldered fly-leads (`2F00040` §6.12). Vendor address for the
record: 430 Pacific Avenue, San Francisco, CA 94133, (415) 864-6372.

**The 80-column board carries a hard-disk interface.** The OSMOS 5 entry reads in
full:

> An INTERNAL 80 column board with lots of additional features and NO alteration
> required to existing software:
> - Full width screen > 80 columns on internal and external video
> - Normal/Inverted video · Underline · ⅔ and ½ intensity
> - Additional graphics characters for screen form design
> - **Includes a Hard Disk interface for future plug-in expansion**
> - At a very low price of only $250

So the video board was also the doorway to a hard disk — "**future** plug-in
expansion", i.e. the interface ships before OSMOS 7 (the Winchester product) is
something you can buy. The board this project treats as a bus-interposer
template is therefore a **storage** interposer too, not only a wider screen, and
that is a second reason to read its manual closely for #11/#12.

Note the attribute list as well: **normal/inverted video, underline, and ⅔ / ½
intensity**. The stock machine exposes underline and dim as attribute bits
([`docs/o1-memory-io-map.md`](https://github.com/Myrcurial/o1next/blob/main/docs/o1-memory-io-map.md) §2a/§3); Osmosis advertises two intensity steps. The
mapping between the two is not established — relevant to #24.

## What this means for this project

1. **A video personality (#24) needs four interfaces, not one.** The
   SCREEN-PAC's `E1A5H`/`2400H`, Nuevo's patched CBIOS, Osmosis's escape
   sequences and the TRA's **IEEE-port driver plus disk configuration** are four
   different contracts. Emulating the window is not enough; the *selection*
   mechanism — and, for the TRA, the *connector* — differs per board.
2. **Osmosis is prior art for the interposer, not just for video** (#11/#12): a
   board that takes the Z80's socket and drives the bus is the shape being
   designed here.
3. **The application-patch problem is universal.** WordStar and SuperCalc needed
   settings on the SCREEN-PAC; dBASE needed a three-byte patch on *both* Nuevo
   and Osmosis. Any 80-column story for this project has to answer for software
   that assumes 52 columns — the practical reason the O1's upgrades shipped with
   application notes.
4. **The 128-character row is the common ground.** All three widen the *window*,
   not the memory ([`docs/o1-memory-io-map.md`](https://github.com/Myrcurial/o1next/blob/main/docs/o1-memory-io-map.md) §2a); only the control interface
   differs.

## How software finds the board

The three implementations answer "is the board there?" in three different ways,
and only one of them is a register.

| Board | How software detects it | Status |
|---|---|---|
| **OCC SCREEN-PAC** | read `2400H` in bank 2: **bit 2 LOW** = board fitted | documented (user guide p. 13, [`docs/o1-memory-io-map.md`](https://github.com/Myrcurial/o1next/blob/main/docs/o1-memory-io-map.md) §2a) |
| **Osmosis** | **no detection register** — the interface is commands, so a program probes by *sending* an OS/5-unique escape and watching the screen | the manual's own warning *is* the answer; its paid Technical Manual is where "the CP/M interface" is documented |
| **Nuevo** | BIOS 1.5 **reads a port the Osborne 1 does not decode**; if it is not zero (i.e. no board), the 80-column configuration is skipped | read out of the two CBIOS images (#173); the one step needing a board is named below |

### Osmosis: the probe *is* the interface

The closing note to Appendix E is the answer, stated as a warning:

> Commands which are unique to the **OS/5 80-column OSBORNE 1** are annotated
> with an `*` symbol. Use of these commands on standard systems may cause
> spurious data to be displayed on the screen; **the program should not be
> otherwise affected.**

That is the contract. There is no flag to read; a program that wants to know
whether the board is there sends a `*`-marked code and looks at the screen — and
the manual is telling the programmer that doing so on a stock machine is *safe but
visible*, which is a design decision rather than an omission. It is the opposite
of the SCREEN-PAC's passive status bit, and it means a video personality (#24)
has to model **command effect**, not a register, to be Osmosis-compatible.

### Nuevo: the check is a read of an undecoded port (#173)

The DD manual says BIOS 1.5 does the check (quoted in
[`docs/dd-upgrade-formats.md`](https://github.com/Myrcurial/o1next/blob/main/docs/dd-upgrade-formats.md)), and we hold CBIOS 1.5 in two forms: the DDT objects
the installer inserts (`BIOS15.OBJ`, `BIOS15BM.OBJ`) and the relocated system the
disk actually boots — the system tracks of `OS1NUEVO.IMD`. The latter confirms the
manual's item 1: its sign-on reads

```
Osborne 1 Computer
CP/M vers 2.2
CBIOS vers 1.5
```

against the factory disk's `Osborne Computer System` / **`59k`** `CP/M vers 2.2`.
The `59k` is gone, exactly as the 1.4→1.5 list says.

**The check is the first thing the cold boot does that 1.4 does not.** Both CBIOSes
open identically — stack, one `CALL`, five variable loads — and then part:

| | 1.4 (`O1CPM.IMD`) | 1.5 (`OS1NUEVO.IMD`) |
|---|---|---|
| cold boot | `E4ED`–`E513`, **38 bytes** | `E469`–`E4BE`, **85 bytes** |
| after the five variable loads | `XOR A` / `LD (0004H),A` / `INC A` | **47 new bytes**, then those same three |

and those 47 bytes open with a guard:

```
E488  IN   A,(04H)      ; read port 04H
E48A  AND  1FH
E48C  JR   NZ,E4B7H     ; not present -> skip the configuration
```

**Port `04H` is not a device on the Osborne 1.** Its I/O decode uses only `A0`/`A1`
([`docs/o1-memory-io-map.md`](https://github.com/Myrcurial/o1next/blob/main/docs/o1-memory-io-map.md) §4), so a *write* to `04H` is an alias of the bank-2
latch — but a **read** of it is answered by nothing on the machine, and a floating
TTL bus reads back non-zero. On a stock machine the guard therefore takes the
skip; with the board fitted, the board has only to pull those five bits low. That
is the manual's behaviour exactly: *"If not present, the configuration routine for
the 80 Column Upgrade will be skipped."*

What the guard protects is a **video** configuration, and that is the rest of the
evidence:

- it reads the config byte at BIOS variable **`E1A6H`** — the address immediately
  above `E1A5H`, the width variable the SCREEN-PAC user guide documents
  ([`docs/o1-memory-io-map.md`](https://github.com/Myrcurial/o1next/blob/main/docs/o1-memory-io-map.md) §2a), so Nuevo kept OCC's variable layout rather
  than inventing one;
- it then drives the **BIT 9 latch** with `OUT (06H),A` — `06H` aliases `02H`, the
  latch that maps bank 3, the video/dim bank, into `F000–FFFF`
  ([`docs/o1-memory-io-map.md`](https://github.com/Myrcurial/o1next/blob/main/docs/o1-memory-io-map.md) §4). **The factory BIOS never touches that latch**:
  its only bank selects are ports `00H` and `01H`.

The consistency check that lifts this above a guess: BIOS 1.5 ships on **both** the
DD-only disk and the 80-column disk — the installer inserts the *same*
`BIOS15.OBJ` either way — and it is precisely a *shared* BIOS that needs the
check, because the DD customer has no video board for the configuration routine to
talk to. That is the manual's stated reason, verbatim.

**The one step that needs a board:** that `IN A,(04H)` reads zero with the card
fitted. Everything above is read out of the two images. If that read is *not* zero
with the card fitted, the guard is something else and this subsection is wrong —
so it is recorded as the evidence supports it, not as established fact.

## Open

- **Nuevo's presence check** — the mechanism is read out of the images (#173); the
  remaining step is one measurement, `IN A,(04H)` with the board fitted.
- Osmosis's *technical* manual ("theory of operation; documentation on the CP/M
  interface; cursor addressing") is a paid document the archive does not hold. If
  a detection register exists, that is where it is — but the user manual's own
  warning suggests there is not one.
- The DD halves of both vendors are **covered**, in [`docs/dd-upgrade-formats.md`](https://github.com/Myrcurial/o1next/blob/main/docs/dd-upgrade-formats.md):
  Nuevo's boot-time auto-configuration via `NEWSETUP.COM` and its 2 x 2 / 4 x 4
  formats, and Osmosis's OSMOS 1–3 density line plus the standalone OSMOS 4
  conversion product.



## Sources

- [`research/screenpac/o1screenpacusersguide.pdf`](https://github.com/Myrcurial/o1next/blob/main/research/screenpac/o1screenpacusersguide.pdf) — SCREEN-PAC User Guide, p. 13.
- [`research/nuevo/OS1NUEVO.IMD`](https://github.com/Myrcurial/o1next/blob/main/research/nuevo/OS1NUEVO.IMD) and `Nuevo_Electronics_DD_Upgrade_Manual.pdf`.
  Scripts extracted with `cpmcp -f osborne1`; cpmtools ships an `osborne1`
  diskdef matching the image exactly (`seclen 1024, sectrk 5, blocksize 1024,
  maxdir 64, boottrk 3`).
- `AUTOST.COM` / `AUTOST.BAK` on the same image — the 80-column feature list
  (extracted with `cpmcp -T raw -f osborne1`; the identical text is visible with
  `strings`).
- [`research/osmosis/Osmosis_80_Column_Board.pdf`](https://github.com/Myrcurial/o1next/blob/main/research/osmosis/Osmosis_80_Column_Board.pdf) (+ `.ocr.txt`), §3, §4 and
  **Appendix E** (the escape sequences — hand-transcribed from the PDF, not the
  OCR).
- [`research/shipped-software/O1CPM.IMD`](https://github.com/Myrcurial/o1next/blob/main/research/shipped-software/O1CPM.IMD) — the factory DD boot disk used as the
  CBIOS 1.4 diff partner; its system tracks are the first three tracks
  (`boottrk 3`), converted with `disk-analyse`.
- `BIOS15.OBJ` / `BIOS15BM.OBJ` on `OS1NUEVO.IMD` — the installer's DDT objects,
  disassembled with `z80dasm -g 0x1F00` / `-g 0x29E0`.
- [`research/technical-articles/TPC-Issue05-1983-pp98-tra-80-100-column-video-and-winchester-ads.pdf`](https://github.com/Myrcurial/o1next/blob/main/research/technical-articles/TPC-Issue05-1983-pp98-tra-80-100-column-video-and-winchester-ads.pdf)
  — the TRA "80 and 100 column video" advertisement (video), and the Helix
  Winchester advertisement on the same page.
- [`docs/o1-rom-variants.md`](https://github.com/Myrcurial/o1next/blob/main/docs/o1-rom-variants.md) — ROM inventory, char-gen variants, Nuevo 1.51.
- [`docs/o1-memory-io-map.md`](https://github.com/Myrcurial/o1next/blob/main/docs/o1-memory-io-map.md) §2a — the window, the widths, the bit fields.
- [`docs/dd-upgrade-formats.md`](https://github.com/Myrcurial/o1next/blob/main/docs/dd-upgrade-formats.md) — the DD halves of both vendors, and the Nuevo
  BIOS 1.4→1.5 list.
