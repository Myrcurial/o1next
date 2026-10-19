---
layout: page
title: keyboard-adapter
subtitle: O1NEXT USB Keyboard Adapter — a modern USB keyboard on the Osborne 1's own connector
---

**Status:** reference design defined; spec validation pending.
Tracks **#47** (split out of #45). Source: `hardware/keyboard-adapter/`.
Board register:
[`hardware/README.md`]({{ site.repository }}/blob/main/hardware/README.md).

## What it is

A small RP2040 board that presents a USB-A port for any HID keyboard, and drives
the Osborne 1's own 8×8 keyboard matrix as if the original keys were being
pressed. Plug in a keyboard, type, and the machine sees keystrokes — no BIOS
change, no software, nothing cut.

## How it attaches

The **P4 keyboard connector** on later "blue/grey" O1A machines: a coiled cable
with a 24-hole plug of which only the inner 20 pins mate. The documented pinout is
`1 = GND`, `2–9 = rows`, `10–17 = columns`, `18 = NC`, **`19 = +12 V`**, `20 = GND`.

- Rows are watched as 5 V-tolerant **inputs**; columns are driven
  **open-drain** through a 74LVC07-class buffer, matching the stock 74LS05 stage,
  so the adapter can never fight the host.
- The matrix firmware is shared with the interposer's web-KVM personality
  (**#45**), which pokes the same matrix.

## Power, and why it no longer needs the case opened

There are three ways to feed it, and the third is the one to use:

1. **Variant A — internal.** +12 V from P4 pin 19, which is wired through jumper
   **J6** and a 22 Ω **R21**. J6 is factory-open, so this means **opening the
   machine to bridge it**.
2. **Variant B — external.** Power from a USB hub or a 5 V feed on the upstream
   side, for a completely untouched machine.
3. **Variant C — from the MODEM port.** The MODEM port (P1, DE-9 pin 7) carries
   **the same +12 V through the same R21, and it is reachable from outside**. A
   9-pin passthrough from the adapter to the modem port takes power there.
   **Nobody cracks the case.**

One PCB serves all three through a power-source jumper. Both loads share R21 if
the WiFi modem is also fitted — see [External WiFi modem]({{
'/hardware/wifi-comm-pac/' | relative_url }}).

## Still to confirm on a real machine

- The pinout against `research/osborne1/OCC1_1A2011-00_Schem_RevE.pdf`, and a
  continuity check of rows vs columns, GND, and pin 19.
- That rows really are driven low one-hot via open-collector inverters with the
  columns pulled up through a 3.3 K pack.
- The stock scan rate, to size the polling loop or PIO snoop.
- That P1 pin 7 is live **without** a J6-style bridge.
