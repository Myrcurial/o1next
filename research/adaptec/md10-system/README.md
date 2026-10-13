# md10-system — the MD-10 operating system, as written by the 1984 installer (#179)

The **bootable half** of the MD-10: the disk label, the partition table and the
operating system that `HARD.COM` boots from a hard disk. The archive held the
*driver* (`research/adaptec/*.img`) and the *installer* (`PREP.COM`) but no
*system* — nothing in it initialised the low-RAM DPH/DPB tables, and no disk
carried a system image (`docs/harddisk-decision.md` §7.3). These two files are
that system, captured off a drive the vendor's own tool configured.

**They are not hand-written and not synthesised.** `PREP.COM` option 3
("Configure operating system") reads `HARDCCP.SPR` and `HARDBDOS.SPR` from the
2.01 utilities disk, relocates them and writes them to the drive; it reports
*"Relocating operating system... Writing operating system... Operating system
configuration complete"*. The recipe, the tooling and the measured memory map are
in `docs/md10-system.md`; `tools/research/md10drive.py` lays these two files onto
a fresh drive.

| File | Size | What it is |
|---|---|---|
| `lba0-15.bin` | 8 192 B | the first sixteen blocks of the drive: LBA 0 the disk label (`M`,`D` at +0, the label text at +14, the 28-byte partition records from +48), LBA 1–3 the rest of the header, LBA 4 a table, LBA 5–15 the operating system |
| `md10-os.bin` | 5 632 B | just the operating system — LBA 5, 11 blocks (0x1600 bytes) — which is exactly what `HARD.COM`'s BIOS reads to `0xC200` and jumps into |

Provenance: **generated in-project on 2026-10-12** by running the archive's own
`PREP.COM` under `osborne1ng` (the emulated interposer, #191) against a drive
built by `tools/research/mkdrive.py`, then `chdman extracthd`. The drive's md5
was `7fa2a3836813dabdeaaa664ea88d002e`; `tools/research/md10drive.py` reproduces
it byte for byte from these two files.

The sources it is derived from are the archive's own, so nothing here is a new
primary source in the "would we lose the work if the upstream link died?" sense
— but the *system* is not obtainable from the archive by reading, only by
running, and it took the MAME machine to run it. Kept in `research/` rather than
`docs/` because it is a **binary artifact**, and the repo's rule is that
`research/` holds the things a work cannot be completed without.
