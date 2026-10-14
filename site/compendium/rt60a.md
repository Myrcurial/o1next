---
layout: page
title: "The RT-60A real-time clock"
subtitle: "Peripherals and storage · partially solved"
draft: "Draft &mdash; assembled from the working notes by `tools/build_book.py`. The source document is the authority; this page is a copy for reading, and it is regenerated from that source."
---

**Status:** Partially solved, and **the contract below is the deliverable** (#7).
The hardware handshake stays a *known unknown* (reopen only if an RT-60A unit or
a good `CLOCK.COM` dump ever turns up); the **memory ABI is settled and is what
[`firmware/rt60a-rtc/`](https://github.com/Myrcurial/o1next/blob/main/firmware/rt60a-rtc/) implements** (#18). See §"The contract" and §"The third
shape: the O1's own clock" — read those two before writing any clock code.

Source: research/rtc/RT-60A_Manual.pdf (JG Communications, Tucson AZ).
The TD0 on bitsavers is a damaged dump (27 bad sectors, extraction
failed); this doc reconstructs the interface from the manual per
user direction: "virtually rebuild from descriptions".

## Hardware

- Plugs into the Osborne 1 **IEEE-488 port** (card-edge), battery
  backed (DL2420/DL2430/CR2320 lithium, ~1 yr), runs standalone.
- Based on **OKI Semiconductor MSM5832 / MSM58321** CMOS RTCs
  (BCD time/date chips, 4-bit bus, address-selected registers).
- **Pass-through**: an output connector + extra circuitry keeps the
  IEEE-488 / Centronics / general-purpose port usable. The clock's
  outputs are normally **high-impedance**; a "special low voltage
  CMOS circuit" recognizes a **unique handshake sequence** from the
  software to activate clock outputs for reading. The handshake is
  designed not to disturb IEEE/Centronics devices.
- Prerequisite: the port must be in **source-handshake mode**
  (Centronics output mode). If not found (or an interrupt hits
  mid-handshake), the read is deferred to the next 1/60 s interrupt.
- Crystal-controlled with a trimcap for speed adjustment.
- Clock reset only by deliberately shorting two vertical pins on the
  board (prompted by CLKSET).
- Bulletin #2 documents a **Drive C modification** — relevant since
  Drive C also uses the IEEE port (6821 PIA bit-bang); protocol clash
  management matters for our interposer coexistence too.

## Host software architecture (CLOCK.COM)

- Installed by changing the boot disk to call **CLOCK.COM instead of
  AUTOST.COM** on both cold and warm boot; OS relocated **1 KB lower**
  to make room for resident clock code above the BIOS.
- Hooks the **interrupt vector word at 0xEFF8** (O1 60 Hz interrupt;
  CTC-driven). Each tick decrements MEMBUFF from 60; at 1 it reads
  the clock (~once/second), translates time to binary + ASCII, stores
  in registers, chains to the original handler.
- **Phantom Display**: on-screen clock updated every 60th via Z80
  block-transfer screen sensing (costs ~15% CPU).
- **At Trap**: patches the BIOS **LIST output jump**; intercepts `@T`
  / `@D` in printer output and expands to time/date (char after
  @T/@D must be space or CR).
- File time/date stamping patches installed at boot (BDOS-level).
- Warm-boot reload needed for stamping patches; 1.4x ROM can bypass
  (bulletin #7).

## Software-visible register map (offset from pointer at 0x0040)

Pointer word at **0x0040** points to DAY; add offsets (hex offsets
shown relative to the pointer):

| Offset | Name       | Contents |
|--------|------------|----------|
| -15 (FFF1 rel) | FLAGS   | bit0: phantom on; bits3,4: at-trap use; bit5: at-trap on; bit7: software off |
| -14 (FFF2) | TIMEFLAG    | bit0: 0=12h/1=24h; bit1: 1=AM/PM off; bit2: 1=seconds suppressed |
| -13 (FFF3) | DATE (7 B)  | YYMMDD, DOW order; bit2 of 10s-of-days = leap year. **Only always-current date rep** |
| -6  (FFFA) | TIME (6 B)  | raw BCD unpacked 12-hour, HHMMSS; bit2 of first byte: 1=PM. Raw from clock chip |
|  0 (0000)  | DAY         | binary day (SD: FF/BB = invalid) |
|  1 | MONTH               | binary |
|  2 | YEAR                | binary (0x53 = 1983) |
|  3 | HOURS               | binary, 24 h, 0 = midnight |
|  4 | MINUTES             | binary |
|  5 | SECONDS             | binary |
|  6 | MEMBUFF             | 60→1 decrementer; sticks at 1 when reads failing (port not in output mode etc.) |
|  7 | TIMEASCII           | NUL-terminated ASCII time string (chosen format) |
| 19 (0013)  | DATEASCII   | NUL-terminated date string |

## The contract — what an RT-60A-compatible time service must publish (#7)

This is the *specification*, promoted out of the analysis above. It is what
[`firmware/rt60a-rtc/`](https://github.com/Myrcurial/o1next/blob/main/firmware/rt60a-rtc/) (the resident publisher, #18) and the interposer (#12) must
agree on. The rule that makes it implementable is the one sentence that decided
#7: **the RT-60A does not put the time anywhere in memory — `CLOCK.COM` does.**
The hardware is read-only; the ABI is software. So we build the *publisher*, not
the *chip*.

**The pointer.** A word at **`0x0040`** holds the address of the block. It is the
only fixed address; everything else is an offset from the pointer.

**The block** (offsets from the pointer, negative offsets below the pointer):

| Off | Len | Field | Encoding |
|---|---|---|---|
| −15 | 1 | `FLAGS` | bit0 phantom display; bit3/4 At-Trap use; bit5 At-Trap on; bit7 software off |
| −14 | 1 | `TIMEFLAG` | bit0 `0`=12 h / `1`=24 h; bit1 `1`=AM/PM off; bit2 `1`=seconds suppressed |
| −13 | 7 | `DATE` | `YYMMDD`+DOW, BCD; bit2 of tens-of-days = leap year. **The only always-current date** |
| −6 | 6 | `TIME` | raw BCD `HHMMSS`, 12-hour; bit2 of the first byte = PM. Straight from the chip |
| 0 | 1 | `DAY` | binary |
| 1 | 1 | `MONTH` | binary |
| 2 | 1 | `YEAR` | binary (`0x53` = 1983) |
| 3 | 1 | `HOURS` | binary, 24 h, `0` = midnight |
| 4 | 1 | `MINUTES` | binary |
| 5 | 1 | `SECONDS` | binary |
| 6 | 1 | `MEMBUFF` | 60→1 decrementer; sticks at 1 when reads fail |
| 7 | 12 | `TIMEASCII` | NUL-terminated ASCII time string, chosen format |
| 19 | 12 | `DATEASCII` | NUL-terminated ASCII date string |

**The cadence.** `CLOCK.COM` hooks the interrupt vector **word at `0xEFF8`** and
decrements `MEMBUFF` once per 60 Hz tick; at 1 it reads the clock (~1/second),
translates to binary + ASCII and refills the block, then chains to the handler it
replaced. `0xEFF8` is the stock ROM's keyboard-interrupt vector:
`INTBL = 0xEFF0` and the ROM sets `INTBL+(4*2)` (`rom144.asm` line 235) — so the
vector slot is `INTBL` entry 4, and a replacement publisher must save and chain,
not simply overwrite.

### Sentinel and invalidation rules (the "no clock" vs "clock stopped" question)

These are the rules a reader must be able to rely on — #7 asked for them
explicitly, and they are what distinguishes the three states:

| State | How a reader tells | What a reader must do |
|---|---|---|
| **No clock software installed** | pointer word at `0x0040` is `0xFF` or `0xBB` | treat time as unavailable; do not POKE `0x0040` yourself |
| **Clock software installed, reads failing** | pointer is valid but `MEMBUFF` has stuck at 1 for more than ~2 ticks | time is *stale* — show it, do not trust it for stamping |
| **Clock running** | valid pointer and `MEMBUFF` decrementing | `DAY`…`SECONDS` and `DATE`/`TIME` are current |

`MEMBUFF` is therefore not just a countdown: **it is the health signal.** A
publisher that cannot read the clock must leave `MEMBUFF` at 1 (the documented
behaviour) rather than let it run free, so that a reader can distinguish "no
clock" from "clock stopped". `DATE` at −13 is the one field the manual calls
always-current even when the clock read is deferred, so it is the field to trust
when `MEMBUFF` is stuck.

**What this buys.** Any software written against the documented RT-60A ABI —
`CLOCK.COM`'s consumers, the `@T`/`@D` At Trap, the BDOS file-stamp patches —
works unchanged against our publisher. What we deliberately do **not** reproduce
is the undocumented IEEE-488 wake-up handshake, which buys nothing because the
only thing that speaks it is `CLOCK.COM` itself.

## Conditions that block clock reads (from HELP)

1. Disabled interrupts; 2. peripherals off/off-line; 3. port set as
   input for extended periods; 4. DAV/ATN held low; 5. printer status
   lines wired to NRFD (IEEE pin 13) — Centronics cables should have
   **no connections on pins 13 and 21**; 6. long periods not in IEEE
   source-handshake mode / long data transfers.

## WordStar WSMODS patch (DD systems)

UCNSTA JMP → 0DD06H, INCON JMP → 0DD09H, third JMP → 0DD0CH
(SD: 0E106H/0E109H/0E10CH; original DD values 0E506H/0E509H/0E50CH).

## Prior art: a *software* date facility, before the RT-60A (#18, #28)

Before any clock hardware, the machine's users kept the date in **page zero**.
"**Dating your computer — a system's date facility**" by **Walter B. Novinger**,
*The Portable Companion* #7 (June 1983, PDF pp. 50–51 = printed 48–49; extract
[`research/technical-articles/TPC-Issue07-1983-pp50-51-dating-your-computer-date-in-memory.pdf`](https://github.com/Myrcurial/o1next/blob/main/research/technical-articles/TPC-Issue07-1983-pp50-51-dating-your-computer-date-in-memory.pdf)),
describes a three-part scheme:

- **`DATE.BAS`** prompts `MMDDYY` at boot, validates month/day/year, and pokes the
  date into **`0050H–005BH`** — a **12-byte block the *Osborne 1 User's Guide*
  "Memory Allocation" chart (p. R-243) marks "not used"**. It is written twice
  over so a reader can take either form: **binary** (`POKE 80,D`, `POKE 81,M`,
  `POKE 91,Y`) and an **ASCII month name** at `82H`–`8AH`. `DATE.BAS` then `NEW`s
  itself, leaving BASIC pristine.
- **`GETDATE`** is a BASIC subroutine that reads the block back (`PEEK(80)` …
  `PEEK(91)`) — no machine code, no `CALL`/`USR`.
- **`AUTOST.COM`** is modified (per the User's Guide ch. 8 listing) so boot runs
  `MBASIC DATE`: `LXI B,10` → `LXI B,13` (command longer than 8 characters, so
  `length + 2`) and the command string becomes `'MBASIC DATE',0`.

The buffer survives a **warm start (RESET) and diskette swaps** but **not
power-off** — the same "no hardware, so it dies with the power" limitation the
RT-60A exists to fix. That is why it is the right prior art for #18: it is what a
user did *before* buying a clock, and it fixes the **page-zero ABI** that any
emulated date must not disturb. `0050H–005BH` is also worth remembering as a
**free 12-byte scratch block** for the interposer (#12) — see
[`docs/o1-memory-io-map.md`](https://github.com/Myrcurial/o1next/blob/main/docs/o1-memory-io-map.md) §2.

## The third shape: the O1's *own* clock, and what OZROM 1E does with it (#81)

#7's stated worry was "read the OZROM manual before we fix our own ABI, so we do
not invent a third shape". Reading it — and the OCC source — turned up something
better than a warning: **the Osborne 1 already has a native software clock, and
OZROM did not invent an ABI either; it adopted the O1's own reserved cells.**
There is no third *invention*; there is a third *convention*, and it predates
both third-party products.

### The machine already ticks a clock — `UPTIM`

The stock ROM's 60 Hz keyboard interrupt handler calls `UPTIM`, which keeps the
time as BCD and handles the bell and disk-active countdown:

```asm
GKEY:                       ; rom 1.3 source, BMKEY.ASM
    CALL UPTIM              ;UPDATE SYSTEM CLOCK
UPTIM:
    ;Update time via 60hz interrupt
    ;  Time is kept as hhmmss (3 locations)
    ...
    DEC [hl]                ; HL => SEC6  (sixtieths)
    RNZ                     ; if not 1 sec transition
    STO 59,[hl]             ; 60th tick is NOW
    XOR A                   ; A:=0, CY:=0 for DAA
    DEC HL                  ; HL => SECS
    LD A,[hl] ! INC A ! DAA ! STO A,[hl]
    CMP 60h
    RC                      ; if not 60 secs
    STO 0,[hl]
    DEC HL                  ; HL => MINS
    ...
    CMP 25h                 ; 24-hour wrap
```

Measured two ways, and they agree:

- the increment code walks **`SEC6 → SECS → MINS → HOURS`**, so the cells run
  downward in address from `SEC6`; and
- the CBIOS RAM map (`occram25.asm`) places them with
  `HOURS: DS 6 / MINS=HOURS+1 / SECS=HOURS+2 / SEC6=HOURS+3`, and its
  `DACTVE = HOURS+4`, `BELCNT = HOURS+5` match the ROM's own absolutes
  `DACTVE = 0EF6AH`, `BELCNT = 0EF6BH` (`rom144.asm` lines 128–129).

So the addresses are fixed:

| Cell | Address | Meaning |
|---|---|---|
| `IDAY` / `IMONTH` / `IYR` | `EF63` / `EF64` / `EF65` | calendar date, binary |
| `HOURS` | **`EF66`** | hours, 2-digit BCD |
| `MINS` | **`EF67`** | minutes, 2-digit BCD |
| `SECS` | **`EF68`** | seconds, 2-digit BCD |
| `SEC6` | **`EF69`** | sixtieths, 2-digit BCD |
| `DACTVE` | `EF6A` | disk-active countdown (ticked by the same routine) |
| `BELCNT` | `EF6B` | bell countdown |

The clock **starts at midnight on every boot** (the ROM clears `EF00–EFEF`),
nothing in the stock machine *sets* it, and nothing displays it. It is a
running counter with no reader and no setter — which is precisely why both
third parties built on top of it rather than beside it.

One caveat, stated honestly: the ROM 1.3 source's `UPTIM` comment says the time
is "kept in video memory", which is inconsistent with the address map (video is
`F000`+, the clock is `EF66`+). The addresses are confirmed by two independent
files, so the comment is stale, not the map. **ROM 1.44's source does not tick
the clock**: its `GKEY` was rewritten ("fixed bell bug", `rom144.asm` line 16)
and now handles the bell and `DACTVE` but no longer decrements `SEC6`, and the
file contains no `SEC6`/`UPTIM` reference at all. So under a 1.44 machine the
`EF66–EF69` cells are *reserved but not ticked*.

### OZROM 1E adopts those cells and adds the setter, the display and the hook

OZROM's documented memory map (manual Appendix C-5) is the same cells, named:

| OZROM's name | Address | = the O1 cell |
|---|---|---|
| Start of system clock — hours, 2-digit BCD | `EF66` | `HOURS` |
| Minutes, 2-digit BCD | `EF67` | `MINS` |
| Seconds, 2-digit BCD | `EF68` | `SECS` |
| Sixtieths of a second, 2-digit BCD | `EF69` | `SEC6` |

and it adds `EFDF` (time-display toggle), `EFE8` (clock position on the first two
display lines), and its own interrupt hook at **`EFF2–EFF4`** (preset to `RET`,
`0C9h`) with 192 bytes of interrupt-routine RAM at `FCC0–FD7F`. OZROM's `TIME`
sets the clock, ctrl-shift-T shows it, and `ALARM`/`TIMER`/`QUIKTIME` ride the
hook. **So OZROM's "time-of-day clock" is the machine's own `EF66–EF69`, finally
given a setter and a reader.** Its hook is *not* the RT-60A's `0xEFF8`: it is a
fixed call OZROM's own `SYSINT` makes with registers already saved, at `EFF2`,
which is a different `INTBL` slot and a different calling convention. Full map:
[`docs/ozrom-1e.md`](https://github.com/Myrcurial/o1next/blob/main/docs/ozrom-1e.md).

### What this means for our ABI (the #7 decision)

Three conventions now, and they do not conflict:

| Convention | Cells | Who reads it |
|---|---|---|
| **RT-60A / `CLOCK.COM`** | pointer at `0x0040` → binary `DAY…SECONDS` + ASCII + `MEMBUFF` | software written to the documented RT-60A ABI |
| **O1 native / OZROM** | fixed BCD `EF66–EF69` (+ `EF63–EF65` date) | OZROM's display/`ALARM`/`TIMER`, and anything that reads the machine's clock cells |
| *(ours)* | **both**, published together | whichever the software expects |

The cheap, correct move is that our resident publisher **maintains the native
`EF66–EF69` cells as well as the `0x0040` block**. They are four bytes apart in
effort and they make our clock visible to OZROM-style readers *and* to RT-60A
software, without inventing anything. That is the whole of the "third shape"
question: not a new ABI, but two existing ones kept in step.

- We can emulate the RT-60A faithfully WITHOUT its exact hardware
  handshake: implement the MSM5832 register semantics and the 0x40
  pointer ABI, plus the IEEE-port handshake activation observed at
  the PIO lines. For software compatibility, matching the **memory
  ABI + interrupt cadence + At Trap/BIOS hooks** matters more than
  the internal CMOS circuitry.
- MSM5832 register set (from datasheet, 4-bit regs): sec 1/10, min
  1/10, hr 1/10 (with AM/PM + 12/24), day-of-week, day 1/10, month
  1/10, year 1/10 — matches the BCD layouts above.
- Drive C coexistence: both devices live on the same IEEE port; the
  interposer can present BOTH virtual devices with proper arbitration
  (Drive C's 6821 bit-bang vs clock handshake) — worth an
  interference test in #29.
