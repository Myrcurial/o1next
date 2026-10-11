# drive-c — a Drive C reproduction (IEEE-488)

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
| IEEE-488 bus | **P3**, 26-pin card edge (pins 25/26 unused) | `docs/o1-memory-io-map.md` §6; PIA UC7 (6821) at `2900–2903` |
| Power | **P5**, 10-pin video connector, via an EXMON-style passive shunt | EXMON shunt: Sullins MP-0100-10-DS-4 edge connector + Hyko K688-DI sync combiner, **powered from +12V** |
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
- **Tri-state and handshake.** The device has to honour the PIA handshake, and the
  BIOS's device-status routine is a **stub** — so a device must be ready when
  addressed (`docs/o1-rom-source.md`).

## Open questions

- [ ] **Power at P5.** The EXMON shunt takes +12V; confirm what else is on the
      connector, whether +5V is available, and the connector's current budget.
      **Do not assume — measure on a real machine.**
- [ ] **Which Drive C variant to emulate** — capacities and the exact command set
      (#6).
- [ ] **Firmware sharing with #22.** The same device as an interposer personality;
      it should be one implementation, not two.

## The shunt is a mod

It is passive and reversible, which keeps it inside the project's "leave the
machine intact" rule — but it is a mod and must be documented as one, the same way
the USB keyboard adapter's J6 bridge is.

## Research to archive first

BrettHallen's `Osborne_1` repo carries the EXMON shunt photographs and the
connector part numbers. It is the only description of the video shunt we have and
should be archived into `research/` with provenance before it moves or disappears.

## References

- `docs/drive-c-protocol.md` — the contract this device implements (#6)
- `docs/o1-ieee488-port.md` — device-level port behaviour
- `docs/o1-memory-io-map.md` §6 — P3/P5 pinouts
- `docs/interposer-survey.md` §5 — NODISKEMU and cbmSD, the IEEE-488 state
  machines to port
