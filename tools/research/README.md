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
- **`o1raw2imd.py`** — wraps a bare raw Osborne 1 SD sector image in an
  ImageDisk container. `imdmake.py` writes *blank* IMDs and `imdinfo.py` reads
  them; nothing wrapped a raw one, and MAME will not open a raw sector image.
  Written for #178, where the MD-10 utilities disks are held as raw 100 KiB
  `.img` files. Convention is the archive's own: the image is in physical track
  order with R = position+1, so the numbering map is the identity.
- **`o1keys.lua` + `o1keys.sh`** — the scripted-keystroke harness: boot a disk,
  then drive the guest with a list of directives (`wait`, `type`, `key`, `sleep`,
  `dump`, `shot`, `peek`). `o1disk-copy` types one command and waits for the
  prompt, which is not enough for a program that never returns to `A>` until you
  walk its menus. Written for #178 to run `MD10.COM`. **`key esc` is not
  usable** — posting `\27` segfaults MAME's Lua layer — and `peek` is the
  directive that made the editor's in-memory table checkable. Note
  `O1_ROMPATH` must be absolute, because MAME runs from a neutral directory.
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
- **`drivetbl.py`** — dumps the whole MD-10 drive table out of `DRIVETBL.DAT`.
  Written for #178 because `cpmfs.py get` cannot: the file's directory entry says
  128 bytes while it holds 16 512, so the table is only reachable by walking the
  block list. Prints each entry's name, description and geometry.
- **`mkdrive.py`** — builds a **blank but formatted** ST-506/MFM hard-disk image
  for any geometry, byte-wise, for the `osborne1ng` card to talk to (#191). The
  ACB-4000's `FORMAT` writes a fill pattern into every data field — `6C` hex
  unless the command says otherwise — so that is what this writes, and the
  geometry goes to `chdman`, whose `GDDD` metadata is the same record the
  controller keeps in the disk's ID fields. It exists because MAME's `SCSIHD`
  cannot finish a format (no `FORMAT UNIT`, no `SEARCH DATA EQUAL`), so
  `PREP.COM`'s initialize loops at *"Verifying disk (first pass)..."*. Needs
  `chdman` (`REQUIREMENTS.md`). See `docs/harddisk-decision.md` 7.2 and
  `docs/osborne1ng-machine.md` 5.
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
