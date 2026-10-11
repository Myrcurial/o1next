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
  bytes. See `docs/mame-emulation.md` §4. (Note for anyone writing their own:
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
