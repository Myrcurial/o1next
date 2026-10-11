---
layout: page
title: "OZROM 1E: a third-party monitor ROM"
subtitle: "The machine"
draft: "Draft &mdash; assembled from the working notes by `tools/build_book.py`. The source document is the authority; this page is a copy for reading, and it is regenerated from that source."
---

**Status:** Solved, as tooling. It boots under MAME on all three Osborne 1
machines (measured, §3), its 58-page manual is OCR'd and indexed here (§4–§8),
and its three engineering features — a software 52/80/104-column switch, a
chip-level memory tester and a *documented* ROM interface — are available to us
without hardware. One test is still not run: driving the ctrl-shift column keys
from the harness (§9).

**Source:** [`research/roms/OZROM-1E/OZROM_1E.BIN`](https://github.com/Myrcurial/o1nextgen/blob/main/research/roms/OZROM-1E/OZROM_1E.BIN) (4096 bytes) and
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
duplicate of `7a3007-00.ud15` ([`docs/o1-rom-variants.md`](https://github.com/Myrcurial/o1nextgen/blob/main/docs/o1-rom-variants.md)), and it is what makes
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
| **System memory tester** that names the failing chip | A ready-made second oracle for #29, alongside [`tools/check_o1_map.sh`](https://github.com/Myrcurial/o1nextgen/blob/main/tools/check_o1_map.sh). |
| **Software-redefinable keyboard**, plus eight locally-redefinable function keys (up to 63 chars) | Relevant to #45/#47. |
| **Time-of-day clock** (`TIME`, `ALARM`, `TIMER`, `QUIKTIME`) | #7/#18 — see §8 and [`docs/rt60a-analysis.md`](https://github.com/Myrcurial/o1nextgen/blob/main/docs/rt60a-analysis.md) "The third shape". |
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
source in [`docs/rt60a-analysis.md`](https://github.com/Myrcurial/o1nextgen/blob/main/docs/rt60a-analysis.md).

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
harness to post a *modifier-qualified* keystroke ([`tools/research/mame-boot-probe.lua`](https://github.com/Myrcurial/o1nextgen/blob/main/tools/research/mame-boot-probe.lua)
only posts plain characters), and the column keys' effect under MAME depends on
whether the driver models the width as a PIA-driven horizontal offset or as fixed
hardware. It is the one open item from #81 that needs code rather than reading —
see §9.

## 8. The clock, the memory tester, and the error codes

**Time-of-day clock.** OZROM's `TIME HHMMSS` sets it, ctrl-shift-T shows it (top
two display lines, position set by `EFE8`), and `ALARM`/`TIMER`/`QUIKTIME` ride
the interrupt hook. Its cells are the machine's own `EF66–EF69` (hours, minutes,
seconds, sixtieths, BCD) — **not** a new ABI. Accuracy is "better than three
minutes a day" with the drives idle; disk access momentarily stops the clock
(the manual is explicit that the clock "has no guarantee" under disk load). The
full treatment, and why it matters to our own clock contract, is in
[`docs/rt60a-analysis.md`](https://github.com/Myrcurial/o1nextgen/blob/main/docs/rt60a-analysis.md) "The third shape".

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

## 9. What is left from #81

- **Drive the column switch from the harness** (§7) — the one measurement still
  missing. Needs modifier-aware key injection.
- **Diff the jump table against `rom144.asm`** entry by entry (§6 vs
  [`docs/o1-rom-source.md`](https://github.com/Myrcurial/o1nextgen/blob/main/docs/o1-rom-source.md)). The tables are the same shape; a disagreement would
  be a finding.
- **Reconcile the `EF66–EF69` clock against ROM 1.44**, whose source no longer
  ticks the cells (`rt60a-analysis.md`). Which ROM revision dropped `UPTIM`, and
  did any shipped 1.4x keep it?

## Sources

- [`research/roms/OZROM-1E/OZROM_1E.BIN`](https://github.com/Myrcurial/o1nextgen/blob/main/research/roms/OZROM-1E/OZROM_1E.BIN), `OZROM_1E_Manual.pdf`,
  `OZROM_1E_Manual.ocr.txt` — BrettHallen `Osborne_1`, `ROM/`; OCR per the
  [`research/README.md`](https://github.com/Myrcurial/o1nextgen/blob/main/research/README.md) convention (300 dpi, `tesseract`).
- [`research/source-code/BIOS-144-source/rom144.asm`](https://github.com/Myrcurial/o1nextgen/blob/main/research/source-code/BIOS-144-source/rom144.asm) and the OCC CBIOS modules
  (`occram25.asm`, `occbio15/45/95.asm`) — the stock interface and RAM map the
  jump table and clock cells are compared against.
- [`docs/mame-emulation.md`](https://github.com/Myrcurial/o1nextgen/blob/main/docs/mame-emulation.md) §2/§5, [`docs/o1-rom-variants.md`](https://github.com/Myrcurial/o1nextgen/blob/main/docs/o1-rom-variants.md),
  [`docs/rt60a-analysis.md`](https://github.com/Myrcurial/o1nextgen/blob/main/docs/rt60a-analysis.md) — machine widths, ROM inventory, the clock.
