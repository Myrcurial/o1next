---
layout: page
title: next-integrated
subtitle: O1NEXT Integrated — the SFF board: one board, no interposer, the whole machine
---

**Status:** concept; the directory exists and the spec is in it. **No schematic
yet** — #49 is the issue that produces one.
Tracks **#49** (Phase 5). Source: `hardware/next-integrated/`. Board register:
[`hardware/README.md`]({{ site.repository }}/blob/main/hardware/README.md).

## What it is

The **SFF board** — the foundation of the O1NEXT. A **fully integrated
board**: everything the [interposer]({{ '/hardware/interposer-upgrade/' | relative_url }})
does, designed in as firmware rather than plugged in.

**It is not a 1:1 swap, and it does not try to be.** This board can go into a real
chassis **or** into any other design — up to the end user. Nothing about it is
constrained by a 1982 footprint. (A 1:1 mainboard replacement, which *would* be
constrained that way, is possible if a chassis ever needs restoring and is not
planned — see *Hardware that is not a board* in the register.)

**The [O1NEXT]({{ '/hardware/o1next-complete/' | relative_url }}) is this board with
the rest of the machine wrapped around it.**

## Why build it at all, if the interposer exists

Because they answer different questions:

- The **[interposer]({{ '/hardware/interposer-upgrade/' | relative_url }})** is
  the *precursor*: the same capability on a board that plugs into a real machine,
  and it keeps the upgrade path open for anyone who wants it.
- This board is the *new* machine. It can be smaller, cheaper, and faster than an
  Osborne 1 with an interposer in it, and it does not need a 40-year-old CPU
  socket to work.

## What it adds over the original

- **Turbo-capable** — an 8 MHz clock, which is the "2× business turbo" the WiFi
  modem's baud buffering exists to exploit.
- **Onboard flash library**, so it boots from internal storage with no card.
- **USB-C PD power**, shared with the [complete O1NEXT]({{
  '/hardware/o1next-complete/' | relative_url }}).
- The interposer's personalities **as firmware**, not as a second board.

## The I/O complement

Deliberately **not** the original machine's connector set: what is kept is kept
because period hardware needs it, and what is dropped is dropped because a
personality replaces it.

| Function | Connector | Note |
|---|---|---|
| Serial | **DB-25 (P2)** | The RS-232C port, 6850 ACIA-driven |
| IEEE-488 | **Edge connector (P3)** | The GPIB / Drive C bus |
| Keyboard | **24-position (P4)** | So a real O1 keyboard can be used |
| Video | **HDMI out** | Adjacent to the **RESET** and **TURBO** buttons |
| Storage | **SD / microSD slot** | The bulk removable store |
| Expansion | **USB-A #1** | **Fixed function**: memory expansion |
| Keyboard (USB) | **USB-A #2** | **Fixed function**: the USB keyboard |

The two USB-A ports are fixed function on purpose — neither is a general-purpose
host, so neither needs a hub, a driver stack or a negotiation story.

**No composite.** The board carries none of the analogue driver circuitry, so
there is no composite output to offer at all — that discrete chain is an OEM
mainboard's job.

**No MODEM port — but the modem is in.** P1 is a TTL tap onto the same 6850 ACIA
the RS-232 port uses, so the *connector* has nothing left to do; the **modem
personality is fundamental** (the machine needs WiFi) and lives on the board.
The DB-25 RS-232 port stays.

The display is an **8" 1024×768 HDMI panel** inside, plus an **external HDMI
port**: the RP2354B drives HDMI directly, and that panel size is available off the
shelf.

## What it keeps

Original ROMs and original software, unchanged. The whole project's thesis is
augmentation rather than replacement, and this board is the strictest test of it:
if period software cannot tell it apart from an Osborne 1, it is finished.

## Still to do

Everything, past the concept. The block diagram comes first, then connector
placement for the complement above — and there is **no footprint to inherit**:
the end user decides what this board goes into.
