---
layout: page
title: Bus interposer + control pod
subtitle: The core board, and the panel it talks to
---

**Status:** Rev A engineering-sample schematic generated, ready for KiCad capture
review and routing. **No board built.**
Tracks **#11** (Phase 1), **#12** (interface spec), **#13** (Rev A), **#15**
(Rev B), **#14** (the pod). Source: `hardware/interposer/`,
`hardware/front-panel-ui/`.

## What it is

The centrepiece: a board that sits **between the Z80 and its socket**, carrying a
**Pico 2 W** (RP2350 + CYW43439). Because it sees every bus cycle, it can both
**observe** the machine and **drive** it — which is what makes the whole
"virtual peripheral" idea possible.

## What it hosts

Nine personalities, each with its own page of research behind it: the passive bus
analyzer (#17), the RT-60A time service (#18), the virtual MX-80 printer (#19),
the floppy interposer (#20), the WiFi modem (#21), Drive C (#22), the virtual
CoPower-88 (#23), the SCREEN-PAC video personality (#24) and the web KVM console
(#45).

## How it attaches

- **Z80 DIP-40 socket** — socket-safe header, 4 MHz bus sampled synchronously via
  PIO.
- **74AHCT/HCT both directions.** All Osborne 1s are NMOS Z80s, so AHCT/HCT
  matches the NMOS I/O thresholds; this superseded an earlier 74LVC245 choice.
- **Its own dedicated 5 V feed** near the Z80 socket, sized for Pico 2 W WiFi
  bursts (~300 mA+).
- **It must stack.** The design has to coexist with a real SCREEN-PAC *and* a
  real CoPower-88 on a fully-loaded machine, so pass-through height matters.
- **An optional second tap**: the 24-pin character-generator socket (UA15), for
  the video personality. Read-only by necessity — the ROM's `/CE` and `/OE` are
  grounded on the mainboard, so it is always driving.

## The two revisions are two products

- **Rev 0 "test probe"** — superseded. Kept for the decision record; parts lead
  time for a passive probe was within days of an engineering sample of the active
  board, so the passive step was skipped.
- **Rev A engineering sample** — the *instrument*. An SMT Z84C00 on the board
  (pull the original CPU, drop the interposer in), **/BUSRQ bus mastering**,
  a 595/165 shift-register drive-and-capture fabric, Pico 2 plus a castellated
  ESP32-C3, and W25Q library flash. The goal is blunt: the development partner
  **controls the hardware** — memory read/write, ROM dumping, code injection and
  execute.
- **Rev B** — not a revision but the *live-cycle personality engine*. A
  **74AHCT688 window comparator** plus **/WAIT cycle stretching** — the
  period-correct slow-peripheral mechanism — replaces 16 direct address lines
  with two. HSTX is fixed to GP12–19, so HDMI lives there; the status LED bank
  moves to the ESP32; SD goes on SPI.

## The control pod

A ribbon cable to the front-panel pod (`hardware/front-panel-ui/`) carries
**SD/USB storage, VGA/HDMI out, an OLED, FlashFloppy-style controls, a modem LED
bank**, and a **second-keyboard USB-A path**.

## Onboard storage

The interposer carries enough flash to hold a **built-in library — at minimum the
boot diskette** — so the machine is useful with no card inserted, and the
lunchbox can boot "factory" images out of the box. A DD diskette image is about
400 KB, so a handful of SOIC-8 W25Q-class parts is effectively free.
