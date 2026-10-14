# md10-system — the MD-10 operating system, as written by the 1984 installer (#179)

The **bootable half** of the MD-10: the disk label, the partition table and the
operating system that `HARD.COM` boots from a hard disk. The archive held the
*driver* (`research/adaptec/*.img`) and the *installer* (`PREP.COM`) but no
*system* — nothing in it initialised the low-RAM DPH/DPB tables, and no disk
carried a system image (`docs/harddisk-decision.md` §7.3). These files are that
system, captured off drives the vendor's own tool configured — in **two
layouts**, because the installer sizes its partitions from the drive it is given.

**They are not hand-written and not synthesised.** `PREP.COM` option 3
("Configure operating system") reads `HARDCCP.SPR` and `HARDBDOS.SPR` from the
2.01 utilities disk, relocates them and writes them to the drive; it reports
*"Relocating operating system... Writing operating system... Operating system
configuration complete"*. The recipe, the tooling and the measured memory map are
in `docs/md10-system.md`; `tools/research/md10drive.py` lays these two files onto
a fresh drive.

| File | Size | What it is |
|---|---|---|
| `lba0-15.bin` | 8 192 B | **PYXIS13, two partitions.** The first sixteen blocks of the drive: LBA 0 the disk label (`M`,`D` at +0, the label text at +14, the 28-byte partition records from +48), LBA 1–3 the rest of the header, LBA 4 a table, LBA 5–15 the operating system |
| `md10-os.bin` | 5 632 B | its operating system — LBA 5, 11 blocks (0x1600 bytes) — which is exactly what `HARD.COM`'s BIOS reads to `0xC200` and jumps into. **Relocated 0x100 high**, so it needs `tools/research/md10reloc.py` before it will boot (#198) |
| `lba0-15-p27.bin` | 8 192 B | **PYXIS27, THREE partitions.** Same structure, and the partition table is the driver's own static fallback table: `CP/M-CCP` 4+16, `CP/M-A` 20+15399, `CP/M-B` 15419+15399, `CP/M-C` 30818+15399. This is the layout whose partitions match the driver's shared DPB, so it is the one that is safe to write to — **the floor pin** |
| `md10-os-p27.bin` | 5 632 B | its operating system, **already at its load base** — entry `JP 0C4C8h` with `LD SP,nn` at the target — so no relocation step is needed |

Provenance: **generated in-project** by running the archive's own `PREP.COM`
under `osborne1nx` (the emulated interposer, #191) against a drive built by
`tools/research/mkdrive.py`, then `chdman extracthd`. The PYXIS13 pair was
captured on 2026-10-12 (the drive's md5 was
`7fa2a3836813dabdeaaa664ea88d002e`); the PYXIS27 pair on 2026-10-14, by
`tools/research/md10prep.sh 321,8,18 3`, and that script independently reproduces
it byte for byte. `tools/research/md10drive.py` reproduces either drive from its
pair (`--layout md10` / `--layout md20`), and `md10table.py` reads a drive back.

The sources it is derived from are the archive's own, so nothing here is a new
primary source in the "would we lose the work if the upstream link died?" sense
— but the *system* is not obtainable from the archive by reading, only by
running, and it took the MAME machine to run it. Kept in `research/` rather than
`docs/` because it is a **binary artifact**, and the repo's rule is that
`research/` holds the things a work cannot be completed without.
