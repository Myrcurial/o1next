# tools/ — disk images, CP/M filesystems, scanned schematics, machine checks

## Pipeline

```
.td0 --[SAMdisk 4]--> .dsk (EDSK) --[edsk2raw.py]--> .raw --[cpmfs.py]--> files
.imd --[disk-analyse]--> .raw --[cpmfs.py]--> files
```

Run everything: `tools/extract_all.sh [path-to-samdisk]`

## Components

- **edsk2raw.py** — EXTENDED CPC DSK (SAMdisk output) to raw CP/M
  sector image. Sorts sectors by R id (handles interleave and Kaypro's
  side-continuous sector numbering: side0 = 0-9, side1 = 10-19).
  `--pad SECTRK,SECLEN` emits fixed-geometry images from partial dumps
  (missing sectors -> 0xE5).
- **cpmfs.py** — read-only CP/M 2.x list/extract (`ls`, `get`,
  `getall`). Explicit geometry presets: `osb1sssd` (Osborne 1 SD:
  40x10x256B FM, boottrk 3, 2K blocks), `kp2x`/`kpiv` (Kaypro DSDD:
  80 logical trk side-per-track x 10 x 512B, boottrk 1, 2K blocks).

## The machine's own typeface (`romfont.py`)

Decodes the character generator ROM (UA15, 2716) into a real font — the blog is
set in the letters the Osborne 1 drew on its own screen.

```
tools/romfont.py                      # write site/assets/fonts/*.{ttf,woff2}
tools/romfont.py --check              # fail if they are stale
tools/romfont.py --specimen /tmp/f.png   # render a sheet to look at
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
ASCII 0x20–0x7E only: the 0x00–0x1F graphics set is Osborne's own encoding rather
than Unicode, and mapping it would be a guess. Typographic punctuation (curly
quotes, en/em dashes) is mapped onto the machine's ASCII glyphs, because the
posts contain them and the alternative is the browser substituting a different
face mid-sentence.

Requires **fonttools** and **brotli** (`pip3 install fonttools brotli`) —
build-time only; the font files are committed.

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
  for extraction; cpmtools remains handy for quick probes.
- **z80dasm 1.2.0** (brew) — OK for spelunking; linear sweep misaligns
  around data tables.

## Disk format cheat sheet (learned during #2)

- Osborne 1 SD: FM, 40 cyl, 10x256B sectors, R=1..10, boottrk 3,
  dir 64 entries (2K blocks).
- Kaypro 2X/4/10: MFM, 40 cyl x 2 heads, 10x512B per side, R 0-based
  continuous across sides (0-9 / 10-19), physical interleave in R,
  dir at logical track 1 (= cyl 0 head 1), 64 entries, 2K blocks.
- RT-60A.TD0 (bitsavers) is a DAMAGED dump: 27 no-id sectors ignored
  by SAMdisk, most tracks fragmentary; filesystem extraction fails.
  Needs a re-dump (see #7).
