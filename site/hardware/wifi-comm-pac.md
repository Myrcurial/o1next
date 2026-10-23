---
layout: page
title: wifi-comm-pac
subtitle: O1NEXT WiFi COMM PAC — a Hayes-compatible modem in the machine's floppy pocket
---

**Status:** Rev A schematic captured; no PCB yet.
Tracks **#56** (an extension of **#21**); the physical interface is #57; the
board itself is #324 (the P1 stage) and #325 (panel, audio, power). Board
register: [`hardware/README.md`]({{ site.repository }}/blob/main/hardware/README.md).

## What it is

An **ESP32-S2** running a **Zimodem fork** — Hayes AT command set plus telnet,
and with two pieces of new work on top:

- **SSH as a first-class transport**, with keys, host verification and session
  management from a web UI. An Osborne 1 dialling into a modern host with `ssh`.
- **Baud-rate buffering**, decoupling the machine's 6850 ACIA rate from the
  far-end link rate — which makes a turbo upgrade usable and quietly corrects the
  factory 600/2400 → 650/2600 quirk.

The S2 rather than an ESP8266 or a C3 is deliberate: its auto-baud pulse counter
is 20-bit, and the C3/S3 are 12-bit, which puts 300/1200/2400 below their floor.
The ESP8266 lacks the headroom for SSH entirely.

## How it attaches

It sits in the **left floppy pocket** and hangs off the machine's **MODEM port
(P1)** by a short **10-conductor ribbon**: a **DE-9 plug** into the machine, a
**2×5 IDC header** on the board. There is no case opening and no separate supply.

The port is **TTL, not RS-232** — it feeds the 6850 ACIA directly (status
`2A00H`, data `2A01H`). The levels are asymmetric, and both halves need work:

- **TXD and MCB arrive at 5 V** and the ESP32 is not 5 V tolerant, so a
  dual-supply translator (74LVC4T245) sits in each direction.
- **MSB is open-collector** and gets an open-drain driver (74LVC1G07).
- **RXD is bipolar** (`−0.5 … −10 V = 1`), so a **MAX3232 on 3.3 V** supplies
  ±5.5 V from its own charge pump.

## Power

DE-9 pin 7 is **+12.6 V DC, and it is behind the machine's 22 Ω** — the Technical
Manual §4.3.2 says so in words ("Connected to power supply through 22 ohms"), and
sheet 7 shows `R21` feeding both this pin and the keyboard branch (`J6 → P4-19`).
So the port is a **low-current supply**: 22 Ω at 500 mA would drop 11 V, and at
100 mA it drops 2.2 V. The board's average draw has to be tens of mA, and it
shares the resistor with the keyboard adapter.

Two sources, **diode-OR**'d so neither back-feeds the other: the port's
**12.6 V → 5 V → 3.3 V**, and **USB-C 5 V → 3.3 V** for programming and bench
work. The switch is ahead of the buck, so "off" is genuinely dark. The bulk
capacitor at the buck input supplies the WiFi TX peaks, which `R21` cannot.

## The panel, and the noise

Eleven lamps on an **AW9523B** (16 constant-current channels, 256-step dimming,
holds its outputs so a hung firmware leaves a readable frozen panel): radio,
connected, HS, AA, CD, OH, RD, SD, TR, MR, RI. A second expander is a DNP
option and carries the handshake lines.

Sound is an **I²S class-D amplifier with its own DAC** on the 5 V rail, driving a
passive transducer — dial tone, DTMF and a ring cadence, not a one-note buzzer.

## The case

A **"COMM PAC-look" case** fits the left pocket — period-authentic Osborne
industrial design, so it reads as original kit rather than a modern dongle. The
STL is already designed and fit-tested; left to right across the front: antenna,
power switch, 2×5 IDC, LED row, USB-C.

## Still to confirm

- The **2×5 IDC orientation** on a real machine (#324).
- The **RXD negative swing** in hardware — ±5.5 V should be comfortable, but the
  receiving front end is a comparator with a 5.1 V clamp.
- The **audio transducer** and where it points once the case is closed (#325).
