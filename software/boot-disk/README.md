# boot-disk — updated O1 boot disk (packaging + integration)

The distribution vehicle for everything Osborne-side: a bootable O1
disk image with storage + RTC integration and the project's utilities,
validated against real media via the extraction pipeline (`tools/`).

Tracks: #28; the 1.44 DD CBIOS's DPB/skew table (`docs/dd-upgrade-formats.md`
— native formats only, #95), FATCOPY (#51), MOUNT (#27), Drive C / OCC1
usage docs (#22/#8), RT-60A (#18).

## Contents

- BIOS disk-table updates: the 1.44 DD CBIOS DPB/skew table as documented
  in `docs/dd-upgrade-formats.md`. **Foreign-format tables are not
  included** — the O1 does not need to recognise them (#95)
- RTC integration for the RT-60A personality (or real RT-60A)
- Storage drivers: original Drive C / OCC1 hard disk drivers (period
  code, redistributed with provenance notes) + usage docs
- Utilities: `FATCOPY.COM`, `MOUNT.COM`, plus useful period tools from
  the extracted Kaypro CP/M set where licensed/appropriate
- README/usage documentation on-disk

## Build

- Scripted assembly from parts (disk image built by `tools/cpmfs.py`
  pipeline) — reproducible, no hand-edited images.

## Deliverables

- Build script + `O1NG_BOOT.IMD`/`.TD0` image
- Validation: boots stock O1, O1 + interposer, and o1ng (#49)
