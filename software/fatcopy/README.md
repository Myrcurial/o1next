# fatcopy — FATCOPY.COM, CP/M ↔ FAT12 file copy (CP/M)

A PIP sibling that copies files between the O1's native CP/M disks and
MS-DOS FAT12 360K diskettes — so a stock O1 (native Z80 CP/M, no
CoPower-88) can exchange files with PC-formatted media.

Tracks: #51; ships on the updated boot disk (#28); physical read path
via the DD board / o1ng data separator (#49); coexists with the boot
disk's DD disk-table changes (#28, #95).

## Definition (deliberately small)

- **Read** FAT12 360K directories; copy files out to a CP/M drive.
- **Write** CP/M files into a FAT12 360K diskette (allocate directory
  entry + cluster chain). Root directory only for v1.
- PIP-style one-shot `from:to` syntax, e.g.
  `FATCOPY B:README.TXT A:` — exact UX TBD.
- FAT12 only (360K, 9×512, 40 tracks), 8.3 names, no subdirs v1.
- Physical sector access via the O1 BIOS disk table / DD path.
- 64 KB TPA machine: assembly or compact C, buffers of a few KB max.

## Deliverables

- `FATCOPY.COM` + source
- Short usage doc + FAT12 subset supported (`docs/`)
