---
layout: page
title: Hardware
subtitle: The planned devices, what each attaches to, and where it stands
---

The project builds more than one thing. Every other vintage computing platform has cool new hardware being built. It's time for the Osborne 1 to get the same treatment. The **bus interposer** is the centre of it, but three of the devices need no interposer at all — they hang off ports the machine already exposes. If you install any of the external devices, you end up with a cool Osborne 1 that has awesome extras. If you add the interposer to an OEM Osborne 1 or the (planned) LFF 1:1 reproduction mainboard then you've got an O1NEXT. The ultimate though is the fully integrated O1NEXT SFF mainboard in the opinionated case and peripherals. Of course, you can use the SFF mainboard any way you want. 

**Nothing here has been fabricated... YET** Hardware, firmware, and software is in a wild state of flux. Each page says what is actually in hand, not what is planned.

## The boards

One name per board, and the **same set** here as in the repository's board
register (`hardware/README.md`), which is the authority. `tools/check_boards.py`
fails if this list and that table drift apart.

| Board | Attaches to | Status |
|---|---|---|
| [**O1NEXT Floppy Adapter**]({{ '/hardware/floppy-adapter/' | relative_url }}) | Mainboard floppy header | Floppy Adapter's Rev A schematic captured; ready for routing review |
| [**O1NEXT USB Keyboard Adapter**]({{ '/hardware/keyboard-interface/' | relative_url }}) | P4 keyboard connector | Reference design defined; spec validation pending |
| [**O1NEXT WiFi COMM PAC**]({{ '/hardware/external-modem/' | relative_url }}) | MODEM (P1), DE-9 | Concept; pinout and levels documented |
| [**O1NEXT Drive C Repro**]({{ '/hardware/drive-c/' | relative_url }}) | IEEE-488 (P3) + video (P5) | Concept; blocked on the #6 protocol |
| [**O1NEXT Upgrade**]({{ '/hardware/interposer/' | relative_url }}) | Z80 socket, the main ROM socket UD11, the char-gen socket UA15, ribbon to the pod | Interposer's Rev A engineering-sample schematic generated; Rev B is a pin map with no schematic yet |
| [**O1NEXT Integrated**]({{ '/hardware/sff-integrated/' | relative_url }}) | One integrated board; not a 1:1 swap | Concept — **no directory in the tree yet** (#49) |
| [**LFF board**]({{ '/hardware/lff-replacement/' | relative_url }}) | Replaces the mainboard, 1:1 — OCC1 or OCC1A | Block-level KiCad skeleton. **Won't build** |
| [**O1NEXT Complete**]({{ '/hardware/o1next-complete/' | relative_url }}) | The O1NEXT Integrated board with the machine wrapped around it | Concept render exists |

The **O1NEXT Upgrade**'s **interface pod** — the front-panel faceplate with the
SD/USB sockets, HDMI, the OLED and the modem LED bank (#14) — is part of that
board, not a board of its own.

**Not a board:** the [MAME machine]({{ '/compendium/emulation/' | relative_url }}),
the emulated Osborne 1 (`osborne1nx`) used to explore the machine and to test the
firmware long before any hardware exists.

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
- **the character-generator and main ROM socket** (UA15 / UD11) — doing flying replacement of ROM code; and
- **the mainboard itself** — for the reproduction.

Each device below takes one of those, and the point of the standalone three is
that they need **no interposer, no BIOS change, and nothing cut**.

## Where the design decisions live

The engineering detail — pinouts, levels, open questions — is in `hardware/` in
the repository, one folder per device, and the reasoning is in the issues. These
pages are the readable version: what it is, how it attaches, and what is still
unknown.
