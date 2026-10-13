# ROM 2.0 — CP/M resident in the ROM, and how it boots (#83)

**Status:** design, first pass. The **arithmetic** (§2) and the **interface** (§3)
are *measured* — from the shipped 1.44 bytes and from a shipped system disk's
reserved tracks, with the tool in `tools/research/romvec.py` reproducing the
interface half. The **bank map, boot path and jump table** (§4–§5) are the
*design*: what we intend to build, with the reasoning that got us there. What is
not done is stated in §8.

**Issues:** #83 (deliverable 1; deliverable 2's toolchain proof landed as #203/#204),
#49 (the reproduction this ROM is for), #72 (the ROM source), #179 (the MD-10 boot
that wants the same ROM window), #24 (the column mode), #81 (OZROM, the pattern).

## 1. What ROM 2.0 is, and what it is not

The goal from #83 is unchanged: **an O1 ROM that boots to a working `A>` with no
disk access at all** — real or virtual. It is a *replacement part*, not a patch:
optional, socket-reversible, legitimate on the replica and (with a daughterboard)
on a real O1.

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

### 2.2 Why the 4 KB ROM cannot hold it, and the 16 KB one cannot either

Bank 2 is the only place the CPU reads ROM (`docs/o1-memory-io-map.md` §2):

| Range | Bank 2 |
|---|---|
| `0000–0FFF` | Monitor ROM (2732 at UD11) |
| `1000–1FFF` | Unused — **mirror of the ROM**, because A12 is not decoded |
| `2000–2FFF` | Memory-mapped I/O |
| `3000–3FFF` | Unused — mirror of `2000–2FFF` |
| `4000–FFFF` | Mirrors bank 1 RAM |

So the contiguous ROM window is **8 KB, and that is a hard ceiling**: a 27128
wants `0000–3FFF` and `2000–3FFF` is the I/O window. 11776 bytes does not fit in
8 KB, and the stock 2732 holds 4096 of which **150 bytes are free** (`0F6Ah–0FFFh`;
the code ends at `0F69h` and the source's own guard is `IF RLWA > 0FFBH`).

**Therefore: banked, or nothing.** And the good news is that the mirror is the
room — `1000–1FFF` is 4 KB nobody else wants.

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

### 4.1 The part, and the one thing it must decode that the socket does not carry

| | |
|---|---|
| Part | **27128** (16 KB, 28-pin) — the same 28-pin JEDEC package the existing 2732→2764 daughterboard accepts. **Not a drop-in for it:** pin 27 is `A13` on a 27128 where a 2764 has `/PGM`, so the adapter has to *drive* that pin rather than tie it high. That is the daughterboard's one electrical change |
| Window | the monitor stays at `0000–0FFF`; **`1000–1FFF` becomes a 4 KB banked window** |
| Banks | 4 × 4 KB: the system image (2 banks), the MD-10 BIOS image (1), diagnostics + spare (1) |
| Latch | one write-only latch supplying A12/A13 (and A14 for a 27512) |

The electrical problem, stated plainly because it decides the build: **a 24-pin
2732 socket has `A0–A11`, `/CE`, `/OE` and the data bus — no `A12`, no `A13`, and
no write strobe.** A 27128 needs all three. So the daughterboard is not passive:
it has to take `A12`/`A13` and the latch strobe from elsewhere on the board, which
is the "ROM-socket hijack" of #83's design discussion and, on the O1NG, the
interposer's job. On the stock machine this is the one part of ROM 2.0 that is not
a drop-in — and it is why the emulator build comes first (§6).

**The minimum viable part is a 2764, and that de-risks the first build.** The
diskless-CP/M goal — deliverable 3 — needs **only banks 0 and 1: 8 KB**, which is
exactly what a 2764 provides and what the existing daughterboard already takes.
The 27128 buys banks 2 and 3 (the MD-10 image and diagnostics). So the first build
and the full build share one layout and differ only in the part, and the first one
can be tested on real hardware with the adapter that already exists — no new board
spin before the design is proven.

**Where the latch lives.** A write to **`2300h`** while bank 2 is selected. That
address is the free block `docs/o1-memory-io-map.md` §7 recommends for virtual
peripherals, it is a clean gap (`2300–28FF`), it needs no port decode (the stock
machine's port space is masked to two bits, so no `OUT` port is free), and it is
only reachable while the ROM is live — which is exactly when it should be
writable. On stock hardware a write there is currently a no-op, so the latch is
what makes it mean something; on the `osborne1ng` machine and the interposer the
decode is already widened.

### 4.2 The invariant that keeps the CBIOS working

**The monitor is never banked.** Only `1000–1FFF` moves. This is not a
convenience — it is required, because the CBIOS calls ROM routines by *absolute
address* (`LDK DE,SENDEN` in `occbio45.asm`, `LDK DE,ROMVEC+3*13` in
`occbio65.asm`) while bank 2 is mapped, and the CBIOS's own `ROMCDE` arithmetic
(`ROMVEC+3N`) depends on the monitor being where it always was. Bank the monitor
and the CBIOS breaks in ways that look like data corruption.

The other invariant follows from it: **`0000–0FFF` must stay a 4 KB monitor**, so
ROM 2.0's new monitor code has to fit in the **150 free bytes** of the 1.44
layout. That budget is in §4.7, and it is the real design constraint of this
whole document.

### 4.3 The bank map

| Bank | Window `1000–1FFF` holds | Size used | Why |
|---|---|---|---|
| 0 | system image bytes `0000–0FFF` (CCP first half + BDOS start) | 4096 | copied to `CB00h+` on cold boot |
| 1 | system image bytes `1000–1DFF` (rest of the 7680) | 3584 | the rest; 512 bytes spare |
| 2 | **MD-10 BIOS image** (1477 B) + its install/patch shim (~60 B) | ~1537 | `HCBOOT`'s real body for the hard-disk boot (#179) |
| 3 | diagnostics: the chip-level memory test, and spare | — | the OZROM-borrowed tester (§4.7) |

Bank 2 is the point of overlap with #179: `HCBOOT` needs the MD-10 BIOS at
`0D800h` and a jump to `0D882h`, and the BIOS image is 1477 bytes — it fits in one
4 KB bank with room for the patch shim. That is the "route 1" of #83's earlier
discussion, and it needs no new part beyond the 27128 already specified here.

### 4.4 Cold boot

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
guard sits right behind it. It becomes:

```
HCBOOT:  latch bank 2          ; the MD-10 BIOS image
         copy 1477 bytes to 0D800h
         patch the console slots from the ROM's jump table (5 LDIRs — HARD.COM's own code at 0x0200 is the worked example)
         JP 0D882h             ; the MD-10 BIOS entry
```

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
| 1 | `BANKSEL` | `A` = bank, write the latch | §4.3 |
| 2 | `SCRMOD` | `A` = `0`/`1`/`3` → 52/104/80 columns, by writing `02400h` in bank 2 | #24, and the CBIOS's own `PLUGH` mechanism (`occbio55.asm`'s `MAGIC`) — no video RAM taken, per #83's constraint |
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

## 5. The six open questions from #83, answered

| # | Question | Answer |
|---|---|---|
| 1 | Where does the BDOS get its parameters with no disk? | **Keep the DPB.** It costs nothing: the DPB, allocation vector and check vector live in the CBIOS's own RAM area at `E900h+` exactly as today, and with no media they are never dereferenced (§4.5, the null-DPH gate). Stubbing them would save no ROM space — they are RAM, not ROM — and would break the case where a real floppy *is* fitted |
| 2 | Warm boot, when there are no system tracks | **Already solved by the machine.** The CBIOS's `WBOOT` calls ROM vector 1; ROM 2.0 points it at `SYSLD`. No CBIOS change, no new mechanism (§4.5) |
| 3 | Does the CCP need to be relocatable? | **No — pin it.** `MSIZE = 59`, `CCP = CB00h`, `BDOS = D300h`, `BIOS = E100h`, all as the vendor shipped them. `MOVCPM`/`SYSGEN` are disk-build tools for a disk build; a ROM build wants the layout fixed so the ROM's copy loop can be two `LDIR`s with literal addresses. It also keeps the CBIOS's `ROMCDE` arithmetic valid, which *requires* `BIOS & 0FFh == 00h` |
| 4 | Keep floppy support, or drop it? | **Keep it.** The ROM carries the vendor's CBIOS unchanged, so a real disk still boots. The diskless case is handled at `SELDSK` by returning a **null DPH** when no media is present, which is documented CP/M behaviour (the BDOS then reports `Bdos Err on X: Select` for that drive) rather than a hang in the FDC retry loop. Deleting the drivers would save ROM space we do not need to save — the CBIOS is 2048 bytes either way, and it is already written |
| 5 | Which socket/part on the replica? | **27128 in the monitor socket**, with the latch and `A12`/`A13` from the hijack/interposer (§4.1). The O1NG's SFF board is a new design and could put the ROM anywhere, but keeping the *monitor socket* means the same build drops into a real O1 with the existing daughterboard — which is the only way to test it on hardware |
| 6 | What can we borrow from OZROM's memory map? | The **shape**, not the contents: a documented table and map, a documented version, a column switch, a memory test. Its specific choices — video RAM at `FC00–FFFF`, keyboard redefinition, IEEE-488 removed — are the ones #83 rules out. `docs/ozrom-1e.md` §5–§8 has the detail |


The `LDIR`/patch/jump body is the ~40–60 bytes #83's analysis identified, plus
the bank latch write. It reuses `SYSLD`'s copy loop, so the marginal cost is small.


## 6. The build (deliverable 2)

| Step | Tool | State |
|---|---|---|
| Monitor source assembles to the shipped 4096 bytes | **ACT80** (SORCIM 3.0/3.2, in-repo) under MAME | **Done** — #203/#204, byte-identical, CRC32 `c0596b14`. `tools/research/rom144-reassemble.sh` |
| The jump table is what the source says it is | `tools/research/romvec.py` | **Done** — 53 entries, 0 opcode disagreements |
| ROM 2.0's new monitor code assembles | ACT80 | Not started. New source, linked at the same addresses |
| The system image's CCP+BDOS+CBIOS | **taken from the shipped disk**, not rebuilt | Available today — the reserved tracks of `research/shipped-software/OS1SYSD.IMD`, at image offsets `0000`, `0800` and `1600` (§2.1) |
| The bank-0/1 payload | the 7680 bytes split `4096 + 3584` | mechanical, from the above |
| The MD-10 BIOS payload | `HARD.COM`'s embedded copy at file offset `0x053A` | Available — `tools/research/hardbios.py` already reads it |

**Why take the CCP/BDOS/CBIOS bytes rather than rebuild them:** the CBIOS's build
recipe (`bios141.gen`) names **ACT 3.5e, DDT 2.2, SYSGEN 2.1 and MOVCPM**, and
ACT 3.5e is *not in the archive* (`docs/o1-rom-source.md`; 3.0 and 3.2 are, and
they agree with each other on `rom144.asm`). Rebuilding the CBIOS is therefore an
open risk with no payoff: the vendor's own 2048 bytes are on the disk, and the
whole point of the design is that they do not need to change. The *monitor* is the
part we are writing, and that is the part the toolchain is proven for.

The build therefore produces **one 16 KB image = four 4 KB banks**, which is what
the 27128 takes, and — for the emulator — the same image with a banked-ROM device
in front of it (§7).

## 7. The boot test (deliverable 3)

Deliverable 3 is a MAME boot test, and it is worth making it *stronger* than
"no floppy attached", because "no floppy attached" is satisfiable by a ROM that
hangs:

| Check | Passes when |
|---|---|
| `A>` reached | the probe sees the banner and an `A>` prompt |
| **No FDC access** | the harness sees **no access to `2100–2103`** from reset to the prompt — this is the "no disk access at all" of the issue title, asserted rather than implied |
| A program runs | a `DIR` typed at the prompt returns a directory listing (proves the BDOS is live, not just the CCP banner) |
| Warm boot works | a `Ctrl-C` (or a program exit) returns to `A>` **without** an FDC access |

The mechanism is the one #191 already built: `tools/emulator-setup/mame-osborne1ng/`
is a MAME patch that adds a machine and a device, and the natural extension is a
banked-ROM device plus the `2300h` latch — the same shape as the ACB-4000 card
(`docs/osborne1ng-machine.md`). The harness is `tools/research/o1keys.sh` +
`tools/research/mame-boot-probe.sh`, which is what measured every row of
`docs/mame-emulation.md` §4.

**Not yet run.** The image does not exist yet, so this is the specification of the
test rather than a result.

## 8. What is still open

1. **Does ROM 2.0's monitor code fit in 150 bytes?** The estimate in §4.7 says yes
   with ~24 bytes to spare; the assembler's guard is the arbiter. Plan B is a
   banked loader.
2. **The bank latch on real hardware.** `2300h` is free per the schematic and the
   ROM source, but the *write* has never been measured on a real machine — the
   decode is described as sloppy (`docs/o1-memory-io-map.md` §7) and this needs a
   scope before a board is spun. `hardware-gated`.
3. **Does the CBIOS really never call ROM vectors 10–12 and 16?** §3.2 says the
   labels do not line up and that nothing breaks; that is read from the sources,
   not traced. A MAME trace of a boot with a breakpoint on those addresses would
   settle it in an afternoon.
4. **`MEMTEST`'s scope.** Chip-level means per-4116, which needs the refresh
   timing and the bank-3 dim bit to be respected. Not designed here.
5. **The 512 bytes of RAM residue.** Harmless to the build (we take a fixed 2048
   for the CBIOS), but it is a reminder that the *system image* is not a clean
   artefact and a future `SYSGEN`-equivalent should say so.

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
  `docs/mame-emulation.md`, `docs/osborne1ng-machine.md`, `docs/ozrom-1e.md`,
  `docs/md10-system.md`, `docs/acb4000-host-adapter.md`.
