# acb4000-scsi — Adaptec ACB-4000 SCSI target personality (RP2350)

Emulates the **Adaptec ACB-4000**, the ANSI X3T9.2 SCSI-1 controller that the
Media Distributing **MD-10** hard disk was built on. Decided in #8
(`docs/harddisk-decision.md`).

It is the **controller** that is emulated — not the MD-10's host adapter
specifically. The host adapter is a small, configurable shim, so the same
firmware serves any Z80 machine with an ACB-4000-class driver and not only the
Osborne 1.

Tracks: #8 (decision and personality). Analysis in
`docs/occ1-harddisk-analysis.md`; the decision and plan in
`docs/harddisk-decision.md`; the controller contract in the OEM manual,
`research/adaptec/acb4000/500504-00_ACB-4000_OEM_Manual_Mar84.pdf`.

## Three layers (`harddisk-decision.md` §5)

1. **SCSI target** — ACB-4000 command set, phases, status/sense, two LUNs,
   `MODE SELECT` geometry, `FORMAT` fill byte. Machine-independent; written to
   the manual.
2. **Host-adapter shim** — the Z80-side port block, as a *profile* (data, not
   code):
   - `md10` — the Osborne 1 adapter: base `30h`, data/control/status, the
     observed status bit map. Runs the period MD-10 software unchanged.
   - `reference` — the OEM manual's Appendix A model: `BASE` data, `BASE+1`
     control (`SEL 40h`), `BASE+2` status (`REQ 80h`, `I/O 40h`, `MSG 20h`,
     `C/D 10h`, `BUSY 08h`), controller ID `01`.
3. **Backing store** — the sparse volume blob (`docs/harddisk-decision.md` §7)
   behind the FAT32 library, with the mailbox / `MOUNT.COM` front end.

## Command set (OEM manual Table 6-1)

`00` Test Unit Ready, `01` Rezero Unit, `03` Request Sense, `04` Format Unit,
`08` Read, `0A` Write, `0B` Seek, `0F` Translate, `13`/`14` Write/Read Buffer,
`15` Mode Select, `1A` Mode Sense, `1B` Start/Stop Unit, `1C`/`1D`
Receive/Send Diagnostic; the Class 01 set (Read Capacity, …) is optional.

## Faithfulness (`harddisk-decision.md` §9.3)

The controller's own ROMs are archived (`research/adaptec/acb4000/firmware/`),
so a bit-exact ACB-4000 is possible — but v1 implements the *documented*
behaviour and keeps the ROMs as the **oracle** to test against.

## Deliverables

- SCSI target module (CDB decode, phases, geometry, fill byte)
- Host-adapter shim with the `md10` and `reference` profiles
- Volume blob format definition + tooling note (`tools/`)
- Bring-up log against the period MD-10 software (`HARD.COM` + the `.SPR`
  overlays)
