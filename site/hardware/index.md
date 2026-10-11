---
layout: page
title: Hardware
subtitle: The planned devices, what each attaches to, and where it stands
---

The project builds more than one thing. The **bus interposer** is the centre of
it, but three of the devices need no interposer at all — they hang off ports the
machine already exposes — and the O1 Next Generation is a separate project
downstream of all of it.

**Nothing here has been fabricated.** A Rev A schematic exists for the interposer
and another for the floppy adapter; no PCB has been made and no firmware has run
on hardware. Each page says what is actually in hand, not what is planned.

| Device | Attaches to | Status |
|---|---|---|
| [USB keyboard interface]({{ '/hardware/keyboard-interface/' | relative_url }}) | P4 keyboard connector | Reference design defined; spec validation pending |
| [External WiFi modem]({{ '/hardware/external-modem/' | relative_url }}) | MODEM (P1), DE-9 | Concept; pinout and levels documented |
| [Drive C adapter]({{ '/hardware/drive-c/' | relative_url }}) | IEEE-488 (P3) + video (P5) | Concept; blocked on the #6 protocol |
| [Floppy adapter]({{ '/hardware/floppy-adapter/' | relative_url }}) | Mainboard floppy header | Rev A schematic captured; ready for routing review |
| [Bus interposer + control pod]({{ '/hardware/interposer/' | relative_url }}) | Z80 socket, char-gen socket, ribbon to the pod | Rev A engineering-sample schematic generated |
| [LFF replacement board]({{ '/hardware/lff-replacement/' | relative_url }}) | Replaces the mainboard, 1:1 | Block-level KiCad skeleton |
| [SFF integrated board]({{ '/hardware/sff-integrated/' | relative_url }}) | Replaces the mainboard, one piece | Concept |
| [Complete O1 Next Generation]({{ '/hardware/o1ng-complete/' | relative_url }}) | The whole machine, case included | Concept render exists |

## Why so many?

Because the machine is unusually open. The Osborne 1 puts every peripheral in a
memory-mapped bank and gives the Z80 a slow, simple external bus, so there are
four independent places to attach something modern:

- **the Z80 socket** — the interposer, and anything that wants to see or drive
  every bus cycle;
- **a port on the back** — the keyboard connector (P4), the MODEM port (P1), the
  IEEE-488 card edge (P3), the video connector (P5);
- **the character-generator socket** (UA15) — for video work; and
- **the mainboard itself** — for the reproduction.

Each device below takes one of those, and the point of the standalone three is
that they need **no interposer, no BIOS change, and nothing cut**.

## Where the design decisions live

The engineering detail — pinouts, levels, open questions — is in `hardware/` in
the repository, one folder per device, and the reasoning is in the issues. These
pages are the readable version: what it is, how it attaches, and what is still
unknown.
