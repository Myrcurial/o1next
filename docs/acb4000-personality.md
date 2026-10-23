# The ACB-4000 personality — what is built, and what the acceptance still needs (#179)

**Status: Partially solved.** The three layers of the personality
(`harddisk-decision.md` §5) are built and host-tested: the SCSI-1 target, the
host-adapter shim with both profiles, and the backing-store interface. The
**end-to-end acceptance is not met**, and the blocker is no longer the drive: the
MD-10 system is produced by `PREP.COM` option 3 and boots to a prompt with three
partitions (`docs/md10-system.md` §1, §7), so the acceptance has a drive to run
against. What remains is **who copies the static DPB and descriptor tables into
the running system** (`docs/harddisk-decision.md` §7.3, `docs/md10-system.md` §9)
and pointing the MAME harness at this personality rather than MAME's generic SCSI
model (§5).

Serves #179 (the personality) and #8 (the decision). Reads alongside
`docs/harddisk-decision.md` §5–§9, `docs/acb4000-firmware.md`,
`docs/acb4000-host-adapter.md` and `docs/osborne1nx-machine.md`.

## 1. What was built, and where

`firmware/acb4000-scsi/` — portable C99, no board, no SDK, no dependencies,
tested on the host the way `firmware/rom-ident/` is.

| Layer | File | Interface |
|---|---|---|
| 1. SCSI target | `acb4000_target.c` | `acb4000_target_command()` → phase, length, status; `acb4000_target_read()`/`_write()` move the bytes |
| 2. host-adapter shim | `acb4000_shim.c` | `acb4000_shim_read()`/`_write()` on four register offsets, driven by an `acb4000_profile` |
| 3. backing store | `acb4000_store.c` | five calls: `capacity`, `block_size`, `read`, `write`, `format` |

The split is the deliverable, not a filing convention: because layer 2 is data,
the same target serves the MD-10 (`base` 30h) and the OEM manual's Appendix A
reference model, and because layer 3 is five calls, the target does not know
whether it is over a buffer or a FAT32 blob (#180).

`firmware/acb4000-scsi/run_tests.sh` builds and runs the suite; CI runs it.

## 2. The one thing the tests are built around

The MD-10's geometry reaches the driver either from what the controller reports or
from the drive itself — the driver holds no DPB of its own
(`docs/acb4000-firmware.md`; which copy a boot uses is open,
`docs/md10-system.md` §9.1) — so `MODE SENSE` (`1A`) and `READ CAPACITY` (`25`)
are not conveniences — they are the personality's correctness. The suite
therefore does not test the register model through a convenient wrapper: it
contains a **transcription of the driver's own transaction routine**
(`HARDBIOS.SPR` file `0x285`, address `0xE285`), including its quirks, and drives
the shim with it.

That matters because three of those quirks are load-bearing and were each a hang
until they were right (`docs/osborne1nx-machine.md` §4):

1. the status phase asserts PHASE and END but **not** REQ;
2. the status byte survives two reads;
3. the CDB index resets when the command phase starts.

A test that called `acb4000_target_command()` directly would pass with all three
wrong. Replaying the routine means a wrong bit map fails the suite — verified by
flipping one status bit, which produced 38 failures.

## 3. `2F` is VERIFY, and the sector count is unresolved

Two facts the manual settles, and one it does not.

**`2F` is VERIFY, and `31` is SEARCH DATA EQUAL — two different commands, and the
difference is load-bearing.** The manual separates them: `2F` is `VERIFY`
(5.4.5, no data phase — it checks the ECC of blocks already on the drive) and `31`
is `SEARCH DATA EQUAL` (5.4.6, a pattern compare with an argument and an Equal
status). `PREP.COM`'s "format and verify" issues `2F`, so the personality
implements `VERIFY` for it — and `31` as well, because the manual's own "verify
disk integrity after format by searching for the 6C fill" is the search. Read from
Table 5-1/5-2 and §5.3–§5.5 of
`research/adaptec/acb4000/400003-00A_ACB-4000A_Users_Manual_Oct85.ocr.txt`.

**The drive table and the manual disagree about sectors per track, and nothing
reconciles them.** `DRIVETBL.DAT`'s capacity formula is `cylinders × heads × 18 ×
512 B` (`harddisk-decision.md` §7.2), while the manual's track is "the normal 32
sectors" of 256 bytes — 8 KiB, i.e. **16** × 512-byte blocks (5.3.4), or 64 ×
128-byte CP/M records (`harddisk-decision.md` §7.3). So `PYXIS13` is
23 112 blocks by the table's arithmetic and 20 544 by the manual's. The
personality does not paper over it: `acb4000_params.sectors_per_track` is an
explicit field defaulting to the table's 18, so a reported geometry matches what
period software shows, and `READ CAPACITY` reports the **store's** last block —
the drive's real one — rather than either formula. Which is right is a question
for the drive table (#178), not for the controller.

## 4. Why the acceptance is not met

The acceptance is *"the period MD-10 software (`HARD.COM` + the `.SPR` overlays)
runs against it and boots CP/M from the emulated hard disk."*

Everything the **software asks of the controller** now has an implementation, and
the suite exercises it through the driver's own routine. The remaining work is not
in the controller, and it is not the memory map either:

- `HARD.COM` is a **hard-disk boot loader**, not an installer. It reads LBA 5 for
  eleven blocks (the `CCP`+`BDOS` of the O1 system layout), patches page zero and
  jumps into what it read (`docs/osborne1nx-machine.md` §5). So the drive must
  *already* carry an MD-10 system — and it can. `PREP.COM` option 3 configures one
  onto a drive, and the result boots to `A0>`/`B0>`/`C0>` with three partitions
  (`docs/md10-system.md` §1, §7).
- The DPH/DPB tables at `0x055E`/`0x056E` are **not low RAM and not missing**:
  `0x055E` is an offset from the BIOS base `0xD800`, so the tables are static data
  inside `HARD.COM` at `0xDD5E`/`0xDD6E`, with the DPB at `0xDDB6`
  (`docs/harddisk-decision.md` §7.3, `docs/md10-system.md` §9). What is not chased
  is **which copy a boot uses** — the static fallback, or the drive's own copy of
  the geometry and type bytes at LBA 4 (`docs/md10-system.md` §3, §9.1). That is
  #178's residue.

So the gap is neither "does the controller behave?" (this personality answers
that, with tests) nor "what is the MD-10's memory map?" — that map is read, and the
system it boots is captured (`docs/md10-system.md`). What is left is **pointing the
emulated machine at this personality** and settling the table copy:

1. **Run the period software against this target rather than MAME's generic SCSI
   model.** `tools/emulator-setup/mame-osborne1nx/` delegates the SCSI side to
   `t10spc`/`t10sbc` today, which is why `PREP.COM`'s verify pass (`2F`) has no
   handler. That is a harness change, not a controller one.
2. **Settle who copies the static tables into the running system** — a `peek` at
   `0xDD5E`/`0xDD6E` on the booted system (`docs/harddisk-decision.md` §10 item 1).

## 5. Where this could go next, in order of value

1. **Settle which copy of the tables a boot uses** — a `peek` at `0xDD5E`/`0xDD6E`
   on the booted system. It is the last open number, and it is measured work on a
   system that already runs (`docs/md10-system.md` §7, §9).
2. **Give the MAME harness the personality.** `tools/emulator-setup/mame-osborne1nx/`
   currently delegates the SCSI side to MAME's generic `t10spc`/`t10sbc`, which
   is why `2F` had no handler. Pointing the card at this target would let the
   period software exercise the real logic, and would make `PREP.COM`'s
   format-and-verify finish for the first time.
3. **Wire the FAT32 store (#180)** behind the five calls — the interface is
   already the seam, so this is a new `acb4000_store` implementation and no
   change above it.

## Sources

- `research/adaptec/acb4000/400003-00A_ACB-4000A_Users_Manual_Oct85.ocr.txt` —
  Table 5-1/5-2 (the command set), §5.3–§5.5 (the CDBs, the parameter lists, the
  completion status byte and the sense bytes).
- `research/adaptec/acb4000/firmware/` — the six 8 KiB controller ROMs, the
  oracle the personality is written against.
- `docs/harddisk-decision.md` §5 (the three layers), §6 (the O1 shape of it),
  §7.2 (the drive table and `PYXIS13`), §7.3 (the DPB, and where it is read from).
- `docs/acb4000-firmware.md` (the controller's firmware, and the `MODE SENSE`
  requirement), `docs/acb4000-host-adapter.md` §1 (the register protocol),
  `docs/osborne1nx-machine.md` §3–§5 (the handshake quirks, and the acceptance).
- `docs/md10-system.md` §1, §3, §7, §9 — the MD-10 system, the drive's own copy of
  the tables, the boot, and the DPB read out of `HARD.COM`.
- `firmware/acb4000-scsi/` — the implementation, its README and its tests.

