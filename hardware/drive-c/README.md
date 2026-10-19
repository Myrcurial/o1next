# drive-c — the O1NEXT Drive C Repro (IEEE-488)

**Board:** the **O1NEXT Drive C Repro** — the project's **fourth deliverable**.
See the register in [`../README.md`](../README.md). Signal interface via the
IEEE-488 port, power via the video shunt plug. The PCB mounts an RP2354B, a
12 V→5 V/3.3 V buck, a microSD slot, a USB-A port for USB drive sticks, the
EX MON composite-video conversion (and the composite port), an aux power port for
the USB Keyboard Adapter, and a USB-C port for programming or powering it when
not connected to the computer.

**A Drive C, rebuilt on modern parts.** Standalone: no interposer, no Z80 socket,
no reverse-engineering of an undocumented controller. It attaches to interfaces
the machine already exposes and does the one thing the O1's IEEE-488 port was
designed for.

It is a **reproduction**, not an adapter: the machine sees the same device on the
same bus speaking the same protocol, so period software drives it unchanged. Look
closely and you find an RP2040 where the original had a handful of TTL — which is
the whole point of the exercise.

Tracks: #84 (device), #6 (the protocol it must speak). Sibling of
`usb-keyboard-adapter/` and `wifi-modem-module/` — same idea: a period device
reproduced on modern parts, hanging off a port, reversible.

## Why this one and not the hard disks

Seven storage routes were advertised for the Osborne 1 (`docs/research-gaps.md`
§B1). Only one is buildable from what this project holds:

| Route | Why not |
|---|---|
| ACT / OCC1 hard disk | Controller command set not reverse-engineered; Z80-side relocatable port window (#8) |
| Media Distributing / Adaptec (**MD-10**) | Same problem, different vendor (#8) |
| Trantor TSL-5/TSL-10, Helix, Corvus, OSMOS 7 | No media, no controller documentation held |
| **Drive C** | Protocol **fully observable from software alone** — `DRIVE_C.IMD` plus the ROM source's IEEE-488 implementation. Host interface is a **documented, standard bus** |

## Host interfaces

| Element | Interface | Evidence |
|---|---|---|
| IEEE-488 bus | **P3**, 26-pin card edge (pins 25/26 unused) — full pinout in `docs/o1-ieee488-port.md` §6 | Technical Manual §4.1.2, corroborated line for line by the ROM's comment block; PIA UC7 (6821) at `2900–2903` |
| Power | **P5**, 10-pin video connector, via an EXMON-style passive shunt | EXMON shunt: Sullins MP-0100-10-DS-4 edge connector + Hyko K688-DI sync combiner, **powered from +12V**; the original Drive C drew **11–14.5 V at 0.3 A max** from the same connector (Drive C manual §7-2) |
| Compute | A stock **Pico (RP2040)** — enough for IEEE-488 bit-banging | — |
| Storage | One external flash chip | Even the largest Drive C variant was not large |
| Bonus | The same shunt gives **composite video out** | EXMON does exactly this, passively |

## Electrical constraints

- **Open-collector.** The O1 drives the bus through 7406 open-collector drivers
  with 3.3 K pull-ups. A replacement device must **release** lines, not drive them
  high.
- **Level shifting.** IEEE-488 on the O1 is 5 V; the RP2040 is 3.3 V and not 5 V
  tolerant. The same **74AHCT/HCT** conclusion that governs the interposer applies
  here (`docs/research-gaps.md` gap 2).
- **Tri-state, and no handshake.** There is **no IEEE-488 three-wire handshake on
  this port** — `DAV`, `NRFD` and `NDAC` are among the five lines the ROM's driver
  set does not implement (`docs/o1-ieee488-port.md` §6.1). A device therefore has
  to be **ready when addressed**: the BIOS's device-status routine is a **stub**
  (`docs/o1-rom-source.md`), and Drive C's transport clocks bytes on `CA2`/`IFC`
  (P3 pin 17) with no ready line the host reads.

## Open questions

The **protocol is solved** (`docs/drive-c-protocol.md`), the **build spec is
`docs/drive-c-design.md`**, and the three things the spec was waiting on all
turned out to be **in the archive already**:

- [x] **The P3 pinout** — §4.1.2 of the Technical Manual, in
      `research/osborne1/modem/o1techman-interface-extract.pdf`, transcribed in
      `docs/o1-ieee488-port.md` §6. The ROM's own comment block agrees with it
      line for line, so this needed no measurement after all.
- [x] **Power at P5** — the Drive C manual's §7-2 states the original unit's own
      requirement: **11 to 14.5 VDC at 0.3 A max**, drawn from the O1's
      **EXT. VIDEO connector**. A Pico plus flash is a fraction of that, so the
      shunt passes less than the original did.
- [x] **The DPB** — read out of `DCL.COM` (file `0x142F`, installed `0x052F`):
      `SPT=2`, 2 KiB blocks, `DSM=191` → **384 KiB**, 128 directory entries. Every
      field matches the manual's 384K column (`docs/drive-c-protocol.md` §8.1).

What is left:

- [ ] **Which Drive C variant to emulate** — the DPB says the archived disk is the
      384K unit, and the protocol's ceiling is 448 KiB, so a 512 KiB flash covers
      every variant. **Decide 384K and move on** (`docs/drive-c-design.md` §4).
- [ ] **Bus loading** — the one real electrical unknown, and it only decides
      whether the board needs a buffer. Confirm cheaply with a scope rather than
      designing around it (`docs/drive-c-design.md` §7).
- [ ] **Firmware sharing with #22.** The same device as an interposer personality;
      it should be one implementation, not two (`firmware/drive-c-gpib/`).

## The shunt is a mod

It is passive and reversible, which keeps it inside the project's "leave the
machine intact" rule — but it is a mod and must be documented as one, the same way
the USB keyboard adapter's J6 bridge is.

## Research to archive first

BrettHallen's `Osborne_1` repo carries the EXMON shunt photographs and the
connector part numbers. It is the only description of the video shunt we have and
should be archived into `research/` with provenance before it moves or disappears.

## References

- `docs/drive-c-protocol.md` — the contract this device implements, plus the DPB
  and the capacity ceiling (#6, #145)
- `docs/drive-c-design.md` — this device's hardware and firmware spec (#84)
- `docs/o1-ieee488-port.md` — device-level port behaviour **and the P3 pinout**
  (§6), including what the port does not implement
- `docs/interposer-survey.md` §5 — NODISKEMU and cbmSD, the IEEE-488 state
  machines to port
- `research/osborne1/modem/o1techman-interface-extract.pdf` — Technical Manual
  §4.1.2, the primary source for the P3 pinout
- `research/drive_c/Drive_C_Users_Manual.pdf` — §7-2 (power) and §7-3 (CP/M
  parameters)
