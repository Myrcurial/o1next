# acb4000-scsi — Adaptec ACB-4000 SCSI-1 personality (RP2350)

**Issue:** #179 (part of #8). **Status: the three layers are built and tested on
the host; the end-to-end acceptance — the period MD-10 software booting CP/M from
the emulated hard disk — is not reached, and the reason is named below.**

Emulates the **Adaptec ACB-4000**, the ANSI X3T9.2 SCSI-1 controller that the
Media Distributing **MD-10** hard disk was built on. Decided in #8
(`docs/harddisk-decision.md`); the design and the open end are in
`docs/acb4000-personality.md`.

It is the **controller** that is emulated — not the MD-10's host adapter
specifically. The host adapter is a small, configurable shim, so the same
firmware serves any Z80 machine with an ACB-4000-class driver and not only the
Osborne 1.

## Three layers (`harddisk-decision.md` §5), and where each one is

| Layer | File | What it is |
|---|---|---|
| 1. SCSI target | `acb4000_target.c` | the ACB-4000 command set, phases, status/sense, two LUNs, `MODE SELECT` geometry, `FORMAT` fill byte. Machine-independent; written to the OEM manual and to nothing else |
| 2. host-adapter shim | `acb4000_shim.c` | the Z80 port block, as **data**: profiles `md10` (base `30h`, measured from the driver) and `reference` (the OEM manual's Appendix A model) |
| 3. backing store | `acb4000_store.c` | the volume, behind five calls (`capacity`, `block_size`, `read`, `write`, `format`). On hardware this is the FAT32 blob (#180); on the host it is a buffer |

`acb4000.h` is the whole interface between them. Nothing above layer 2 knows a
Z80 address, and nothing below it knows a host exists — which is what makes the
target testable without a board.

## Running the tests

```sh
firmware/acb4000-scsi/run_tests.sh
```

No board, no SDK, no dependencies: plain C99 and a host compiler, the same shape
as `firmware/rom-ident/`. CI runs it (`.github/workflows/acb4000-scsi.yml`).

What the tests cover, and why each earns its place:

- **the register handshake, replayed from the driver's own routine.** The test
  suite contains a transcription of `HARDBIOS.SPR` file `0x285` (the MD-10 BIOS's
  transaction) rather than a convenient wrapper, so a wrong status bit map fails
  the suite instead of silently working in one direction. It is the closest the
  host gets to running the period software.
- **the geometry round trip.** `MODE SELECT` in, `MODE SENSE` out, byte for byte
  — because the MD-10's DPB is *derived* from what the controller reports
  (`docs/acb4000-firmware.md`), so this is the personality's correctness, not a
  nicety.
- **the commands that blocked the harness.** `VERIFY` (`2F`) and the
  `SEARCH DATA EQUAL` family (`31`) have no handler in MAME's generic SCSI
  target, which is why `PREP.COM` could not finish a format
  (`docs/osborne1ng-machine.md` §5).
- **`FORMAT`'s fill byte**, including `PREP.COM`'s unique-fill path — the
  property #180's sparse blob is built on.
- **the expanded set behind jumper I-J**, refused rather than quietly accepted
  when the jumper is off.
- **the two LUNs** (the MD-10's "units A and B") and **the `reference` profile**,
  which is the argument for layer 2 being data.

## What is authoritative

| Question | Source |
|---|---|
| command set, CDB lengths, data layouts, status and sense meanings | the OEM manual, `research/adaptec/acb4000/400003-00A_ACB-4000A_Users_Manual_Oct85.ocr.txt` (Table 5-1/5-2, sections 5.3–5.5) |
| the `md10` register block and status bit map | the driver — `docs/acb4000-host-adapter.md` §1, `docs/osborne1ng-machine.md` §3–§4 |
| the default geometry (`PYXIS13`) | `docs/harddisk-decision.md` §7.2, read out of `MD10.COM` |
| the controller's own firmware, as the oracle | `research/adaptec/acb4000/firmware/` (six 8 KiB ROMs) |

Two things are **inferred** and say so in the source: `TRANSLATE`'s byte widths
(the manual's figure 5-6 gives the field order, not the widths) and the commands
whose transfer length the manual does not pin (`WRITE`/`READ BUFFER`, the
diagnostics) — those accept the command and return status rather than inventing a
length.

## What is *not* built

- **The end-to-end acceptance.** `HARD.COM` reads LBA 5 for eleven blocks and
  jumps into what it read, so the drive has to *already carry an MD-10 system* —
  and the archive holds none: nothing initialises the low-RAM DPH/DPB tables at
  `0x055E`/`0x056E` (`docs/harddisk-decision.md` §7.3). That is #178's residue,
  not this personality's, and it is what `docs/acb4000-personality.md` records.
- **The FAT32 store.** `acb4000_store.c` ships the in-memory implementation. The
  blob format is #180 and the mailbox front end is #181.
- **The RP2350/PIO glue.** The register block is modelled, not driven; the PIO
  side is `firmware/bus-analyzer/`'s shared engine (#17) and the on-hardware
  validation is Phase 4 (#29).

## Deliverables

- [x] SCSI target module (CDB decode, phases, geometry, fill byte)
- [x] Host-adapter shim with the `md10` and `reference` profiles
- [x] Host test suite + CI
- [ ] Volume blob format definition + tooling note (`tools/`) — #180
- [ ] Bring-up log against the period MD-10 software (`HARD.COM` + the `.SPR`
      overlays) — blocked on an MD-10 system image
