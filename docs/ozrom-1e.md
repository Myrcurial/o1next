# OZROM 1E — the third-party monitor ROM as tooling (#81)

**Status:** Solved, as tooling — and **#81 is closed** on that deliverable. It
boots under MAME on all three Osborne 1 machines (measured, §3), its 58-page
manual is OCR'd and indexed here (§4–§8), and its three engineering features — a
software 52/80/104-column switch, a chip-level memory tester and a *documented*
ROM interface — are available to us without hardware. The column switch's
mechanism is now measured from the ROM as well as documented (§7): it drives the
stock video PIA through the stock ROM's own helper, and OZROM adds no cell of its
own. Its companion **Utilities disk** surfaced in 2026-10 and is catalogued in §10
— the directory is complete, the file bodies are partly erased. What is left is
routed rather than carried: **#167** (drive the column keys from the harness) and
**#168** (a complete Utilities disk) — §9.

**Source:** `research/roms/OZROM-1E/OZROM_1E.BIN` (4096 bytes) and
`OZROM_1E_Manual.pdf`, both from BrettHallen's `Osborne_1` repository;
`OZROM_1E_Manual.ocr.txt` is the 300 dpi `tesseract` text layer (grep it for the
appendices — but not for exact code, it is OCR). Micro Management, Inc.,
Manual Rev. A 84/09/01. Serves #81, and touches #24 (video), #29 (validation),
#45/#47 (keyboard), #20 (floppy) and #7/#18 (clock).

## 1. What it is

A replacement for the 2732 monitor ROM at UD11, sold in 1984 by Micro
Management (Irving, TX). It is a **ROM swap with capability**, not a font
change: the manual's feature list is mostly things the stock ROM lacks. The two
engineering features that matter to this project are the *documented memory map
and jump table* (§5–§6) — a second, independent description of the machine's
interface to hold against `rom144.asm` (#72) — and the *software column switch*
(§7), which is on the design path for the video personality (#24).

## 2. How to run it under MAME

MAME cannot be told about a BIOS it does not define, but it **will** load a file
whose bytes do not match the expected hash (it warns and carries on). So present
OZROM under a stock BIOS filename.

**Build a romset, do not just drop files in a directory.** The simple
`mkdir .../osborne1 && cp ...` recipe in `mame-emulation.md` §5 works for
`osborne1` and `osborne1sp` but **fails for `osborne1nv`**, because the Nuevo
machine needs `character_generator_6-29-84.14`, which MAME satisfies by CRC
fallback from `7a3007-00.ud15` *only when the files are loose in the rompath root
or inside a zip* — not when they sit in a plain `osborne1/` directory. Build the
zip instead:

```bash
mkdir -p /tmp/ozbuild/osborne1
cd /tmp/ozbuild/osborne1
cp <repo>/tools/emulator-setup/roms/*.ud11 \
   <repo>/tools/emulator-setup/roms/*.ud15 \
   <repo>/tools/emulator-setup/roms/*.ua15 .
cp <repo>/research/roms/OZROM-1E/OZROM_1E.BIN 3a10082-00rev-e.ud11
cp 7a3007-00.ud15 character_generator_6-29-84.14   # satisfies the clone's chargen
mkdir -p /tmp/ozset && zip -q -X /tmp/ozset/osborne1.zip *

mame osborne1nv -verifyroms -rompath /tmp/ozset     # -> romset ... is good
```

The `character_generator_6-29-84.14` copy is not a hack: it is a byte-identical
duplicate of `7a3007-00.ud15` (`docs/o1-rom-variants.md`), and it is what makes
the hash fallback deterministic across all three machines.

## 3. Measured: it boots on all three machines

```
O1_ROMPATH=/tmp/ozset tools/research/mame-boot-probe.sh MACHINE \
    tools/emulator-setup/floppies/52-blank.imd 120
```

| Machine | Screen | Columns | Banner | Result |
|---|---|---|---|---|
| `osborne1` | 416×240 | 52 | `OZROM 1E #00187 / (c) 1984 Micro Management` | **BOOTED** to `A>` |
| `osborne1sp` | 832×240 | 104 | same | **BOOTED** to `A>` |
| `osborne1nv` | 640×240 | 80 | same | **BOOTED** to `A>` |

So OZROM's *window* is the machine's (52/104/80), exactly like every other disk
(`mame-emulation.md` §2), and it boots CP/M off the utility disk to `A>` on all
three. MAME prints *"the machine might not run correctly"* because the ROM hash
is not what it expects — that warning is the point, not a problem.


## 4. What it adds, and what it gives up

From the manual (page 1 feature list; Appendix C for the losses):

| Gained | Why it matters here |
|---|---|
| Keyboard-selectable **52 / 80 / 104-column** display | A *documented software* video-mode switch — the mechanism the video personality (#24) is being built on. On an un-expanded machine it can also toggle the left/right 52 columns of an 80-column display. |
| **System memory tester** that names the failing chip | A ready-made second oracle for #29, alongside `tools/check_o1_map.sh`. |
| **Software-redefinable keyboard**, plus eight locally-redefinable function keys (up to 63 chars) | Relevant to #45/#47. |
| **Time-of-day clock** (`TIME`, `ALARM`, `TIMER`, `QUIKTIME`) | #7/#18 — see §8 and `docs/rt60a-analysis.md` "The third shape". |
| **Documented interfaces**: interrupt hook, ROM jump table, memory map, keytable | An externally documented O1 ROM interface to hold against `rom144.asm` (#72). |
| **1793/1797 FDC** notes; truer Televideo 912/920 emulation | #20 and terminal behaviour generally. |
| Removes the *"Centronics printer not connected"* lockout on DD systems | #19. |

| Given up | Consequence |
|---|---|
| **IEEE-488 functions** (Appendix C) | **OZROM and Drive C cannot coexist out of the box** — Drive C is an IEEE-488 device. The manual says *"extra software would be required"*, and that software is the driver whose source we hold in `rom144.asm` (#6/#22). |
| The stock 4 KB video window | OZROM uses **3 KB** (`F000–FBFF`) for video and the last 1 KB (`FC00–FFFF`) for the redefinable keyboard and function keys, so it scrolls by moving the 23 lines above rather than the window. This is the 1 KB price of the redefinable keyboard, and it constrains the 2.0 ROM design (#83). |

The IEEE-488 loss is not passive: the jump-table appendix says the entries at
`013F–0156` *were* the IEEE-488 routines and **calling one now produces a
controlled system crash** (no disk damage — the machine's two top display lines
go "gangbusters hog-wild"), and *"IEEE-488 AS IOBYTE DEVICE 3 NOW NULL DEVICE"*.
The parallel/Centronics entries at `0193`+ survive unchanged.

## 5. The OZROM memory map (Appendix C-5)

"Some of the memory locations reserved by the OZROM 1E for its own purposes."
The OCR splits the address column from the description column, but the pairing
is unambiguous; the clock rows are confirmed independently against the OCC
source in `docs/rt60a-analysis.md`.

| Address | Purpose |
|---|---|
| `EF07` | Parallel-printer control — 0 = normal, non-zero = null device (DD only?) |
| `EF57–EF58` | Current BIOS starting address — how to find the start of the O1's special BIOS regardless of MOVCPM/OS patches |
| `EF5C–EF5D` | `KTBPTR` — keyboard pointer. OZROM sets it to `FC00`; if `(KTBPTR)+2` changes from its initial 0, OZROM repoints it at the ROM table |
| `EF5F` | Keyboard matrix value of the last key pressed |
| **`EF66`** | **Start of system clock — hours, 2-digit BCD** |
| **`EF67`** | **Minutes, 2-digit BCD** |
| **`EF68`** | **Seconds, 2-digit BCD** |
| **`EF69`** | **Sixtieths of a second, 2-digit BCD** |
| `EFDF` | Time-display toggle byte |
| `EFE0` | Keyclick toggle byte |
| `EFE1` | Keyclick counter |
| `EFE2` | Blink toggle byte |
| `EFE3` | Blink counter |
| `EFE4` | Blink rate value — gives `30/X` blinks/sec; default 20 (decimal) = 1.5 blinks/sec |
| `EFE5` | `KEYTYP` — whether the current key is normal / shift / control / control-shift |
| `EFE6–EFE7` | Temporary pointer used by the keyboard-redefinition routines |
| `EFE8` | Clock position — `F000 + ((value + 43) MOD 256)`, anywhere on the first two display lines |
| `EFE9` | Temporary storage of the character at the cursor (used by the blink routine) |
| `EFF2–EFF4` | **Interrupt routine hook** — preset with `RET` (`0C9h`); see §8 |
| `F000` | Beginning of video RAM (3 KB, `F000–FBFF`) |
| `FC00` | Start of the RAM keycode table: `FC00–FC37` normal, `FC38–FC6F` shift, `FC70–FCA7` control |
| `FCA8–FCBF` | Reserved for future use |
| `FCC0–FD7F` | Used by `ALARM`/`TIMER`; **192 bytes available to a programmer's interrupt routine** |
| `FD80–FDBF` | Temporary storage for the bottom video line (64 chars) during MyKey II reprogramming |
| `FDC0–FDCF` | MyKey II function-key pointers |
| `FDE0` | MyKey II cyclic counter (next function-key space) |
| `FDE1–FDFF` | MyKey II stack space |
| `FE00–FFFF` | MyKey II function-key definition space (8 definitions) |

## 6. The ROM jump table (Appendix C-6)

Provided "for the programmer's convenience … since actual ROM addresses called
by this table may vary according to which version of the OZROM 1E is being
used". This is the *same interface* the stock ROM exposes at `0100`+, so it is
directly comparable to `rom144.asm`'s vector table (#72).

| Addr | Entry | Note |
|---|---|---|
| `0100` | `JMP COLD_BOOT` | |
| `0103` | `JMP WARM_BOOT` | |
| `0106` | `JMP INPUT_STATUS+01` | keyboard |
| `0109` | `JMP CONSOLE_INPUT+01` | keyboard |
| `010C` | `JMP CONSOLE_OUT+01` | display |
| `010F` | `JMP LIST` | serial output |
| `0112` | `JMP PUNCH` | serial output |
| `0115` | `JMP READER` | serial input |
| `0118` | `JMP DRIVE_RESET` | |
| `011B` | `RET ! NOP ! NOP` | **no ROM-level select-disk** |
| `011E` | `JMP READ` | |
| `0121` | `JMP WRITE` | |
| `0124` | `JMP READ_TRACK_INFO` | |
| `0127` | `JMP READ_SECTOR` | |
| `012A` | `JMP WRITE_SECTOR` | |
| `012D` | `JMP LIST_STATUS` | serial-port status |
| `0130` | `JMP SENSE_DISK_DENSITY` | same entry as the stock ROM's `SENDEN` |
| `0133` | `JMP ROM_JUMP_1` | exit from the interrupt routine for bank 1 |
| `0136` | `RET ! NOP ! NOP` | no ROM_JUMP_2 |
| `0139` | `JMP FORMAT` | |
| `013C` | `JMP INIT_SERIAL` | |
| `013F–0156` | *(were IEEE-488 routines)* | **calling these crashes the machine** |
| `0157–0186` | same functions as O1 ROM 1.4 | |
| `0187` | `OR 0FFH ! RET` | IEEE printer input status → **null device** |
| `018A` | `OR 0FFH ! RET` | IEEE printer output status → null |
| `018D` | `XOR A ! RET ! RET` | IEEE printer input → null |
| `0190` | `RET ! RET ! RET` | IEEE printer output → null |
| `0193` | `JMP PARALLEL_INPUT_STATUS` | **Centronics path survives** |
| `0196` | `JMP PARALLEL_OUTPUT_STATUS` | |
| `0199` | `JMP PARALLEL_INPUT` | |
| `019C` | `JMP PARALLEL_OUTPUT` | |
| `019F` | `JMP READ/WRITE_SEC` | direct FDC command execution; needs `RWCMD` (`EFD1`) and `SAVTYP` set |

## 7. The keytable (Appendix C-7) and the column switch

OZROM's normal, shift and control keytables are moved up into RAM at power-up or
RESET (`FC00`+ per §5); the control-shift table stays in ROM and cannot be
redefined. The codes are the machine's own, not ASCII: `0x80–0x89` are the ten
function keys, `0x8A–0x8D` the four arrow keys, and the control-shift table
carries the "process immediately" codes `0xF0–0xFC` (screen positioning; the
time, keyclick, blink and auto-horizontal-scroll toggles; the **Screen-Pac
52/80/104-column select keys**; and the assign/reassign-parallel-printer keys).
Three codes are permanently assigned: `0xDD` = ctrl-shift-Z, `0xDE` =
ctrl-shift-X, `0xDF` = ctrl-shift-R.

**The column switch is the part on our design path (#24).** OZROM's own words
(Appendix C): the ctrl-shift keys include "the Screen-Pac 52-, 80-, and
104-column select Keys", and on a machine with no 80-column upgrade the switch
"can also toggle between the left and right 52 columns of an 80-column display".

### Measured against the three machines (§3)

OZROM boots at the machine's native width — **52 / 104 / 80** columns on
`osborne1` / `osborne1sp` / `osborne1nv` — and reaches `A>`. That is the same
result every other disk gives (`mame-emulation.md` §2): the *window* is the
machine's, the *text layout* is the software's.

What is **not yet measured** is the switch itself in action: pressing
ctrl-shift-<column key> and watching the width change. Doing that needs the
harness to post a *modifier-qualified* keystroke (`tools/research/mame-boot-probe.lua`
only posts plain characters), and the column keys' effect under MAME depends on
whether the driver models the width as a PIA-driven horizontal offset or as fixed
hardware. It is the one open item from #81 that needs code rather than reading —
routed to **#167**, see §9.

### The mechanism, from the ROM

The switch is **not a new mechanism and it uses no new RAM cell**: it drives the
video PIA through the *stock* ROM's own helper.

`rom144.asm` defines `H.VIO = 02C00H ; Video memory controls` and
`PIAAD = 0EF61H`, and carries this routine:

```
        LDK  A,4+3          ; PIA control: select the data register
        STO  A,H.VIO+1      ; 2C01 = 7
        MOV  A,C
        STO  A,PIAAD        ; 0EF61 - the stock ROM's "last PIA-A data" cell
        STO  A,H.VIO        ; 2C00 - send data
        RET
```

Disassembling `OZROM_1E.BIN` finds **the same routine, unchanged**, at `016F`
(`ld a,007h / ld (02c01h),a / ld a,c / ld (0ef61h),a / ld (2c00h),a / ret`), and
OZROM's console path reads the same two registers back at `04EC` and `0BE1`. So
the column keys compute an offset and hand it to the stock video-PIA write: the
**register that holds the mode is `2C00`**, with **`EF61` (`PIAAD`)** as the
cached copy — which is why OZROM's own memory map (Appendix C-5, §5) has no
column-mode byte in it. There is not one.

Two things this does **not** settle, and they are the honest boundary of the
finding:

- **Which field** of the `2C00` byte is the horizontal offset. That port also
  carries the drive-select and density (`DDEN`) lines (`o1-memory-io-map.md` §3),
  and `rom144.asm`'s own note on `PIAAD` is about **bit 0 = density**. The manual
  gives the *effect* precisely — control-up-arrow repositions the window to start
  at column 29, control-down-arrow to column 76, control-`[` homes it — so the
  values are known even though the bit layout is not.
- **The dispatch address** for the control-shift codes `0xF0–0xFC`. A linear
  sweep cannot follow it: `z80dasm` warns about self-modifying code, and the codes
  are dispatched through a table rather than by direct calls. Locating it is worth
  doing only if we want to *trace* OZROM's handler; for #24 we need the register
  and the values, and those are above.

## 8. The clock, the memory tester, and the error codes

**Time-of-day clock.** OZROM's `TIME HHMMSS` sets it, ctrl-shift-T shows it (top
two display lines, position set by `EFE8`), and `ALARM`/`TIMER`/`QUIKTIME` ride
the interrupt hook. Its cells are the machine's own `EF66–EF69` (hours, minutes,
seconds, sixtieths, BCD) — **not** a new ABI. Accuracy is "better than three
minutes a day" with the drives idle; disk access momentarily stops the clock
(the manual is explicit that the clock "has no guarantee" under disk load). The
full treatment, and why it matters to our own clock contract, is in
`docs/rt60a-analysis.md` "The third shape".

**The interrupt hook.** On the 60 Hz video interrupt, OZROM's `SYSINT` saves the
stack pointer, PC and registers and then calls **`0EFF2h`**; a bare `RET` there
continues normally, so a programmer puts a jump to their routine at `EFF2` and
ends with `RET` — **no register save/restore needed**. 26 bytes of interrupt
stack (13 levels) and 192 bytes of routine RAM (`FCC0–FD7F`) are available. Note
this is *not* the RT-60A's `0xEFF8` hook: different `INTBL` slot, different
calling convention (see `rt60a-analysis.md`).

**The memory tester.** Press TAB at power-up or after RESET; it cycles
`0 → 0EFFFh`, writing and checking `0`, `0FFh`, `0AAh` and `55h` at each
location and naming the failing chip. Video RAM is not tested. A ready-made
second oracle for #29.

**Error codes** (Appendix D): `BOOT ERROR` = "you are not using an OZROM 1E";
`NO SYS!` = a formatted diskette with no system on it (SYSGEN it); `OH, NO!` =
same as `BOOT ERROR` (or a bad system track). Also worth knowing: OZROM **enables
CRC checking on disk access** where previous ROMs did not, so copy verification
now catches real read errors.

## 9. What is left, and where it goes

**#81 is closed on its stated deliverable.** The manual is indexed, the column
switch is documented *and* its mechanism measured from the ROM (§7), the memory
tester and the error codes are written down (§8), and the ROM interface is
recorded — memory map, jump table, keytable, interrupt hook (§5–§6). Four
residues were left at the close; none of them is work that belongs *here*, so each
is routed rather than carried:

| Residue | Where it goes |
|---|---|
| **Drive the column switch from the harness** (§7) — the one measurement still missing | **#167** — the harness can only post plain characters, so ctrl-arrow and ctrl-shift are inexpressible. That is a tools capability, wanted by #24 as much as by this issue. |
| **A complete copy of the Utilities disk** (§10) | **#168 — closed: we already have it.** The "290 of 400 sectors erased" reading was a `cpmfs.py` sector-skew bug (§10.2); with the correct skew all twenty files extract whole. |
| **Diff the jump table against `rom144.asm`** (§6) | **Done** — see below. |
| **Reconcile the `EF66–EF69` clock against ROM 1.44** | Not OZROM's question: it is about *which stock revision* dropped `UPTIM`. Recorded in `docs/rt60a-analysis.md`; belongs with #83/#18, not here. |

### The jump-table diff, done

Entry for entry, the manual's Appendix C-6 table (§6) and `rom144.asm`'s vector
table at `0100`+ describe **the same interface**. Every address matches, including
the ones where the *names* differ: `0118` is the stock ROM's `JMP RDRV` / `HOME`
and OZROM's `DRIVE_RESET`; `0112` is the stock ROM's second `JMP LIST` for punch
output, which OZROM calls `PUNCH`. The only structural differences are the two
already recorded — **`013F–0156`**, where OZROM removed the IEEE-488 routines so
that calling them crashes the machine, and **`0136`**, where the stock ROM's `JMP
ROMJP2` becomes `RET / NOP / NOP`. Two independent descriptions of the same
interface agreeing is the point of the exercise.

## 10. The OZROM 1E Utilities disk — the software half (#81)

`research/roms/OZROM-1E/OZROM_1E_Utilities.IMD` is the disk that goes with the
ROM: the utilities the manual documents, as a customer received them. We had the
ROM and the manual and not the software, so this is the missing third of the
package.

It is a **data disk, not a system disk.** It does not boot — the system tracks
carry a stub whose message is "There is no CP/M system on this disk." You boot
your own CP/M and put this in drive B, which is why the package shipped as a
bare set of files.

### 10.1 The directory — complete

Readable in full: 20 files, all in user 0, in creation order, allocation intact.
Standard single-density O1 geometry (40 cyl × 10 × 256 B FM, 2 KiB blocks,
3 boot tracks, 64 directory entries).

| File | Bytes | File | Bytes |
|---|---:|---|---:|
| `ALARM.COM` | 640 | `OZPATCH.COM` | 3328 |
| `CLKPATCH.COM` | 640 | `QUIKTIME.COM` | 256 |
| `CLKPATCH.DOC` | 1792 | `QWERTY.COM` | 1024 |
| `CRASH.COM` | 256 | `READ.ME` | 1280 |
| `CRCKLIST.CRC` | 512 | `SET.COM` | 2048 |
| `DVORAK.COM` | 1024 | `SHOW.COM` | 512 |
| `DVORAK.DOC` | 1024 | `TD.COM` | 896 |
| `FK.COM` | 2816 | `TD.DOC` | 1024 |
| `MEMORIZE.COM` | 1280 | `TIME.COM` | 640 |
| `MYKEYII.COM` | 640 | `TIMER.COM` | 768 |

The set maps onto the manual's feature list one for one: the column switch
(`SHOW`), the keyboard remaps (`DVORAK`, `QWERTY`, `MYKEYII`), the clock
(`TIME`, `TIMER`, `QUIKTIME`, `CLKPATCH`, `ALARM`), the function keys (`FK`,
`MEMORIZE`), and `OZPATCH` to patch the ROM image itself. Two things it settles
that the manual only implies:

- **The utilities are separate `.COM` files, not ROM calls.** Nothing here is
  resident; the ROM supplies the interface and the disk supplies the programs.
  A reproduction does not need to ship this disk to be OZROM-compatible.
- **`CRCKLIST.CRC` is a self-check file** — a name/CRC list, so a 1984 owner could
  verify their copy. It is the vendor's own integrity manifest, and the hashes are
  what a replacement would be checked against (§10.2 has the news: we do not need
  one).


### 10.2 Condition — intact, and the first reading was ours to blame

**Corrected 2026-10-11.** This section previously said the disk was *partially
erased*: "110 of 400 sectors carry data and 290 read back as uniform `0xE5`",
with the holes *inside* file bodies — `CRASH.COM` gone, `READ.ME` missing its
first sector. **That was a tooling artefact, not the disk.** The 290 sectors are
**free space**.

`tools/cpmfs.py`'s `osb1sssd` preset was missing the format's **sector skew**
(`skew 2` — the Osborne SD layout interleaves its ten sectors per track).
Without it, block pointers resolve to the wrong physical sectors: the *directory*
still reads, which is why the file list looked right and the damage looked like
erasure, while every **file body** came back from sectors that had never been
written. `cpmtools`' own `osb1sssd` diskdef carries the skew, and reading the same
image through it returns real content — `CRCKLIST.CRC`, for one, is intact text.

Re-extracted with the correct skew, **all twenty files are whole**: no file holds
an interior run of `0xE5` longer than a handful of bytes (those are ordinary data
bytes), and every size matches the directory. `READ.ME` — reported here as having
lost its first sector — is complete, which the emulated machine confirms by
printing it from the start (§10.2a).

The `0xE5` is still real, and still not a de-skew problem *in the sense §10.4
meant*: the image genuinely holds ~291 sectors of format fill, because that is
what a CP/M formatter writes across a disk. They are **free blocks**, not holes.
The arithmetic agrees: twenty files totalling ~22 KB plus a 64-entry directory
and three system tracks is ~110 sectors of the 400 — exactly the sectors that are
not `0xE5`.

### 10.2a Measured on the machine: the ROM makes no difference

The OZROM ROM and this disk had **never been run together** — every OZROM test
used `52-blank.imd`. Run both ways (`-flop1 52-blank.imd -flop2
OZROM_1E_Utilities.IMD`) with the same commands posted to each:

| | stock ROM | OZROM 1E |
|---|---|---|
| `DIR B:` | 20 files | **the same 20 files** |
| `TYPE B:CRCKLIST.CRC` | the full vendor CRC list | **the same list** |
| `TYPE B:READ.ME` | the TIMER syntax note, from its start | the same |

So the diskette does **not** read differently with the ROM installed. The ROM
supplies the interface and the disk supplies data; nothing in OZROM's disk path
changes what the bytes are. OZROM *does* enable CRC checking on disk access
(§8), but that can only make it stricter, not more permissive.

One behavioural difference is worth knowing, and it is not about reading:
**OZROM's console acts on its control-shift codes `0xF0–0xFC`** — the "process
immediately" set from §7 — so `TYPE`ing a *binary* file such as `CRCKLIST.CRC`
makes OZROM execute whatever codes its bytes happen to contain. Under OZROM the
screen came up with the keyboard-redefinition display after that `TYPE`; the
stock ROM simply prints the bytes.

### 10.3 The boot sector is not vendor code

Track 0 sector 1 holds a stub, and it does not look like anything Micro
Management shipped:

```
C3 5C D2   JP 0D25Ch
...
+20   "PUT THIS ON T0S1"
...
+80   "THIS IS A TEST OF THE AMERICAN BROADCAST NETWORK"
```

"PUT THIS ON T0S1" is an instruction addressed to whoever was writing the disk,
and the Emergency Broadcast System test line is a fill/verification pattern. The
pair reads like a **placeholder written by whoever produced this image**, not
product. Two consequences: treat the boot sector as an imaging artefact rather
than evidence about the product, and expect that this disk cannot be booted to
check anything — that has to be done by copying the files onto a system disk.


### 10.4 A tooling bug this found

`imdinfo.py --raw` appended sectors in the order they appear in the `.imd`, which
equals logical order only when the numbering map is sorted. Single-density
Osborne disks are not: they number `(2,3,…,10,1)`, so **every track came out
rotated by one sector.**

The failure was silent, and that is the part worth remembering. A rotated CP/M
disk still parses — the directory lands somewhere plausible and `cpmfs.py`
returns a file list — it is just the *wrong* list. Here it returned 12 files
instead of 20, with 8 of them carrying another file's blocks. Nothing errors,
nothing looks malformed, and the output is plausible enough to archive.

Fixed in `tools/research/imdinfo.py`; the dump is now byte-identical for sorted
maps (checked against `DRIVE_C.IMD`) and correct for rotated ones. Two archived
images turn out to be rotated and were never convertible before the fix:
`research/diagnostics/DIAG_2.04.IMD` now yields the **15-file Osborne diagnostic
disk** (`DIAG.COM`, `FILETEST.COM`, `DDBIT.COM`, `SETUP.COM`, `SYSGEN.COM`, …),
and `research/source-code/OCCROM.IMD` its 77-track FM/MFM disk.

**A second bug of the same class was found on 2026-10-11, and it did more
damage.** `cpmfs.py`'s `osb1sssd` preset had no **sector skew** for the format it
names, so every SD Osborne *file body* it read came back from the wrong sectors —
which is what made this disk look "partially erased" (§10.2). The lesson repeats:
both bugs produced output that *parsed*, and one of them was believed for a day
because the directory survived and the result looked like physical damage rather
than a misread. **A reader that returns plausible garbage is more dangerous than
one that errors.**

### 10.5 What it changes for #81

Less than the file count suggests, and that is the honest answer: the ROM is the
deliverable and this is the optional companion disk. What it does give us:

- The **complete and authoritative file list** of the utilities — and, as §10.2
  now records, the **complete files themselves**, not a holed copy.
- Confirmation that the utilities are **external programs, not ROM entry
  points**, which bounds the reproduction scope: OZROM compatibility means the
  ROM's jump table and memory map, not this disk.
- A second, independent description of the feature set to hold against the
  manual (§4).

**No longer open, though this section used to say it was:** the hunt for a
complete copy. **#168** was filed to find one and closed the same day — the "290
of 400 sectors erased" that justified it was our own skew bug (§10.2), and the
disk we hold is whole. The one check still not possible is against the vendor's
own manifest: `CRCKLIST.CRC` lists a two-byte CRC per file, and none of the
standard CRC-16 variants tried so far reproduces them, so per-file verification
against the manifest has to wait for someone to identify the algorithm.

## Sources

- `research/roms/OZROM-1E/OZROM_1E.BIN`, `OZROM_1E_Manual.pdf`,
  `OZROM_1E_Manual.ocr.txt` — BrettHallen `Osborne_1`, `ROM/`; OCR per the
  `research/README.md` convention (300 dpi, `tesseract`).
- `research/roms/OZROM-1E/OZROM_1E_Utilities.IMD` — the companion utilities disk
  (§10). Owner-supplied local file, 2026-10-11; source URL not yet recorded.
  ImageDisk 1.19, label `ozrom`, 40 cyl × 10 × 256 B FM.
- `research/source-code/BIOS-144-source/rom144.asm` and the OCC CBIOS modules
  (`occram25.asm`, `occbio15/45/95.asm`) — the stock interface and RAM map the
  jump table and clock cells are compared against.
- `docs/mame-emulation.md` §2/§5, `docs/o1-rom-variants.md`,
  `docs/rt60a-analysis.md` — machine widths, ROM inventory, the clock.

