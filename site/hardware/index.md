---
layout: page
title: Hardware
subtitle: The planned boards, what each attaches to, and where it stands
---

The project builds more than one thing. Every other vintage computing platform has cool new hardware being built. It's time for the Osborne 1 to get the same treatment. The **bus interposer** is the centre of it, but three of the boards need no interposer at all — they hang off ports the machine already exposes. If you install any of the external boards, you end up with a cool Osborne 1 that has awesome extras. Add the interposer to an OEM Osborne 1 and you've got an O1NEXT. The ultimate is the fully integrated **O1NEXT Integrated** board in the opinionated case and peripherals — and you can use that board any way you want.

**Nothing here has been fabricated... YET** Hardware, firmware, and software is in a wild state of flux. Each page says what is actually in hand, not what is planned.

## The boards

**One name per board, and the name is the folder.** This is the same set as the
repository's board register (`hardware/README.md`), which is the authority —
`tools/check_boards.py` fails if this list and that table drift apart.

| Board | Attaches to | Status |
|---|---|---|
| [`floppy-adapter`]({{ '/hardware/floppy-adapter/' | relative_url }}) | Mainboard floppy header | Floppy Adapter's Rev A schematic captured; ready for routing review |
| [`keyboard-adapter`]({{ '/hardware/keyboard-adapter/' | relative_url }}) | P4 keyboard connector | Reference design defined; spec validation pending |
| [`wifi-comm-pac`]({{ '/hardware/wifi-comm-pac/' | relative_url }}) | MODEM (P1), DE-9 | Concept; pinout and levels documented |
| [`drive-c-repro`]({{ '/hardware/drive-c-repro/' | relative_url }}) | IEEE-488 (P3) + video (P5) | Concept; blocked on the #6 protocol |
| [`interposer-upgrade`]({{ '/hardware/interposer-upgrade/' | relative_url }}) | Z80 socket, the main ROM socket UD11, the char-gen socket UA15, ribbon to the pod | One unit in four parts — the interposer board, the UI pod and the two ROM socket taps. Rev A engineering-sample schematic generated; Rev B is a pin map with no schematic yet |
| [`next-integrated`]({{ '/hardware/next-integrated/' | relative_url }}) | One integrated board; not a 1:1 swap | Concept; no schematic yet (#49) |

The longer forms — **O1NEXT Floppy Adapter**, **O1NEXT USB Keyboard Adapter**,
**O1NEXT WiFi COMM PAC**, **O1NEXT Drive C Repro**, **O1NEXT Upgrade**, **O1NEXT
Integrated** — are how each board is *described*; the shortform above is its name,
its folder, and its page here.

## Not boards

- [`o1next-complete`]({{ '/hardware/o1next-complete/' | relative_url }}) — **the
  machine**, deliverable 7: the `next-integrated` board with a case, an 8" panel,
  an 18650 pack and a keyboard.
- **An LFF (large form factor) 1:1 mainboard** — a faithful OCC1/OCC1A
  replacement, with the Z80 left socketed so the interposer stays the upgrade path.
  It is **possible** if a chassis ever needs restoring, and it is **not planned,
  not built and not checked**: no folder, no page.
- The [MAME machine]({{ '/compendium/emulation/' | relative_url }}) — the emulated
  Osborne 1 (`osborne1nx`), used to explore the machine and to test the firmware
  long before any hardware exists.

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

Each board below takes one of those, and the point of the standalone three is
that they need **no interposer, no BIOS change, and nothing cut**.

## Where the design decisions live

The engineering detail — pinouts, levels, open questions — is in `hardware/` in
the repository, one folder per board, and the reasoning is in the issues. These
pages are the readable version: what it is, how it attaches, and what is still
unknown.
