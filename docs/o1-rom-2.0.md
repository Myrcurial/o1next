# ROM 2.0 — CP/M resident in the ROM, and how it boots (#83)

**Status:** design, first pass. The **arithmetic** (§2) and the **interface** (§3)
are *measured* — from the shipped 1.44 bytes and from a shipped system disk's
reserved tracks, with the tool in `tools/research/romvec.py` reproducing the
interface half. The **bank map, boot path and jump table** (§4–§5) are the
*design*: what we intend to build, with the reasoning that got us there. The
**contents of the boot are measured, not estimated — 7681 bytes (§2.3)** — and the
**feature set is decided against OZROM's, including what to refuse (§4.8)**. The
**hardware half of §4 is explicitly open** — there is no ROM 2.00 part (§4.1), and
the window's address, paging and selector belong to #12's interface spec (§4.1a).
What is not done is stated in §8.

**Issues:** #83 (deliverable 1; deliverable 2's toolchain proof landed as #203/#204),
#49 (the reproduction this ROM is for), #72 (the ROM source), #179 (the MD-10 boot
that wants the same ROM window), #24 (the column mode), #81 (OZROM, the pattern).

## 1. What ROM 2.0 is, and what it is not

The goal from #83 is unchanged: **an O1 ROM that boots to a working `A>` with no
disk access at all** — real or virtual. It is a *replacement part*, not a patch:
optional, socket-reversible, legitimate on the replica and (with the interposer's
ROM daughterboard, below) on a real O1.

**One ROM, two hosts (recorded 2026-10-13).** The two routes this issue used to
carry — "a bigger ROM of our own" and "the interposer serves the system image in a
memory window" — have **collapsed into one design**. The interposer now carries a
lead-set to the **main ROM socket (UD11)** as well as the character-generator
socket (UA15), so the ROM window is the interposer's to fill on any OEM-faithful
mainboard, and the SFF board grafts the same capability in. **There is one ROM
2.00** — one image, one layout — and it runs on either.

That also settles a documentation question that would otherwise duplicate this
whole document: **OEM board + interposer ≡ LFF board + interposer**, because the
LFF board is a faithful recreation of *just* the OEM board with the Dual Density
upgrade built in (`hardware/o1next/o1next-lff/README.md`). There is no separate "LFF
path" to design for — one interposer brief covers both, and "the stock machine" in
this document means the mainboard-plus-interposer combination.

**OZROM 1E is the pattern, not the feature set.** Per the direction recorded on
#83, and the measured shortcomings in `docs/ozrom-1e.md`:

| Borrow — structural | Why | Explicitly not wanted |
|---|---|---|
| A *documented* ROM jump table and memory map | OZROM's manual is why third-party code can target it; the stock ROM already has a table (§3), it is just undocumented | OZROM's keyboard redefinition, which takes `FC00–FFFF` of video space. #24's VRAM shadow assumes `F000–FFFF` and OZROM's move constrains every later decision |
| A software 52/80/104-column switch | The mechanism already exists in the stock CBIOS (§4.7, `SCRMOD`) and it is on #24's design path | — |
| A chip-level memory tester | The O1 has no built-in RAM test; it is cheap and it is what a new ROM is for | — |

## 2. The arithmetic, measured

The four pieces, all read from primary sources or the shipped bytes:

| Piece | Size | Where it lives | How we know |
|---|---|---|---|
| Monitor ROM | **4096** | `0000–0FFF`, bank 2 | The part: 2732 at UD11. Its own source asserts its code ends below `0FFBh` |
| CCP | **2048** | `CB00–D2FF` | `occbio15.asm` pins `CCP = 0CB00h`, `BDOS = ccp+806h` → the CCP is `0x800` |
| BDOS | **3584** | `D300–E0FF` | `BIOS = ccp+1600h` and the CCP/BDOS boundary at `ccp+806h` → `1600h − 800h = 0E00h` |
| CBIOS | **2048** | `E100–E8FF` | `BIOS = ccp+1600h`, `MSIZE = 59` → the BIOS region is `E100–EBFF`; its own guard stops code at `CCP+1E00h = E900h` |
| **Total resident** | **11776** | | **11.5 KB** |

**This is the *no-disk-anywhere* list** — CP/M resident with no disk of any kind,
real or virtual. It is **not** the list for the boot this project is building, which
is shorter because the ACB-4000 supplies the CCP and BDOS: see §2.3 for that list
and its single total.

**The ROM's own boot code states the total, and it agrees.** `rom144.asm`'s
`CBOOT` and `WBOOT` load the system in 128-byte blocks, and the counts are the
arithmetic:

| Routine | Constant | Bytes | Equals |
|---|---|---|---|
| `CBOOT` (cold boot) | `LDK B,60  ;CCP/BDOS/CBIOS` | 7680 | 2048 + 3584 + 2048 |
| `WBOOT` (warm boot) | `LDK B,44  ;CCP/BDOS and don't read CBIOS` | 5632 | 2048 + 3584 |

That is the strongest evidence available for the 11776-byte figure: the shipped
firmware says it reads 7680 bytes of "CCP/BDOS/CBIOS", and 4096 + 7680 = 11776.

### 2.1 The numbers are measured on a shipped disk too

`research/shipped-software/OS1SYSD.IMD` (DD, 1024-byte sectors, 5/track, 3
reserved tracks) carries the system image from the **CCP** upward, and every
piece lands exactly where the source's equates say:

| Image offset | Address | Content | Size |
|---|---|---|---|
| `0000` | `CB00` | CCP | 2048 |
| `0800` | `D300` | BDOS — entry at `D306` holds `JP 0D311h` | 3584 |
| `1600` | `E100` | CBIOS — its 34-entry jump table, byte for byte | 2048 |
| `1E00` | `E900` | `CCP+1E00h`: the CBIOS's own *RAM* area begins here | — |
| `2000` | `EA00` | end of what SYSGEN wrote (8 sectors, rounded up) | — |

Four independent anchors, none of them assumed:

1. **The CBIOS's jump table** is at image offset `1600`, and `occbio15.asm` puts
   it at `BIOS = CCP+1600h`. Its 13 `CALL ROMCDE` entries are 13 consecutive
   `CD 12 E3` at `E139h`–`E15Ah` — one routine, called thirteen times, exactly as
   the source's table is written.
2. **That routine's address is confirmed by module order.** `occbio35.asm` places
   `ROMRI`, then `ROMCDE`, `ROMCD1` and `ROMJMP`; the image has `ROMRI` at `E2FEh`
   (20 bytes of `POP`/`EI`/`RET`), `ROMCDE` at `E312h`, `ROMCD1` at `E317h`
   (`16 01` = `LD D,01h` = `high(ROMVEC)`) and `ROMJMP` at `E319h`.
3. **The ROM locates the CCP itself, at every boot, from the same bytes.** `CBOOT`
   reads sector one to `0D000h` and checks three bytes of it: `[0D000h] == 0C3h`,
   `[0D001h] == 05Ch`, and then `[0D002h] − 3` is the CCP's page. On the disk
   those bytes are `C3 5C CE` — and `0CEh − 3 = 0CBh`, so the CCP is at `CB00h`.
   The first three bytes of the CCP are therefore a *marker* as well as code
   (`JP 0CE5Ch`), which is why `0x5C` is checked.
4. **The `ROMCDE` arithmetic requires it.** It forces the high byte of the vector
   to `high(ROMVEC)` = `01h` and leaves the low byte as the CBIOS's own address
   low byte, so `BIOS & 0FFh` must be `00h` — `E100h` does, `E000h` would not.

**A caution, because it nearly fooled this pass.** The 512 bytes at image offset
`1E00–1FFF` are *not* CBIOS code. They are the contents of RAM at `E900h` when
the disk was made — DDT's leftovers, written out because SYSGEN writes whole
sectors. On this disk they happen to be a readable Osborne sales text ("…
Accessories planned for the Osborne 1: 12" display monitor … battery pack for
portable operation …"). Anyone who reads the system image as "the CBIOS" will
count 2560 bytes and be wrong by 512. The 2048 figure is the source's own guard:
`IF XXX > CCP + 1E00H / .9 ERROR SYSTEM SIZE TOO LARGE`.

### 2.2 Why 4 KB cannot hold it, and why the ROM page is not one block

Bank 2 is the only place the CPU reads ROM (`docs/o1-memory-io-map.md` §2):

| Range | Bank 2 |
|---|---|
| `0000–0FFF` | Monitor ROM (2732 at UD11) |
| `1000–1FFF` | Unused — **mirror of the ROM**, because A12 is not decoded |
| `2000–2FFF` | Memory-mapped I/O |
| `3000–3FFF` | Unused — mirror of `2000–2FFF` |
| `4000–FFFF` | Mirrors bank 1 RAM |

So the ROM page offers **8 KB contiguous** (`0000–1FFF`) and **4 KB more at
`3000–3FFF`** — but only by jumping *past* the assigned I/O block at `2000–2FFF`,
so the two runs are not one block.

**The boot this project is building fits the contiguous 8 KB.** Interposer +
ACB-4000, to `A>`, with no floppy ever read, is **7681 bytes** (§2.3) — 511 bytes
to spare, and no paging. The 11776-byte figure in §2 is a *different* list for a
*different* goal (CP/M resident with no disk of any kind): it is the one that fits
neither run, and the one that needs §4.1a's paging. There is no 16 KB ROM in any
case, and never will be (§4.1). The stock 2732 holds 4096 of which **150 bytes are
free** (`0F6Ah–0FFFh`; the code ends at `0F69h` and the source's own guard is
`IF RLWA > 0FFBH`).

### 2.3 The contents, and the one number

This is the goal the project is actually building: an **interposer + ACB-4000**
that boots to `A>` on the hard disk with **no floppy read, ever** — virtual or
physical. It has one content list and one total.

| Piece | Bytes | Why it is there | Source |
|---|---|---|---|
| Monitor ROM | **4096** | the machine's ROM. Its boot path is replaced; its 53-vector jump table is kept | `rom144.asm` |
| CBIOS | **2048** | **the MD-10 BIOS borrows 30 of its 34 jump-table entries.** Measured: `HARD.COM` copies `18 + 21 + 3 + 3 + 45 = 90` bytes from `(page zero+1)+3` = `0xE106` — CBIOS vectors 2–31 — into the MD-10 BIOS's slots at `0xD806`, `0xD86A`, `0xD82D`, `0xD87F` and `0xD833`. Those are `JMP`s into the CBIOS, so the CBIOS's code has to be in RAM for them to land anywhere | `OS1SYSD.IMD`, image offset `0x1600` |
| MD-10 BIOS image | **1477** | the ACB-4000 driver, and the partial BIOS that reads the system off the hard disk. Copied to `0xD800` | `HARD.COM`, file offset `0x053A` (`0x5C5` bytes) |
| install / patch / jump | **60** | all of the loader's work the ROM has to do: `LD HL,053Ah` / `LD DE,0D800h` / `LD BC,(0547h)` / `LDIR`, the five patching `LDIR`s, `XOR A` / `LD (0013h),A`, `JP 0D800h` | `HARD.COM`, `0x01E5`–`0x0220` |
| **Total** | **7681** | | |

**7681 bytes — and it fits the 8 KB contiguous window with 511 bytes to spare.** No
paging is needed for this boot at all.

**What is deliberately *not* in the list.** The **CCP and BDOS**, 5632 bytes,
because the ACB-4000 supplies them: `HARD.COM`'s BIOS reads 11 blocks from **LBA 5**
into `0xC200` and jumps to it (`docs/md10-system.md` §3–§5). Carrying them in ROM as
well would be a second copy of bytes already on the drive, and would make the ROM
decide which one wins.

**Nor are the loader's other 1022 bytes.** `HARD.COM` is 2560 bytes — a 1082-byte
loader and a 1478-byte embedded BIOS, of which 1477 are copied. The loader's banner,
its presence probe and its `TEST UNIT READY` are diagnostics for a human installing
a card; the MD-10 BIOS's own `BOOT` selects the card and reads. The shim does not
need them.

**One number, and it is this one.** Earlier notes carried "11.2 KB" and "11776
bytes" for overlapping things, and the difference was never the arithmetic — it was
the *list*. 11.2 KB was monitor + MD-10 + CCP/BDOS with **no CBIOS**; 11776 is
monitor + CCP + BDOS + CBIOS with **no MD-10**. Neither is the boot described here.
The boot described here is **7681**, and any figure quoted for it has to name the
list it came from.
**The boot screen does not come out of the 511-byte spare, and does not need to.**
`research/boot-screen/` holds the authored art and `tools/research/rom2strokes.py`
measures it: every raster-shaped encoding of the logo lands at **784–857 B** — raw
striped bitmap 857, RLE 816, an exact rectangle cover 784 — because the letters are
heavy and the cover is dominated by diagonals (the X is 72 rectangles where it is
structurally two strokes). The geometric route was not converged, so it is
estimated rather than demonstrated.

What settles it is the architecture: **one window page is 4096 bytes and the video
buffer is 128 × 32 = 4096 cells**, so **one page is exactly one screen**. In bank 2
the window and the video RAM are both visible (§4.4), so a frame is one `LDIR` from
`1000h` to `F000h` — about 40 bytes of ROM, with the frames in the interposer's
flash, and the animation is the viewport slide, which is a register write. The one
casualty is that the art is 153 columns and a screen is 128, so the 26 columns of
hatch to the left of the O are dropped in favour of keeping the logo whole.



## 3. The interface that already exists

ROM 2.0 does not have to invent its jump table. The stock ROM **already
publishes one**, at `0x0100`, and the CBIOS already calls it — Osborne simply
never documented it outside the source.

**Measured:** 53 entries, `0100h`–`019Eh`, 3 bytes each. The table ends exactly
where the source's `IMSG:` sign-on message begins (`019Fh`), which is what makes
53 the whole table rather than a guess — the first byte of `IMSG` is
`'Z'-40h` = `1Ah` and `019Fh` holds `1Ah`. `tools/research/romvec.py` prints the
table, labels each entry from `rom144.asm`'s own table text, and cross-checks the
binary's opcode sequence against the source's — **0 disagreements** on the 1.44
ROM.

| # | Addr | Target | ROM source | CBIOS vector | Note |
|---|---|---|---|---|---|
| 0 | `0100` | `0255` | CBOOT | CBOOT | cold boot — **this is the one ROM 2.0 replaces** |
| 1 | `0103` | `02AB` | WBOOT | WBOOT | warm boot — **hard-coded by `occbio55.asm`** |
| 2 | `0106` | `0375` | SKEY | CONST | keyboard status |
| 3 | `0109` | `0382` | CI | CONIN | keyboard input |
| 4 | `010C` | `03EF` | COUT | CONOUT | console output |
| 5,6 | `010F`,`0112` | `0BEC` | LIST | LIST, PUNCH | both point at one routine |
| 7 | `0115` | `0BD2` | READER | READER | reader input |
| 8 | `0118` | `0C15` | RDRV | HOME | home the drive |
| 9 | `011B` | — | `RET/NOP/NOP` | SELDSK | **stub** — the CBIOS supplies SELDSK itself |
| 10–12 | `011E`–`0124` | `0D49`,`0D50`,`0DBE` | READ, WRITE, RADR | SETTRK, SETSEC, SETDMA | **labels do not line up** — see §3.2 |
| 13 | `0127` | `0C2F` | RSEC | READ | one sector read — **hard-coded by `occbio65.asm`** |
| 14,15 | `012A`,`012D` | `0C36`,`0BE3` | WSEC, SLST | WRITE, LISTST | one sector write; list status |
| 16 | `0130` | `0C7C` | SENDEN | SECTRN | **labels do not line up** — see §3.2 |
| 17,18 | `0133`,`0136` | `0099`,`009E` | ROMJP1, ROMJP2 | RRI, ROMJMP | RAM/ROM exit; the ROM call gate |
| 19 | `0139` | `0F29` | FORMAT | FMTJ | format a track |
| 20 | `013C` | `0BC5` | SIRST | SBAUD / ACICTL | SIO reset = set the baud/control register |
| 21–28 | `013F`–`0154` | `0949`…`0AAC` | IE.CO … IE.PP | IEB1C … IEB8C | the eight IEEE-488 drivers |
| 29–31 | `0157`–`015D` | `06DD`,`06F1`,`06D5` | VLDDR, VLDIR, STODIM | (extensions) | SuperCalc video helpers |
| 32–52 | `0160`–`019C` | `0F0A`…`0BB0` | 21 entries | — | disk primitives, SELDRV, and the IEEE status/input/output quartet |

### 3.1 How the CBIOS reaches it — and why the numbering is a contract

Two mechanisms, both in the source, both already load-bearing:

1. **By arithmetic, from the CBIOS's own address.** `occbio35.asm`'s `ROMCDE`
   pops the return address, subtracts 3, and forces the high byte to
   `high(ROMVEC)` = `01h`. So CBIOS vector *N*, sitting at `BIOS + 3N`, selects
   ROM vector *N*. `occbio15.asm` states the requirement in a comment: *"NOTE:
   ROM jump vector must match CBIOS vector"*. This is why `BIOS & 0FFh` must stay
   `00h`, and why the CBIOS's 13 `CALL ROMCDE` entries all land on the right
   routines without a table pointer.
2. **By absolute address, twice.** `occbio55.asm`'s warm boot does
   `LDK DE,ROMVEC+3*1`, and `occbio65.asm`'s sector transfer does
   `LDK HL,ROMVEC+3*13`. The CBIOS also calls the ROM's `SENDEN` by its absolute
   ROM address (`LDK DE,SENDEN`), which is why **the monitor must stay mapped
   while the CBIOS is running** — see §4.2.

**The consequence for ROM 2.0:** vectors 0–52 keep their numbers and their
semantics, and the monitor stays where it is. Both of the hard-coded vectors are
exactly the two the diskless build wants to change (§4.5), and both are changed
*inside the ROM*, so the CBIOS does not have to move.

### 3.2 Two things that do not line up, recorded rather than smoothed over

* **Indices 10, 11, 12 and 16 carry the ROM's own labels** (READ, WRITE, RADR,
  SENDEN) where the CBIOS's table has SETTRK, SETSEC, SETDMA, SECTRN. Nothing is
  broken: the CBIOS implements those four itself and never calls the ROM for
  them, so the ROM's slots are free to be its own API.
* **`occtxt6.ast` publishes constants for the alignment that does not exist** —
  `BSTTRK = 10*3`, `BSTSEC = 11*3`, `BSTDMA = 12*3`, `BSECTR = 16*3`, alongside
  the ones that are correct (`BCONST = 2*3`, `BREAD = 13*3`, `BIECO = 21*3` …
  `BIEPP = 28*3`). **No CBIOS source uses any `B*` constant, or `BIOCAL`, the
  macro that would.** They are dead code, and four of them have the wrong
  numbers. Recorded here because the obvious reading of that file is that they
  are the mapping.

### 3.3 What this gives the design

* A **documented interface already exists** — 53 entry points with a stable
  numbering — so ROM 2.0 extends it rather than inventing one, which is exactly
  the OZROM property worth borrowing (#81).
* The **warm-boot hook already exists**: the CBIOS's `WBOOT` calls ROM vector 1.
  A ROM-resident CP/M needs a different *source* for the system image, not a
  different *mechanism*.
* The **boot keys already exist**: `RETURN` = floppy A, `"` = floppy B, `ESC` =
  hard disk, with `HCBOOT` a documented empty stub (`JMP START`) that Osborne
  left in the ROM for exactly this purpose (`rom144.asm` line 4634; it assembles
  to `JP 0000h` at `0F67h`).
## 4. The design

### 4.1 The softROM serves the window — there is no ROM 2.00 part

**There is no physical ROM 2.00 and there never will be** — not a 27128, not a
2764, not a 16 KB part in any form (settled 2026-10-13). The ROM window is served
by the interposer's **softROM**: the interposer already has the bus, and the ROM
socket bridge gives it the window itself, so it presents the ROM in firmware.

| | |
|---|---|
| The host | **OEM board + interposer**, **LFF reproduction + interposer**, or the **SFF board**, where the interposer is built in as one unit. There is no third case and no part in the socket |
| The LFF board on its own | Keeps a socket that takes a standard 1.44 ROM, so it is a stock machine and the restoration path boots stock. That is the *stock* part — not ROM 2.00 |
| Window | the monitor stays at `0000–0FFF`; the rest of the ROM page is not one contiguous block (§2.2), and **where the payload goes is open** |
| Banks | the intended *content* split is 4 × 4 KB (system image 2, MD-10 BIOS 1, diagnostics + spare 1). The content plan stands; **what selects a bank, and where it is presented, is open** |

**What is deliberately not decided here.** The window's address, how the payload is
paged, and what the selector is are **pseudo-hardware**, and this document does not
settle them — they are **#12's interface spec**. An earlier draft of this section
proposed a 27128 with `A12`/`A13` supplied from a latch at `2300h`; that route is
**withdrawn** (there is no physical part to put in the socket, and no host without
an interposer to design it for). The withdrawal is recorded rather than quietly
deleted, because it was in a merged revision of this document.

### 4.1a The socket's limit, and why it does not bind

The limit is real, and worth stating because it is what *would* bind if we were
fitting a part: **a 24-pin 2732 socket has `A0–A11`, `/CE`, `/OE` and the data bus
— no `A12`, no `A13`, and no write strobe.** A part in that socket could never
exceed 4 KB however large it was.

It does not bind, because **we are not fitting a part.** The softROM is not in the
socket's address space the way a part is: the Pico already sees every bus cycle and
presents the ROM window itself, so the lines past `A11` are irrelevant — which is
also why ROM 2.00 needs **no programmer** and is updatable in flash. With the part
removed nothing else drives those data lines either, which is what makes this
cheaper than the per-cycle bus race #83's earlier analysis worried about.

**The socket bridge is not speculative as a technique.**
`docs/o1-rom-variants.md` records **BrettHallen's 2732→2764 daughterboard image**
(8 KiB, CRC32 `edc31846`): OCC 1.44 and OZROM 1E in one 2764, **with `A12`
selecting between them** — banking in the ROM socket, built and tested, passively.
That is prior art for the mechanical form, and it is why the bridge is a known-good
shape. It is **not** the route ROM 2.00 takes.

**Withdrawn (2026-10-13): the larger-part route.** An earlier revision of this
section offered three ways past the socket limit, of which case 2 was *"a 27128 in
the socket, with `A12`/`A13` and the latch strobe coming from outside it … the path
for a board with no interposer"*, and nominated a write to **`2300h`** as the
latch. That is withdrawn:

- there is no board with no interposer — the SFF has one built in, and the OEM and
  LFF boards take one;
- there is no physical part, so there is nothing for `A12`/`A13` to address;
- `2300h` was chosen as a *latch* address; with no latch it is a candidate register
  address and nothing more.

**What is open, and where it lands.** The window's address, the payload's paging and
the selector are **#12's interface spec** — not decisions this document makes. What
is settled is the constraint from §2.2: the ROM page gives 8 KB contiguous plus
4 KB beyond the assigned I/O block, 11776 bytes must be presented, and there is no
larger part to put them in.

### 4.2 The invariant that keeps the CBIOS working

**The monitor is never banked.** Only the window moves, wherever it ends up
sitting (§4.1a). This is not a convenience — it is required, because the CBIOS
calls ROM routines by *absolute address* (`LDK DE,SENDEN` in `occbio45.asm`,
`LDK DE,ROMVEC+3*13` in `occbio65.asm`) while bank 2 is mapped, and the CBIOS's
own `ROMCDE` arithmetic (`ROMVEC+3N`) depends on the monitor being where it always
was. Bank the monitor and the CBIOS breaks in ways that look like data corruption.

The other invariant follows from it: **`0000–0FFF` must stay a 4 KB monitor**, so
ROM 2.0's new monitor code has to fit in the **150 free bytes** of the 1.44
layout. That budget is in §4.7, and it is the real design constraint of this
whole document.

### 4.3 The content, and what it costs

The **payload** is what goes in the window; the monitor is not part of it. For the
boot this project is building (§2.3) the payload is **3585 bytes**:

| Holds | Size | Why |
|---|---|---|
| **CBIOS** | 2048 | the running BIOS whose vectors 2–31 the MD-10 BIOS patches in (§4.6). Resident in RAM at `0xE100` |
| **MD-10 BIOS image** | 1477 | copied to `0xD800` — the ACB-4000 driver, and the partial BIOS that reads the system off the drive |
| **install / patch / jump** | 60 | §4.6, measured at `HARD.COM` `0x01E5`–`0x0220` |
| spare | 511 | `8192` (the contiguous window) − `4096` (monitor) − `3585` |
| **payload total** | **3585** | **7681 with the monitor** (§2.3) |

**The no-disk goal's payload is a different, larger one** — the system image, 7680
bytes (CCP + BDOS + CBIOS) — and *that* is the one that does not fit the contiguous
window (§2.2). The two goals share one image and differ only in what has to be
paged, which is the point of building one image rather than two.

**Where any of it is presented, and what selects it, is open** (§4.1a) — these are
content slots, not addresses.

### 4.4 Cold boot — the no-disk path

This is the cold boot for the **no-disk** goal (CP/M out of the ROM). The boot this
project is actually building is `HCBOOT`, the ACB-4000 path (§4.6), and that is the
one §2.3 sizes.

**The copy semantics below are the design; "latch bank *N*" is a placeholder for
the open selector (§4.1a).** The destinations, the `LDIR` lengths and the final
jump do not depend on how the window is paged.

The copy is cheap because of a property of bank 2 that is easy to miss: **in bank
2, `4000–FFFF` mirrors bank 1 RAM.** So while the monitor is running from the ROM
window it can write the RAM at `CB00h+` directly — source and destination are both
visible at once, and no RAM/ROM mode switching is needed mid-copy.

1. `START` prints the prompt (unchanged).
2. `RETURN`/`"` → the ROM's `CBOOT` path is replaced by **`SYSLD`**: latch bank 0,
   `LDIR` 4096 bytes from `1000h` to `CB00h`; latch bank 1, `LDIR` 3584 bytes from
   `1000h` to `DB00h`. Roughly 30 bytes of code.
3. `JP 0E100h` — the CBIOS's `CBOOT`, **still in bank 2.** No bank switch here, and
   that is deliberate: in bank 2 `0E100h` is already bank 1 RAM, so the jump lands
   on the freshly-copied CBIOS, and the CBIOS calls `SW2RAM` itself (its first
   `CALL`s) exactly as it does today. Switching to RAM *before* the jump would be
   a bug — it would unmap the monitor out from under the very instruction that
   follows.
4. The CBIOS's `CBOOT` does what it always did: `MAGIC` (screen size, via
   `SW2ROM`/`02400h`), the IOBYTE, the baud rate, `CDISK = A`, page zero
   (`0000: JP WBOOT`, `0005: JP BDOS`), then `JMP [CCP+3]` with `C = drive`.
5. The CCP prompts **`A>`** — and nothing has touched the FDC.

Note what does *not* change: `HCBOOT` becomes `SYSLD` with a different bank
selection, the boot keys stay as they are, and the CBIOS is byte-for-byte the
vendor's. The copy destinations also land exactly where the source's own RAM
equates put them: `0CB00h + 7680 = 0E900h`, which is `CCP+1E00h`, the first byte
of the CBIOS's RAM area.

### 4.5 Warm boot

This is the part that is already solved by the hardware and only needed the
source changed. The CBIOS's `WBOOT` calls **ROM vector 1** (`LDK DE,ROMVEC+3*1`);
today that reads CCP+BDOS from the floppy. In ROM 2.0 **vector 1 points at
`SYSLD`** (or at a `SYSLD` variant that copies only the CCP+BDOS, 5632 bytes —
matching the stock `WBOOT`'s `B,44`).

So:
* the CBIOS does not change at all;
* the mechanism is the one CP/M already uses on this machine;
* and the "warm boot has no system tracks" problem in #83's open questions
  dissolves — the ROM's own jump table was always the hook, as #83's comment
  anticipated.

One runtime consequence to be honest about: the CBIOS's disk vectors are still
there and still real. `HOME` is harmless (it only flushes a buffer and clears
flags), but a program that *selects* a drive will reach `SELDSK` → `SENDEN` → the
ROM's FDC spin loop and retry. The clean fix is a **null-DPH gate** (§5, question 4)
rather than deleting the drivers.

### 4.6 HCBOOT, filled in

`HCBOOT` is `JP 0000h` at `0F67h` — three bytes, and the ROM's own end-of-code
guard sits right behind it. It becomes, essentially byte for byte, what `HARD.COM`'s
loader does once its diagnostics are dropped — **60 bytes**, measured at `HARD.COM`
`0x01E5`–`0x0220`:

```
HCBOOT:  latch the MD-10 payload           ; the open selector (§4.1a)
         LD   HL,053Ah                     ; the embedded BIOS in the ROM image
         LD   DE,0D800h                    ; where the MD-10 BIOS lives
         LD   BC,(0547h)                   ; 0x5C5 = 1477 bytes, read from the image
         LDIR
         LD   HL,(0001h)                   ; page zero+1 = the running BIOS's WBOOT
         INC  HL / INC HL / INC HL         ; +3 -> vector 2
         LD   DE,0D806h / LD C,12h / LDIR  ; 18 bytes -> 0xD806
         LD   DE,0D86Ah / LD C,15h / LDIR  ; 21 bytes -> 0xD86A
         LD   DE,0D82Dh / LD C,03h / LDIR  ;  3 bytes -> 0xD82D
         LD   DE,0D87Fh / LD C,03h / LDIR  ;  3 bytes -> 0xD87F
         LD   DE,0D833h / LD C,2Dh / LDIR  ; 45 bytes -> 0xD833
         XOR  A
         LD   (0013h),A                    ; page zero, drive A
         JP   0D800h                       ; the MD-10 BIOS's own jump table
```

Two things in that are load-bearing, and neither was obvious before it was read out
of the file:

- **The patch source is `(page zero+1)+3` — the *running* BIOS's jump table, not the
  ROM's.** `LD HL,(0001h)` reads the `WBOOT` vector, so on a stock boot the source is
  the **CBIOS at `0xE100`**, and the 90 bytes copied are its vectors 2–31. That is
  why the CBIOS has to be resident (§2.3), and why it cannot be deleted from the
  build as "not needed on a hard-disk machine".
- **The jump is to `0D800h`, the BIOS's jump table**, not to `0D882h`'s `BOOT`
  directly — entry 0 is a `JP` that gets there.

The `latch` step is the open selector (§4.1a); the copy, the patch and the jump are
measured.

### 4.7 The ROM 2.0 jump table, and the 150-byte budget

The legacy table is preserved exactly — 53 entries, same numbers, same semantics
(§3.1). ROM 2.0 adds a second, **self-describing** block after it, so third-party
code can detect the ROM and find the new calls without guessing:

| Address | Content |
|---|---|
| `0100`–`019E` | the 53 legacy vectors, unchanged |
| `019F` | signature, 8 bytes ASCII: `O1ROM2.0` (where `IMSG` sits today) |
| `01A7` | extension count (1 byte) |
| `01A8`+ | the extension table: 3-byte `JMP`s, `ROMVEC2 + 3N` |

Proposed extensions — short on purpose, each one justified by an issue:

| # | Entry | Does | Serves |
|---|---|---|---|
| 0 | `SYSLD` | reload the system image from ROM (also ROM vector 1's target) | §4.5 |
| 1 | `BANKSEL` | `A` = the payload slot, write the selector | §4.3, §4.1a (the selector itself is open) |
| 2 | `SCRMOD` | `A` = `0`/`1`/`3` → 52/104/80 columns, by the stock video-PIA write to `02C00h` with `EF61h` (`PIAAD`) as the cached copy | #24. The CBIOS's own `PLUGH` mechanism (`occbio55.asm`'s `MAGIC`), and the register and routine confirmed against `OZROM_1E.BIN` (§4.8) — **no video RAM taken**, per #83's constraint |
| 3 | `MEMTEST` | chip-level memory test | §1 |
| 4 | `HDBOOT` | install and enter the MD-10 BIOS from bank 2 | #179 |
| 5 | `VERSION` | `HL` = version word | so a program can branch on the ROM, which is the OZROM property worth having |

**The budget.** The new monitor code has to fit in the 150 free bytes of the 1.44
layout, and the accounting is:

| Piece | Estimate |
|---|---|
| `SYSLD` copy loop + bank latch + entry | ~30 B |
| `HCBOOT` body (reuses `SYSLD`'s loop) | ~30 B |
| signature + count + 6 extension vectors | ~26 B |
| `SCRMOD`, `BANKSEL`, `VERSION` | ~40 B |
| **Total** | **~126 B of 150** |

Feasible but tight, and the ACT source's own `IF RLWA > 0FFBH / .9 ERROR CODE TOO
LARGE` guard will fail the assembly if it is wrong — which is the right place to
find out. **Plan B if it does not fit:** the loader moves into bank 3 and is paged
in by a ~12-byte trampoline in the monitor, which buys a full 4 KB for loader code
at the cost of one bank. `MEMTEST` is the first thing to move there.

### 4.8 The feature set: what to take from OZROM, and what to refuse

OZROM 1E is the pattern for *how* to be a replacement ROM (`docs/ozrom-1e.md`
§4–§8). It is also the cautionary tale: **its feature set is shaped by its part.**
It had a 4 KB 2732, and the two things it gave up are things this project needs.

**Refuse, explicitly — both are 4 KB decisions, not ideas:**

| OZROM's choice | Why we refuse it |
|---|---|
| **IEEE-488 removed** — jump table `013F–0156` *were* the IEEE-488 routines, and calling one now "crashes the machine"; `IEEE-488 AS IOBYTE DEVICE 3 NOW NULL DEVICE` | **Drive C is an IEEE-488 device** (#22, `docs/drive-c-protocol.md`) and we hold the driver's own source (`rom144.asm`, #6). OZROM could not have both. We can |
| Video window cut to 3 KB (`F000–FBFF`), the last 1 KB (`FC00–FFFF`) spent on the redefinable keyboard | #24's VRAM shadow assumes the full `F000–FFFF`, and OZROM's move "constrains every later decision" (`docs/ozrom-1e.md` §4) |

**Take — and there is room to take them:**

| OZROM feature | Take? | Notes |
|---|---|---|
| 52 / 80 / 104-column switch | **Yes** | On #24's design path, and it is **not a new mechanism**: the stock video-PIA write, register `2C00` with `EF61` (`PIAAD`) as the cached copy — the *same routine*, unchanged from `rom144.asm`, disassembled out of `OZROM_1E.BIN` at `016F` (§4.7) |
| Chip-level memory tester that names the failing chip | **Yes** | The O1 has none, and it is #29's second oracle. TAB at power-up in OZROM; `MEMTEST` is already in §4.7's extension table |
| A *documented* jump table, memory map and version | **Yes** | The stock ROM already publishes the 53-vector table (§3); OZROM's manual is precisely why third-party code could target it. The `O1ROM2.0` signature and `VERSION` (§4.7) are the same property |
| The interrupt hook at `0EFF2h` — a bare `RET` continues, no register save/restore | **Yes** | #18. It is a **different `INTBL` slot and calling convention** from the RT-60A's `0EFF8h` (`docs/rt60a-analysis.md`); reconcile the two, do not merge them blindly |
| Time-of-day clock in `EF66–EF69` (BCD) | **Yes** | #7/#18. The cells are the machine's own, so this is not a new ABI |
| CRC checking on disk access | **Yes** | Free correctness; the stock ROM does not do it |
| Removing the *"Centronics printer not connected"* lockout on DD systems | **Yes** | #19, and cheap |
| Software-redefinable keyboard plus eight function keys | **Not yet** | #45/#47. This is the one feature that costs **RAM** (1 KB at `FC00–FFFF`), not ROM, and it is the reason OZROM moved the video window. Do it with a RAM budget, never by taking video space |
| 1793/1797 FDC notes; truer Televideo 912/920 emulation | **Not yet** | #20; not on this boot's path |

**The rule this leaves us with, and its one constraint.** Every entry in the
"refuse" table is a consequence of a 4 KB part. Ours is served from the interposer's
own flash, and the boot needs 7681 of the 8192 contiguous bytes (§2.3) — so there is
room in the *image* that OZROM never had.

The constraint is narrower than that, and worth stating precisely: **the 4 KB monitor
is still 4 KB**, with 150 free bytes (§4.7), and anything that must be resident there
answers to that budget. The clock, the interrupt hook and the CRC check are bigger
than that between them, so they cannot be monitor-resident. They do not have to be —
the extension table at `01A8h` (§4.7) is the hook for code that lives in the window,
and that is what the window is for. **The monitor stays a monitor; the new features
live in the window and are reached through the table.**

**So no — we do not have to drop a peripheral the way OZROM did.** IEEE-488 stays,
the 4 KB video window stays, and the test of the design is that nothing in the
"take" table above requires giving either one up.

### 4.9 The boot screen: one page, and a fallback that pays for itself

The screen is **one window page** — 4096 bytes, which is exactly the video buffer
(128 × 32 cells). In bank 2 the window and the video RAM are both visible (§4.4),
so a frame is one `LDIR` from `1000h` to `F000h`: **4096 × 21 T-states = 86016, or
21.5 ms at 4 MHz.** A fiftieth of a second, against a floppy boot measured in
seconds. The frames live in the interposer's flash, not the ROM, and the animation
is the viewport slide — a register write.

**The frame is someone else's file, so it validates itself.** The flash is
updatable and a hand-built image will get it wrong, and a bad frame puts garbage
on the screen with no way back. So the frame carries a marker in the rows nobody
can see — rows 24–31 are off-screen:

| offset | content |
|---|---|
| `0FF8h` | `O1NEXT`, the magic — **six** bytes |
| `0FFEh` | the 16-bit sum of `0000h`–`0FF7h`, little-endian |

The trailer is eight bytes, as it always was: the magic grew from four bytes to
six by **consuming the two reserved bytes at `0FFEh`**, so the checksum
definition does not move — it still covers exactly the 4088 bytes before the
trailer. The one cost is that the monitor's compare grows from four bytes to
six, inside the 150-byte budget §4.4 accounts as about 126 used (#228).

**The fallback is `o1next - press return`, and it costs nothing** — because ROM 2.0
*replaces* the stock sign-on rather than adding to it:

| | bytes |
|---|---|
| the text (21 characters; the last carries bit 7, which is `OSTR`'s terminator) | 21 |
| `LDK DE,MSG` / `CALL OSTR` | 6 |
| **total** | **27** |
| `IMSG`, which it replaces (§2.1) | 182 |

So the fallback **frees 155 bytes**, and pays for its own validity check out of
them. The order at boot is: **print the text first, then page the frame in and
check the trailer; if it is right, blit over the text.** A missing or malformed
image leaves the message on screen, which is the whole point of having it.

`tools/research/rom2strokes.py --frame` writes a frame with its trailer:
4096 bytes, and the art is placed by `--origin` — see §2.3 for why that is not
cosmetic.

## 5. The six open questions from #83, answered

| # | Question | Answer |
|---|---|---|
| 1 | Where does the BDOS get its parameters with no disk? | **Keep the DPB.** It costs nothing: the DPB, allocation vector and check vector live in the CBIOS's own RAM area at `E900h+` exactly as today, and with no media they are never dereferenced (§4.5, the null-DPH gate). Stubbing them would save no ROM space — they are RAM, not ROM — and would break the case where a real floppy *is* fitted |
| 2 | Warm boot, when there are no system tracks | **Already solved by the machine.** The CBIOS's `WBOOT` calls ROM vector 1; ROM 2.0 points it at `SYSLD`. No CBIOS change, no new mechanism (§4.5) |
| 3 | Does the CCP need to be relocatable? | **No — pin it.** `MSIZE = 59`, `CCP = CB00h`, `BDOS = D300h`, `BIOS = E100h`, all as the vendor shipped them. `MOVCPM`/`SYSGEN` are disk-build tools for a disk build; a ROM build wants the layout fixed so the ROM's copy loop can be two `LDIR`s with literal addresses. It also keeps the CBIOS's `ROMCDE` arithmetic valid, which *requires* `BIOS & 0FFh == 00h` |
| 4 | Keep floppy support, or drop it? | **Keep it.** The ROM carries the vendor's CBIOS unchanged, so a real disk still boots. The diskless case is handled at `SELDSK` by returning a **null DPH** when no media is present, which is documented CP/M behaviour (the BDOS then reports `Bdos Err on X: Select` for that drive) rather than a hang in the FDC retry loop. Deleting the drivers would save ROM space we do not need to save — the CBIOS is 2048 bytes either way, and it is already written |
| 5 | Which socket/part on the replica? | **The ROM socket, and on a real machine no part in it.** The LFF board keeps a socket that takes a standard 1.44 ROM, so it is a stock machine on its own; with the interposer fitted, a daughterboard takes the socket and the **Pico serves the ROM**, so ROM 2.00 needs no new part and is updatable in flash. A **27128/2764 is only for a board with no interposer** — and there is no such board, so there is no larger part at all, not in any form. Every host (OEM + interposer, LFF + interposer, SFF) has the softROM. Because OEM board + interposer ≡ LFF board + interposer, there is one host to design for and one to test on |
| 6 | What can we borrow from OZROM's memory map? | The **shape**, not the contents: a documented table and map, a documented version, a column switch, a memory test. Its specific choices — video RAM at `FC00–FFFF`, keyboard redefinition, IEEE-488 removed — are the ones #83 rules out. `docs/ozrom-1e.md` §5–§8 has the detail |


The `LDIR`/patch/jump body is **exactly 60 bytes**, not an estimate — measured at
`HARD.COM` `0x01E5`–`0x0220` (§4.6) — plus the bank/selector write.


## 6. The build (deliverable 2)

| Step | Tool | State |
|---|---|---|
| Monitor source assembles to the shipped 4096 bytes | **ACT80** (SORCIM 3.0/3.2, in-repo) under MAME | **Done** — #203/#204, byte-identical, CRC32 `c0596b14`. `tools/research/rom144-reassemble.sh` |
| The jump table is what the source says it is | `tools/research/romvec.py` | **Done** — 53 entries, 0 opcode disagreements |
| ROM 2.0's new monitor code assembles | ACT80 | Not started. New source, linked at the same addresses |
| The system image's CCP+BDOS+CBIOS | **taken from the shipped disk**, not rebuilt | Available today — the reserved tracks of `research/shipped-software/OS1SYSD.IMD`, at image offsets `0000`, `0800` and `1600` (§2.1) |
| The **ACB-4000 boot payload** (§2.3) | CBIOS + `HARD.COM`'s embedded BIOS at file offset `0x053A` + the 60-byte shim | Available — `tools/research/hardbios.py` already reads the BIOS; the shim is measured at `HARD.COM` `0x01E5`–`0x0220` |
| **The image itself** | `tools/research/rom2image.py` | **Done** — **7681 bytes**, every anchor re-checked, CRC32 `aef92022`. It is a *content* image: the monitor is still the stock 1.44, so it does not boot until `rom2asm` lands and calls the shim at `1DC5` |
| The no-disk payload (the *other* goal) | the 7680-byte system image split `4096 + 3584` | mechanical, from the above |

**Why take the CCP/BDOS/CBIOS bytes rather than rebuild them:** the CBIOS's build
recipe (`bios141.gen`) names **ACT 3.5e, DDT 2.2, SYSGEN 2.1 and MOVCPM**, and
ACT 3.5e is *not in the archive* (`docs/o1-rom-source.md`; 3.0 and 3.2 are, and
they agree with each other on `rom144.asm`). Rebuilding the CBIOS is therefore an
open risk with no payoff: the vendor's own 2048 bytes are on the disk, and the
whole point of the design is that they do not need to change. The *monitor* is the
part we are writing, and that is the part the toolchain is proven for.

The build therefore produces **one image**: the 4096-byte monitor plus the
3585-byte payload of §4.3 — **7681 bytes**, fitting the contiguous 8 KB window with
511 to spare. That single artefact is what the SFF's flash holds, what the
interposer's flash serves to the Pico, and what the emulator sees behind a
banked-ROM device (§7). **One image, three consumers, no per-host variants.** How
the payload is *presented* — and therefore what the emulator device has to model —
is the open window decision (§4.1a); the image's content is not.

## 7. The boot test (deliverable 3)

Deliverable 3 is a MAME boot test, and it is worth making it *stronger* than
"no floppy attached", because "no floppy attached" is satisfiable by a ROM that
hangs:

| Check | Passes when |
|---|---|
| `A>` reached | the probe sees the banner and an `A>` prompt |
| **No FDC access** | the harness sees **no access to `2100–2103`** from reset to the prompt — this is the "no disk access at all" of the issue title, asserted rather than implied |
| The BDOS is live, without a disk | a **nonsense command** typed at the prompt is echoed and answered `?`. The CCP reads the line with BDOS function 10 and prints the reply with function 9, so this exercises the CCP→BDOS path end to end — and unlike `DIR`, it does not need a disk, which is the whole point |
| Warm boot works | a `Ctrl-C` (or a program exit) returns to `A>` **without** an FDC access |
| *(CBIOS-ND build only)* the gate holds | `DIR A:` returns `Bdos Err on A: Select` rather than hanging in the FDC retry loop — the §5-question-4 null-DPH gate doing its job |

The mechanism is the one #191 already built: `tools/emulator-setup/mame-osborne1nx/`
is a MAME patch that adds a machine and a device, and the natural extension is a
banked-ROM device plus the `2300h` latch — the same shape as the ACB-4000 card
(`docs/osborne1nx-machine.md`). The harness is `tools/research/o1keys.sh` +
`tools/research/mame-boot-probe.sh`, which is what measured every row of
`docs/mame-emulation.md` §4.

**Not yet run.** The image now exists — `tools/research/rom2image.py`, 7681 bytes,
CRC32 `aef92022` (§6, #225) — but it is a *content* image: the monitor is still
the stock 1.44, so there is nothing yet that reaches for the window and the test
cannot run. **#247** is the plan that carries it: the banked-ROM device first, so
the machine works and the window is de-risked, then `rom2asm` with `HCBOOT`
filled in from the hard-disk chain that is already measured.

## 8. What is still open

1. **The window: address, paging and selector.** This is the largest open item, and
   it is **#12's interface spec**, not this document's call (§4.1a). The constraint
   is fixed (8 KB contiguous plus 4 KB beyond the assigned I/O block, §2.2; 11776
   bytes to present); the answer is not.
2. **Does ROM 2.0's monitor code fit in 150 bytes?** The estimate in §4.7 says yes
   with ~24 bytes to spare; the assembler's guard is the arbiter. Plan B is a
   banked loader.
3. **If a register is wanted at `2300h`.** `2300h` is free per the schematic and the
   ROM source, but a write there has never been measured on a real machine — the
   decode is described as sloppy (`docs/o1-memory-io-map.md` §7). The *latch* it was
   proposed for is withdrawn (§4.1a); what would still need checking is that a write
   to `2300h` is a no-op the interposer can claim. `hardware-gated`.
4. **Does the CBIOS really never call ROM vectors 10–12 and 16?** §3.2 says the
   labels do not line up and that nothing breaks; that is read from the sources,
   not traced. A MAME trace of a boot with a breakpoint on those addresses would
   settle it in an afternoon.
5. **`MEMTEST`'s scope.** Chip-level means per-4116, which needs the refresh
   timing and the bank-3 dim bit to be respected. Not designed here.
6. **The 512 bytes of RAM residue.** Harmless to the build (we take a fixed 2048
   for the CBIOS), but it is a reminder that the *system image* is not a clean
   artefact and a future `SYSGEN`-equivalent should say so.
7. **The memory map *at the moment the boot screen runs*.** §2.3 sizes what is
   resident and §4.4 describes the copy, but neither states the map the monitor
   sees when it decides to draw the screen — what is where, and what is safe to
   overwrite. That is planning that has not been done, and §4.9's blit depends on
   it: writing 4096 bytes to `F000h` is only safe if nothing else has claimed that
   range yet.
8. **Where the frame comes from in Pico-land, and how the ROM knows to ask for
   it.** §4.9 says the frames live in the interposer's flash and that a marker
   lets the ROM validate one — but not which flash slot, not what the ROM does to
   make the Pico present it, and not how the ROM distinguishes "a frame is
   available" from "the flash is empty". The page-select mechanism is §4.1a's and
   is #12's; the rest is undesigned.
9. **The mailbox protocol.** `docs/mailbox-protocol.md` is the interposer's
   *host*↔firmware channel (#155) and does not cover what the ROM asks the Pico
   for at boot. Nothing here defines that conversation, and the boot screen is the
   first thing that needs it — so it will otherwise accrete out of the first
   implementation, which is exactly what #155 exists to prevent.

## Sources

- `research/source-code/BIOS-144-source/rom144.asm` — the monitor: the jump table
  (`ORG 100h`, lines 507–581), `CBOOT` (641), `WBOOT` (728), `BCPM` (746), the
  boot-block counts (`LDK B,60` / `LDK B,44`), `START` (211), `HCBOOT` (4634).
- `research/source-code/BIOS-144-source/occbio15.asm` — the CBIOS's 34-entry jump
  table, `MSIZE`/`CCP`/`BIOS`/`BDOS`; `occbio35.asm` — `ROMRI`/`ROMCDE`/`ROMCD1`/
  `ROMJMP` and the `ROMVEC+3N` arithmetic; `occbio45.asm`, `occbio55.asm`,
  `occbio65.asm` — `HOME`, the warm boot, and the two hard-coded vectors;
  `occram15.asm` — the `CCP+1E00h` RAM area and the size guard; `occtxt6.ast` —
  `ROMVEC = 100h` and the `B*` constants (§3.2).
- `research/roms/os1-144.rom` — the shipped 4096 bytes (CRC32 `c0596b14`).
- `research/shipped-software/OS1SYSD.IMD` — the DD system disk whose reserved
  tracks carry the CCP/BDOS/CBIOS image (§2.1).
- `tools/research/romvec.py` — decodes and cross-checks the jump table.
- `tools/research/rom144-reassemble.sh`, `tools/research/acthex.py` — the
  toolchain proof (#203).
- `docs/o1-rom-source.md`, `docs/o1-rom-variants.md`, `docs/o1-memory-io-map.md`,
  `docs/mame-emulation.md`, `docs/osborne1nx-machine.md`, `docs/ozrom-1e.md`,
  `docs/md10-system.md`, `docs/acb4000-host-adapter.md`.
