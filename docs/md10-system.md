# The MD-10's operating system, and the memory map that was missing (#179, #178)

**Status: solved — the system boots to a prompt, with three partitions
(2026-10-14).** The three-partition PYXIS27 drive of §3 was produced and booted:
`A0>`, `B0>`, `C0>`, and a file written to `C:` and read back off it. That layout
is the **floor pin** — it is the only one whose partitions match the driver's
shared DPB (§9) — and it is what `tools/research/md10drive.py --layout md20`
builds. The two-partition PYXIS13 drive the earlier sessions used boots
`A0>`/`B0>` but is **not safe to write to** (§9).

`PREP.COM`'s option 3 configures an operating system onto the drive; `HARD.COM`
then boots it from the emulated hard disk: it installs the MD-10 BIOS at
`0xD800`, reads the system from **LBA 5, 11 blocks** into `0xC200`, patches page
zero, and CP/M runs. The image is the vendor's own tool's output, not
synthesised.

The last inch was a **re-relocation**. The image `PREP.COM` wrote has its
addresses **0x100 bytes above the address `HARD.COM` loads it at**, so its CCP
jumped into the middle of an instruction, ran garbage and warm-booted for ever —
which is what "boots but never reaches its prompt" (#198) actually was. §7 is the
measurement; `tools/research/md10reloc.py` is the fix.

This note also closes the question the hard-disk research left open twice over —
**the MD-10's memory map**, and with it the meaning of the low-RAM block at
`0x0559`–`0x055D` that `docs/acb4000-host-adapter.md` §4 and
`docs/harddisk-decision.md` §7.3 recorded as *written by nothing in the archive*.

Serves #179 (the personality's acceptance), #178 (the DPB residue) and #191 (the
harness that made it measurable). Reads alongside `docs/acb4000-firmware.md`,
`docs/acb4000-host-adapter.md`, `docs/osborne1nx-machine.md` and
`docs/harddisk-decision.md` §7.

## 1. Why there was no system image, and where it came from

The archive holds the **driver** (`research/adaptec/*.img`) and, on the 2.01
utilities disk, the **installer** — but no *system*. The conclusion recorded in
`docs/harddisk-decision.md` §7.3 was that the values are not in the files:
nothing initialises the low-RAM tables at `0x055E`/`0x056E`, and the utilities
disk is a data disk whose system tracks are all `0xE5`.

That is still true, and it is why reading was never going to work. What was
missing was the observation that `PREP.COM` does not merely *format* a drive — it
**installs an operating system on one**:

```
     Main function menu:
          (1) - Initialize, check, and partition disk drive
          (2) - Drive table display and edit
          (3) - Configure operating system
```

and option 3, given an O/S partition, reports:

```
Relocating operating system...
Writing operating system...
Operating system configuration complete
```

So the system was not synthesised. It was **produced by the 1984 toolset** on the
emulated interposer, and then read off the drive. `research/adaptec/md10-system/`
holds both captures; `tools/research/md10drive.py --layout md20` (or `md10`) lays
one onto a fresh drive, and `md10table.py` reads one back.

## 2. The recipe

**For a new geometry, use `tools/research/md10prep.sh`** — it is this recipe,
scripted and parameterised (`md10prep.sh 321,8,18 3 /tmp/md10` builds the PYXIS27
floor-pin drive), and it reads the drive back and reports the O/S's relocation
base for you. What follows is the same session by hand, which is what both
captures were made with, and it is worth reading for the three traps below.

Four menu steps, in this order, and the order is load-bearing.

```sh
# 1. a labelled drive to configure
tools/research/mkdrive.py --out /tmp/md10/hd.chd --label MD10SYS

# 2. wrap the 2.01 utilities disk for MAME (it is a bare raw image)
tools/research/o1raw2imd.py \
  'research/adaptec/Osborne Hard Disk Control Software Version 2.01 (1984).img' \
  /tmp/md10/prep.imd

# 3. drive PREP.COM: option 1 -> drive address -> the initialization menu,
#    then option 5 (label), option 4 (partition, "Two logical drives (MD-10)"),
#    then option 3 from the main menu (configure the operating system).
#    /tmp/md10/keys.txt is the o1keys.lua directive script:
#      wait A> / type PREP / wait Main function / key 1 / wait drive address /
#      key cr / wait Disk initialization menu / key 5 / wait disk label /
#      type MD10SYS / sleep 3 / key 4 / wait Partition definition menu / key 1 /
#      sleep 8 / key esc / sleep 2 / key 3 / wait drive address / key cr /
#      sleep 60
cd /tmp/md10 && O1_MACHINE=osborne1nx O1_FLOP1=/tmp/md10/prep.imd \
  O1_KEYS="$(cat /tmp/md10/keys.txt)" SDL_VIDEODRIVER=dummy \
  /path/to/osborne1nx osborne1nx -flop1 /tmp/md10/prep.imd -hard /tmp/md10/hd.chd \
  -video none -sound none -nothrottle \
  -autoboot_script tools/research/o1keys.lua -seconds_to_run 300 \
  -rompath tools/emulator-setup/roms

# 4. read the result back
chdman extracthd -i /tmp/md10/hd.chd -o /tmp/md10/hd.raw -f
```

Three things about that, all measured:

1. **The label has to be written before the partition.** Option 5 ("Change disk
   label") builds the label *and* terminates the partition table at label+48
   with `FFh`. Do the partition first — as this session's first attempt did — and
   the walker at `0x23E6` runs off the end of the table, which is the failure
   `docs/osborne1nx-machine.md` §6 records as *"Initializing all partitions..."*
   walking `E5h` over the whole drive.
2. **Option 3 needs an O/S partition.** Without one it answers, exactly, *"No
   O/S partition"* and returns to the menu. That is what makes the order
   mandatory rather than tidy.
3. **The format step is not needed.** A drive built by `mkdrive.py` is already
   the `6Ch` fill the controller's `FORMAT` writes, so options 1/2/3 of the
   *initialization* menu — the ones that need the `2F` verify pass — can be
   skipped entirely. `PREP.COM`'s own partition initialiser writes the `E5h`
   directories it needs.

## 3. What the drive ends up carrying

Measured off the configured drive (`chdman extracthd`, then a scan for non-`6C`
blocks):

| Region | What |
|---|---|
| LBA 0 | the disk label: `M`,`D` at +0, the label text at +14, the **partition table** from +48 — 28-byte records, walked at `0x23E6` with `ADD IX,1Ch` and stopped by a first byte of `FFh` |
| LBA 1–3 | the rest of the four-block header (`docs/osborne1nx-machine.md` §6) |
| LBA 4 | a table |
| **LBA 5–15** | **the operating system — 11 blocks, `0x1600` bytes** |
| LBA 20–83 | `E5h` — the first 64 blocks of the `CP/M-A` partition: CP/M's empty directory |
| LBA 11564–11627 | `E5h` — the same for `CP/M-B`, *PYXIS13 layout* |
| LBA 15419–15482 | `E5h` — the same for `CP/M-B`, *PYXIS27 layout* |
| LBA 30818–30881 | `E5h` — the same for `CP/M-C`, *PYXIS27 layout* |
| everything else | the `6Ch` fill |

The partition table, decoded — each 28-byte record is a flag byte, a
little-endian 24-bit start at +1, a little-endian 16-bit length in 512-byte
blocks at +4, ten bytes, then the name at +16. **The size the installer picks is
a function of the drive it was given**, and two layouts are captured:

**PYXIS13** — main menu option 1, then *Disk initialization* option 5 (label),
option 4 (partition), option 1 *"Two logical drives (MD-10)"* — the original
capture:

| Record | Name | Start (LBA) | Blocks |
|---|---|---|---|
| 0 | `CP/M-CCP` | 4 | 16 |
| 1 | `CP/M-A` | 20 | 11544 |
| 2 | `CP/M-B` | 11564 | 11544 |
| 3 | — | — | terminator (`FFh`) |

**PYXIS27** — the same walk with partition option **2**, *"Three logical drives
(MD-20)"* — **the floor pin**, captured 2026-10-14:

| Record | Name | Start (LBA) | Blocks |
|---|---|---|---|
| 0 | `CP/M-CCP` | 4 | 16 |
| 1 | `CP/M-A` | 20 | **15399** |
| 2 | `CP/M-B` | 15419 | **15399** |
| 3 | `CP/M-C` | 30818 | **15399** |
| 4 | — | — | terminator (`FFh`) |

Three 15399-block partitions at `20`, `15419`, `30818` **is the driver's own
static fallback table** (§9) — so the vendor's installer and the vendor's driver
agree exactly, which is what makes this the layout to build rather than merely a
convenient one. `tools/research/md10table.py` prints either table from a raw
image or a CHD; `tools/research/md10prep.sh` produces one for a new geometry.

`CP/M-CCP` is the **O/S partition** option 3 insists on: sixteen blocks at LBA 4,
and the operating system sits at LBA 5 — block 1 of that partition. The MD-10's
two *logical drives* are `CP/M-A` and `CP/M-B`, which tile `20 … 23107`, the whole
PYXIS13 drive bar the header. They are the `A0>` and `B0>` of §7.

An earlier revision of this section had the records shifted by one — it read
`CP/M-CCP` as the 11544-block record and dropped the 16-block O/S partition — and
had the field offsets wrong, which put the start at +13 and the length at +16.
The record *is* 28 bytes and *is* walked at `0x23E6` with `ADD IX,1Ch`; the walk
stops on the `FFh` first byte, which is record 3.

**LBA 4 is the runtime half of §9's table.** It is not an anonymous "table": it
mirrors the partition geometry and then the **per-drive type bytes** the driver
indexes —

```
10 00 00 | 14 00 00 | 18 2d 00 00 | 00 2c 2d 00 | 18 2d 00 | 80 00 … | 81 00 …
16       | 20       | 11544       | 11564       | 11544    | type 0   | type 1
```

— so the drive, not the BIOS, carries the values the driver's `SELDSK` reads at
run time. Who copies them into `0xDD5E`/`0xDD6E` is not yet chased; the login
completes without it (§7), so it is not load-bearing for the boot.

`tools/research/md10drive.py` reproduces the captured drive **byte for byte**
from the two artifacts, and that is the check that the capture is complete: the
partitions are the `E5h` fill and everything else is the `6Ch` fill, so LBA 0–15
is all that has to be carried.

## 4. The MD-10's memory map

This is the thing `docs/harddisk-decision.md` §7.3 and
`docs/acb4000-host-adapter.md` §3–§4 both stopped short of. It is read out of
`HARD.COM`, which turns out to be **two programs in one file**: a loader at
`0x0100`–`0x0539` and, at `0x053A`–`0x0AFF`, a **relocated copy of the MD-10
BIOS** — whose jump table is the first thing in it, at `0x0540`.

| Region | Address | How it is known |
|---|---|---|
| **CCP** | `0xC200` | `HARD.COM` `0x05C0` `LD HL,0C200h`; the system read lands here and `0xC200` holds the CCP's own header |
| **BDOS** | `0xCA00`, entry `0xCA06` | page zero+5 is patched to `JP 0CA06h`, and `0xCA00` is `0x806` into the system image — the stock `CCP+806h` relationship |
| **MD-10 BIOS** | `0xD800`, 0x5C5 bytes | `HARD.COM` `0x01E8` `LD DE,0D800h`; the jump table is at `0xD800` itself |
| stack | `0xC200`, growing down | the BIOS's `BOOT` does `LD HL,0C200h / LD SP,HL` |

and the BIOS's own data, all at **base + offset**:

| What | Offset | Address |
|---|---|---|
| the card parameter block | `+0x559` | `0xDD59` — select byte, LBA, count |
| the card's CDB | `+0x1FA` | `0xD9FA` |
| the transaction routine | `+0x185` | `0xD985` |
| `BOOT` / `WBOOT` | `+0x082` / `+0x086` | `0xD882` / `0xD886` |

`HARDBIOS.SPR`'s own jump table sits `0x100` into the file and its operands are
offsets from the load base — which is why `tools/research/hardbios.py`'s reading
of it needs `0x100` added and `HARD.COM`'s embedded copy does not: the `.SPR`
carries a `0x100` header, the embedded copy does not.


## 5. The boot chain, step by step

Read out of `HARD.COM` and **confirmed in the running guest** by peeking memory
after each stage.

1. **The loader** (`0x0100`) prints its banner, runs the presence probe at
   `0x02E6` (the same four-register sequence `docs/acb4000-host-adapter.md` §1
   records) and leaves the card *selected*.
2. It issues **TEST UNIT READY** through the transaction core at `0x023A`.
3. It copies **`0x053A` → `0xD800`**, `(0x0547)` bytes. That length is read out
   of `HARD.COM`'s own embedded jump table — it is the `0x05C5` in the `JP` at
   `0x0546` — so the copy is `0x053A…0x0AFF`, the whole embedded BIOS.
4. It **patches the installed BIOS from the *running* BIOS**: 18 bytes from
   `(page zero+1)+3` to `0xD806`, then 21 to `0xD86A`, 3 to `0xD82D`, 3 to
   `0xD87F`, 45 to `0xD833`. Page zero+1 before the run is `0xEFC1` — the ROM's
   jump table — so what lands in the MD-10 BIOS's `CONST`/`CONIN`/`CONOUT`/… is
   the **ROM's** console routines. The MD-10 BIOS is a partial BIOS: its own disk
   routines plus the machine's console and floppy, which is why it is only
   `0x5C5` bytes.
5. It patches page zero and jumps to `0xD800` → the BIOS's `BOOT`.
6. **`BOOT`** (`0xD882`) sets `SP = 0xC200`, copies the parameter block
   `0xDD59…0xDD5D` into the card's CDB at `0xD9FB…0xD9FE`, and issues a **READ
   into `0xC200`**, looping until it succeeds.
7. It patches page zero to `JP 0D803h` (WBOOT) and `JP 0CA06h` (BDOS) and jumps
   to the **CCP at `0xC200`**.
8. Every **warm boot** re-enters at `0xD886` — four bytes into the same routine —
   so the system is re-read from the drive on every warm boot. That is the MD-10's
   design, not a bug.

Measured after the hand-off, on a run that reached the CCP:

```
page zero   c3 03 d8 40 00 c3 06 ca      JP 0D803h, IOBYTE 40h, drive 0, JP 0CA06h
0xD800      c3 82 d8 c3 86 d8 c3 2e e7 … the BIOS jump table, console -> the ROM
0xC200      c3 c8 c5 c3 c4 c5 7f 00 …    the CCP, as the drive supplied it
0xDD59      01 05 00 00 0b 00            select 01, LBA 5, count 11
0xD9FA      08 00 00 05 0b 00            CDB: READ, LBA 5, 11 blocks
```

**Correction (2026-10-14, #247): page zero+1 is `0E103H`, and the source is the
CBIOS — not `0EFC1H`, and not the ROM's jump table.** The dump just above is the
evidence: `0xD806` is `C3 2E E7`, and `C3 2E E7` is the CBIOS's vector 2, whose
slot is at `0E106H` (`0E103H` holds `C3 13 E5`). The CBIOS writes page zero
itself, as `JP BIOS+3` = `0E103H` (`occbio55.asm`, `BCCP`). `0EFC1H` is not a table
at all: it is `ROMSTK`, the monitor's stack top (`rom144.asm`), and it is what a
read of `0001H` returns **while the ROM is mapped** — the operand of the monitor's
own `LD SP,0EFC1H`. That is the bank-2 trap ROM 2.0's `HCBOOT` has to work around
(`docs/o1-rom-2.0.md` §4.6): in bank 2 the monitor cannot read or write page zero.

## 6. `0x0559`–`0x055D` is not an unwritten block (#178)

`docs/acb4000-host-adapter.md` §4 and `docs/harddisk-decision.md` §7.3 both
record the same negative result: the MD-10 BIOS's `BOOT` reads a five-byte block
at `0x0559`–`0x055D` and **nothing in the archive writes it**, which is one of
the reasons a system image was thought to be unobtainable.

It is not unwritten. It is **inside the BIOS image**, at base + `0x559`:

| Address | `HARD.COM` file offset | Value | Meaning |
|---|---|---|---|
| `0xDD59` | `0x0993` | `01` | the card's select byte — "controller 01" |
| `0xDD5A`–`0xDD5B` | `0x0994` | `05 00` | the LBA, little-endian → **5** |
| `0xDD5C` | `0x0996` | `00` | the CDB's byte 1 |
| `0xDD5D` | `0x0997` | `0B` | the block count → **11** |

`BOOT` copies them into the CDB, and that is the whole of it — the "unwritten
block" is a *constant in the driver*, not a run-time table. The search that
concluded otherwise was looking for a writer of `0x0559` in low RAM; what it
needed was `0xD800 + 0x559`, and a file offset `0x0993` in `HARD.COM`.

The two numbers also confirm the shape the documentation already asserted: the
system is at **LBA 5**, **11 blocks**, and `0x1600` bytes is exactly the
`CCP`+`BDOS` of the O1 layout.


## 7. What boots, and what does not

**Boots.** With the captured drive in `-hard`, `HARD.COM` from the 2.01 disk runs
its whole chain: the probe answers, the BIOS is installed at `0xD800`, the system
is read from **LBA 5** into `0xC200`, page zero is patched, and the guest then
executes **CP/M out of the MD-10 BIOS**, doing block reads into CP/M's own
buffers (`0xCA1D`, `0xD689`, `0xCCA7`, `0xC7CE`, `0xD3F8`) through the
transaction routine at `0xD985`. The drive's bytes are confirmed in memory: at
`t = 240` emulated seconds `0xCA00` held the image's `03 16 03 00 15 2e c3 11 cb
…` byte for byte. A drive rebuilt from the artifacts alone by
`tools/research/md10drive.py` boots identically.

**Does not — and the reason is the CCP, not the drive.** It never prompts because
the CCP the loader installs is **relocated 0x100 bytes too high**, so its first
instruction jumps into the middle of another one and the system warm-boots for
ever. That is the whole of it, and it is worth stating plainly because the
earlier reading of this section — "the BDOS is stuck in a drive login" — was
**wrong**, and so was the hypothesis that opened #198 (that the driver's static
table and the drive's partition table disagree).

A transaction-level trace of the card (#198) is what settles it. Every
transaction is byte-for-byte identical, **1 303 of them in 150 emulated
seconds**:

```
SEL 01 / assert / release / CDB 08 00 00 05 0b 00    READ LBA 5, 11 blocks
R32 42   -> the data phase
R30 x5632                                            5632 bytes moved
R32 60   -> the status phase
STATUS 00                                            GOOD
```

So the read **succeeds**, there is no login, and the drive's partition table never
enters into it: `BOOT` reads the system, jumps to `0xC200`, and the CCP
immediately warm-boots — and a warm boot re-reads the system (§5 step 8), for
ever. The PC histogram agrees: 95.5% of samples are inside the BIOS's `inir`
block-read pair (`0xD9F4`–`0xD9F6`), with brief excursions into the CCP.

Why, measured rather than inferred:

- `HARD.COM` reads the system to `0xC200` and patches page zero to `JP 0CA06h`,
  so the CCP belongs at `0xC200` and the BDOS at `0xCA00`. That is also the only
  placement that fits, because the BDOS ends exactly where the MD-10 BIOS starts
  at `0xD800`.
- The captured CCP's first instruction is `JP 0C5C8h` — and `0xC5C8` is the
  *middle* of a `CP 20h`.
- `0xC4C8`, exactly 0x100 lower, is `LD SP,0C8C5h` / `PUSH BC` / `LD A,C` /
  `RRA ×4` / `AND 0Fh` / `LD E,A` / `LD C,0Dh` / `CALL 5` — CP/M's own
  `COMMAND:` entry, ending in the BDOS reset-disk call. Its sibling
  `JP 0C4C4h` lands on `XOR A` / `LD (nn),A`, which is `CLEARBUF`.

The correction is **exact, not a patch**, because the two `.SPR` files on the 2.01
utilities disk are the relocatable source `PREP.COM` relocates from. Comparing
each SPR body against the matching half of the captured image, they differ **only
in the high byte of relocated operands**, at one constant delta per file — `C3h`
for the CCP (232 bytes) and `CBh` for the BDOS (558 bytes, plus four stamped
serial-number bytes). Those are page deltas: `PREP.COM` added `0xC300`/`0xCB00`
where the load addresses are `0xC200`/`0xCA00`. So the captured image is one
uniform relocation of the SPRs at a base 0x100 too high, and re-applying it at
the right base is exact.

`tools/research/md10reloc.py` does that and checks itself — the CCP entry must
land on `LD SP,nn` — and `tools/research/md10drive.py --os` lays the result on a
drive. With that drive in `-hard`:

```
r21|A0>
r21|A0>B:
r22|B0>A:
r23|A0>
```

`A0>` is the MD-10's own CP/M (the O1's CCP prompts `A>`; DRI's includes the user
number). `B:` is the proof rather than decoration: **there is no floppy in drive
B**, so only the hard disk's own CP/M can answer `B0>` — and it does, against the
`CP/M-B` partition at LBA 11564. The drive letters are the two partitions, which
is what `docs/harddisk-decision.md` §4 says they should be.

One further measurement falls out: the BDOS's login reads the directory as **64
blocks** — the trace catches `READ LBA 83`, the last block of `20 … 83` — which is
exactly the `E5h` region §3 records. So the drive and the driver *do* agree about
drive A.

### 7.2 The three-partition drive, and the first write (2026-10-14)

The result above is two partitions, on the PYXIS13 drive. On the **PYXIS27** drive
of §3 — the floor pin — the same `HARD.COM` boot gives three, and the third one
takes a write:

```
r21|A0>C:
r22|C0>SAVE 1 TEST.COM
r23|C0>D:DIRA
r24|C:  0:TEST     COM
r25|C0>
```

`C0>` is the third partition, and that `SAVE` is the first time anything in this
project **wrote** to a hard-disk partition. `D:DIRA` — the disk's own lister, run
from the floppy the hard disk displaced (§7.1) — reads the entry back. The write
is visible in the image afterwards: block `30818`, the first block of `CP/M-C`'s
directory, changes from `E5h` fill to a CP/M directory entry
`00 54 45 53 54 20 20 20 20 43 4f 4d …` (user 0, `TEST    .COM`). That is why
`tools/research/md10table.py` reports `C:`'s `E5h` region as `30819-30881` on the
driven image and `30818-30881` on a fresh one — the region is the check.

It is also the check that the shared DPB's 7.5 MiB lands *inside* the partition
rather than past its end (§9.1): on the PYXIS13 drive it does not, which is why
that drive is not safe to write to and the PYXIS27 layout is the floor pin.

### 7.1 The drive letters, and the floppy the hard disk displaced

The MD-10 takes `A:`/`B:` for the hard disk, so the floppies move — and *where the
boot floppy went* is the check that the floppy half of the relocation works, not
just the hard-disk half. Measured at the `A0>` prompt with the 2.01 utilities disk
in physical drive A and **nothing in drive B**:

| Letter | What it is | How it answers |
|---|---|---|
| `A:` | the hard disk, `CP/M-A` (LBA 20) | the prompt itself |
| `B:` | the hard disk, `CP/M-B` (LBA 11564) | `B0>` |
| `C:` | the hard disk, the *third* descriptor — not configured on this drive | `C0>`, and no further |
| **`D:`** | **the floppy that was drive A** | `DIRA` lists all 23 files of the 2.01 disk |
| `E:` | the floppy in physical drive B, which is empty | `Unformatted diskette on drive B` / `Bdos Err On E: Select` |

So the boot floppy is **`D:`**, not `E:`: the hard disk takes *three* letters, not
two, because the driver's type table gives drives 0–2 the three hard-disk
descriptors (`00 01 02`) and the floppies begin at drive 3 (`80h`, `81h`, …).
`E:` is the *second* floppy — the one with no disk in it — which is why it is the
letter that errors.

`DIRA` is the disk's own lister (`DIR` is a transient program in CP/M 2.2, and
this disk has no `DIR.COM`, so `DIR E:` answers `DIR?` on the hard disk and
cannot be used for this). From `D0>` it prints exactly the archive's contents:

```
D:  0:PORTCHNG COM  0:HD04BIOS SPR  0:HD00BIOS SPR  0:DRST     COM
D:  0:FREEDIR  COM  0:FSET     COM  0:ERQ      COM  0:DIRS     COM
D:  0:GET      COM  0:PUT      COM  0:CNT04COD OVL  0:NS       COM
D:  0:CNT00COD OVL  0:SUBMIT   COM  0:DRIVETBL DAT  0:DIRA     COM
D:  0:HARDBIOS SPR  0:HARDBDOS SPR  0:HARDCCP  SPR  0:PREP     COM
D:  0:CNTLRCOD OVL  0:AREN     COM  0:HARD     COM
```

— the 23 files `tools/cpmfs.py … ls` reports for `research/adaptec/Osborne Hard
Disk Control Software Version 2.01 (1984).img`, name for name, and nothing extra.
`PREP` also **runs** from `D:`, printing its own `PREP version 2.01` banner and
main menu.

That is the proof that the floppy the hard disk displaced is still fully readable
through the MD-10's relocated floppy driver: its directory, and a 12 KB program
loaded and executed out of it.

#179's acceptance — *boots CP/M from the emulated hard disk* — is met, and so is
#198's: the prompt appears, and it answers.

## 8. What this changes elsewhere

- **#178's last open question is closed.** `0x0559`–`0x055D` is not an unwritten
  block; it is a constant in `HARD.COM`'s embedded BIOS (§6). The DPB *values*
  are still derived rather than tabulated, but nothing about the *system* is
  missing any more.
- **#179's acceptance has a drive to run against.** The firmware personality in
  `firmware/acb4000-scsi/` and this image are two halves of the same test; the
  commands the period software issues (`VERIFY` `2F`, `SEARCH DATA EQUAL` `31`)
  are implemented there.
- **#191's `peek 0x055E`/`0x056E` is now reachable.** It needs an MD-10 *system* on
  the drive, and the system now reaches its prompt (§7) — so the runtime tables
  can be read against a *running* system rather than inferred. What that will
  show is still open: the tables are static data in `HARD.COM` (§9), the drive's
  LBA 4 carries its own copy of the geometry and type bytes (§3), and who copies
  one into the other is not yet chased.
- **`docs/osborne1nx-machine.md` §5's "`HARD.COM` is a hard-disk boot loader"
  is right, and now it is read end to end** — including that it *also carries the
  BIOS*, which that section did not know.

## 9. The DPB and the drive table are *in the archive* after all (#178)

`docs/harddisk-decision.md` §7.3 concluded that the DPB's values "are not
obtainable from the files in the archive", because `tools/research/hardbios.py
audit` found **no writer and no pointer** to the tables at `0x055E`/`0x056E`.

The negative result was an artefact of two things, and both are now measured:

1. **`0x055E` is not a low-RAM address. It is an offset from the BIOS's base.**
   The MD-10 BIOS loads at `0xD800` (§4), so the per-drive type byte table is at
   **`0xDD5E`** and the 24-byte descriptor table at **`0xDD6E`**. The audit
   searched `0x0500`–`0x0700`, which is why it found only the *relocatable
   operands* inside the overlay (`LD BC,055E` / `LD DE,056E` — the latter **is**
   reported, at `hardbios.spr` offset `0x200`).
2. **Both tables are static data inside the BIOS image**, so they are readable
   from the file — in `HARD.COM`'s embedded copy at file offsets `0x998` and
   `0x9A8` (addresses `0xDD5E`/`0xDD6E` less the loader's `0x0100` origin), and
   at `0x9F0` for the DPB.

   They are **not** in `HARDBIOS.SPR`, which an earlier revision of this section
   claimed "at the matching offsets". A byte search for the 16-byte type run, the
   `01 14 00 00 27 3C` descriptor prefix and the ten-byte DPB prefix finds all
   three in `HARD.COM` and in **none** of `HARDBIOS.SPR`, `HARDBDOS.SPR` or
   `HARDCCP.SPR`. The `.SPR` is a *different, larger* build — its body is `0x880`
   bytes against the embedded copy's `0x5C5` — so it is the same BIOS at the same
   entry points but not the same image. The driver's fallback table therefore
   lives only in the loader that installs it, which is why #178's audit of the
   `.SPR` files found no writer.

Read out of `HARD.COM` (2.01), the tables are:

| Address | `HARD.COM` file | What |
|---|---|---|
| `0xDD5E` | `0x0998` | 16 per-drive type bytes: `00 01 02 80 81 82 83 84 85 86 87 88 89 8A 8B 8C` |
| `0xDD6E` | `0x09A8` | the 24-byte descriptors, `type × 24`, DPH at `+8` |
| `0xDDB6` | `0x09F0` | **the DPB** — 15 bytes, reached at DPH+10 |

The DPB itself:

```
file 0x09F0   9C F0 05 1F 01 83 07 FF 03 FF 00 00 00 00 00
              SPT   BSH BLM EXM DSM   DRM   AL0 AL1 CKS   OFF
              ?     5   31  1   1923  1023  FF  00  0     0
```

and **`DPB+3` is `31`** — which is exactly what §7.3 read out of the driver's
*code* ("the driver reads `DPB+3` as `BLM`") before the data had been found. Two
independent readings agreeing is what makes `0xDDB6` the DPB rather than a
lookalike.

`BLM = 31` gives 4096-byte blocks; `DSM = 1923` is therefore 7.88 MB per logical
drive; `DRM = 1023` is 1024 directory entries; `AL0 = FFh` is the eight
directory blocks; `CKS = 0` is a fixed disk, which is right. **`SPT` reads
`F09Ch` — 61596 — and that is not a sector count: it is the partition measured in
128-byte records.** `61596 × 128 = 7 884 288 = 15399 × 512`, exactly one
15399-block partition (resolved 2026-10-14; §7.3's "patched at run time from
`MODE SENSE`" reading is retired). So the DPB does not merely *describe* a
partition size — it **is** the partition size, and it is the same 15399 blocks
`PREP.COM` writes when it is given a PYXIS27 (§3).

### 9.1 One DPB for every hard-disk drive, and what that pins

Read out of `HARD.COM` at file offsets `0x9A8` (the descriptors) and `0x9F0`
(the DPB), the three hard-disk descriptors are:

```
type 0: 01 14 00 00 27 3c 00 00 | 00.. | 80 ee | b6 dd | 00 00 | c5 dd
                 start=20 len=15399        DIRBUF  DPB     CSV    ALV
type 1: ...                                80 ee | b6 dd | 00 00 | b6 de
type 2: ...                                80 ee | b6 dd | 00 00 | a7 df
```

Read as the standard CP/M DPH at descriptor+8: **`XLT` 0, `DIRBUF` `0xEE80`,
`DPB` `0xDDB6` and `CSV` 0 are shared by all three drives — only the allocation
vector differs**, at `0xDDC5`, `0xDEB6`, `0xDFA7`: exactly `0xF1` = **241 bytes**
apart, which is the ALV size for `DSM = 1923` (`(1923 + 1) / 8`, rounded up).
Two consequences, both load-bearing:

1. **Every hard-disk partition is the same size in CP/M's view — 7.5 MiB usable —
   because there is one DPB.** So the only configuration in which the drive and
   the driver agree is **three 15399-block partitions on a PYXIS27**. That is the
   **floor pin**, and it is why §3's PYXIS27 layout is the one to build.
2. **The two-partition PYXIS13 drive is not safe to write to.** Its `CP/M-A` is
   11544 blocks (5.6 MiB) while the shared DPB tells CP/M it has 7.5 MiB, and the
   1.9 MiB difference runs straight into `CP/M-B` — starting with `B:`'s own
   directory. Nothing caught this earlier because every earlier test only ever
   *read*; the first write to a hard-disk partition was `SAVE 1 TEST.COM` on the
   PYXIS27 drive (§7.2).

Bigger partitions need the DPB, the ALV addresses and the descriptor table
patched together — #247's driver step. CP/M 2.2's own ceilings are `DSM` at 16
bits (256 MiB at `BSH = 5`) and **32 MiB per partition**, because the partition
length field is 16 bits of 512-byte blocks.

**And that reconciles the residue.** The static descriptors carry three
partitions — starts `20`, `15419`, `30818` (each entry's bytes 1–3 differ by
`0x3C27` = 15399 blocks, and 15399 × 512 = 7.88 MB, the DPB's own `DSM × 4096`)
— which is a **fallback for a drive with no usable label**, not the drive in
front of it: three of those do not fit in PYXIS13's 23112 blocks. The
*configured* drive carries two partitions of 11544 (§3), which is what
`PREP.COM` wrote and what the drive's own partition table says.

**So the two disagree — and the fallback is a *drive*, not a guess.** The three
descriptors are three partitions of 15399 blocks at `20`, `15419`, `30818`, and
that is exactly the shape of **PYXIS27**:

| Entry | Cylinders | Heads | Sectors | Blocks | Size |
|---|---|---|---|---|---|
| `PYXIS13` | 321 | 4 | 18 | 23 112 | 11.8 MB |
| `PYXIS27` | 321 | 8 | 18 | **46 224** | 23.7 MB |

The fallback's third partition ends at `30818 + 15399 = 46217`, and PYXIS27 holds
`46224` — it fits with **seven blocks to spare**. So the static table is not "a
fallback for a drive with no usable label" in the abstract: it is **PYXIS27's
partitioning**, and 15399 × 512 = 7.88 MB is the same 7.88 MB the fallback DPB
describes (`DSM = 1923` × 4096). Both entries are in the driver's own table
(`DRIVETBL.DAT` indexes 53 and 55; `tools/research/drivetbl.py`), and PYXIS27 is
PYXIS13 with the heads doubled — `321/4/18` against `321/8/18`.

Which is also the answer to *where `C:` went*: on a **PYXIS13** only one
15399-block partition fits, so `PREP.COM` wrote two of 11544 instead (§3) and the
third descriptor has nothing behind it — `C0>` selects and no partition answers.
On a **PYXIS27** the fallback's third partition is real and `C:` is a real drive.
The MD-10 claims three letters because its type table gives drives 0–2 the three
hard-disk descriptors (`00 01 02`, §7.1); the *drive* decides whether the third
one has anything in it.

**And the disagreement never mattered.** An earlier revision of this section
concluded from it that the system could not prompt because the BDOS was logging in
to the wrong directory. **That was wrong** (§7): there is no login at all before
the prompt, the trace shows only the boot `READ LBA 5` with status GOOD, and the
login that does happen — after the prompt, when `B:` is typed — reads LBA 83, the
last block of drive A's own `E5h` directory. The fallback is never consulted on a
drive that carries a label.

## 10. The test that was named, and its answer

An earlier revision of this section named a test: watch the card's CDB while the
guest is at the login, or build a drive whose partition table matches the driver's
static descriptors. **Neither was needed, and the premise was wrong.** The CDB is
*always* `08 00 00 05 0b 00` — LBA 5, the boot read — and it comes back with
status `00` (GOOD), so there is no login to watch and no partition-table
disagreement to reconcile. The blocker was in the operating system's relocation
(§7), which no amount of drive-building would have fixed.

The answer, in the order it was measured:

1. **The transaction trace** — every READ succeeds and repeats byte for byte, so
   the failure is above the card, not in it.
2. **The PC histogram** — 95.5% of the guest's time is inside the BIOS's block
   read, with brief excursions into the CCP, which is a warm-boot loop and not a
   stalled login.
3. **The CCP's first instruction** — `JP 0C5C8h` lands mid-instruction; `0xC4C8`
   is CP/M's `COMMAND:` entry.
4. **The SPR diff** — the image is a uniform relocation of `HARDCCP.SPR` /
   `HARDBDOS.SPR` at a base 0x100 too high, so the repair is exact.

The recipe that produced a bootable disk, end to end:

```sh
# 1. re-relocate the captured O/S to the address HARD.COM loads it at
tools/research/md10reloc.py --out /tmp/md10/md10-os.bin

# 2. lay it on a drive (the partition table and the O/S come from the capture)
tools/research/md10drive.py --out /tmp/md10/hd.chd --os /tmp/md10/md10-os.bin --force

# 3. boot HARD.COM from the 2.01 utilities disk against it -- §2's recipe, with
#    -harddisk /tmp/md10/hd.chd
```

The acceptance is the prompt, and `B:` from a machine with **no floppy in drive
B** is what makes it a boot rather than a banner (§7).

## Sources

- `research/adaptec/md10-system/` — the captured system: `lba0-15.bin`,
  `md10-os.bin`, and the provenance note. **The capture is unmodified**; its
  0x100 relocation is a property of what `PREP.COM` wrote, and the corrected
  image is derived on demand rather than committed.
- `research/adaptec/Osborne Hard Disk Control Software Version 2.01 (1984).img`
  — `PREP.COM`, `HARD.COM`, `HARDCCP.SPR`, `HARDBDOS.SPR`, `HARDBIOS.SPR`.
- `research/adaptec/MD Utilities Adaptec 4000 Controller Ver. 1.93 Osborne -
  MD-10 MD-20.img` — the 1.93 copies, used to check the 2.01 ones.
- `tools/research/o1keys.lua` — the scripted-keystroke harness, and its `pc`,
  `peek` and `poke` directives, which are how every "measured" above was taken.
  `peek`/`poke` take bare hex (`peek dd5e 4`) as well as `0x`-prefixed.
- `tools/research/md10reloc.py` — re-applies the SPR relocation at the load
  address, and checks that the CCP entry lands on `LD SP,nn`.
- `tools/research/md10drive.py` — lays an O/S image onto a drive (`--os`).
- `tools/emulator-setup/mame-osborne1nx/` — the `osborne1nx` machine (#191).
- `docs/osborne1nx-machine.md` §6 (the header field map), §5 (the harness
  findings); `docs/harddisk-decision.md` §7.2–§7.3;
  `docs/acb4000-host-adapter.md` §1, §4.

