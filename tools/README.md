# tools/ — disk images, CP/M filesystems, scanned schematics, machine checks

## Pipeline

```
.td0 --[SAMdisk 4]--> .dsk (EDSK) --[edsk2raw.py]--> .raw --[cpmfs.py]--> files
.imd --[disk-analyse]--> .raw --[cpmfs.py]--> files
```

Run everything: `tools/extract_all.sh [path-to-samdisk]`

## Bringing a machine up (`bootstrap.sh`)

Every row of `REQUIREMENTS.md` §Required, executable:

```
tools/bootstrap.sh --check     # ok / MISSING / DEAD per row; exit 1 if short
tools/bootstrap.sh             # install what is missing (Homebrew + repo .venv)
tools/bootstrap.sh --all       # ...then clear the dead /usr/local relics (sudo)
tools/bootstrap.sh --dry-run   # print the plan, change nothing
```

It checks that a tool *runs*, not merely that it resolves. `command -v gs` will
happily return a 2013 Intel binary on a host with no Rosetta — present to a loop
over `command -v`, a corpse to anything that calls it. `DEAD` is that state, and
telling it apart from `MISSING` is the reason this is a script.

It cannot install `disk-analyse` or SAMdisk (built from source, not in Homebrew),
and it will not guess about another machine's `/usr/local` tree: it prints what
it found and leaves the decision. `--legacy` is the one destructive mode — it
needs `sudo`, and it removes only the paths it names, skipping anything native or
under the Homebrew prefix.

## Components

- **edsk2raw.py** — EXTENDED CPC DSK (SAMdisk output) to raw CP/M
  sector image. Sorts sectors by R id (handles interleave and Kaypro's
  side-continuous sector numbering: side0 = 0-9, side1 = 10-19).
  `--pad SECTRK,SECLEN` emits fixed-geometry images from partial dumps
  (missing sectors -> 0xE5).
- **cpmfs.py** — read-only CP/M 2.x list/extract (`ls`, `get`,
  `getall`). Explicit geometry presets: `osb1sssd` (Osborne 1 SD:
  40x10x256B FM, boottrk 3, 2K blocks, **skew 2**), `kp2x`/`kpiv`
  (Kaypro DSDD: 80 logical trk side-per-track x 10 x 512B, boottrk 1,
  2K blocks), `drivec` (the Drive C RAM disk blob). Each preset carries
  the format's `skew`; see "Sector skew" below.

## Sector skew — why a raw image needs it, and why it bit us

A raw image stores each track's sectors in **physical** order, but CP/M numbers
them in **logical** order; on an interleaved disk the two differ, and the format
describes the mapping with a `skew` factor (cpmtools' diskdef field of the same
name). `cpmfs.py` reproduces cpmtools' table generation exactly — for the
Osborne 1 SD format (`skew 2`, 10 sectors/track) it is

```
logical  0 1 2 3 4 5 6 7 8 9
physical 0 2 4 6 8 1 3 5 7 9
```

so consecutive logical sectors sit two physical sectors apart. Without it,
`osb1sssd` still listed the right files — because the three directory sectors in
use all happened to land inside block 0 in *some* order — while every **file
body** was read from sectors that were never written, i.e. a uniform `0xE5`.
That is what made `research/roms/OZROM-1E/OZROM_1E_Utilities.IMD` look
"partially erased"; with the skew, all twenty files extract whole. Full story in
`docs/ozrom-1e.md` §10.2/§10.4 and **#170**.

`skew` defaults to 1 (identity) for the non-interleaved presets (`kp2x`,
`drivec`), so their output is byte-for-byte what it always was. `osb1sssd` is
checked against cpmtools on the three in-archive SD images
(`OZROM_1E_Utilities.IMD`, `DRIVE_C.IMD`, `OCC1_HARDDISK.IMD`): every file
matches `cpmcp -T raw -f osb1sssd` exactly.

## cpmtools against a raw image: always pass `-T raw`

`cpmls`, `cpmcp`, `cpmrm` and friends ask **libdsk** to autodetect the container
unless they are told otherwise — and libdsk **1.4.2**, the release Homebrew
ships, misreports a raw CP/M image as a *system* error out of its IMD driver:

```
$ cpmls -f drivec d.img
cpmls: cannot open d.img (No such file or directory)
```

on a file that is plainly there. `mkfs.cpm` is unaffected: it opens the file
directly and never consults libdsk. Name the driver and everything works:

```
mkfs.cpm -f drivec d.img                      # no -T: mkfs never asks libdsk
cpmcp -T raw -f drivec d.img hello.txt 0:HELLO.TXT
cpmls  -T raw -f drivec d.img                 # -> 0: hello.txt
cpmcp -T raw -f drivec d.img 0:HELLO.TXT hello.out
```

`raw` is `dc_posix`, the "Raw file driver" — the driver libdsk's own probe was
*supposed* to select — so this is the correct invocation, not a workaround.
`-T logical` works equally well. Fixed in libdsk 1.5.x, which upstream labels the
*development* line; the diagnosis, the measurement and the backport request are
in `docs/drive-c-design.md` §4.2 and **#157**.

## The machine's own typeface (`romfont.py`)

Decodes the character generator ROM (UA15, 2716) into a real font — the blog is
set in the letters the Osborne 1 drew on its own screen.

```
tools/romfont.py                      # write site/assets/fonts/*.{ttf,woff2}
tools/romfont.py --check              # fail if they are stale
tools/romfont.py --specimen /tmp/f.png   # render a sheet to look at
tools/romfont.py --art-sheet /tmp/a.png  # the graphics set, labelled for authoring
```

Two things make this worth a tool rather than a one-off:

- **The layout is not glyph-contiguous.** The byte for scanline `ra` of character
  `chr` is `rom[ra * 128 + chr]` — all 128 characters' row 0, then row 1, and so
  on. 10 rows × 128 characters = 1280 bytes; the rest of the 2 KiB is `0xFF`.
  This comes from MAME's `osborne1` driver, not from guessing (see
  `docs/o1-rom-variants.md` §"How the font is stored" for the trail of failed
  guesses).
- **It verifies itself.** It reloads the font it just built, rasterises every
  glyph back to 8×10 bits and compares them against the ROM; if that fails it
  writes nothing. `--check` regenerates and compares bytes for CI, the same shape
  as `gen_rom_table.py` and `check_schematics.py`.

Glyphs are one rectangle per run of set pixels, so the outlines are exact.
Typographic punctuation (curly quotes, en/em dashes) is mapped onto the machine's
ASCII glyphs, because the posts contain them and the alternative is the browser
substituting a different face mid-sentence.

**The graphics set ships too, as a second face** (`osborne1-art-*`, #97). The
0x00–0x1F block glyphs, 0x20 and the 0x7F hatch are not in the *text* family,
because mapping them would be a guess — but they are what the machine draws
*with*: the AUTOCPM/AUTOST boot art is a wall of these characters. So the art face
maps each glyph to its charcode **+ 65**, which is the arithmetic the ROM's own
loader does (`sui 65`):

```
'A' (0x41) -> glyph 0x00    ...    'a' (0x61) -> the blank    ...    U+00C0 -> 0x7F
```

Type the art as text, switch the font, and the picture appears. The cell is 8×10
and one line is exactly one em, so at line-height 1.0 the cells tile with no
seams. It sidesteps #97 rather than pre-empting it: the face needs the
*arithmetic*, #97 needs the *identification*, and the identification is a job of
looking at the art — which is what this renders. `--art-sheet` is the key, every
glyph labelled with the character that draws it.

**The face maps two halves, because art carries text as well as graphics.** ROM
2.00's boot screen has *"press return to begin"* nested in a letterform, and
those are the machine's ordinary letters: `sui 65` cannot reach them, because `p`
is 0x70 and 0x70 − 65 = 0x2F is not a glyph. So 0x41–0x61 maps to the graphics
glyphs (charcode + 65) and **every other printable codepoint maps to the machine's
own glyph for that code** — 34 graphics plus 62 text, one face, and the same split
the ROM's printer branches on.

The verification covers the **cmap** as well as the outlines, for both faces. A
font whose glyphs are perfect but whose mapping is off by one draws a *plausible*
picture that is simply wrong, which is far harder to notice than a blank cell.

Requires **fonttools** and **brotli** in the repo `.venv` that
`tools/bootstrap.sh` creates — build-time only; the font files are committed.

```sh
tools/bootstrap.sh                          # creates .venv, among other things
.venv/bin/python tools/romfont.py --check   # what CI runs as `python3`
```

The venv rather than a bare `pip3 install fonttools brotli`, because Homebrew's
Python is PEP 668 externally-managed and refuses that install outright, and
because which interpreter `python3` resolves to is a property of the *machine*
rather than the repo — so the repo carries its own. CI is unaffected: it installs
both into its runner's Python and runs `python3 tools/romfont.py --check`. The
tool is the same either way.

## Reading scanned schematics (`schematic_render.sh`, `schematic_atlas.sh`)

Renders sheets — or a zoomed region of one sheet — from a scanned schematic
PDF. The archive schematics are 600 dpi bilevel scans; scaled to a screen the
pin numbers are unreadable, and the PDF's own text layer is a 1990s OCR pass
full of garbage, so they have to be read one region at a time at native
resolution.

```
tools/schematic_atlas.sh PDF [OUTDIR]                     # overview + tile grid, all sheets
tools/schematic_atlas.sh PDF build/atlas --sheet 5 --cols 3 --rows 3
tools/schematic_render.sh PDF --info                      # sheet size in px, page count
tools/schematic_render.sh PDF OUTDIR --sheet 12 --dpi 600 # one sheet, native res
tools/schematic_render.sh PDF OUTDIR --sheet 12 --dpi 600 --crop X Y W H
```

`schematic_atlas.sh` writes `OUTDIR/index.md` mapping every tile to the pixel
box it covers, plus `OUTDIR/sheet-NN/overview.png` and `rRcC.png` tiles. It
defaults to `build/atlas/` — gitignored, because the tiles are regenerable and
the *coordinates* are the durable part, so a region found by eye once can be
re-rendered exactly with `schematic_render.sh --crop`. Both tools require
poppler (`pdftoppm`, `pdfinfo`) — already needed by `ocr_pdf.sh`.

**Part numbers must be read at native resolution.** At 300 dpi `LS00`/`LS08`
and `LS138`/`LS139` are indistinguishable; an overview pass over the O1
mainboard got both wrong. The sheet index, the regions read this way, and what
that caution means for the device lists are in
`docs/o1-mainboard-schematic.md`.

## Machine checks (`check_o1_map.sh`)

Boots an Osborne 1 headlessly under MAME and interrogates it over its own bus,
then asserts what `docs/o1-memory-io-map.md` claims — which pages are RAM,
where the ROM is and how it mirrors, what the bank-switch ports do, and which
bank-2 I/O windows answer.

```
tools/check_o1_map.sh                    # 12 checks, exits non-zero on failure
O1_ROMPATH=... O1_FLOPPY=... O1_MACHINE=... O1_SECONDS=180 tools/check_o1_map.sh
```

`tools/o1_mame_probe.lua` holds the assertions and the method (RAM is told from
ROM by writing back the complement of the byte that was there and restoring it).

Requires `mame` and a ROM path. If the ROMs sit loose in one directory rather
than in an `osborne1/` directory or an `osborne1.zip`, the wrapper builds a
temporary rompath containing an `osborne1` symlink rather than making you
rearrange them.

**The boot image's name is a label, not a driver.** The `52-`/`80-`/`104-`
prefix records the video mode an image was prepared for, but it does **not** gate
what the image can boot: measured against MAME, all three of
`emulator-setup/floppies/*.imd` boot on `osborne1`, `osborne1sp` **and**
`osborne1nv`. What gates bootability is the CBIOS on the disk. The wrapper still
derives the machine from the prefix (52 → `osborne1`, 104 → `osborne1sp`,
80 → `osborne1nv`) and warns when it selects anything but the stock machine, but
pass `O1_MACHINE` explicitly when it matters. The measured matrix, and why the
Nuevo system disk is a separate problem, are in `docs/mame-emulation.md` §4.

It is the counterpart to `check_schematics.py`: that one checks our own boards,
this one checks our *understanding of the machine* against the machine. It has
already earned its keep — see `docs/o1-mainboard-schematic.md` §7a.

## Emulator setup (`emulator-setup/`)

The ROM sets and blank boot images the MAME checks need, committed so the
harness is reproducible without hunting for dumps:

- `emulator-setup/roms/` — **one `osborne1.zip` serves all three machines**
  (`osborne1`, `osborne1sp`, `osborne1nv`): `rev1.40.ud11`, `rev1.43.ud11`,
  `3a10082-00rev-e.ud11`, `char.ua15`, `7a3007-00.ud15`,
  `monrom-rev1.51-12.ud11`. `mame osborne1nv -verifyroms` reports *good*;
  `osborne1` and `osborne1sp` report *best available* because the only missing
  ROMs are the four BIOS revisions that have never been dumped (A, 1.2, 1.2.1,
  1.3). Per-machine requirement table: `docs/mame-emulation.md` §3; CRC
  inventory: `docs/o1-rom-variants.md`.
- `emulator-setup/floppies/` — `52-blank.imd`, `80-blank.imd`, `104-blank.imd`.
  Despite the name they are **not blank**: each is a double-density CP/M 2.2
  system disk (CBIOS 1.4, MBASIC, SYSGEN, PIP, SETUP, XDIR, XREF …), and the
  three differ by exactly two bytes in the boot area. All three boot on all
  three machines — see the correction above.

The ROMs duplicate `research/roms/` deliberately: `research/` is the
provenance-tracked archive, this directory is a working rompath. If the two
ever disagree, `docs/o1-rom-variants.md` is the tie-breaker.

- `emulator-setup/mame-osborne1ng/` — the **fourth machine** (#191), as a patch
  against a stock MAME source tree: `osborne1ng`, a clone of `osborne1` whose Z80
  sits behind an emulated card that decodes the full 8-bit I/O address, so the
  MD-10's ACB-4000 host adapter can answer on `30h`–`33h`. `apply.sh` patches a
  tree, builds the `osborne` subtarget and runs `o1ng-probe.lua`; the whole
  story is `docs/osborne1ng-machine.md`. It is *not* part of `research/` and not
  a fork — five files, shaped to be sent upstream.

Full setup, launch, disk-tool and headless-testing instructions:
**`docs/mame-emulation.md`**.

## Schematic checking (`check_schematics.py`)

Regenerates each board's netlist with `kicad-cli` and asserts the electrical
invariants the design depends on. Run it before committing any `.kicad_sch`
or `gen_*_sch.py` change:

```
python3 tools/check_schematics.py          # all boards
python3 tools/check_schematics.py -v       # per-net detail
```

Why it exists: a schematic can pass structural ERC and still be electrically
wrong. The interposer generators placed every pin mirrored (`y + py` where
KiCad needs `y - py`), and reva had a '595 sitting directly on top of a '165 —
ERC reported only `label_dangling` / `pin_not_connected`, nothing that named
the fault. Reading the netlist pin by pin found both. What it checks:

- **Datasheet pinouts.** Z80 DIP-40 (pin 11 = +5V, 29 = GND, 30 = A0) on every
  connector/CPU that mates with the O1's socket.
- **Connector pin usage.** The Gotek header carries exactly Loxley's 11 signal
  lines and never a power rail or 4 MHz; drive B is never switched.
- **Sheet geometry.** No two symbol bodies overlap, and no two differently
  named labels sit on the same point (that is a short).
- **No `NC` net.** Labelling unused pins "NC" ties them all together — on reva
  that joined four unused 74AHCT595 totem-pole outputs. Use no-connect flags.
- **ERC budget.** Per-type ceilings; any new violation type or any increase
  fails, so regressions cannot hide in the warning noise. Keyed on the type
  only — KiCad renames checks and moves them between error and warning across
  releases (KiCad 9's `label_dangling` error is KiCad 10's `isolated_pin_label`
  warning), so a severity-keyed budget would pin the gate to one KiCad version.
- **Generator drift.** Regenerates each board and compares netlists, so a
  committed `.kicad_sch` cannot silently diverge from its generator.

CI runs it on every change to `hardware/**/*.kicad_sch` or `gen_*_sch.py`
(`.github/workflows/schematic-check.yml`). Requires `kicad-cli` (KiCad 7+);
set `KICAD_CLI` if it is not on PATH. Standard library only.

## Tool evaluation notes (why this exists)

- **SAMdisk 4** (Simon Owen; built from source, macOS: cmake) —
  decodes TeleDisk TD0 including advanced compression. Cannot write
  IMD; refuses raw output for non-sequential sector ids -> we bridge
  via EDSK. `samdisk copy in.td0 out.dsk`.
- **disk-analyse** (Keir Fraser, Disk-Utilities) — does NOT read TD0,
  but converts IMD -> raw img cleanly and reports per-track format
  (great for unknown disks).
- **libdsk dsktrans** — failed on the Kaypro TD0 ("Bad format" after
  decompression checks) and on SAMdisk EDSK output.
- **cpmtools 2.23** (homebrew cpmls/cpmcp) — worked perfectly for
  Osborne SSSD (`osb1sssd`) raws, but silently misread the Kaypro DSDD
  image (stock `kpiv` def has blocksize 2048 vs actual directory
  structure; even corrected defs produced garbage, cause not fully
  diagnosed — possibly sides/boottrk handling). cpmfs.py replaces it
  for extraction; cpmtools remains handy for quick probes. On libdsk
  1.4.2 every call needs `-T raw` — see "cpmtools against a raw image"
  above, and #157 for why.
- **z80dasm 1.2.0** (brew) — OK for spelunking; linear sweep misaligns
  around data tables.

## Disk format cheat sheet (learned during #2)

- Osborne 1 SD: FM, 40 cyl, 10x256B sectors, R=1..10, **2:1 sector
  skew** (logical→physical `0 2 4 6 8 1 3 5 7 9`), boottrk 3,
  dir 64 entries (2K blocks).
- Kaypro 2X/4/10: MFM, 40 cyl x 2 heads, 10x512B per side, R 0-based
  continuous across sides (0-9 / 10-19), physical interleave in R,
  dir at logical track 1 (= cyl 0 head 1), 64 entries, 2K blocks.
- RT-60A.TD0 (bitsavers) is a DAMAGED dump: 27 no-id sectors ignored
  by SAMdisk, most tracks fragmentary; filesystem extraction fails.
  Needs a re-dump (see #7).

## Osborne graphics art (`o1art.py`)

Renders an image as Osborne 1 graphics characters — the AUTOCPM technique. The
original boot logo (`AUTOCPM.ASM`, 10/12/81, Thom Hogan) is a picture drawn in the
machine's own 0x00-0x1F glyph set, a half-block/quarter/diagonal set that gives
four bits of picture per character cell. The loader enables it with `sui 65`:
subtract 65 from every byte so ASCII letters index the glyphs.

```
tools/o1art.py IMAGE OUTDIR [--name NAME] [--cells 104]
```

For every cell it picks the ROM glyph that matches that cell's 2x2 sub-pattern
with least pixel error, so nothing is drawn by hand and the diagonals are used
where they help. Two artifacts: `NAME.art.txt`, the art as ASCII `db` lines (the
*source*, assembler-ready, the same form as AUTOCPM) and `NAME.png`, the art
rendered with the ROM's glyphs.

The site's masthead *used to* be generated this way — the traced
`site/assets/o1nextgen-wordmark.svg` (from the Osborne Computer Corporation
logotype) went in, and `site/assets/o1nextgen-logo.art.txt` came out. It is not
any more. Since #83 the masthead is the **boot screen's own art**, drawn rather
than downsampled, because rasterising a traced outline at this size stair-steps:

```
tools/research/rom2strokes.py --logo site/assets/o1nextgen-logo.png
```

That takes `research/boot-screen/o1next-art.txt` and keeps the art's graphics
only, so the wordmark carries no boot-screen text. The old `.art.txt` is kept as
the record of the earlier approach.

Needs `sips` for non-SVG input and `qlmanage` for SVG — both macOS built-ins.
