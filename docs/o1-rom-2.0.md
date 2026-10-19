# ROM 2.0 — CP/M resident in the ROM, and how it boots (#83)

**Status:** design, first pass. The **arithmetic** (§2) and the **interface** (§3)
are *measured* — from the shipped 1.44 bytes and from a shipped system disk's
reserved tracks, with the tool in `tools/research/romvec.py` reproducing the
interface half. The **bank map, boot path and jump table** (§4–§5) are the
*design*: what we intend to build, with the reasoning that got us there. The
**contents of the boot are measured, not estimated — 7695 bytes (§2.3)** — and the
**feature set is decided against OZROM's, including what to refuse (§4.8)**. The
**boot keys are built too, and they are two bytes of the monitor's dispatch
(§4.6)**. The
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
whole document: there is **one host brief**, because the interposer's ROM window
does not care which OEM-faithful mainboard it is plugged into — an existing OEM
board, or any faithful 1:1 recreation of one with the Dual Density upgrade built
in. (Such a recreation is *possible* if a chassis ever needs restoring; it is not
in the set, and it has no directory — see *Not boards* in `hardware/README.md`.)
So "the stock machine" in this document means the mainboard-plus-interposer
combination, and there is no second path to design for.

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
ACB-4000, to `A>`, with no floppy ever read, is **7695 bytes** (§2.3) — 497 bytes
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
| install / patch / jump | **60** | the vendor's own loader block — *the shim*, in §4.6's language — kept in the window as the reference `HCBOOT` was lifted from: `LD HL,053Ah` / `LD DE,0D800h` / `LD BC,(0547h)` / `LDIR`, the five patching `LDIR`s, `XOR A` / `LD (0013h),A`, `JP 0D800h`. **Nothing calls it** — the machine forces `HCBOOT` to do that work in the monitor instead (§4.6) — so the window's copy is the anchor the image is checked against, not code | `HARD.COM`, `0x01E5`–`0x0220` |
| the hand-over stub | **14** | the one piece only RAM can run: `LD HL,0CB00h` / `LD (0EFD2h),HL` / `LD A,80h` / `LD (0003h),A` / `JP 0D800h`. `HCBOOT` copies it to `0E0F0h`, and the bank switch enters *it* (§4.6) | `tools/research/rom2image.py` |
| **Total** | **7695** | | |

**7695 bytes — and it fits the 8 KB contiguous window with 497 bytes to spare.** No
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
The boot described here is **7695**, and any figure quoted for it has to name the
list it came from.
**The boot screen does not come out of the 497-byte spare, and does not need to.**
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
* The **boot keys already exist**, and ROM 2.0 re-letters them (#247 step 4):
  `RETURN` = **the hard disk**, `:` = floppy A, `"` = floppy B, and `ESC` is
  released. 1.44 had `RETURN` = floppy A, `"` = floppy B, `ESC` = hard disk — so
  the machine's own disk sat on a *shifted* key while a facerolled RETURN booted
  a floppy nobody asked for. `HCBOOT` is a documented empty stub (`JMP START`)
  that Osborne left in the ROM for exactly this purpose (`rom144.asm` line 4634;
  it assembles to `JP 0000h` at `0F67h`), and the re-lettering is **two bytes** of
  the dispatch, in place — §4.6.
## 4. The design

### 4.1 The softROM serves the window — there is no ROM 2.00 part

**There is no physical ROM 2.00 and there never will be** — not a 27128, not a
2764, not a 16 KB part in any form (settled 2026-10-13). The ROM window is served
by the interposer's **softROM**: the interposer already has the bus, and the ROM
socket bridge gives it the window itself, so it presents the ROM in firmware.

| | |
|---|---|
| The host | **OEM board + interposer**, or the **`next-integrated` board**, where the interposer is built in as one unit. There is no third case and no part in the socket |
| A mainboard on its own | Keeps a socket that takes a standard 1.44 ROM, so a stock machine boots stock. That is the *stock* part — not ROM 2.00 |
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

- there is no board with no interposer — the `next-integrated` board has one built
  in, and an OEM board takes one;
- there is no physical part, so there is nothing for `A12`/`A13` to address;
- `2300h` was chosen as a *latch* address; with no latch it is a candidate register
  address and nothing more.

**What is open, and where it lands.** The window's address, the payload's paging and
the selector are **#12's interface spec** — not decisions this document makes. What
is settled is the constraint from §2.2: the ROM page gives 8 KB contiguous plus
4 KB beyond the assigned I/O block, 11776 bytes must be presented, and there is no
larger part to put them in.

### 4.1b The window this boot uses, measured in the machine (#247)

§4.1a leaves the window's address, paging and selector to **#12**, and this does
not close that: the 11776-byte no-disk goal still needs a paging answer. But the
boot this project is actually building (§2.3, **7695 bytes**) needs **none of
it** — and that is now measured in the emulated machine rather than argued.

**The window is `0000–1FFF`, and it is already 8 KB wide.** The mainboard never
decoded `A12` (§2.2), so the stock machine reads the same 4 KB monitor twice
across that range. MAME says so in one line:

```cpp
m_rom_view[0](0x0000, 0x0fff).mirror(0x1000).rom().region("maincpu", 0).unmapw();
```

**`mirror(0x1000)` *is* the undecoded `A12`.** So a softROM that decodes it gets
two 4 KB pages **contiguous, in the ROM page, with no new address space, no latch
and no register** — which is exactly the "8 KB contiguous" of §2.2, and why the
7695-byte image fits with 497 bytes spare.

| | |
|---|---|
| Page 0 (`A12 = 0`) | the monitor, `0000–0FFF` — the 4 KB that must never move (§4.2) |
| Page 1 (`A12 = 1`) | the payload, `1000–1FFF` — 3599 bytes of the 4096 (§4.3) |
| Given a 4 KB image | `A12` is ignored and the page mirrors: the stock part, unchanged |

**What that makes step 1 of #247.** The machine already has the idiom for
replacing a view entry: `osborne1sp` calls `osborne1_mem(map)` and then
re-registers the entry it wants to own — and the same shape replaces the ROM
window:

```cpp
m_rom_view[0](0x0000, 0x1fff).r(m_softrom, FUNC(softrom_device::read)).unmapw();
```

So **for this boot there is no window decision to wait on** — only the file the
device serves, and whether an image is 4 KB (mirror, stock) or more (two pages).
The `A12`/`A13` latch at `2300h` that §4.1a withdrew was for a *part*; a softROM
needs no such thing, and this is where that stops being an argument and becomes
an address map.

**And it is now built and measured.** `softrom_device` is
`src/devices/machine/softrom.{h,cpp}` in the patched tree
(`tools/emulator-setup/mame-osborne1nx/`), `osborne1nx_mem()` is the one line
above, and the image is named on the machine's own command line after the
device's tag — `-softrom rom2.rom`. What the window serves:

| Image | The window |
|---|---|
| none | the machine's own ROM region, mirrored — a stock machine |
| 4 KB or less | the image, mirrored: the image *is* the stock part |
| larger | two pages, `0000-0FFF` and `1000-1FFF`; past the image's end, `0xFF` (erased flash) |

`tools/emulator-setup/mame-osborne1nx/softrom-check.sh` is the acceptance, and it
is all of it:

- **the window is the device's** — `o1next-softrom.lua` reads all 8192 bytes back
  and compares them against the table above. This half is not optional: the stock
  monitor never reads page 1, so an override that reached only `0000-0FFF` would
  boot identically and silently.
- **the boot is identical** — `osborne1nx` with no image mounted, and with
  `rom2image.py`'s 7695-byte image mounted, both produce a screen dump
  byte-identical to `osborne1`'s, `A>` included (the machine name is the only
  difference).

Measured 2026-10-14, and again on 2026-10-15 with the hand-over in the image: all
five checks pass. The 7695-byte image reads `31 C1 EF D3` at `0000h` (the monitor)
and `C3 ED E4 C3` at `1000h` (the CBIOS, which is `JP`s), with the hand-over stub's
`21 00 CB 22 D2 EF 3E 80 32 03 00 C3 00 D8` at `1E01h` and `FF` from `1E0Fh` to
`1FFFh` — the payload's 497-byte spare. The MD-10 hard-disk boot to
`A0>`/`B0>`/`C0>` is unchanged.

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
boot this project is building (§2.3) the payload is **3599 bytes**:

| Holds | Size | Why |
|---|---|---|
| **CBIOS** | 2048 | the running BIOS whose vectors 2–31 the MD-10 BIOS patches in (§4.6). Resident in RAM at `0xE100` |
| **MD-10 BIOS image** | 1477 | copied to `0xD800` — the ACB-4000 driver, and the partial BIOS that reads the system off the drive |
| **install / patch / jump** | 60 | the shim — the vendor's loader block at `HARD.COM` `0x01E5`–`0x0220` (§4.6). The machine forces `HCBOOT` to do that work in the monitor, so nothing calls this copy; it is carried as the reference |
| **the hand-over stub** | 14 | the store only RAM can make: `CCPADR`, the IOBYTE, and the MD-10 BIOS's entry. `HCBOOT` copies it to `0xE0F0` and the bank switch enters it (§4.6) |
| spare | 497 | `8192` (the contiguous window) − `4096` (monitor) − `3599` |
| **payload total** | **3599** | **7695 with the monitor** (§2.3) |

**The no-disk goal's payload is a different, larger one** — the system image, 7680
bytes (CCP + BDOS + CBIOS) — and *that* is the one that does not fit the contiguous
window (§2.2). The two goals share one image and differ only in what has to be
paged, which is the point of building one image rather than two.

**Where any of it is presented, and what selects it, is open** (§4.1a) — these are
content slots, not addresses.

### 4.4 Cold boot — the no-disk path

> **Retired (2026-10-15).** The **no-disk** goal this section designs — CP/M
> resident in ROM with no disk at all — is **not a goal any more**, and the
> decision is a product one rather than a technical one. What the project wanted
> was *"it turns on and is sitting at a useful prompt"*: **no floppy in the drive
> to kick off the boot-transfer.** That is reached, and reached without this
> section: the firmware serves drive letters (the interposer's own storage
> personalities), so there is always a disk, and the MD-10's `HCBOOT` path (§4.6)
> boots the hard disk with no floppy in the machine at all. The consequence is
> that **the 11776-byte payload and its paging are gone from the plan** — the
> largest open item in §8 item 1 shrinks to the 1-bit page-1 selector the boot
> screen needs (`docs/rom-pico-protocol.md` §5), and `SYSLD` and §4.5's
> vector-1 retarget have nothing left to do. The section is kept because it is
> the design of the *other* goal and the record of why it was dropped.

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
selection, `RETURN` still boots the machine's own system — the one key that keeps
its meaning across the two goals, §4.6 — and the CBIOS is byte-for-byte the
vendor's. The copy destinations also land exactly where the source's own RAM
equates put them: `0CB00h + 7680 = 0E900h`, which is `CCP+1E00h`, the first byte
of the CBIOS's RAM area.

### 4.5 Warm boot

> **Retired (2026-10-15), with §4.4.** With the firmware serving drive letters
> there is always a system on `A:`, so warm boot reads it from the disk exactly as
> the stock ROM does and **ROM vector 1 keeps its meaning**. The mechanism below
> is kept as the design of the dropped no-disk goal.

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

**Built, and measured in the machine.** ROM 2.0's monitor is `rom144.asm` plus one
diff — `research/source-code/BIOS-200-source/rom2.diff` — assembled by the vendor's
own ACT80 (`tools/research/rom2asm.sh`, the pipeline #203 proved). The result is
checked against the invariant the design rests on: **the stock 1.44 below `0F67h`
is byte-identical** (3,943 bytes) and the new code is **77 bytes**, `0F67`–`0FB3`,
with **72 bytes free** to the vendor's guard: 67 bytes of copy, patch and jump, and
the 10-byte `LDIR` that puts the hand-over stub in RAM.

Three things the machine forced, and none of them is visible in the source:

- **Page zero is the ROM in bank 2, so the shim's `LD HL,(0001H)` cannot be used
  as it stands.** `HCBOOT` runs from the monitor, in bank 2, where `0000–1FFF` is
  the ROM window: a write to page zero is dropped and a read returns *this file's*
  bytes — `(0001H)` reads `C1 EF`, the operand of the monitor's own
  `LD SP,0EFC1H`, not a BIOS vector. `HARD.COM` had to ask page zero where the
  BIOS was; the ROM knows, and uses the CBIOS's vector 2 at `0E106H`, which is
  what `(page zero+1)+3` resolves to on a booted system (§2.3).
- **The bank switch has to be taken by code that survives it.** The monitor's own
  code is in the bank it is leaving, so `HCBOOT` ends by pushing the MD-10 BIOS's
  entry and jumping to the CBIOS's `SW2RAM` (`0E8E2H` in the shipped bytes):
  `SW2RAM` switches the bank, and its `RET` lands on the pushed address.
- **The machine's own interrupt exit needs a store only RAM can make.** The ROM's
  60 Hz handler returns *through the CBIOS* at `CCPADR + 1633h`, and `CCPADR` is the
  ROM's own `CBOOT`'s to write — `HCBOOT` was lifted from `HARD.COM`'s loader
  without it, so the exit lands on `1633h` and the machine never comes back
  (measured below). It cannot be written from bank 2 either, because `0EFD2h` is
  reached only in RAM mode — so `HCBOOT` copies a **14-byte stub** out of the
  payload's spare into RAM at `0E0F0h`, pushes *that* address instead of `0D800h`,
  and `SW2RAM`'s `RET` enters it. The stub writes `CCPADR`, the CBIOS's IOBYTE
  default, and jumps to `0D800h`.

`tools/emulator-setup/mame-osborne1nx/rom2-check.sh` measures the chain, and it
passes: the CBIOS is at `0E100H` and is the window's `1000H`; the MD-10 BIOS's
jump table is at `0D800H`; it is patched from the CBIOS's vectors, all 90 bytes
into the five slots; the bank switches to RAM; the stub is in RAM at `0E0F0H` with
`CCPADR = CB00H`; and with a drive mounted the system is read off it into `0C200H`
(`C3 C8 C4 …`) and the machine reaches **`A0>`**.

**The hand-over: measured, and it was one cell.** The chain completed and the
machine still did not reach `A0>`, and the reason was *not* the CBIOS's
uninitialised RAM in general. It was **`CCPADR` (`0EFD2h`)** — the cell the ROM's
own `CBOOT` writes at `02A3h` and `HCBOOT` was lifted without.

The ROM's 60 Hz interrupt handler ends by returning *through the CBIOS*:

```asm
;Exit interrupt code via exiting to RAM and then enable or disable ROM code
;depending on the value contained in ROMRAM cell.
	LD	A,ROMRAM	;IS ROM IN OR OUT?
	OR	A
	JNZ	ROMJP1		;if return to RAM
```

`ROMJP1` is `CCPADR + 1633h` — the CBIOS's `RRI` at `0E133h`, whose `OUT (C),A`
(C = `ROMRAM`) **restores the bank**. With `CCPADR = 0` that exit jumps to
`1633h`, which in bank 2 is the softROM's page 1: the payload's own copy of the
CBIOS's console dispatch. That copy reads `IOBYTE` at page zero+3 — and in ROM
mode page zero *is* the ROM, so it reads the ROM's own byte `D3h` (the opcode of
the `OUT (03h),A` at `0004h`), whose low two bits are **3: the IEEE device**. The
dispatch trampolines through `ROMJMP` into the ROM's IEEE input routine, which
waits for a handshake no device answers, for ever.

Measured with `rom2bank.lua` — the same instrument on the same path, before the
store was built and after:

| | stock boot | ROM 2.0, before the store | **ROM 2.0, with it** |
|---|---|---|---|
| reads of `0003h` (the IOBYTE) | 858, **all `80h`** — RAM, CRTOUT | **1, returning `D3h`** — the ROM, IEEE | **11, all `80h`** — RAM, CRTOUT |
| bank selects | 454 `OUT 0`, 492 `OUT 1` | 1 `OUT 1` (HCBOOT), 1 `OUT 0` (the trampoline) | 6 `OUT 0`, **44 `OUT 1`** |
| `CCPADR` (`0EFD2h`), and the exit it gives | **`CB00h` → `E133h`**, the CBIOS's `RRI` | **`0000h` → `1633h`**, the payload | **`CB00h` → `E133h`** |

`ROMRAM` (`0EF08h`) reads `00h` at the end of *both* runs, because `SW2ROM` clears
it on every ROM call and the sample lands inside one; it is 1 at the tick, which is
what makes the handler take the `ROMJP1` path at all.

The stock machine survives because its CBIOS brackets every ROM call with
`SW2ROM`/`SW2RAM`, so it is in RAM mode whenever the dispatch runs — 492 asks for
RAM in a single boot. The hand-over made exactly one, then left the guest to run
across a tick, and the tick's handler could not get back to RAM because `CCPADR`
was zero. **The bank is not something a guest can hold**; it is re-derived on every
instruction fetch and on interrupt acknowledge (`docs/o1-memory-io-map.md` §4), so
what the hand-over has to do is make the machine's own exit work — and the third
column is that working: the guest asks for RAM 44 times in the 8 s after RETURN,
and the IOBYTE answers `80h`, which is the stock machine's own answer.

**The fix is one store, and it is proved twice.** First by poking it in from
outside: with `CCPADR = CB00h` — and the CBIOS's own IOBYTE, `80h`, at page zero+3
— written into RAM just after the hand-over (`rom2handover.lua`), the machine boots
to `A0>` **with no floppy in the machine**:

```
                   OSBORNE 1
              Rev 1.44 (c) 1983 OCC
    Insert disk in Drive A and press RETURN.
A0>
```

And then by building it: `HCBOOT` copies the stub out of the payload's spare into
RAM and switches the bank to *it*, `rom2-check.sh` with a drive mounted reads the
stub's 14 bytes back at `0E0F0h` and `CCPADR = CB00h` on the way past, and the
prompt arrives from the ROM alone. Two details are worth keeping:

- **`0CB00h` is not this boot's CCP.** This boot puts the system at `0C200h`; the
  value is the *base the exit adds `1633h` to*, and `0CB00h + 1633h = 0E133h` is
  the CBIOS's `RRI` — the stock CCP-to-CBIOS offset. This boot keeps the CBIOS at
  `0E100h` exactly as a floppy boot does, so the stock value is the right one.
- **The stub's home is `0E0F0h`** — 14 bytes in the 104-byte hole between the
  driver's third allocation vector (`0DFA7h` + 241 = `0E098h`, `docs/md10-system.md`
  §9.1) and the CBIOS at `0E100h`. It has to be at or above `4000h`: in bank 2
  anything below that is the ROM, the window or I/O rather than RAM, and a write
  there is dropped.


**The boot keys, and they cost two bytes (#247 step 4).** `HCBOOT` hangs off the
sign-on dispatch, which is three comparisons, and ROM 2.0 re-letters it *in
place* — no code added, no address moved:

| Key | Boots | 1.44 |
|---|---|---|
| `RETURN` | the **hard disk** (`HCBOOT`) | floppy A |
| `"` | floppy **B** (`DSKSWP = 1`) | floppy B — unchanged |
| `:` | floppy **A** (`DSKSWP = 0`) | unused |
| `ESC` | nothing — released | the hard disk |

`CMP ESC` becomes `CMP CR` and `CMP CR` becomes `CMP ':'` (`rom144.asm`
~295-309; the diff's first hunk, and the two bytes are `0048h` and `0050h` in
the image). It fits in place, and it is correct rather than merely lucky:
`START` clears `0EF00h`-`0EFEFh` on every pass — `DSKSWP` (`0EFC7h`) included —
so `:` always finds it zero and means drive A, and `"` is the only path that
increments it. Nothing else in the dispatch moves: the three `JZ`s and the `JR`
are the ones 1.44 has.

ESC gets no new job. It is a non-standard keystroke in MAME as well as a poor
choice for a boot key, and it now falls through to the prompt's `JR START` like
any unclaimed key. The CBIOS's own `ESCH` cell is a different thing and is
untouched.

Because those two bytes are the **only** thing below `0F67h` that moves,
`rom2asm.sh` checks them *by value* rather than merely tolerating them: a build
whose dispatch is not this map stops with the map in the message, and
`rom2boot.lua` reads the same two bytes back out of the *running* monitor.

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

**Measured, not estimated.** `HCBOOT` as built is **77 bytes** — `0F67`–`0FB3` —
with 72 bytes still free to the guard, and the stock 1.44 below `0F67h` is
byte-identical (§4.6). That is 67 bytes of copy, patch and jump, plus the 10-byte
`LDIR` that puts the hand-over stub in RAM. The estimate above was ~126 of 150 for
the whole new monitor; `HCBOOT` is the part of it that is written, and it came in
under its share.

**And the boot screen does not fit in the 72 that are left (measured 2026-10-15,
#247 turn 3).** The screen's code — the attribute fill, the fallback text, the
door helper, the trailer check and the two `LDIR` blits — is **212 bytes** (182 when
first measured; #247's W3 grew the fallback), and the assembler's own guard says so in
its own words:

```
I 1021  .9   ERROR   CODE TOO LARGE..      Program LWA = 1102h.
```

So §8 item 2's question is answered: **the monitor code did not fit in 150
bytes**, and the screen was the piece that proved it. The code is written and
measured in `research/source-code/BIOS-200-source/rom2-screen.asm` (with the
per-piece arithmetic), and it needed a home rather than a squeeze — a **third
content id in the softROM** (`PRESENT(3)`, a 4096-byte blob in the Pico's flash
beside the frame, reached by a ~21-byte stub that copies page 1 to RAM and jumps
into it; recommended, because it needs no payload change and the screen code is
firmware like the frame), the **payload's spare** (`1E0Fh`–`1FFFh`, 497 bytes,
where the hand-over stub already lives), or this section's **Plan B** (a banked
loader). Any of the three fits in the tail's 72 bytes, because the monitor's share
becomes the stub.

**Measured, 2026-10-15 (turn 3's second pass): it was built.** Option 1 landed —
`PRESENT(3)` and a 4096-byte blob — and the blob is **183 bytes** at
`4000h`–`40B6h`, with `Program LWA = 40B7h`. The monitor's own new code was
**128 bytes**, `0F67h`–`0FE6h`, **21 free to the guard**: the cold boot, the
sign-on hook, and the stub that fetched the blob (`SCRN`, `0FB4h`–`0FE6h`, 51
bytes including the shared door helper). One assembly produced
both artifacts, and `tools/research/rom2blob.py` turned the `4000h` records into
`firmware/rom-service/screen.bin`.

**And #278 undid it, on purpose, because the premise went (2026-10-17).** The
stub, the blob, the asset, the tool and the `-bootsplash` slot all retired when the
ROM-side frame path did: the RP2354B is the display (§4.9), so the screen's code is
no longer the fill, the text, the door, the trailer and the two blits. It is **26
bytes** — fill the attribute array bright, print the fallback, return — which fits
the 72 the stub occupied, and the monitor's new code is `0F67h`–`0FCDh`: **103 bytes
of the tail's 149, 46 free** to the guard at `0FFBh`, up from 21. The *message* went
into `IMSG`'s own slot at `019Fh` (72 bytes of text where the vendor's 182-byte
sign-on message sat, at the vendor's own length, with the vendor's `FF` fill behind
it), so nothing below `0F67h` moved — and the 110 bytes left over there are what the
signature and the extension table in this section will take.

**And turns 3's `130 bytes` came down to `128` because the acceptance found two
defects in the new code (2026-10-15, turn 4).** Neither was visible in a boot:
the door helper's `JNZ` was testing flags left by its *length* probe rather than
by the result code, so every caller took its "no such content" path and the
machine printed the stock 1.44 sign-on however well the door answered; and the
frame's trailer *sum* was read from the half's `0FFEh` instead of the window's
`1FFEh` — the ROM's own byte — so the check could never pass and the screen
stayed the bright fill with no character written. Both are fixed, the blob is
regenerated, and `bootscreen-check.sh` measures the result off the machine: the
character plane, byte for byte, and the attribute plane, bit 7 — with no splash
mounted it measures the fallback instead, which is what says the frame is the
code's doing.

**And the 85 errors that stood in the way were not syntax errors.** They were two
defects, both read off the ACT80's own listing (which `L=B:` writes to a file
rather than scrolling past on the console): five comment lines that had lost their
leading `;`, so four assembled as illegal mnemonics — three bytes of junk code each
at `0FB4h` and `0FD9h` — and one as an unterminated string; and the blob sitting
*inside* the vendor's `ECHO 0FFFH-RLWA ! DB 0FFH … ENDM` block. `ECHO` **repeats**
its body, so the blob was assembled and listed 11 times: ten extra passes over its
eight labels, and 80 duplicate-label errors. 85 = 80 + 5. With both fixed the build
is `no ERRORs, 487 Labels, Program LWA = 40B7h`.

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
own flash, and the boot needs 7695 of the 8192 contiguous bytes (§2.3) — so there is
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

**The fallback is the screen's own two lines, and it costs nothing** — because ROM 2.0
*replaces* the stock sign-on rather than adding to it. Since #247's W3 (2026-10-17) it
carries the **same text and the same bright/dim runs as the animation's resting
frame**, at the frame's own rows and columns — array rows 20 and 22, ink from columns
24 and 30:

| | bytes |
|---|---|
| the message: `VCLRS`, the padding as `OSTR`'s `7Fh` repeat escape, both lines, and the `ESC,VSHI`/`ESC,VEHI` mode changes | 72 |
| `IMSG`, which it replaces (§2.1) | 182 |

So the fallback still **frees 110 bytes**, and it needs no code of its own: the
attribute runs *are* the text's own escapes, and dim is the vendor's own
half-intensity mode. Three things were measured rather than assumed, and the first is
why an unpositioned fallback is not merely misplaced — it is invisible:

- **`CURS` is 0 when the screen code runs.** `START` clears `0EF00h`–`0EFEFh` on
  every pass, and `COUT` writes through `CURS` — so a message that does not position
  itself is written to address 0, which is the ROM, and nothing appears anywhere. The
  vendor's `IMSG` began with `VCLRS` for exactly that reason; the fallback does too.
- **dim is `ESC,VSHI` … `ESC,VEHI`**, the vendor's half-intensity mode: `VHALF`
  writes `DIMBIT` (`00h`) into the attribute array, which reads back **`7Fh`** — the
  animation's own dim value, so the plane and the asset's attribute half compare byte
  for byte.
- **the `7Fh` repeat escape is `OSTR`'s own** (`IMSG` uses it), so a padding run of
  twenty costs three bytes rather than twenty.

The order at boot is unchanged: **print the text first, then page the frame in and
check the trailer; if it is right, blit over the text.** A missing or malformed image
leaves the message on screen, which is the whole point of having it.

**And the blit is two passes, not one — measured 2026-10-15.** The O1's video cell
is **9 bits**: 8 for the character and 1 for brightness, and the 9th bit is not in
the video RAM. It lives in a *separate* 4K×1 array that `OUT (02h)` pages into
`F000–FFFF`; `OUT (03h)` pages the character RAM back, and the array's low seven
bits are not physically present and read high. Measured in `osborne1nx`:

| | |
|---|---|
| with `OUT (02h)` then writing `00h` to `F000h` | reads back **`7Fh`** |
| the palette (`palette_init_monochrome_highlight`) | 0 = black, 1 = `C0C0C0`, 2 = white |
| the renderer (`BIT(attr,7) ? 2 : 1`) | **bit 7 set = bright, clear = dim** |
| the array at the sign-on | 4072 × `FFh`, **24 × `7Fh`** — so it is not a blank slate |
| the 116 character cells at the sign-on | all bright |

So the screen **fills the attribute array bright** (`OUT (02h)`, 4096 stores of
`FFh`, `OUT (03h)`), because 24 stray dim cells would show in a 4096-cell screen.
That is 21.5 ms, and it is what makes the fallback's own dim runs the *only* dim
cells on the screen — which is the trigger the RP2354B watches for (§4.9's `IMSG`,
and `docs/rom-pico-protocol.md` §5.1).

**And since #278 that fill is the only thing the ROM does to the attribute plane.**
It used to blit the frame's attribute half over the fill, and the RP2354B draws both
planes out of the frame it is playing instead. The frame is still two 4096-byte
halves — characters and attributes — and v1.0's attribute half is all `FFh`. The
format, the trailer and the sequence that *used* to be the ROM's are
`docs/rom-pico-protocol.md` §4.1 and §5.

**And the frame lives in the Pico's own flash, not the library flash** — one
frame, compiled into the firmware, swappable only by rebuilding it. The library
flash holds the *default disks*.

`tools/research/rom2strokes.py --frame` writes the whole artifact — **8192 bytes,
the character half then the attribute half**, each with its own trailer at its own
`0FF8h` — and the art is placed by `--origin`; see §2.3 for why that is not
cosmetic. `--half` writes one half, `--verify` validates a half or a whole frame
off the disk. The copy the firmware compiles in used to be
`firmware/rom-service/frame.bin`; that asset was **retired on 2026-10-16**, when the
boot screen became the animation the RP2354B plays
(`firmware/rom-service/boot-animation.bin`, #247's W5), and the `--check` that re-built
it went with it. **`firmware/rom-service/screen.bin` — the screen's code, served as a
window page — went the same way on 2026-10-17 (#278)**, when the code came back into
the monitor's own tail; `tools/research/rom2blob.py` and `rom2asm.sh`'s `-b` retired
with it.

## 5. The six open questions from #83, answered

| # | Question | Answer |
|---|---|---|
| 1 | Where does the BDOS get its parameters with no disk? | **Keep the DPB.** It costs nothing: the DPB, allocation vector and check vector live in the CBIOS's own RAM area at `E900h+` exactly as today, and with no media they are never dereferenced (§4.5, the null-DPH gate). Stubbing them would save no ROM space — they are RAM, not ROM — and would break the case where a real floppy *is* fitted |
| 2 | Warm boot, when there are no system tracks | **Already solved by the machine.** The CBIOS's `WBOOT` calls ROM vector 1; ROM 2.0 points it at `SYSLD`. No CBIOS change, no new mechanism (§4.5) |
| 3 | Does the CCP need to be relocatable? | **No — pin it.** `MSIZE = 59`, `CCP = CB00h`, `BDOS = D300h`, `BIOS = E100h`, all as the vendor shipped them. `MOVCPM`/`SYSGEN` are disk-build tools for a disk build; a ROM build wants the layout fixed so the ROM's copy loop can be two `LDIR`s with literal addresses. It also keeps the CBIOS's `ROMCDE` arithmetic valid, which *requires* `BIOS & 0FFh == 00h` |
| 4 | Keep floppy support, or drop it? | **Keep it.** The ROM carries the vendor's CBIOS unchanged, so a real disk still boots. The diskless case is handled at `SELDSK` by returning a **null DPH** when no media is present, which is documented CP/M behaviour (the BDOS then reports `Bdos Err on X: Select` for that drive) rather than a hang in the FDC retry loop. Deleting the drivers would save ROM space we do not need to save — the CBIOS is 2048 bytes either way, and it is already written |
| 5 | Which socket/part on the replica? | **The ROM socket, and on a real machine no part in it.** An OEM-faithful mainboard keeps a socket that takes a standard 1.44 ROM, so it is a stock machine on its own; with the interposer fitted, a daughterboard takes the socket and the **Pico serves the ROM**, so ROM 2.00 needs no new part and is updatable in flash. A **27128/2764 is only for a board with no interposer** — and there is no such board, so there is no larger part at all, not in any form. Every host (OEM + interposer, and the `next-integrated` board) has the softROM, so there is one host to design for and one to test on |
| 6 | What can we borrow from OZROM's memory map? | The **shape**, not the contents: a documented table and map, a documented version, a column switch, a memory test. Its specific choices — video RAM at `FC00–FFFF`, keyboard redefinition, IEEE-488 removed — are the ones #83 rules out. `docs/ozrom-1e.md` §5–§8 has the detail |


The `LDIR`/patch/jump body is **exactly 60 bytes**, not an estimate — measured at
`HARD.COM` `0x01E5`–`0x0220` (§4.6) — plus the bank/selector write.


## 6. The build (deliverable 2)

| Step | Tool | State |
|---|---|---|
| Monitor source assembles to the shipped 4096 bytes | **ACT80** (SORCIM 3.0/3.2, in-repo) under MAME | **Done** — #203/#204, byte-identical, CRC32 `c0596b14`. `tools/research/rom144-reassemble.sh` |
| The jump table is what the source says it is | `tools/research/romvec.py` | **Done** — 53 entries, 0 opcode disagreements |
| ROM 2.0's new monitor code assembles | ACT80 | **Done** — `HCBOOT` is **77 bytes**, `0F67`–`0FB3`, with **72 bytes free** to the vendor's guard, and the stock 1.44 below `0F67h` is byte-identical. `tools/research/rom2asm.sh`, CRC32 `ce51a4eb` (§4.6) |
| The system image's CCP+BDOS+CBIOS | **taken from the shipped disk**, not rebuilt | Available today — the reserved tracks of `research/shipped-software/OS1SYSD.IMD`, at image offsets `0000`, `0800` and `1600` (§2.1) |
| The **ACB-4000 boot payload** (§2.3) | CBIOS + `HARD.COM`'s embedded BIOS at file offset `0x053A` + the vendor's 60-byte loader block + the 14-byte hand-over stub | Available — `tools/research/hardbios.py` already reads the BIOS; the loader block is measured at `HARD.COM` `0x01E5`–`0x0220`, and the stub is written down in `rom2image.py` |
| **The image itself** | `tools/research/rom2image.py` | **Done** — **7695 bytes**, every anchor re-checked. Built on the stock monitor it is CRC32 `28840c50`; built on ROM 2.0's monitor it is `a9453f51`, and *that* is the one that boots (§4.6, §7) |
| The no-disk payload (the *other* goal) | the 7680-byte system image split `4096 + 3584` | mechanical, from the above |

**Why take the CCP/BDOS/CBIOS bytes rather than rebuild them:** the CBIOS's build
recipe (`bios141.gen`) names **ACT 3.5e, DDT 2.2, SYSGEN 2.1 and MOVCPM**, and
ACT 3.5e is *not in the archive* (`docs/o1-rom-source.md`; 3.0 and 3.2 are, and
they agree with each other on `rom144.asm`). Rebuilding the CBIOS is therefore an
open risk with no payoff: the vendor's own 2048 bytes are on the disk, and the
whole point of the design is that they do not need to change. The *monitor* is the
part we are writing, and that is the part the toolchain is proven for.

The build therefore produces **one image**: the 4096-byte monitor plus the
3599-byte payload of §4.3 — **7695 bytes**, fitting the contiguous 8 KB window with
497 to spare. That single artefact is what the SFF's flash holds, what the
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

**Run, and it boots.** The image exists — `tools/research/rom2image.py`, 7695 bytes
(§6) — the softROM window serves it, and `HCBOOT` runs the chain *and* the boot:
`rom2-check.sh` boots the emulated interposer **with no floppy**, presses RETURN at
the sign-on prompt — and reads the dispatch's two key bytes, the CBIOS, the MD-10
BIOS, the patch, the bank switch, the hand-over stub's 14 bytes in RAM at `0E0F0h`,
`CCPADR = CB00h`, the system off the drive and the `A0>` prompt back (§4.6).

Which of the rows above that settles is worth being exact about, because the goal
is a boot with **no disk at all**:

| Check | State |
|---|---|
| `A>` reached | **the hard-disk variant is measured** — `A0>` arrives with no floppy in the machine. This row on the *no-disk* payload is the same prompt reached a different way |
| **No FDC access** | **not yet** — the system is read off the drive, so the FDC *is* used. This is the row that needs the no-disk payload, and that needs the window's selector (§4.1a) |
| The BDOS is live, without a disk | **not yet** — same reason: `0C200h` came from the drive rather than from the ROM |
| Warm boot works | **not yet** — same |
| *(CBIOS-ND build only)* the gate holds | **not yet** — same |

So the ROM's own half of deliverable 3 is done and measured; what is left is the
**no-disk** payload, which is the one that needs the selector rather than the drive.


## 8. What is still open

1. **The window: address, paging and selector.** This is the largest open item, and
   it is **#12's interface spec**, not this document's call (§4.1a). The constraint
   is fixed (8 KB contiguous plus 4 KB beyond the assigned I/O block, §2.2; 11776
   bytes to present); the answer is not.
   **For the boot this project is building it is settled, measured, and needs no
   paging at all** — the window is `0000–1FFF`, because `mirror(0x1000)` in the
   machine's own address map *is* the undecoded `A12`, so a softROM that decodes
   it gets two contiguous 4 KB pages for free (§4.1b).
   **The 11776-byte half is retired (§4.4, §4.5)** — the no-disk goal was dropped
   on 2026-10-15, so the paging problem went with it. **And the one bit that was
   left is gone too (#278)**: window page 1 is the payload, always, because the ROM
   no longer serves a frame and `PRESENT(1)`/`(2)`/`(3)` retired with the frame path.
   **And the boot's half is built**: `softrom_device` serves the window and
   `-softrom` names the image (§4.1b), accepted by `softrom-check.sh`; and
   ROM 2.0's monitor now *assembles* with `HCBOOT` filled in and runs the chain
   into the MD-10 BIOS (§4.6), accepted by `rom2-check.sh`. What is left of the
   chain is the hand-over, and it is named: `CCPADR` (`0EFD2h`), the ROM's own
   `CBOOT`'s store, without which the interrupt handler's exit cannot return to RAM
   (§4.6, item 10).
2. **Does ROM 2.0's monitor code fit in 150 bytes?** **Answered twice, and the
   second answer is the useful one** (§4.7). *No* — measured 2026-10-15: `HCBOOT`
   took 77 of the 150, the screen's code was 212 bytes against the 72 left, and the
   guard said `CODE TOO LARGE`. That sent the screen's code to the interposer's
   flash as a third content id. **And then yes, after #278** (2026-10-17): the frame
   path's retirement left the screen at **26 bytes**, so it fits the tail, and the
   monitor's new code is `103` of the tail's `149` — **46 free** to the guard. What
   that buys is exactly what this section wanted: the extension table's own home.
   `IMSG`'s slot is 182 bytes with 110 of them free (the fallback text took 72), and
   `BANKSEL`, `SCRMOD`, `VERSION` and the rest are still estimates — but there is
   now room for them, in the tail and in the vendor's dead sign-on slot.
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
7. **The memory map at the moment the boot screen runs.** **Answered and
   measured** — `docs/rom-pico-protocol.md` §6, which also records the BIT 9
   finding: the 9th video bit is a separate 4K×1 array paged into `F000–FFFF` by
   `OUT (02h)`, its polarity is measured from the palette, and the array is *not*
   a blank slate — so the screen is **two passes**, not one (§4.9).
8. **Where the frame comes from in Pico-land, and how the ROM asks for it.**
   **Answered** — `docs/rom-pico-protocol.md` §4 and §5. One frame, in the
   **Pico's own flash**, compiled into the firmware; **two 4096-byte halves**
   (characters and attributes) so the 9th bit is retained by construction; and the
   trailer *is* the "is a frame there?" query, so there is no separate question.
9. **The mailbox protocol for the ROM.** **Answered** — the same protocol, with
   **two doors, one protocol**: the I/O pair `0E7h`/`0EBh` for userland (a TPA
   program cannot reach bank 2) and a bank-2 register pair at `2300h`/`2301h` for
   the ROM (which runs in bank 2, where the console path's own latch writes cannot
   perturb a comparator-decoded claim). `docs/rom-pico-protocol.md` §2 has the
   measurement that decided it.
10. **The hand-over: measured, built, and it is `CCPADR`.** The chain completed and
   the machine still did not reach `A0>`; the reason was **one cell**. The ROM's
   60 Hz interrupt handler exits through `ROMJP1` — `CCPADR (0EFD2h) + 1633h` — to
   the CBIOS's `RRI` at `0E133h`, which is what restores the bank; the ROM's own
   `CBOOT` writes that cell (`02A3h`), and `HCBOOT` does not, so the exit landed on
   `1633h` — the softROM's page 1, the payload's copy of the CBIOS's console
   dispatch — which reads `IOBYTE` from a page zero that in ROM mode is the ROM
   (`D3h` = the IEEE device) and never returned. Measured: the stock boot reads the
   IOBYTE 858 times, all `80h` from RAM; the hand-over read it **once, and got
   `D3h`**.
   **Built.** `HCBOOT` copies a 14-byte stub out of the payload's spare into RAM at
   `0E0F0h`, pushes *that* address instead of `0D800h`, and `SW2RAM`'s `RET` enters
   it; the stub writes `CCPADR`, the CBIOS's IOBYTE default, and jumps to `0D800h`.
   Measured with the same instrument that found the fault: the IOBYTE now answers
   `80h` eleven times, the guest asks for RAM 44 times in the 8 s after RETURN,
   and `CCPADR` gives `E133h` — and `rom2-check.sh` with a drive mounted reaches
   `A0>`
   **with no floppy in the machine** (§4.6, §7). What is left is the *no-disk*
   payload, which is §4.1a's selector, and §8 item 7's map at the moment the boot
   screen runs.


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
- The hand-over's exit — read from the sources, then measured: the monitor's 60 Hz
  handler and its `ROMJP1` return (`rom144.asm` ~2015–2035), `ROMJP1` itself
  (`LDK DE,1633h` / `LD HL,CCPADR` / `JMP [HL]`, 414–421), `ROMRAM = 0EF08h`
  (112) and `CCPADR = 0EFD2h` (141, "assigned in BIOS and filled in by loader in
  ROM"); on the CBIOS side `RRI`/`ROMRI` (`occbio15.asm` 125, `occbio35.asm` 3–17)
  and `SW2ROM`/`SW2RAM` (`occbio85.asm` 484–506).
- `tools/emulator-setup/mame-osborne1nx/rom2trace.lua`, `rom2bank.lua` — the two
  instruments that measured the hand-over (#247): the PC sampler that unwinds the
  stack, and the taps that read the IOBYTE and count the bank selects;
  `rom2handover.lua` is the third, which proved the fix by poking `CCPADR` into RAM
  *before* it was built, and `rom2boot.lua` is the acceptance that checks the built
  store — the stub's 14 bytes in RAM, `CCPADR`, and the prompt.

- `tools/research/rom144-reassemble.sh`, `tools/research/acthex.py` — the
  toolchain proof (#203). `acthex.py`'s `--fill-reference` and `--covered-range`
  are what let a build whose hex file the emulator's floppy write-back damaged
  still be the image the source describes, and stop the build loudly when it
  cannot (`docs/rom-13-reconstruction.md` §7).
- `docs/o1-rom-source.md`, `docs/o1-rom-variants.md`, `docs/o1-memory-io-map.md`,
  `docs/mame-emulation.md`, `docs/osborne1nx-machine.md`, `docs/ozrom-1e.md`,
  `docs/md10-system.md`, `docs/acb4000-host-adapter.md`.
