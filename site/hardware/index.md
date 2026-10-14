---
layout: page
title: Hardware
subtitle: The planned devices, what each attaches to, and where it stands
---

The project builds more than one thing. Every other vintage computing platform has cool new hardware being built. It's time for the Osborne 1 to get the same treatment. The **bus interposer** is the centre of it, but three of the devices need no interposer at all — they hang off ports the machine already exposes. If you install any of the external devices, you end up with a cool Osborne 1 that has awesome extras. If you add the interposer to an OEM Osborne 1 or the (planned) LFF 1:1 reproduction mainboard then you've got an O1NEXT. The ultimate though is the fully integrated O1NEXT SFF mainboard in the opinionated case and peripherals. Of course, you can use the SFF mainboard any way you want. 

**Nothing here has been fabricated... YET** Hardware, firmware, and software is in a wild state of flux. Each page says what is actually in hand, not what is planned.

| Device | Attaches to | Status |
|---|---|---|
| [MAME machine]({{ '/hardware/mame-machine/' | relative_url }}) | Um... your laptop? | A working MAME machine (osborne1nx) so you can explore the machine in emulation before looking at the hardware - also heavily used for testing |
| [USB keyboard interface]({{ '/hardware/keyboard-interface/' | relative_url }}) | P4 keyboard connector | Reference design defined; spec validation pending |
| [External WiFi modem]({{ '/hardware/external-modem/' | relative_url }}) | MODEM (P1), DE-9 | Concept; pinout and levels documented |
| [Drive C reproduction]({{ '/hardware/drive-c/' | relative_url }}) | IEEE-488 (P3) + video (P5) | Concept; blocked on the #6 protocol |
| [Floppy adapter]({{ '/hardware/floppy-adapter/' | relative_url }}) | Mainboard floppy header | Rev A schematic captured; ready for routing review |
| [Bus interposer + control pod]({{ '/hardware/interposer/' | relative_url }}) | Z80 socket, char-gen socket, ribbon to the pod | Rev A engineering-sample schematic generated |
| [LFF replacement board]({{ '/hardware/lff-replacement/' | relative_url }}) | Replaces the mainboard, 1:1 — OCC1 or OCC1A | Block-level KiCad skeleton |
| [SFF integrated board]({{ '/hardware/sff-integrated/' | relative_url }}) | One integrated board; not a 1:1 swap - DIY an O1NEXT | Concept |
| [Complete O1NEXT]({{ '/hardware/o1next-complete/' | relative_url }}) | The SFF board with the machine wrapped around it | Concept render exists |

## Why so many?

Because the machine is unusually open. The Osborne 1 puts every peripheral in a
memory-mapped bank and gives the Z80 a slow, simple external bus, so there are
four independent places to attach something modern:

- **the Z80 socket** — the interposer, and anything that wants to see or drive
  every bus cycle;
- **a port on the front** — the keyboard connector (P4), the MODEM port (P1), the
  IEEE-488 card edge (P3) and the video connector (P5). **Every connector on an
  Osborne 1 is on the front of the machine**; there is nothing at the back, which
  is why fitting anything means unclipping the keyboard that docks over that face;
- **the character-generator and main ROM socket** (UA15 / UA11) — doing flying replacement of ROM code; and
- **the mainboard itself** — for the reproduction.

Each device below takes one of those, and the point of the standalone three is
that they need **no interposer, no BIOS change, and nothing cut**.

## Where the design decisions live

The engineering detail — pinouts, levels, open questions — is in `hardware/` in
the repository, one folder per device, and the reasoning is in the issues. These
pages are the readable version: what it is, how it attaches, and what is still
unknown.
