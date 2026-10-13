# The MD-10's operating system, and the memory map that was missing (#179, #178)

**Status: the system image exists and boots — and it was produced by the
vendor's own tool, not synthesised.** `PREP.COM`'s option 3 configures an
operating system onto the drive; `HARD.COM` then boots it from the emulated hard
disk: it installs the MD-10 BIOS at `0xD800`, reads the system from **LBA 5, 11
blocks** into `0xC200`, patches page zero, and CP/M runs. What is **not** yet
solved is the last inch: the system does disk I/O but never prints a prompt, and
§7 says what is known about why.

This note also closes the question the hard-disk research left open twice over —
**the MD-10's memory map**, and with it the meaning of the low-RAM block at
`0x0559`–`0x055D` that `docs/acb4000-host-adapter.md` §4 and
`docs/harddisk-decision.md` §7.3 recorded as *written by nothing in the archive*.

Serves #179 (the personality's acceptance), #178 (the DPB residue) and #191 (the
harness that made it measurable). Reads alongside `docs/acb4000-firmware.md`,
`docs/acb4000-host-adapter.md`, `docs/osborne1ng-machine.md` and
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
holds it; `tools/research/md10drive.py` lays it onto a fresh drive.

## 2. The recipe

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
cd /tmp/md10 && O1_MACHINE=osborne1ng O1_FLOP1=/tmp/md10/prep.imd \
  O1_KEYS="$(cat /tmp/md10/keys.txt)" SDL_VIDEODRIVER=dummy \
  /path/to/osborne1ng osborne1ng -flop1 /tmp/md10/prep.imd -hard /tmp/md10/hd.chd \
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
   `docs/osborne1ng-machine.md` §6 records as *"Initializing all partitions..."*
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
| LBA 1–3 | the rest of the four-block header (`docs/osborne1ng-machine.md` §6) |
| LBA 4 | a table |
| **LBA 5–15** | **the operating system — 11 blocks, `0x1600` bytes** |
| LBA 20–83 | `E5h` — the first 64 blocks of the `CP/M-CCP` partition: CP/M's empty directory |
| LBA 11564–11627 | `E5h` — the same for the `CP/M-A` partition |
| everything else | the `6Ch` fill |

The partition table, decoded (name at +0, a little-endian start at +13 and length
at +16 inside each 28-byte record):

| Record | Name | Start (LBA) | Blocks |
|---|---|---|---|
| 0 | `CP/M-CCP` | 20 | 11544 |
| 1 | `CP/M-A` | 11564 | 11544 |
| 2 | `CP/M-B` | — | terminated (`FFh`) |

`CP/M-CCP` is the **O/S partition** option 3 insists on. The two records tile
`20 … 23107`, which is the whole PYXIS13 drive bar the header — so the MD-10's
"two logical drives" are `CP/M-CCP` (where the system lives) and `CP/M-A`.

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

**Does not.** No prompt is ever printed, and the screen still shows `HARD.COM`'s
banner. The system is not crashed — it is *busy*: the PC sits at the BIOS's
`inir` block-read pair (`0xD9F5`/`0xD9F6`) and walks the BDOS's buffer area.

What that rules out, and what it leaves:

- It is **not** a load failure. `0xC200` and `0xCA00` both hold the drive's
  bytes; the read completes.
- It is **not** the console being unwired. The MD-10 BIOS's
  `CONST`/`CONIN`/`CONOUT` are the ROM's own routines (`0xE72E`, `0xE733`,
  `0xE738`), the ROM is always mapped, and `HARD.COM`'s own output proves the
  path works.
- It **is** consistent with the BDOS being stuck in a drive login — reading the
  directory of the drive it was told to use — which is the one thing a CP/M cold
  start does before the CCP can prompt.

The next step is to see *which* LBA the login is asking for and what status comes
back, and the harness can now do that: `tools/research/o1keys.lua` gained a `pc`
directive for this, and `peek`/`poke` reach the card's CDB at `0xD9FA` and the
partition records at label+48. A login asking for a directory the capture does
not carry is the first hypothesis to test — the captured partitions are
`E5`-empty directories, and an empty directory is a legitimate CP/M state, so if
the BDOS is unhappy it is more likely about *where* it is looking than *what* is
there.

Until that is answered this doc stays **partially solved**, and #179's acceptance
— *boots CP/M from the emulated hard disk* — is met for the load-and-run half and
not for the prompt.

## 8. What this changes elsewhere

- **#178's last open question is closed.** `0x0559`–`0x055D` is not an unwritten
  block; it is a constant in `HARD.COM`'s embedded BIOS (§6). The DPB *values*
  are still derived rather than tabulated, but nothing about the *system* is
  missing any more.
- **#179's acceptance has a drive to run against.** The firmware personality in
  `firmware/acb4000-scsi/` and this image are two halves of the same test; the
  commands the period software issues (`VERIFY` `2F`, `SEARCH DATA EQUAL` `31`)
  are implemented there.
- **#191's `peek 0x055E`/`0x056E` is now reachable in principle.** It needs an
  MD-10 *system* on the drive, which this is; what it does not yet have is a
  system that reaches its prompt.
- **`docs/osborne1ng-machine.md` §5's "`HARD.COM` is a hard-disk boot loader"
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
   `0x9A8`, and in `HARDBIOS.SPR` at the matching offsets.

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
`F09Ch` and that is not a sector count** — the one field still to explain, and
the likely answer is the one §7.3 already argued for: the driver patches `SPT`
at run time from `MODE SENSE`, so the static value is a placeholder.

**And that reconciles the residue.** The static descriptors carry three
partitions — starts `20`, `15419`, `30818` (each entry's bytes 1–3 differ by
`0x3C27` = 15399 blocks, and 15399 × 512 = 7.88 MB, the DPB's own `DSM × 4096`)
— which is a **fallback for a drive with no usable label**, not the drive in
front of it: three of those do not fit in PYXIS13's 23112 blocks. The
*configured* drive carries two partitions of 11544 (§3), which is what
`PREP.COM` wrote and what the drive's own partition table says.

**So the two disagree**, and that is the most likely reason the system never
reaches its prompt (§7): the BDOS logs in to a drive whose directory is not
where the driver's table says it is. §10 is the test.

## 10. The next test, precisely

The drive is `LBA 20 … 11563` for `CP/M-CCP` and `11564 … 23107` for `CP/M-A`
(§3). The driver's fallback table says `20`, `15419`, `30818`. If the login is
looking at `15419` and finding `6Ch` rather than `E5h`, the fix is to make the
drive match the table — or to work out what writes the *runtime* table from the
label.

The harness can answer it in one run: `poke` the CDB at `0xD9FA` (the LBA is
bytes `+3`/`+4`), or `peek` the partition records at label+48 and the type byte
at `0xDD5E + drive` while the guest is at the login. `tools/research/o1keys.lua`
has `pc`, `peek` and `poke` for exactly this.

## Sources

- `research/adaptec/md10-system/` — the captured system: `lba0-15.bin`,
  `md10-os.bin`, and the provenance note.
- `research/adaptec/Osborne Hard Disk Control Software Version 2.01 (1984).img`
  — `PREP.COM`, `HARD.COM`, `HARDCCP.SPR`, `HARDBDOS.SPR`, `HARDBIOS.SPR`.
- `research/adaptec/MD Utilities Adaptec 4000 Controller Ver. 1.93 Osborne -
  MD-10 MD-20.img` — the 1.93 copies, used to check the 2.01 ones.
- `tools/research/o1keys.lua` — the scripted-keystroke harness, and its `pc`,
  `peek` and `poke` directives, which are how every "measured" above was taken.
- `tools/research/md10drive.py` — lays the captured image onto a drive.
- `tools/emulator-setup/mame-osborne1ng/` — the `osborne1ng` machine (#191).
- `docs/osborne1ng-machine.md` §6 (the header field map), §5 (the harness
  findings); `docs/harddisk-decision.md` §7.2–§7.3;
  `docs/acb4000-host-adapter.md` §1, §4.

