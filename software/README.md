# software/

Software that runs on the Osborne 1 itself (CP/M 2.2, 64 KB Z80) plus
its packaging. Host-side tooling lives in `tools/`; on-device code
lives in `firmware/`.

## Components

| Folder | Component | Issues | Difficulty |
|---|---|---|---|
| `mount-com/` | `MOUNT.COM` — mount disk images from the Pico-hosted library via mailbox port | #27 | Medium |
| `fatcopy/` | `FATCOPY.COM` — CP/M ↔ MS-DOS FAT12 (360K) file copy, PIP-sibling syntax | #51 | Medium |
| `copower88-driver/` | Osborne 1 host driver for CoPower-88 (real board or interposer shim) | #26, #3-#5 | Hard |
| `rt60a-clock/` | RT-60A host software replica: CLOCK.COM/CLKSET reimplemented from the manual (original TD0 dump is damaged) | #7, #37 | Medium |
| `boot-disk/` | Updated O1 boot disk: storage + RTC integration, the DD disk table (native formats only), bundled utilities | #28, #95 | Medium (integration) |

## No-new-code deliverables (documentation only)

Where existing period software does the job, the deliverable is a
setup/usage doc shipped in `docs/` and on the boot disk — not new code:

- **Drive C ramdisk / interposer hard disk on native CP/M** — the
  original Drive C driver and OCC1 hard disk driver work as-is once the
  corresponding personality is running (#22, #8); write usage notes.
- **Stock Zimodem** — until the fork (`firmware/zimodem-fork/`) lands,
  stock ESP32 Zimodem covers telnet; document known-good config.
- **FlashFloppy/Gotek** — publish a known-good `FF.CFG` for the O1 and
  the switchable floppy adapter (`hardware/floppy-adapter/`).
- **cpmtools / disk-analyse recipes** — image in/out workflows for
  development (upstream kpiv fix tracked separately as #35).

## Constraints

- 64 KB Z80 CP/M 2.2: tiny TPA footprint; assembly or compact C
  (e.g. z88dk/Hi-Tech) only.
- Everything must fit the updated boot disk (#28) alongside the
  period drivers.
- Utilities use the BIOS disk path and must coexist with the DD
  disk-table changes (#28, #95).
