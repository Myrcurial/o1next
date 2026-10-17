# drive-c-gpib — Drive C IEEE-488 storage personality (RP2354B)

Pico-based GPIB device emulating the "Drive C" ramdisk and period
IEEE-488 hard-disk products. When this personality runs, the **original
period driver works unmodified** on the CP/M side — no new Osborne-side
code beyond usage docs (`software/README.md` no-new-code list).

Tracks: #22; protocol from #6 / `docs/drive-c-protocol.md`; OCC1 hard
disk analysis `docs/occ1-harddisk-analysis.md` (#8/#32).

## Definition

- Implement the Drive C GPIB device state machine per
  `docs/drive-c-protocol.md` (extracted from `DRIVE_C.IMD`, #33).
- Storage backing: RAM disk (persistent where possible) and/or image
  files from the library, shared with `../floppy-emulator/`.
- Reference GPIB implementation: NODISKEMU (nils-eilers) / cbmSD
  (cbmsteve.ca).
- Optionally present the OCC1 ACT-1982 winchester behavior as a second
  personality once its protocol write-up is complete (#8).

## Variant: TurboPac (Drive C + Trantor hard disk)

Per the Drive C user manual (`research/drive_c/Drive_C_Users_Manual.pdf`,
OCR stored alongside as `Drive_C_Users_Manual.ocr.txt`): **TurboPac** is
the Drive C / Trantor hard-disk system in which *Drive C becomes a
hi-speed cache buffer in front of the hard disk* — "increasing the hard
disk throughput by as much as five times."

- The hard disk attaches to the Drive C **PRINTER/HARD DISK/8088 port** —
  no mechanical modifications to the O1.
- **192K TurboPac:** all of Drive C is cache. **384K TurboPac:** 256K
  cache + 128K fixed print buffer.
- CP/M parameters differ: 8K blocks, 512 directory entries per logical
  drive, 10/20/33 MB capacities (manual §7-3).
- Detaching the hard disk returns Drive C to normal portable
  RAM-disk/print-buffer operation.

Emulation note: a TurboPac personality = this Drive C emulation **plus**
a hard-disk backing device on the downstream port, with the cache layer
implemented in firmware (or trivially: serve the hard disk image
directly and treat "cache" as a no-op — we have no rotational latency
to hide; but implement the software-visible partitioning faithfully so
the original TurboPac software behaves).

## Deliverables

- GPIB device emulation module (snoop/poke engine)
- Backing-store integration + web-UI controls
- Compatibility test notes against the original Drive C driver disk
  (`research/drive_c/`)
