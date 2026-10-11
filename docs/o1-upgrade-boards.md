# Third-party upgrade boards — Nuevo and Osmosis (#73)

Nuevo Electronics and Osmosis each shipped **two** Osborne 1 upgrades — a
double-density board and an 80-column video board — and **neither follows the
pattern OCC used for the same two functions**. That matters twice over: it is
prior art for this project's interposer, and it means a video personality (#24)
cannot assume the ScreenPac's interface.

This doc covers the **video** side. The DD side is in
`docs/dd-upgrade-formats.md` and `docs/research-gaps.md` gap #11.

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
does not say; it is not a claim that the feature is absent.

## OCC SCREEN-PAC — hardware only, driven by the stock BIOS

The one that needs no ROM: `docs/o1-memory-io-map.md` §2a has the full
statement. The parts that make it the odd one out are that the **stock BIOS
already contains the width-switching routine** (`E1A5H` / `E4E5H`), that the
board announces itself at **`2400H` in bank 2**, and that the SCREEN-PAC's own
2 KiB ROM is *the same image as the stock late character generator*
(`docs/o1-rom-variants.md`) — so the capability genuinely is not in a ROM.

## Nuevo — a new monitor ROM, and a CBIOS patched on disk

Nuevo's video upgrade is **software**, and the archive holds the installer. The
system disk `research/nuevo/OS1NUEVO.IMD` (Osborne DD: 40 tracks × 5 × 1024 B,
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
patches (`docs/o1-rom-variants.md`), and the Nuevo char-gen differs from stock —
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
  reaches on the stock board (`docs/o1-memory-io-map.md` §2a), and an *option*
  rather than a cut track. It is the other end of #21's range.

The disk products from the same advertisement are in `docs/dd-upgrade-formats.md`.

## Osmosis — a Z80 interposer with an escape-sequence interface

Osmosis's 80-column board is the one that matters most to this project, because
of *how it attaches*. From `research/osmosis/Osmosis_80_Column_Board.pdf` §3:

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

## What this means for this project

1. **A video personality (#24) needs three interfaces, not one.** The
   SCREEN-PAC's `E1A5H`/`2400H`, Nuevo's patched CBIOS, and Osmosis's escape
   sequences are three different contracts. Emulating the window is not enough;
   the *selection* mechanism differs per board.
2. **Osmosis is prior art for the interposer, not just for video** (#11/#12): a
   board that takes the Z80's socket and drives the bus is the shape being
   designed here.
3. **The application-patch problem is universal.** WordStar and SuperCalc needed
   settings on the SCREEN-PAC; dBASE needed a three-byte patch on *both* Nuevo
   and Osmosis. Any 80-column story for this project has to answer for software
   that assumes 52 columns — the practical reason the O1's upgrades shipped with
   application notes.
4. **The 128-character row is the common ground.** All three widen the *window*,
   not the memory (`docs/o1-memory-io-map.md` §2a); only the control interface
   differs.

## Open

- Nuevo's and Osmosis's **presence detection** is unknown — only the SCREEN-PAC's
  `2400H` bit is documented. Worth checking the Osmosis appendix and
  `NEWSETUP.COM` / `AUTOST.COM` on the Nuevo disk.
- Osmosis's full escape-sequence set is in its appendix and should be extracted
  into this doc.
- The DD halves of both vendors' products are not covered here.

## Sources

- `research/screenpac/o1screenpacusersguide.pdf` — SCREEN-PAC User Guide, p. 13.
- `research/nuevo/OS1NUEVO.IMD` and `Nuevo_Electronics_DD_Upgrade_Manual.pdf`.
  Scripts extracted with `cpmcp -f osborne1`; cpmtools ships an `osborne1`
  diskdef matching the image exactly (`seclen 1024, sectrk 5, blocksize 1024,
  maxdir 64, boottrk 3`).
- `research/osmosis/Osmosis_80_Column_Board.pdf` (+ `.ocr.txt`), §3 and §4.
- `docs/o1-rom-variants.md` — ROM inventory, char-gen variants, Nuevo 1.51.
- `docs/o1-memory-io-map.md` §2a — the window, the widths, the bit fields.

