---
layout: page
title: "80-column boards: SCREEN-PAC to TRA"
subtitle: "Peripherals and storage &middot; partially solved"
draft: "Draft &mdash; assembled from the working notes by `tools/build_book.py`. The source document is the authority; this page is a copy for reading, and it is regenerated from that source."
---

Nuevo Electronics and Osmosis each shipped **two** Osborne 1 upgrades — a
double-density board and an 80-column video board — and **neither follows the
pattern OCC used for the same two functions**. That matters twice over: it is
prior art for this project's interposer, and it means a video personality (#24)
cannot assume the ScreenPac's interface.

This doc covers the **video** side. The DD side is in
[`docs/dd-upgrade-formats.md`](https://github.com/Myrcurial/o1nextgen/blob/main/docs/dd-upgrade-formats.md) and [`docs/research-gaps.md`](https://github.com/Myrcurial/o1nextgen/blob/main/docs/research-gaps.md) gap #11.

> **Scope note: "Executive" means a different machine.** In Osborne's world the
> Osborne **Executive** is the O2-class machine, not a variant of the 1. Upgrades,
> software and advertisements aimed at it are therefore **out of scope here** and
> must not be folded into Osborne 1 conclusions — for example the $595
> double-sided-drive upgrade advertised in *The Portable Companion* #14, PDF p. 47,
> which is an Executive product. The three machines this project cares about are
> the Osborne 1, the Osborne 1 with OCC's own upgrades, and clones of them
> ([`docs/research-gaps.md`](https://github.com/Myrcurial/o1nextgen/blob/main/docs/research-gaps.md) gap 12).

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

The one that needs no ROM: [`docs/o1-memory-io-map.md`](https://github.com/Myrcurial/o1nextgen/blob/main/docs/o1-memory-io-map.md) §2a has the full
statement. The parts that make it the odd one out are that the **stock BIOS
already contains the width-switching routine** (`E1A5H` / `E4E5H`), that the
board announces itself at **`2400H` in bank 2**, and that the SCREEN-PAC's own
2 KiB ROM is *the same image as the stock late character generator*
([`docs/o1-rom-variants.md`](https://github.com/Myrcurial/o1nextgen/blob/main/docs/o1-rom-variants.md)) — so the capability genuinely is not in a ROM.

## The Research Associates (TRA) — 80/100 columns, over the IEEE port

A **fourth** 80-column answer, and the only one that reaches the screen through a
*different connector*. An advertisement in *The Portable Companion* #5
(February/March 1983, PDF p. 98 = printed 84; extract
[`research/technical-articles/TPC-Issue05-1983-pp98-tra-80-100-column-video-and-winchester-ads.pdf`](https://github.com/Myrcurial/o1nextgen/blob/main/research/technical-articles/TPC-Issue05-1983-pp98-tra-80-100-column-video-and-winchester-ads.pdf))
announces "**80 and 100 column video**" from **The Research Associates** (Forest
Hill, Dunstable, Massachusetts) as "an add-on to the Osborne 1", providing:

- an **80×24 window** and a **100×24 window** "into a 128 character by 32 line
  video format" — the same 128-wide buffer this project already models
  ([`docs/o1-memory-io-map.md`](https://github.com/Myrcurial/o1nextgen/blob/main/docs/o1-memory-io-map.md) §2a), so TRA widens the *window* exactly as the
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
pattern as the Drive C panel ([`docs/drive-c-protocol.md`](https://github.com/Myrcurial/o1nextgen/blob/main/docs/drive-c-protocol.md)): the add-on
*re-presents* an existing connector. Neither its width-switching mechanism (no
ROM or BIOS patch is mentioned — a driver plus a disk configuration step) nor its
presence detection is documented in the ad, and **unlike SCREEN-PAC and Nuevo it
is not in the archive**: the ad is all we hold.

## Nuevo — a new monitor ROM, and a CBIOS patched on disk

Nuevo's video upgrade is **software**, and the archive holds the installer. The
system disk [`research/nuevo/OS1NUEVO.IMD`](https://github.com/Myrcurial/o1nextgen/blob/main/research/nuevo/OS1NUEVO.IMD) (Osborne DD: 40 tracks × 5 × 1024 B,
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
patches ([`docs/o1-rom-variants.md`](https://github.com/Myrcurial/o1nextgen/blob/main/docs/o1-rom-variants.md)), and the Nuevo char-gen differs from stock —
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
  reaches on the stock board ([`docs/o1-memory-io-map.md`](https://github.com/Myrcurial/o1nextgen/blob/main/docs/o1-memory-io-map.md) §2a), and an *option*
  rather than a cut track. It is the other end of #21's range.

The disk products from the same advertisement are in [`docs/dd-upgrade-formats.md`](https://github.com/Myrcurial/o1nextgen/blob/main/docs/dd-upgrade-formats.md).

## Osmosis — a Z80 interposer with an escape-sequence interface

Osmosis's 80-column board is the one that matters most to this project, because
of *how it attaches*. From [`research/osmosis/Osmosis_80_Column_Board.pdf`](https://github.com/Myrcurial/o1nextgen/blob/main/research/osmosis/Osmosis_80_Column_Board.pdf) §3:

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
([`docs/o1-memory-io-map.md`](https://github.com/Myrcurial/o1nextgen/blob/main/docs/o1-memory-io-map.md) §2a/§3); Osmosis advertises two intensity steps. The
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
   not the memory ([`docs/o1-memory-io-map.md`](https://github.com/Myrcurial/o1nextgen/blob/main/docs/o1-memory-io-map.md) §2a); only the control interface
   differs.

## Open

- Nuevo's and Osmosis's **presence detection** is unknown — only the SCREEN-PAC's
  `2400H` bit is documented. Worth checking the Osmosis appendix and
  `NEWSETUP.COM` / `AUTOST.COM` on the Nuevo disk.
- Osmosis's full escape-sequence set is in its appendix and should be extracted
  into this doc.
- The DD halves of both vendors' products are not covered here.

## Sources

- [`research/screenpac/o1screenpacusersguide.pdf`](https://github.com/Myrcurial/o1nextgen/blob/main/research/screenpac/o1screenpacusersguide.pdf) — SCREEN-PAC User Guide, p. 13.
- [`research/nuevo/OS1NUEVO.IMD`](https://github.com/Myrcurial/o1nextgen/blob/main/research/nuevo/OS1NUEVO.IMD) and `Nuevo_Electronics_DD_Upgrade_Manual.pdf`.
  Scripts extracted with `cpmcp -f osborne1`; cpmtools ships an `osborne1`
  diskdef matching the image exactly (`seclen 1024, sectrk 5, blocksize 1024,
  maxdir 64, boottrk 3`).
- [`research/osmosis/Osmosis_80_Column_Board.pdf`](https://github.com/Myrcurial/o1nextgen/blob/main/research/osmosis/Osmosis_80_Column_Board.pdf) (+ `.ocr.txt`), §3 and §4.
- [`research/technical-articles/TPC-Issue05-1983-pp98-tra-80-100-column-video-and-winchester-ads.pdf`](https://github.com/Myrcurial/o1nextgen/blob/main/research/technical-articles/TPC-Issue05-1983-pp98-tra-80-100-column-video-and-winchester-ads.pdf)
  — the TRA "80 and 100 column video" advertisement (video), and the Helix
  Winchester advertisement on the same page.
- [`docs/o1-rom-variants.md`](https://github.com/Myrcurial/o1nextgen/blob/main/docs/o1-rom-variants.md) — ROM inventory, char-gen variants, Nuevo 1.51.
- [`docs/o1-memory-io-map.md`](https://github.com/Myrcurial/o1nextgen/blob/main/docs/o1-memory-io-map.md) §2a — the window, the widths, the bit fields.
