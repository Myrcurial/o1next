---
layout: page
title: "CoPower-88: the schematics"
subtitle: "Peripherals and storage"
draft: "Draft &mdash; assembled from the working notes by `tools/build_book.py`. The source document is the authority; this page is a copy for reading, and it is regenerated from that source."
---

Sources: research/copower88/zorba/611-0003-{1..4}.pdf ("SCHEMATIC 8088
BOARD", Software Publishers Inc., Arlington TX).

## Sheet 1 — 8088 CPU
8088 (U11) in minimum mode (MN/MX hi), 8284 clock generator (U5) with
X'TAL1 + reset conditioning, address demux via LS373 (U19, A0-A7) and
LS375 (U12, A16-A19), data bus transceiver LS645 (U20, DIR/EN), control
buffering via LS244 for RD/WR/IO-M/DEN. HOLD/HLDA + INTA/INTR brought
out. So: standalone 8088 system, 20-bit address space.

## Sheet 2 — RAM and ROM array
16 x 4164 = 128 KB DRAM on-board ("M1 THRU M16"), header "TO 128K RAM
EXPANSION BOARD" (256 KB total option). 2732A 4 KB boot/monitor ROM
(U28) with ROMCS + RD/OE gating. Address muxing via LS257 (U26/U27),
refresh address counter LS244 (U18) driven by REF1-7/REF-ENA. ROM data
buffered by LS244 (U23).

## Sheet 3 — Memory controller
Refresh timing: LS393 (U4) + LS161 x2 (U9/U10) generate REF1-REF7 from
CLK under REF-RST. Refresh arbitration state machine (LS175s U2 +
LS153 U3) arbitrates CPU vs refresh, generating CPU-ENQ, REF-ENQ,
RFSH and — critically — **HOLD**: the board asserts HOLD to seize the
HOST Z80's bus during refresh/arbitration windows. RAS decode: LS138
(U31) CAS0-CAS3, LS138 (U32) + LS08 (U33) RAS0-RAS3 + ROMCS, qualified
by IO/M, A16, A17, A19, HLDA. MUXC + LS74s (U30) for address mux phase.

## Sheet 4 — Z80/8088 PORTS (the host interface)

Host connector P1 carries: BIORQ, RDB, WRB, BA0 (Z80 A0), BD0-BD7 —
i.e. the board snoops ONLY IORQ cycles, one address bit, and data.

### Port decode
- 4077 XNOR comparators (U3) + 4021 shift register compare A1-A7
  against an 8-position **DIP switch** (100K networks) → DECODE.
  **The I/O base address is DIP-switch selectable in units of 2.**
  This matches RAMDISK.COM's "CoPower_88 port address or <CR>"
  prompt: Kaypro factory default 0x7E/0x7F, Zorba 0xFE/0xFF.
- LS139 (U6): BIORQ + DECODE + BA0 → PORT0 (A0=0) / PORT1 (A0=1).

### Mailbox registers
- U24 + U25 (LS373/LS373): two 8-bit latches forming a bidirectional
  data mailbox between BD0-7 (host) and D0-D7 (8088). PORT0 WRB
  latches host→8088 data (also clocking D0 flag LS74 U7 → STATIN
  visible to 8088); RDB+PORT0 reads the 8088→host latch.
- **PORT1 write sets INTR (LS74 U14) → interrupts the 8088**;
  cleared by 8088-side ack / RESET. This is the "command doorbell":
  host writes status/command port to kick the 8088 monitor.
- IRQOUT (WR + LS32 U15): 8088-side write toggles the host-visible
  status flag; host polls STATIN (RD + LS32) — **bit 0 of the status
  port**, exactly the `rra / jp c` poll loop in the drivers.
- RDX (from RD8088 via 40HC32 one-shot-ish network) heads to "PIN 21
  OF BERG PINS" — read-strobe toward the RAM expansion header.
- HC245 (U1): 8088-side data buffer BD0-7 ↔ D0-7 (daughter board).

### Protocol synthesis (hardware + drivers agree)
1. Host polls PORT1 bit0 (mailbox free), writes command byte(s) to
   PORT0, writes PORT1 (any value) to doorbell the 8088.
2. 8088 monitor (2732A ROM) services the request, fills the
   8088→host latch, toggles IRQOUT → status bit.
3. Host sees bit0 change, streams data via OUTI/INI on PORT0.
   Commands seen in RAMDISK.COM: 0x05 then 0x01 prefix a block
   transfer sequence.

## Implications for the interposer (#16/#19)

- The CoPower-88 is itself a **bus interposer precedent**: it sits on
  the host IORQ space with a minimal signal set (IORQ, RD, WR, A0-A7,
  D0-D7, RESET) and steals bus cycles via HOLD for refresh. Our
  RP2354B design needs the same signals, plus WAIT for finer-grained
  interposition (the SWP board couldn't stretch cycles; it used HOLD).
- Emulating a CoPower-88 (#26): trap IORQ at the DIP-configured base,
  implement PORT0/PORT1 + status bit0 semantics, and run the 8088
  side virtually (or stub the monitor protocol).
- For finding the Osborne CoPower-88's DIP setting without the board:
  scan even/odd port pairs for the mailbox signature (write PORT0,
  read back after 8088 echo; or observe INTR behavior). MSDOS.COM's
  "8088 DOES NOT RESPOND" path gives a detection oracle.
