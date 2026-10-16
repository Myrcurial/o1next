# tools/research/ — research & one-off code worth keeping

Home for code written along the way that is **not part of the finished
solution** but is worth preserving: disassembly helpers, one-shot
extraction scripts, protocol probes, format experiments, validation
scratch programs, "figuring it out" notebooks/scripts.

## Rules of the folder

- Anything here may be rough, uncommented, or half-finished — but it
  must carry a one-paragraph header saying **what it was for, which
  issue/research question it served, and what the outcome was**.
- If something here graduates into the product (e.g. a probe becomes
  part of the analyzer, an extractor becomes a build step), **move it
  out** to its proper home (`tools/`, `firmware/`, `software/`) and
  leave a pointer in this file's index.
- Nothing in this folder is built, shipped, or depended upon by the
  finished solution.

## Index

- **`imdinfo.py`** — stdlib-only ImageDisk (.imd) reader: reports an image's
  structure (mode/density, cylinders, heads, sector size, sectors per track) and
  can reconstruct a raw image. Written while working #70/#71/#79 because we kept
  needing to answer "what *is* this disk image?" and `disk-analyse` is an
  external dependency. Its reconstructed raw output is **byte-identical** to
  `disk-analyse`'s on the same image, which is how the parser was validated.
  Finding worth keeping: the `-blank.imd` boot disks are 250 kbps MFM, 40 tracks
  × 5 × 1024-byte sectors, single-sided — and all three differ by exactly two
  bytes. See `docs/mame-emulation.md` §4. **`--raw` de-skews**: each sector is
  placed at its *logical* offset, not its position in the file. The two differ
  whenever the numbering map is rotated, which is normal for single-density
  Osborne disks (`2,3,…,10,1`) — appending in file order rotates every track by
  one sector, and a rotated CP/M disk still parses, just into the wrong file
  list. It cost 8 files on `OZROM.IMD` before anyone noticed (#81). (Note for
  anyone writing their own:
  IMD has **no** "sector type map" — the type byte belongs to each sector's data
  record, and the optional cylinder/head maps are flagged in bits 7/6 of the
  *head* byte.)
- **`mame-boot-probe.lua` + `mame-boot-probe.sh`** — headless MAME boot probe:
  boots a floppy image on any of the three `osborne1` machines, reports whether
  it reached `A>`, dumps the screen from video RAM, reports the screen geometry
  and optionally saves a PNG. Written for #79, where it produced the measured
  52/80/104-column result and the screenshots in `docs/mame-screens/`. It is the
  self-contained counterpart to `o1prsnt`'s `o1harness.lua` (which adds keyboard
  typing and `wait_for` helpers — use that one for real scripted tests).
- **`imdmake.py`** — the *writer* half of `imdinfo.py`: emits a blank Osborne 1
  disk in ImageDisk form (`--dd` = 250 kbit MFM 40×5×1024, `--sd` = 250 kbit FM
  40×10×256, filled `0xE5`). Written for #95, which needed blank disks to copy
  onto. Two things worth knowing: the file **must** begin with an `IMD 1.x:` line
  or `disk-analyse` rejects it, and `imdinfo.py` (the reader) validates the
  output.
- **`o1disk-copy.lua` + `o1disk-copy.sh`** — the keyboard-injecting counterpart
  to the boot probe: boot `-flop1`, put another image in `-flop2`, wait for `A>`,
  type a CP/M command (e.g. `PIP B:=A:MBASIC.COM`) and report the screen. Written
  for #95 to move content on and off a second disk and read it back. **It must
  not call `os.exit()`** — MAME only flushes a modified image on a clean
  shutdown, so `os.exit()` silently discards guest writes. See
  `docs/dd-upgrade-formats.md`.
- **`o1raw2imd.py`** — wraps a bare raw Osborne 1 sector image in an ImageDisk
  container. `imdmake.py` writes *blank* IMDs and `imdinfo.py` reads them;
  nothing wrapped a raw one, and MAME will not open a raw sector image. Written
  for #178, where the MD-10 utilities disks are held as raw 100 KiB `.img`
  files. Convention is the archive's own: the image is in physical track order
  with R = position+1, so the numbering map is the identity. **`--dd`** wraps the
  double-density format (250 kbps MFM, 40 × 5 × 1024) instead of the SD one, and
  was added for #203: `cpmtools` writes *raw* volumes, so a CP/M disk built with
  `cpmcp` had to be wrapped before MAME could mount it, and the archive's DD
  images are already IMD — only a *new* DD volume needed this.
- **`o1keys.lua` + `o1keys.sh`** — the scripted-keystroke harness: boot a disk,
  then drive the guest with a list of directives (`wait`, `type`, `key`, `sleep`,
  `dump`, `shot`, `peek`). `o1disk-copy` types one command and waits for the
  prompt, which is not enough for a program that never returns to `A>` until you
  walk its menus. Written for #178 to run `MD10.COM`. **`key esc` is not
  usable** — posting `\27` segfaults MAME's Lua layer — and `peek` is the
  directive that made the editor's in-memory table checkable. **`poke` was added
  for #191**: patching a *file* in an image (`md10patch.py`) only reaches bytes
  the loader copies verbatim, so a run-time variable the program computes — the
  MD-10 host adapter's select byte at `0x8023`, say — has to be written while it
  runs. Without it the patched flow leaves the select byte `00h`, every
  transaction is delivered to no target, and the guest reports no error at all.
  Note `O1_ROMPATH` must be absolute, because MAME runs from a neutral directory.
  **`O1_MAME_EXTRA` replaces MAME's own arguments**, and its default is the
  `-nothrottle` every caller has always got; set it *empty* to run at the
  machine's real speed. That is what reading an assembler listing needs — the
  ACT80's is ~4700 lines and its error markers are inline in it, so unthrottled
  it scrolls past in under a second of wall time (#247 step 8, turn 3).
- **`acb4000.lua`** — a MAME-side *trace* of the MD-10's ACB-4000 host-adapter
  ports (`30h`–`33h`), written for #178 to watch the driver build its DPB. It
  produced the finding instead: MAME's `osborne1` decodes only two I/O address
  bits, so `30h`–`33h` alias onto the ROM-bank ports and a Lua stub cannot reach
  the adapter — the "stub it in MAME" route needs a driver change. Three traps
  worth knowing: a tap callback that touches `cpu.state["PC"]` throws (and the log
  line vanishes); the guest's console output floods these ports; and the taps go
  **silent** once a harness polls the program space from Lua, so run the trace
  standalone rather than through `o1keys.sh`. See `docs/acb4000-host-adapter.md`.
- **`md10patch.py`** — patches a file *inside* a raw Osborne image, addressed by
  name and file offset. Written for #178: `MD10.COM` refuses to start without an
  ACB-4000 on ports `30h`–`33h`, and MAME cannot emulate one, so three 3-byte
  patches step over the presence check and take the loaded table to the editor's
  menu — the overlay init call at `0x0219`, the probe at `0x15AF` and the branch
  at `0x0EE8` — and nothing else is touched. See
  `docs/harddisk-decision.md` 7.2.
- **`o1prep-patch.sh`** — build a *runnable* `PREP.COM` disk for `osborne1nx`, and
  the durable record of what had to be patched to get there (#191). The disk
  header `PREP.COM` writes is built at run time, so the only way to see it is to
  make the program write it — and the format/verify in front of it cannot finish
  under MAME, so an 8-byte patch over main-menu option 1 (`PREP.COM +0x0EE4`:
  `CALL sub_19a8h` — the probe, the drive address, and the card's select byte —
  then `JP 1200h`, the label build and the header write) takes it there. It has to
  be `1200h` and **not** the Disk initialization menu: the menu path never builds
  the label, so the partition table is left unterminated and *"Initializing all
  partitions..."* walks off the end of memory for ever. The archive image is never
  modified, the output is a new file, and the script prints the bytes that differ.
  Written as the seed of the bootstrap floppy the interposer will have to ship
  (#28, part of the interposer deliverable #136).
- **`drivetbl.py`** — dumps the whole MD-10 drive table out of `DRIVETBL.DAT`.
  Written for #178 because `cpmfs.py get` cannot: the file's directory entry says
  128 bytes while it holds 16 512, so the table is only reachable by walking the
  block list. Prints each entry's name, description and geometry.
- **`mkdrive.py`** — builds a **blank but formatted** ST-506/MFM hard-disk image
  for any geometry, byte-wise, for the `osborne1nx` card to talk to (#191). The
  ACB-4000's `FORMAT` writes a fill pattern into every data field — `6C` hex
  unless the command says otherwise — so that is what this writes, and the
  geometry goes to `chdman`, whose `GDDD` metadata is the same record the
  controller keeps in the disk's ID fields. It exists because MAME's `SCSIHD`
  cannot finish a format (no `FORMAT UNIT`, no `SEARCH DATA EQUAL`), so
  `PREP.COM`'s initialize loops at *"Verifying disk (first pass)..."*. Needs
  `chdman` (`REQUIREMENTS.md`). See `docs/harddisk-decision.md` 7.2 and
  `docs/osborne1nx-machine.md` 5.
  **`--label TEXT`** writes the MD-10 disk label into LBA 0 — `M`,`D` at `+0`, the
  text at `+14`, `FFh` at `+48` — which is what makes `PREP.COM` treat the drive
  as its own rather than answering *"Disk has unrecognizable format (or none)"*.
  The rule is measured: the check at `0x1B37` wants 512-byte blocks from
  `READ CAPACITY`, a successful `READ` of LBA 0, `M`,`D` at `+0`, and `+28 < 20h`.
  Without `--label` the drive is still a fine target for the card; it is just not
  one `PREP.COM` will initialise (`docs/osborne1nx-machine.md` 6).
- **`md10drive.py`** — builds a **bootable** MD-10 hard disk from small committed
  artifacts rather than a 23 MB blob (`--layout`, #247). Each layout pairs a
  header artifact with an O/S artifact and carries its own geometry and `E5h`
  directory regions:
  - **`md20`** (default) — **PYXIS27**, three 15399-block partitions at LBA 20 /
    15419 / 30818. This is the driver's *own static fallback table*, and the only
    layout whose partitions match the driver's shared DPB (`DSM = 1923` → 7.5 MiB
    usable), so it is the one that is safe to write to. **Floor pin.** Its O/S is
    already at its load base.
  - **`md10`** — **PYXIS13**, two partitions of 11544 blocks. The original
    capture. Its O/S sits 0x100 above the load address and needs `md10reloc.py`
    first, and its partitions are smaller than the DPB claims, so a large write
    to `A:` runs into `B:` — see `docs/md10-system.md` §9.1.
  `--chs` overrides the layout's geometry; `--os` lays a different O/S.
- **`md10reloc.py`** — moves a captured MD-10 O/S to the address `HARD.COM` loads
  it at, by re-applying the `.SPR` relocation (`HARDCCP.SPR` / `HARDBDOS.SPR`) at
  the right base — exact, not a patch. The shift is **derived per region** from
  the measured delta and that region's load base, so an already-correct capture is
  left alone; `--shift` overrides the derivation. It then **refuses to write** an
  image whose CCP entry does not land on `LD SP,nn`, because that image would
  warm-boot for ever (#198). Captures measured and they do **not** agree on a base
  — which is why the derivation replaced the old constant `0x100` (#247).
  - **A capture can sit *below* the load base, and it is shifted up.** `PREP.COM`
    *computes* the base rather than storing one — a bit-map walk with a
    self-patched `ADD A,<page>` at `2A9E`, the page being `*(0x0002)` minus a size
    accumulated over its own 24-byte drive-table records, with the CCP `0x16`
    pages below it and the BDOS `+8` above the CCP — so the bigger layouts miss:
    `1200,8,18 eq11` comes out at `0xB900` (nine pages low) and `321,8,18 eq11`
    at `0xC100`, while `eq3`/`eq6` and the standard options land on `0xC200`. The
    correction is a page *add*, so it works either way. The regions must agree on
    the shift, and the result is verified byte for byte against a drive that
    already booted (`docs/md10-system.md` §9.5).
- **`md10table.py`** — prints a drive's disk label, its 28-byte partition records,
  the LBA 4 runtime table and its `E5h` regions, from a raw image or a CHD. The
  readback half of the geometry capability: it is what says whether `md10prep.sh`
  produced the layout it was asked for (#247).
- **`md10dpb.py`** — the **driver patch** (#247): rewrites the MD-10's DPB and its
  three ALV pointers in `HARD.COM`, so CP/M's idea of a hard-disk partition can be
  something other than the shipped 15399 blocks. One DPB per drive is what the
  three descriptors *should* have — they share one, which is why three partitions
  cannot differ in size — and the ALVs are sized from each `DSM` and laid out in
  the RAM that is actually free (`DDC5-E0EF` then `EC00-EE7F`, 1451 bytes; the
  hand-over stub, the CBIOS and `DIRBUF` are never touched). It re-derives the
  shipped DPB field for field, so patching for 15399 reproduces the vendor's file
  **byte for byte**, and it **refuses** what does not fit, what is past PREP.COM's
  measured 8 MiB ceiling, and an unequal layout (three DPBs are 30 bytes of new
  data and `HARD.COM` has one byte free). `--selftest` is the derivation, the
  pocket arithmetic, the extent mask at every block size and the drive-count
  budget; `--check` reads a patched file back.
  - **`--bsh`** sets the CP/M block size. `6` (8 KiB blocks) is the one worth
    knowing: it costs nothing outside the DPB — the drive, the partition table,
    `PREP.COM` and the BIOS are unchanged — and it cuts the ALV to 121 bytes per
    drive, so the free 1451 bytes hold **11 partitions of 8 MiB** instead of 5.
    Measured to boot to `A0>` (`rom2-check.sh` with `O1_BSH=6`;
    `docs/md10-system.md` §9.3).
  - **`EXM`** is derived from Digital Research's own `DISKDEF.LIB`:
    `2**(BSH-3)-1`, **halved past 255 blocks**. An earlier revision read
    Alteration Guide Table 6-9's first column only and hardcoded the shipped
    `EXM=1` at `BSH=5` — right by accident — so every other block size got the
    `DSM < 256` value (7 where `BSH=6` wants 3). Fixed 2026-10-15; `--exm`
    overrides, and `--selftest` now checks all four block sizes.
  - **`--grow`** is the **N-drive build** (#247 step 6): it reads a configured
    drive's own label for the partition count and starts, and rewrites `HARD.COM`
    from three fixed descriptors to N — a five-byte-per-drive table (24-bit start
    + ALV pointer) in `DD6E-DDC4`, one shared DPH, one DPB, the ALVs in the free
    1451 bytes, and the two routines that change (`SELDSK`'s hard-disk tail and
    the LBA routine) inside the space they already occupy. Equal partitions are a
    condition of the build, not a convenience, because the DPB is shared.
    `--drive` takes a **raw** image. **Measured to boot and hold: eleven drives
    `A0>`..`K0>`** on `1200,8,18 eq11`, every one written and read back, each with
    its own ALV — `rom2drives.lua`, 27 checks (`docs/md10-system.md` §9.4).
    - **The defect it shipped with, for the record:** the first revision's LBA
      routine stored the CDB's LBA **byte-swapped** (`ld (0D9FCh),hl` writes `L`
      first; a `READ(6)` wants `LBA[15:8]` first). It booted, and every cell in
      RAM matched the vendor's driver's byte for byte, so the only thing that saw
      it was the *card*: `-log` and the `[:acb4000] CDB ..` trace, which showed
      drive `A:` being read as LBA `0x1400` instead of `0x0014`. Fixed by using
      the shipped idiom (`ld d,l` / `ld e,h` / `ld (0D9FCh),de`), and
      `rom2drives.lua` now checks the two CDB bytes **separately** — a
      byte-symmetric LBA hides the swap in the value.
- **`md10prep.sh`** — the **repeatable new-geometry capability** (#247): builds a
  blank labelled drive, drives the archive's own `PREP.COM` through its menus with
  `o1keys.lua`, reads the drive back, extracts the header and O/S artifacts, and
  reports the O/S's relocation base. `md10prep.sh 321,8,18 3 /tmp/md10` reproduces
  the PYXIS27 floor-pin drive **byte for byte**. `eqN` (e.g. `eq3`) is
  PREP.COM's option 4, "Non-standard equal drive partitioning", which is the only
  way to a bigger partition — and it is capped at 16384 blocks (8 MiB), measured.
  **It finishes the drive**: `PREP.COM` computes the O/S's relocation base rather
  than storing one, and the bigger layouts miss (`eq11` comes out at `0xB900`, nine
  pages low, which warm-boots for ever (#198)). So the script re-relocates the O/S
  with `md10reloc.py` and writes the corrected image back at LBA 5, reporting
  **`bootable.raw` / `bootable.chd`** — `configured.raw` stays exactly what the
  installer left. `1200,8,18 eq11` then boots from the ROM with no floppy to
  `A0>`..`K0>` (`docs/md10-system.md` §9.5).
  It is a *host* script — it wants
  MAME, the patched `osborne1nx` machine (`$O1_MAME`) and `chdman` — so it is not
  shipped tooling.

- **`hardbios.py`** — read the MD-10 hard-disk BIOS overlay. `jump` prints the
  CP/M 2.2 BIOS jump table with every target resolved and walks `SELDSK`'s DPH
  construction; `audit` searches the whole archive for writers of the low-RAM
  DPH/DPB table block. Written for #178, where it produced the **negative** result
  that bounds the DPB question: no file initialises `0x055E`/`0x056E`, so the
  numeric DPB is not in the files we hold. It also documents why reading
  `HARDBIOS.SPR` linearly misleads — the overlay is **relocatable**, and its
  jump-table operands and internal `JP`/`CALL` targets are offsets from the table
  rather than addresses, so a linear disassembler drifts into the data and invents
  instructions. See `docs/harddisk-decision.md` 7.3.
- **`drive-c-trace.lua`** — write taps on the O1's IEEE-488 PIA (`2900–2903`),
  logging every access while the real Drive C software runs. Written for #6; it
  is how the Drive C frame was *measured* rather than only read out of the
  disassembly (`docs/drive-c-protocol.md`). Write taps only, which is why it is
  stable — see the next entry.
- **`drive-c-box.lua`** — a **model of the Drive C box** built from that spec:
  decodes the port-B frame states, reconstructs the record address, stores
  128-byte blocks and answers reads. With it present the 1983 loader completes
  and PIP writes to `C:`. Two MAME gotchas are baked into it: a read tap that
  returns a value **segfaults MAME's Lua layer** on a longer run (a constant is
  fine), and re-fetching a space handle after taps are installed does too. Use it
  for short validation runs, not as a harness.
- **`mame-lua-probe.lua`** — what MAME's Lua API exposes inside a *running*
  machine, and how the O1's bank latch actually behaves (it does not persist).
  Written for #64 while working out how to check `docs/o1-memory-io-map.md`
  against the machine rather than against MAME's driver source; its findings
  graduated into `tools/o1_mame_probe.lua` and
  `docs/o1-mainboard-schematic.md` §7a, which is why the probe is the tool and
  this is the notebook. Still useful for poking at any MAME driver from Lua.
- **`rom144-reassemble.sh`** — the whole #203 job in one script: build a CP/M
  system disk carrying the safety copy of `ACT80.COM` (`research/act-assembler/`)
  and a second disk carrying `rom144.asm`, assemble `ACT B:ROM144 H=B:` under
  MAME, and compare the result with `research/roms/os1-144.rom`. It is mostly a
  record of what each step cost to learn — `AUTOST.COM` must come off the system
  disk (it runs HELP.COM's menu and ESC is unusable in the harness), the source
  must be normalised to CRLF, and drive B needs room for 83 KB of source *and* a
  12 KB hex file. Result: the assembled image is identical to the shipped ROM,
  CRC32 `c0596b14`. See `docs/o1-rom-source.md`.
- **`acthex.py`** — the last step of that job: SORCIM ACT's `H=` output back into
  a flat ROM image. `LOAD.COM` cannot do it (an ORG-0 hex file is *"INVERTED LOAD
  ADDRESS, LOAD ADDRESS 0000"* to it), so it happens on the host. Three ACT
  facts are baked in: records are ordinary Intel HEX and validate under the
  standard checksum; they cover only the bytes the source wrote, so the *gaps*
  need a `--fill` (the 1.44 ROM holds `00` there — `ff` leaves 42 bytes wrong);
  and the file ends with ACT's own four-byte `:00010010` terminator rather than
  `:00000001FF`. `--recover-ff` handles the one damage #203 actually saw — a
  record that reaches the image with six non-hex bytes in it — and only when the
  record's *own* checksum agrees that its content was 16 bytes of `FF`.
  Two more options exist for the damage that arrives as a *run* of records
  replaced by `0xC0DE` pairs, where the checksum says nothing (#247): every gap is
  reported, `--fill-reference ROM` takes the gap bytes from the reference — the
  honest fill for a ROM 2.0 build, which *is* the shipped 1.44 with new code above
  `0F67h` — and `--covered-range LO HI` **refuses to build** (exit 2) when a gap
  falls inside the new code's own range, which is the one place a gap must never
  be. See `docs/rom-13-reconstruction.md` §7 for the hazard itself.
- **`rom2strokes.py`** — reads the authored boot-screen art as *geometry*, to see
  whether it fits ROM 2.00's **497-byte** window spare, and settles that it does
  not need to. Three findings, all measured (#83):
  **the stripes are free** — the art is 14 content rows interleaved with 14 blank
  ones, so a stem spanning nine content rows is one continuous stem the machine
  draws on alternate rows; fill the stripes back in, cover the letterform with
  rectangles, draw them back through the mask and compare: **exact, 0 sub-pixels
  wrong on every letter**; **but it does not fit anyway** — raw bitmap 857 B, RLE
  816 B, the exact rectangle cover 784 B, because the letters are ~40% ink and the
  cover is dominated by diagonals (the X is 72 rectangles where it is structurally
  two strokes); **and a segment model would be smaller but was not converged** — a
  greedy fit over the two diagonal families recovers only 56–76% of the ink, so
  that route is estimated, not demonstrated. `--frame` writes the answer instead:
  one window page is 4096 bytes and the video buffer is 128 × 32 = 4096 cells, so
  **one page is exactly one screen** and a frame is one `LDIR` — about 40 bytes of
  ROM, with the frame in the Pico's own flash. `--origin` picks which 128
  columns of the 153-column art survive; the default keeps the *logo* and drops
  the hatch. See `research/boot-screen/README.md`.
  **The artifact is two halves** (2026-10-15, #247 step 8): the O1's video cell is
  nine bits and the ninth is not in the video RAM but in a separate 4K×1 array that
  `OUT (02h)` pages in, so `--frame` writes **8192 bytes — the character half then
  the attribute half**, each a window page with **its own `O1NEXT` + 16-bit-sum
  trailer at its own `0FF8h`**, and v1.0's attribute half is all `FFh` (every cell
  bright; the ROM blits it whenever it validates, so dim accents need no ROM
  change later). `--half chars|attrs` writes one half — the shape the ROM's
  `PRESENT(1)`/`PRESENT(2)` delivers — and `--verify` validates a frame, or a
  single half, off the disk with no art and no chargen, which is the whole
  machine-free test. The committed asset is `firmware/rom-service/frame.bin`, and
  `--check` re-builds it and compares bytes so the art and the firmware's copy
  cannot drift.
  `--png` renders the character half with the character generator, and `--logo`
  renders the *art* as the site masthead — light glyphs on a transparent ground,
  i.e. the screen inverted, because the site header is the machine's blue panel and
  the Osborne's CRT was paper white. `--logo` keeps the art's **graphics only**: the
  version caption and the `press return to begin` prompt are *text* in the art's
  alphabet, so they are the boot screen's alone and do not belong on a wordmark.
  All 48 text cells in the art lie inside those two captions, and `a` — the blank
  cell — is itself in the text range, so a dropped cell draws the same nothing.
  `--check` re-renders the masthead in memory and compares it with the committed
  `site/assets/o1next-logo.png`, byte for byte, exiting non-zero if it has gone
  stale — and does the same for the frame. It needs the standard library and files
  in the repo, and nothing else, so
  `.github/workflows/generated-artifacts.yml` runs it.
- **`rom2image.py`** — ROM 2.0's build (#83, deliverable 2): assembles the
  **7695-byte image** from the repo's own files and re-checks every anchor the
  design quotes, exiting non-zero if one moves. In: the monitor (the stock 1.44, or
  ROM 2.0's), the CBIOS off `OS1SYSD.IMD`, the MD-10 BIOS image plus the vendor's
  60-byte loader block out of `HARD.COM` on the 2.01 utilities disk, and the
  14-byte hand-over stub (#247). Out: monitor at `0000`, then the payload in the
  window — CBIOS `1000`, MD-10 BIOS `1800`, the vendor's loader block `1DC5`, the
  stub `1E01`, and **497 bytes spare** for the boot screen and the new features.
  **`--hard`** takes a *raw* `HARD.COM` instead of pulling the vendor's off
  `--harddisk`, which is how a patched driver gets in without writing a CP/M
  image just to change 15 bytes of DPB (`md10dpb.py`, and `rom2-check.sh`'s
  `O1_BSH`).
  Things worth knowing: **`HARD.COM` is a CP/M `.COM`, so its file offset is its
  address minus `0x0100`** (reading the length operand at `0x0547` as a file offset
  gives `0x6F3A` instead of `0x05C5`); the loader block is the *vendor's own 60
  bytes* with exactly two operands relocated — the `LD HL,nn` source address and
  the `LD BC,(nn)` length — and **nothing calls it**, because the machine forces
  `HCBOOT` to do that work in the monitor (`docs/o1-rom-2.0.md` §4.6); and the
  stub's address and length are a *cross-file* anchor, so the tool looks for
  `HCBOOT`'s own `LD HL,1E01h / LD DE,0E0F0h / LD C,0Eh / LDIR` in the monitor and
  fails the build if the two files disagree. Built on the stock monitor the image
  is a **content image** and does not boot; built on ROM 2.0's it boots (§4.6, §7).
  See `docs/o1-rom-2.0.md` §2.3 and §6.
