# occ1-harddisk — ACT 1982 Z80-interposer winchester personality (RP2350)

Emulates the **ACT (Australian Computer & Telecommunications) 1982
Osborne 1 hard disk** — itself a Z80-interposer design, so our
interposer can impersonate the whole product. We have the complete
original driver set (`research/harddisk/`, extracted from
`OCC1_HARDDISK.IMD`), so per project rule **"if we have drivers for
period hardware, we plan a personality for it"** this is a first-class
personality — and no Osborne-side driver code needs writing.

Tracks: #8, #32 (analysis: `docs/occ1-harddisk-analysis.md`).

## What the hardware was (from HARDBIOS disassembly)

- Custom host adapter plugged into the Z80 socket; device registers
  memory-mapped in bank 2:
  - **0x2A00** — command/data register (command byte written after
    bank select)
  - **0x2C01** — status register (bit 5 = status flag)
- Host code is a **full BIOS replacement** (`HARDBIOS.HEX` @ 0xDF00,
  17-jump entry table) installed by `LOADBIOS.COM`; `BOOTHd.COM` boots
  from the winchester; MOVCPM variants size 10/5MB volumes.
- Same bank discipline as Drive C: OUT (0x00)=bank 2 (IO),
  OUT (0x01)=bank 1 (RAM), DI/EI bracketed.

## Personality definition

- Answer reads/writes at 0x2A00/0x2C01 (bank 2) via the snoop/poke
  engine (`../bus-analyzer/`), implementing the command set inferred
  from HARDBIOS (+ the indirect `OUT (C),A` whose target is TBD —
  likely NMI/bank control; the bus analyzer resolves this on real
  hardware).
- Backing store: image files from the flash library / SD, sized per
  the MOVCPM variants (5/10 MB, and the TurboPac-era 33 MB notion —
  see `../drive-c-gpib/` TURBOPAC variant for the cache-in-front
  alternative).
- Acceptance: `LOADBIOS.COM` overlays cleanly on a real O1, machine
  boots CP/M from the emulated winchester via `BOOTHd.COM`.

## Deliverables

- Register emulation module + command-set state machine
- Disk-image format definition + tooling note (`tools/`)
- Bring-up log against the original driver set
