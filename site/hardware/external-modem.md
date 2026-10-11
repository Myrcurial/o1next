---
layout: page
title: External WiFi modem
subtitle: A Hayes-compatible modem that plugs into the machine's own MODEM port
---

**Status:** concept; the P1 pinout and levels are documented.
Tracks **#56** (an extension of **#21**); the physical interface is #57.
Source: `hardware/wifi-modem-module/`.

## What it is

An ESP32 running a **Zimodem fork** — Hayes AT command set plus telnet, and with
two pieces of new work on top:

- **SSH as a first-class transport**, with keys, host verification and session
  management from a web UI. An Osborne 1 dialling into a modern host with `ssh`.
- **Baud-rate buffering**, decoupling the machine's 6850 ACIA rate from the
  far-end link rate — which makes a turbo upgrade usable and quietly corrects the
  factory 600/2400 → 650/2600 quirk.

The ESP32 rather than an ESP8266 is deliberate: the ESP32 build already carries
the SSH client, SD shell, FTP and SLIP/PPP, and the ESP8266 lacks the headroom.

## How it attaches

The **MODEM port (P1)**, a DE-9P. This is the interesting part: **the port is
TTL, not RS-232** — it feeds straight into the 6850 ACIA (status `2A00H`, data
`2A01H`), bypassing the level shifters. But the levels are **asymmetric**:

- TXD, MCB and RI are plain TTL;
- **RXD is a bipolar input** (`−0.5 … −10 V = 1`, via an LM1458 and a 1N5231B
  zener), so the module must swing TX-toward-O1 **negative** for a clean mark.
  A small charge pump or transistor stage is expected, and it needs validating in
  hardware.

**It powers itself from the port.** DE-9 pin 7 carries +12 V through R21, which
is what makes the whole "severable module" idea work at all: it hangs on the
front of the machine and feeds itself, with **no case opened and no separate
supply**.

## The case

The module ships with STLs for a **"COMM PAC-look" case** that fits in the **left
floppy storage pocket** — period-authentic Osborne industrial design, so it reads
as original kit rather than a modern dongle.

## Still to confirm

- The 2×5 IDC orientation on a real board (same validation class as P4).
- The RXD level stage, in hardware.
- The current budget, **deliberately deferred**: don't derive it until a board is
  close enough to need the answer. The expected resolution is cheap — a bulk
  capacitor absorbs the WiFi transmit transients, and R21 only has to supply the
  average. R21 is shared with the [USB keyboard interface]({{
  '/hardware/keyboard-interface/' | relative_url }}).
