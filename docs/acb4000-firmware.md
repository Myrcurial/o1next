# The ACB-4000's own firmware (#178)

**Status: Partially solved.** Read: the ROM set (six 8 KiB images plus one
Intel-HEX build — all one firmware, not a 2-ROM set), the controller's internal
machine, the command set (the OEM manual's Table B-1 is authoritative and
complete), the host-side register protocol on ports `30h`–`33h`, and the
measurement that blocked the MAME-stub route (`docs/acb4000-host-adapter.md`).
**Inferred, not traced:** that the MD-10 driver *builds* its DPB from what the
controller reports at run time. What is measured is that a **static fallback DPB**
also sits inside the BIOS image at `0xDDB6`, with the type bytes and descriptors at
`0xDD5E`/`0xDD6E` (`docs/md10-system.md` §9) — so which copy a boot uses is the
open half (`docs/md10-system.md` §9.1).

The controller is a small computer running its own firmware; the ROMs are
archived at `research/adaptec/acb4000/firmware/`. This note records what the
firmware *is*, and what it tells us about the personality — in particular **why
the MD-10 driver carries no literal DPB of its own**.

Serves #178 (the hard-disk geometry), and #179 (the personality).

## What the ROMs are

Six 8 KiB images plus one 8 KiB Intel-HEX build — **all one firmware, not a
2-ROM set**. Each is 8080/Z80 code at `0x0000`–`0x1FFF`, differing only in the
reset target: `JP 0x1BA6` / `0x1BB0` / `0x1C9A` / `0x1CDE` / `0x1CF5` / `0x1F14`
/ `0x1CFE`. The manual confirms the controller is a self-contained SCSI target
with a 1 KiB dual-ported buffer, so a single 8 KiB ROM is the right size.

## The firmware's own machine

Read out of the 400510-01H build (`z80dasm`, `org 0`):

- **I/O ports `0x80`–`0x83`** — the controller's own SCSI/disk interface:
  `OUT (82h)` ×20, `IN A,(81h)` ×10, `IN A,(83h)` ×9, `OUT (80h)` ×1. Note the
  symmetry with the *host* interface at `30h`–`33h`: four registers either side.
- **Memory-mapped state at `0x80xx`** — the current CDB byte at **`0x8080`**
  (with `0x8081`, `0x8082`), return vectors at `0x8094`/`0x8096`, a phase
  register at `0x809C`, a work pointer at `0x8098`; plus a status register at
  `0x4052` and RAM at `0x40xx`.
- The helper at `0x0003` is a two's-complement negate (`DE = −DE`) used by the
  divide at `0x000D` — arithmetic, not I/O.
- **Command decode** is by a **jump table at `0x1AD0`** for one class (gated on a
  four-byte field `H = 30h`, `L = 60h…65h`), and by direct compares elsewhere —
  `XOR 0Bh` (SEEK) at `0x0971`, `XOR 04h` (FORMAT) at `0x0B0A`.

## The command set — take it from the manual, not the ROM

Table B-1 of the OEM manual is authoritative and complete, and better than
anything the disassembly gives: the standard set is
`00 01 03 04 08 0A 0B 0E 13 14 15 1A 1B 1C 1D 25 28 2A 2E 2F 31`, and an
**expanded** set appears behind jumper **I-J** — `05 CHECK TRACK FORMAT`,
`0C INITIALIZE DRIVE`, `0D READ ECC BURST LENGTH` (always returns 8), `0F`/`10`
vendor buffer commands, and `E0`/`E3`/`E4` diagnostics (always good status).
Both **`1A MODE SENSE`** and **`25 READ CAPACITY`** are standard.

## Why the MD-10 driver has no literal DPB

This is the payoff. Two statements in the manual, taken together:

> The ACB-4000 **auto-configures to any size, previously formatted, 5¼" drive**,
> eliminating the need for host initialization of the controller for various
> drive types.

> The MODE SELECT command sends drive parameters to the controller **to be
> written onto the drive at format time.**

So the geometry lives **on the drive** — not in the controller, and not in the
driver. The chain, with each step's status:

| Step | Status |
|---|---|
| `MD10.COM` (PREP) sends the drive-table geometry with `MODE SELECT` (`15`) and `FORMAT` (`04`), which **writes it onto the drive** | **read** — the manual says so, and the drive table is the same field set (`docs/harddisk-decision.md` §7.2) |
| At power-on the controller **auto-configures from the drive** | **read** — the manual |
| The driver **reads the geometry back** and **builds the DPB from it** | **inferred** — `MODE SENSE` (`1A`) is present in the driver image, but the driver also has a static DPB to fall back on, and which path a boot takes is not traced |

What is read, not inferred, is that a DPB exists to reach. The BIOS image
the driver installs carries one — at `0xDDB6`, with the type bytes at `0xDD5E` and
the 24-byte descriptors at `0xDD6E` pointing at it (`docs/md10-system.md` §9) —
which is why `SELDSK` indexes a table instead of embedding a DPB
(`docs/harddisk-decision.md` §7.1, §7.3). That is also what "no literal DPB" means
precisely: the **driver overlay** carries none. The fallback lives in the BIOS
image it installs, and the drive carries its own copy of the geometry and type
bytes at LBA 4 (`docs/md10-system.md` §3).

*(Still open: whether a boot uses the static fallback or the controller's
`MODE SENSE` report. A trace of one `SELDSK` under MAME, or a read of the driver's
command buffer, would settle it.)*

## What this changes

- **The personality must implement `MODE SENSE` (`1A`) and `READ CAPACITY`
  (`25`) faithfully** — because the geometry the driver works from is either
  reported by the controller or read off the drive, and neither is something the
  driver holds. This is a hard requirement for #179, and it is now written down.
- **The residue is not the DPB's values.** The open number was never "the
  driver's DPB" but the `DRIVETBL.DAT` record, and that is read: the record layout
  and the byte→field mapping are in `docs/harddisk-decision.md` §7.2, and it turns
  out to be the same `MODE SELECT` drive parameter block, stored little-endian in a
  128-byte description record behind a name table. The DPB is read too: `0x055E` is
  a **BIOS-base offset**, not a low-RAM address, so the type bytes, the descriptors
  and the DPB itself are static data in `HARD.COM` at `0xDD5E`, `0xDD6E` and
  `0xDDB6` (`docs/harddisk-decision.md` §7.3; `docs/md10-system.md` §9). What is
  left is **which copy a boot uses** — the static fallback, or the drive's own
  geometry and type bytes at LBA 4 (`docs/md10-system.md` §3, §9.1).
- The `0x6C` fill byte found in the *driver* (`docs/harddisk-decision.md` §7.1)
  and the `6Ch` default in the *manual* now sit together: the driver passes the
  fill byte through `MODE SELECT`/`FORMAT`, and the controller writes it.

## Sources

- `research/adaptec/acb4000/firmware/` — the six ROM images and the HEX build.
- `research/adaptec/acb4000/500504-00_ACB-4000_OEM_Manual_Mar84.pdf` — the
  feature list, Table B-1 (Appendix B), and the sample format sequence.
- `docs/harddisk-decision.md` §7.1 — the driver-side structure this explains.
- `docs/md10-system.md` §9 — the DPB and drive tables read out of `HARD.COM`, and
  the one-DPB consequence.