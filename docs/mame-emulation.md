# Emulating the Osborne 1 under MAME

How to run the three Osborne 1 machines MAME models, what ROMs each one needs,
and which floppy images actually boot on which machine.

The install/run mechanics are adapted from the sibling project
[`Myrcurial/o1prsnt`](https://github.com/Myrcurial/o1prsnt) — its
`o1prsnt/docs/emulating-the-osborne-1.md` and
`o1prsnt/utilities/headless-testing-harness/` — which is where the macOS
specifics and the VRAM-dumping technique were worked out. This document adds the
per-machine ROM requirements and the boot-disk compatibility results, both
measured here. (Paths prefixed `o1prsnt/` are in that repository, not this one.)

## 1. Install

```bash
brew install mame
brew install cpmtools     # cpmcp / cpmrm / cpmls - file-level disk work
```

`disk-analyse` (Keir Fraser's [Disk-Utilities](https://github.com/keirf/disk-utilities))
is needed to convert between the IMD images MAME wants and the HFE images a
hardware floppy emulator wants. It is not packaged; build it:

```bash
git clone https://github.com/keirf/disk-utilities.git
cd disk-utilities && make clean && make && sudo make install
```

`samdisk` (TD0 → EDSK) is **not** currently installed on this machine and is
needed for the TeleDisk images in `research/` (Osmosis, RT-60A, the Zorba/Kaypro
CoPower-88 sets).

## 2. The three machines

MAME models three Osborne 1 variants — and this project adds a fourth (below).
Two are clones of the stock machine; one has its own ROMs:

| MAME machine | Description | Year | Parent | Relationship | Display (measured) |
|---|---|---|---|---|---|
| `osborne1` | Osborne-1 | 1981 | — | the stock machine | 416×240 = **52 columns** |
| `osborne1sp` | Osborne-1 with SCREEN-PAC | 1983 | `osborne1` | clone — **no ROM differences at all** | 832×240 = **104 columns** |
| `osborne1nv` | Osborne-1 (Nuevo Video) | 1984 | `osborne1` | own BIOS **and** own character generator | 640×240 = **80 columns** |

This project adds a **fourth** (`tools/emulator-setup/mame-osborne1ng/`, #191):
`osborne1ng` is a clone of `osborne1` whose Z80 sits behind an emulated card
that decodes the full 8-bit I/O address, so the MD-10's ACB-4000 host adapter can
answer on ports `30h`–`33h`. It is not in MAME; it is a patch, and it runs the
**1.44 ROM only**. Banking and video are identical to `osborne1` — measured, not
assumed — and the presence check the MD-10 driver demands now passes. See
`docs/osborne1ng-machine.md`.

**Yes, the Nuevo machine really is 80 columns.** The display width is a property
of the emulated *machine*, not of the disk, and it was measured by booting the
same utility disk on each of the three and reading the screen device's
dimensions (`tools/research/mame-boot-probe.sh`). Screenshots, all booted from
`tools/emulator-setup/floppies/`:

| Screenshot | Machine | Pixels | Columns |
|---|---|---|---|
| `docs/mame-screens/osborne1-52col.png` | `osborne1` | 416×240 | 52 |
| `docs/mame-screens/osborne1nv-80col.png` | `osborne1nv` | 640×240 | 80 |
| `docs/mame-screens/osborne1sp-104col.png` | `osborne1sp` | 832×240 | 104 |

That is also why the disk prefix does not matter for booting (§4): the same
image displays 52 columns on stock hardware and 80 on Nuevo, because the video
window is the machine's, while the *text layout* is the CBIOS's.

The distinction matters: the SCREEN-PAC is modelled as *hardware only* (the
80/104-column logic lives on the board, not in a ROM), whereas Nuevo shipped a
replacement monitor ROM. That is independent evidence that the two 80-column
upgrades are different designs — see #73 and `docs/o1-rom-variants.md`.

### The SCREEN-PAC has three modes, and MAME models one of them

The measured 104 columns is the SCREEN-PAC's *default*, not its only width. Its
own user guide gives the full set, and all of them are selectable **by the stock
BIOS**:

> SCREEN-PAC has preset video contrast in **80 and 104 column format** … In
> these same formats, SCREEN-PAC provides **horizontal scrolling by 32 column
> blocks** … At BIOS location **E1A5H**, POKE or store **0 for 52 columns / 1 for
> 104 columns / 3 for 80 columns**. CALL BIOS location **E4E5H**.
> — *Osborne 1 SCREEN-PAC User Guide*, p. 13 (PDF p. 17)

So 52 / 80 / 104 are three widths of **one window** (`o1-memory-io-map.md` §2a),
and the stock ROM already contains the routine that switches between them —
which is why "no ROM differences at all" is the right description of
`osborne1sp`. MAME models the 104-column window; the **80-column mode should be
reachable by poking `E1A5H` = 3 and calling `E4E5H`**, which is worth testing
precisely because it is the other documented mode and the one nobody quotes.

**Presence flag.** The same page records how software detects the upgrade with
no ROM change:

> reading 2400H (Bank 2) returns data **bit 2 LOW**. Without SCREEN-PAC, this bit
> is read HIGH. This feature allows different screen responses and menus
> depending on whether the Osborne is fitted with SCREEN-PAC.

`2400H` in bank 2 sits inside the memory-mapped I/O window and was not in the
map until now: it is a read-only presence bit, not a register
(`o1-memory-io-map.md` §3).

## 3. ROM requirements

Every ROM either machine needs, with the CRC32 MAME asserts against. Full
inventory and provenance: `docs/o1-rom-variants.md`.

| ROM file | Size | CRC32 | `osborne1` | `osborne1sp` | `osborne1nv` | Role |
|---|---|---|---|---|---|---|
| `rev1.40.ud11` | 4096 | `3d966335` | ✓ (BIOS 1.4) | ✓ | — | monitor ROM 1.4 |
| `rev1.43.ud11` | 4096 | `91a48e3c` | ✓ (BIOS 1.43) | ✓ | — | monitor ROM 1.43 |
| `3a10082-00rev-e.ud11` | 4096 | `c0596b14` | ✓ (BIOS 1.44) | ✓ | — | monitor ROM 1.44 — **the default** |
| `char.ua15` | 2048 | `5297c109` | ✓ (BIOS ≤ 1.4) | ✓ | — | early character generator |
| `7a3007-00.ud15` | 2048 | `6c1eab0d` | ✓ (BIOS 1.43/1.44) | ✓ | ✓ | late character generator |
| `monrom-rev1.51-12.ud11` | 4096 | `298da402` | — | — | ✓ | Nuevo monitor ROM 1.51 |
| `character_generator_6-29-84.14` | 2048 | `6c1eab0d` | — | — | ✓ | Nuevo-era char-gen — **same bytes** as `7a3007-00.ud15` |
| `osba.bin`, `osb12.bin`, `osb121.bin`, `osb13.bin` | 4096 | — | NO_DUMP | NO_DUMP | — | BIOS A / 1.2 / 1.2.1 / 1.3 — **never dumped** |

**One `osborne1.zip` serves all three machines.** The repository's
`tools/emulator-setup/roms/osborne1.zip` holds the six available files, and
MAME's hash fallback satisfies `character_generator_6-29-84.14` from
`7a3007-00.ud15` because the bytes are identical. Verified:

```
$ mame osborne1nv -verifyroms -rompath tools/emulator-setup/roms
romset osborne1nv [osborne1] is good
$ mame osborne1 -verifyroms -rompath tools/emulator-setup/roms
osborne1    : osba.bin (4096 bytes) - NOT FOUND - NO GOOD DUMP KNOWN
... (the four undumped BIOSes only)
romset osborne1 is best available
```

"best available" is the correct and expected result for `osborne1`/`osborne1sp`:
the only missing ROMs are the four that have never been dumped anywhere. The
default BIOS is **1.44** (`3a10082-00rev-e.ud11`), which is what the banner
shows.

### Where to get them

The upstream collection used by `o1prsnt` is
[archive.org/details/osborne-1-roms](https://archive.org/details/osborne-1-roms)
(two files: `occ-7a3007-00-reva.rom`, `occ-v1.44.rom` — enough for `osborne1`
and `osborne1sp`, **not** enough for `osborne1nv`). This repository carries the
full set in `tools/emulator-setup/roms/`, archived with provenance in
`research/roms/`.

### Rompath layouts

MAME looks for machine ROMs in `<rompath>/<machine>.zip` or
`<rompath>/<machine>/`, **and it will also fall back to a loose file in the
rompath root** when a required ROM is missing but a file with the right CRC is
present. Measured, both ways:

```
$ mame osborne1nv -verifyroms -rompath tools/emulator-setup/roms
romset osborne1nv [osborne1] is good          # loose 7a3007-00.ud15 satisfies
                                              # character_generator_6-29-84.14 by CRC
$ # the same files in a plain <rompath>/osborne1/ directory:
osborne1nv  : character_generator_6-29-84.14 (2048 bytes) - NOT FOUND (osborne1)
```

So the CRC fallback works for **loose-root files and for files inside a zip**,
but **not** for files inside a romset *directory*. The wrapper's temporary
`<rompath>/osborne1` symlink (used when the rompath has no `osborne1.zip`) turns
a working loose rompath into a failing directory — which is why
`tools/emulator-setup/roms` keeps `osborne1.zip` alongside the loose files. This
matters when substituting a third-party ROM: build a **zip**, see §5.


## 4. Boot disks: what actually boots on which machine

Measured, not assumed. Each cell is a headless run of the harness in §6 that
presses RETURN at the BIOS prompt and waits for an `A>`.

| Image | `osborne1` | `osborne1sp` | `osborne1nv` |
|---|---|---|---|
| `tools/emulator-setup/floppies/52-blank.imd` | **BOOTED** | **BOOTED** | **BOOTED** |
| `tools/emulator-setup/floppies/80-blank.imd` | **BOOTED** | **BOOTED** | **BOOTED** |
| `tools/emulator-setup/floppies/104-blank.imd` | **BOOTED** | **BOOTED** | **BOOTED** |
| `research/nuevo/OS1NUEVO.IMD` | no-boot | — | no-boot |
| `research/nuevo/OS1NUEVO.IMD` (pristine upstream copy) | — | — | no-boot |

### Correction: the `52-`/`80-`/`104-` prefix is a label, not a gate

`tools/check_o1_map.sh` and `tools/README.md` previously implied that an
80-column image "needs a Nuevo Video board" and will not boot a stock machine.
**That is not true of these images.** All three boot on all three drivers,
because all three are the *same* CP/M system disk — they differ by exactly
**two bytes**:

```
$ cmp -l 52-blank.img 80-blank.img
  5737 377   0        # 52 = 0xFF, 80 = 0x00
  5798   0   3        # 52 = 0x00, 80 = 0x03
$ cmp -l 52-blank.img 104-blank.img
  5737 377   0        # 104 = 0x00
  5798   0   1        # 104 = 0x01
```

Both offsets are in the boot area (track 1, sector 1), which is where a CBIOS
would keep a video-mode selection. Whatever those two bytes select, they do not
change which machines the disk boots on.

So what *does* gate bootability is the **CBIOS on the disk**, not the filename
prefix. The prefix is a useful human label — keep using it — but do not rely on
it to decide the driver. (Worth revisiting in `check_o1_map.sh`, which currently
derives the machine from the prefix.)

### What the `-blank.imd` disks actually are

Despite the name, they are **not blank** — they are Osborne 1 double-density
CP/M 2.2 system disks, IBM-MFM, 40 tracks × 5 × 1024 bytes, single-sided:

```
autost.com  cbas2.com  copy.com  crun2.com  mbasic.com  movcpm.com
pip.com  setup.com  sysgen.com  xdir.com  xref.com
```

The system area identifies them as `Osborne Computer System / 59k CP/M vers 2.2
/ CBIOS 1.4`, with `SETUP VERS. 2.6` and `PIP VERS 1.5`. `AUTOST.COM` runs
XDIR (the `Extended Directory version 3.5` banner) rather than booting to a bare
prompt — the same behaviour `o1prsnt`'s `DISCOVERY.md` records.

### `research/nuevo/OS1NUEVO.IMD` — the Nuevo 80-column system disk

This *is* the Nuevo boot disk. Its label is
`CP/M 2.2 system disk for Osborne 1 w/ Nuevo DD & 80 column mods`, and its
system area carries a CBIOS that is explicitly the 80-column one:

```
Osborne 1 Computer / CP/M vers 2.2 / CBIOS vers 1.5
*  THIS IS AN EIGHTY (80) COLUMN DISPLAY FOR THE OSBORNE ONE.  *
*  (3) FULL SCREEN REVERSE VIDEO CAPABILITY (JUMPER SELECT).
*  (4) CURSOR PROGRAMMABLE AS UNDERLINE OR REVERSE VIDEO BLOCK.
*  (6) REVERSE VIDEO BLOCK CAPABILITY (INSTEAD OF UNDERLINE; JUMPER SELECT).
```

**It does not boot under MAME.** On `osborne1nv` it loads, prints the CBIOS 1.5
banner, and then sits there — screen unchanged over 260 emulated seconds, with
RETURN and space nudges. On the stock `osborne1` it does the same.

That is not a bad copy: the pristine upstream file from Dave Dunfield's
`osborne1.zip` behaves identically, and our copy differs from it only in the
IMD comment block. So either MAME's `osborne1nv` does not reproduce whatever the
Nuevo CBIOS waits on, or the disk needs the physical Nuevo card to get past
initialisation. **Closed as not-needed — see #79.**

### Decision: the Nuevo path is not pursued

The video personality (#24) does **not** depend on answering the above. The
decision taken is to build it from the **ScreenPac design plus OZROM's soft
52/80/104-column switch**, and to treat the Nuevo board as prior art (#73)
rather than as a target. So the Nuevo CBIOS hang is no longer on the critical
path, and #79 is closed with the question recorded rather than chased — nothing
in the Nuevo design has yet turned up a feature worth the validation cost.

### Practical answer for Nuevo work

- To get a **prompt** on `osborne1nv`, use any of the three `-blank.imd` disks.
- To exercise the **Nuevo 80-column video path**, `OS1NUEVO.IMD` is the right
  disk but it cannot get past CBIOS initialisation; per the decision above this
  is no longer a blocker for #24.
- Material for *building* a working Nuevo system disk, if anyone ever wants it:
  `OS1NUEVO.IMD` carries the Nuevo CBIOS 1.5 in its system tracks,
  the `-blank.imd` disks carry `SYSGEN.COM` (and `MOVCPM.COM`) for writing a new
  system, and `research/nuevo/` has the Nuevo DD upgrade manual and the Nuevo
  BIOS ROM (`monrom-rev1.51-12.ud11`). A custom build is therefore plausible.

## 5. Running it

### Directory layout

`o1prsnt` settled on a stable layout so that launching MAME from odd places does
not scatter `cfg/` and `snap/` directories everywhere. Our tooling defaults to
the same paths, so both projects share one tree:

```
~/Documents/Osborne1/
  roms/           osborne1.zip
  floppies/       .imd / .hfe disk images
  o1prsnt/        working copies
  presentations/  slide sources
```

`tools/check_o1_map.sh` and `tools/emulator-setup/` read
`~/Documents/Osborne1/roms` and `~/Documents/Osborne1/floppies` by default;
override with `O1_ROMPATH` and `O1_FLOPPY`.

### Windowed launch

```bash
cd ~/Documents/Osborne1
mame osborne1   -flop1 ~/Documents/Osborne1/floppies/52-blank.imd
mame osborne1sp -flop1 ~/Documents/Osborne1/floppies/104-blank.imd
mame osborne1nv -flop1 ~/Documents/Osborne1/floppies/80-blank.imd
```

The machine name is explicit — do not let the image name imply it (§4).

**macOS:** MAME forces fullscreen. LEFT Option + Return toggles out of it, and
Cmd-Q is not honoured — use the red window button.

### File-level disk work (`cpmtools`)

```bash
cpmls -f osborne1 IMAGE                          # list
cpmcp -f osborne1 IMAGE host.txt 0:CONTENT.TXT   # copy in
cpmrm -f osborne1 IMAGE 0:CONTENT.TXT            # remove
```

The `osborne1` disk definition matches the double-density format these images
use (40 × 5 × 1024).

### IMD ↔ HFE

For a hardware floppy emulator:

```bash
disk-analyse in.imd out.hfe
disk-analyse in.hfe out.imd
```

### Running with a third-party ROM (OZROM 1E)

MAME cannot be told about a BIOS that is not in its ROM definitions, but it
*will* load a file whose bytes do not match the expected hash — it warns and
carries on. So a third-party monitor ROM is run by presenting it under one of
the stock BIOS filenames. Build a **romset zip**, not a plain directory:

```bash
mkdir -p /tmp/ozbuild/osborne1 && cd /tmp/ozbuild/osborne1
cp <repo>/tools/emulator-setup/roms/*.ud11 \
   <repo>/tools/emulator-setup/roms/*.ud15 \
   <repo>/tools/emulator-setup/roms/*.ua15 .
cp <repo>/research/roms/OZROM-1E/OZROM_1E.BIN 3a10082-00rev-e.ud11
cp 7a3007-00.ud15 character_generator_6-29-84.14    # see note below
mkdir -p /tmp/ozset && zip -q -X /tmp/ozset/osborne1.zip *

O1_ROMPATH=/tmp/ozset tools/research/mame-boot-probe.sh \
    osborne1 tools/emulator-setup/floppies/52-blank.imd 120 /tmp/ozrom.png
```

**Why a zip and not `mkdir .../osborne1`.** The simpler directory recipe boots
`osborne1` and `osborne1sp`, but **fails on `osborne1nv`**: that machine needs
`character_generator_6-29-84.14`, which MAME satisfies by CRC fallback from
`7a3007-00.ud15` only when the files are loose in the rompath root or inside a
zip — *not* when they sit in an `osborne1/` directory. Copying the chargen under
its own name (it is byte-identical, `o1-rom-variants.md`) makes the fallback
deterministic for all three. Verified: `mame osborne1nv -verifyroms -rompath
/tmp/ozset` reports *good*.

**OZROM 1E boots and runs on all three machines.** Measured:

```
osborne1    416x240  (52 columns)  ->  A>
osborne1sp  832x240  (104 columns) ->  A>
osborne1nv  640x240  (80 columns)  ->  A>
banner: OZROM 1E #00187 / (c) 1984 Micro Management
```

MAME prints *"the machine might not run correctly"* because the ROM hash is not
the one it expects — that warning is the point, not a problem. **The full OZROM
treatment — memory map, ROM jump table, keytable, column switch, clock, memory
tester — is now `docs/ozrom-1e.md` (#81)**, which supersedes the summary that
used to live here.


**Why this matters to us.** OZROM 1E is not a ROM swap with a nicer font; per its
manual (`research/roms/OZROM-1E/OZROM_1E_Manual.pdf`, Micro Management, Manual
Rev. A 84/09/01) it adds capability we would otherwise have to build:

- **User-selectable 52 / 80 / 104-column display from the keyboard** — a
  documented *software* video-mode switch. Directly relevant to the video
  personalities (#24) and to how the Nuevo and ScreenPac paths are driven. On a
  machine with no 80-column upgrade it can also toggle between the left and
  right 52 columns of an 80-column display.
- **A system memory tester** that reports which chip to replace — a validation
  tool for #29.
- **A software-redefinable keyboard** — individual keys at any time, plus eight
  locally-redefinable function keys of up to 63 characters each — relevant to
  #45/#47.
- **Time-of-day clock support** (`TIME`, `ALARM`, `TIMER`, and a way to set the
  clock) — relevant to #7/#18.
- **Documented interfaces**: an interrupt hook for programmers, the ROM jump
  table, the OZROM memory map and keytable, plus notes on 1793/1797 floppy
  controller operation (#20) and truer Televideo 912/920 emulation.
- Removes the "Centronics printer not connected" lockout on double-density
  systems (#19).

What it gives up, stated precisely in its own Appendix C (the manual is now OCR'd
to `research/roms/OZROM-1E/OZROM_1E_Manual.ocr.txt`):

> **IEEE-488 functions.** The OZROM 1E does not support the IEEE-488 functions.
> Although Centronics printer operation is not affected, some printers … and
> some data acquisition and analysis devices … require the IEEE-488 routines to
> operate. In this instance, extra software would be required …

The jump-table appendix is blunt about it: the entries at `013F–0156` *were* the
IEEE-488 routines and **calling them now produces a controlled system crash**,
and *"IEEE-488 AS IOBYTE DEVICE 3 NOW NULL DEVICE"* — the status entries return
`0FFH`, input returns zero, output does nothing. The parallel/Centronics entries
at `0193`+ survive.

**So OZROM and Drive C are mutually exclusive.** Drive C is an IEEE-488 device
and OZROM removes the routines it talks through; the manual's "extra software
would be required" is exactly the driver we have the source for in
`rom144.asm` — so it is recoverable, but it is not free.

One more difference worth knowing, because it constrains any 2.0 ROM (#83):
OZROM **shrinks the video window to 3 KB** (`F000–FBFF`) and uses the last 1 KB
(`FC00–FFFF`) for its redefinable keyboard and function keys. It therefore
scrolls by moving the 23 lines above rather than by moving the window. The stock
ROM's 4 KB video RAM map in `docs/o1-memory-io-map.md` §2 does not apply to
OZROM.

## 6. Headless testing

The technique, from `o1prsnt`'s `utilities/headless-testing-harness/` — which is
where it was worked out, and which is worth reading in full
(`README.md` for the API, `DISCOVERY.md` for how it was derived):

```
SDL_VIDEODRIVER=dummy mame MACHINE -flop1 IMAGE -video none -sound none \
  -nothrottle -autoboot_script RUN.lua -seconds_to_run N -rompath ROMS
```

- `SDL_VIDEODRIVER=dummy` is **mandatory** from a pure terminal session on
  macOS; without it MAME aborts with "Could not initialize SDL".
- `-video none -sound none` — no window, no audio. The emulated screen still
  renders into VRAM, which is all a test reads.
- The screen is read straight from video RAM: base `0xF000`, **128 bytes per
  row**, 32 rows. Character codes are readable directly; the 9th (attribute) bit
  lives in a separate bank and can be ignored for text.
- `-nothrottle` runs the 4 MHz Z80 as fast as the host allows (~20–25×) but
  **`emu.wait()` and `-seconds_to_run` count emulated seconds**, so any timing
  you measure is a true 4 MHz Z80 timing and transfers to hardware.
- End the script with `os.exit(0)`; letting MAME hit the budget often ends in a
  harmless but noisy macOS teardown segfault.

### The two harnesses in this family

| Harness | Where | Purpose |
|---|---|---|
| `tools/o1_mame_probe.lua` + `tools/check_o1_map.sh` | this repo | asserts `docs/o1-memory-io-map.md` (12 checks) against the running machine |
| `tools/research/mame-boot-probe.{lua,sh}` | this repo | boot one image on one machine: `A>` or not, screen dump, **screen geometry**, optional PNG |
| `o1harness.lua` + `run-test.sh` | `o1prsnt` | keyboard injection (`H.boot_cpm()`, `H.type_line()`) and screen assertions (`H.wait_for()`, `H.find()`, `H.dump()`) |

The boot probe is the one that produced the geometry table in §2 and the
screenshots in `docs/mame-screens/`. It is deliberately dependency-free; for
scripted tests that need to *type* at the machine, use `o1prsnt`'s harness.

**Screenshots.** MAME's Lua screen device has `screen:snapshot(path)`, which
works headless (`-video none`) and needs no display:

```lua
manager.machine.screens[":screen"]:snapshot("/tmp/shot.png")
```

The §4 boot matrix was produced with the second one plus a ten-line script:

```bash
cat o1harness.lua probe.lua > /tmp/run.lua
SDL_VIDEODRIVER=dummy mame osborne1nv -flop1 IMAGE -video none -sound none \
  -nothrottle -autoboot_script /tmp/run.lua -seconds_to_run 120 \
  -rompath tools/emulator-setup/roms
```

### Gotchas worth not rediscovering

1. **VRAM is a ring buffer.** The machine scrolls by rotating a hardware start
   register, not by moving memory, so a given screen line moves between VRAM
   rows after any scroll. Assert with whole-buffer substring searches, never
   fixed row reads.
2. **Pace your typing.** `natkeyboard:post()` drops characters if a second post
   arrives while the first is still being typed, and the guest flushes its input
   buffer around disk I/O. Wait for the prompt, then type (~0.15 s/character).
3. **MBASIC's `Ok` prompts are stale-prone** — count them (`H.ok_count()`) rather
   than matching `"Ok"`.
4. **MAME writes `cfg/` and `snap/` into the current directory** — run from a
   neutral directory so neither the repo nor your home dir collects litter.
5. The BIOS **waits for RETURN** ("Insert disk in Drive A and press RETURN.")
   before it loads anything; every automated test must press it.

## 7. Open items

1. ~~**#79** — why the Nuevo CBIOS 1.5 hangs (`OS1NUEVO.IMD`)~~ **Closed as not
   needed.** The Nuevo path is not pursued (§4) and #24 is built from the
   ScreenPac design plus OZROM's column switch. The hang is recorded rather than
   chased — and it is not a bad copy: Dunfield's pristine upstream behaves
   identically.
2. **The prefix → driver inference** in `tools/check_o1_map.sh` needs revisiting
   (§4): the `52-`/`80-`/`104-` prefix does not determine what a disk can boot.
3. **Identify the two differing bytes** at offsets 5737 and 5798 in the
   `-blank.imd` set — presumably a CBIOS video-mode selector, but unverified.
   A small disassembly job against the CBIOS in the system tracks.
4. **ROM 1.3 is undumped** and we hold its source disk — see
   `docs/o1-rom-variants.md`.
5. **OZROM 1E as a tool (#81)** — **closed.** It boots on all three machines (§5)
   and its manual is indexed in **`docs/ozrom-1e.md`**: memory map, ROM jump
   table, keytable, the 52/80/104-column switch and its mechanism, the clock and
   the memory tester. The one measurement still missing — driving the ctrl-shift
   column keys from the harness — is routed to **#167**.

## 8. Sources

- Adaption base: `Myrcurial/o1prsnt` — its `docs/emulating-the-osborne-1.md`,
  `utilities/headless-testing-harness/{README,DISCOVERY}.md` and
  `scripts/validate-emulator.sh`.
- Machine/ROM structure: MAME `src/mame/osborne/osborne1.cpp`
  (`ROM_START( osborne1 )`, `ROM_START( osborne1nv )`, the `COMP()` lines).
- ROM inventory and CRCs: `docs/o1-rom-variants.md`.
- Archive provenance: `research/README.md`.
- Disk pipeline and machine checks: `tools/README.md`.


