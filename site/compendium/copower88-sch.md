---
layout: page
title: "CoPower-88: the schematics"
subtitle: "Peripherals and storage"
draft: "Draft &mdash; assembled from the working notes by `tools/build_book.py`. The source document is the authority; this page is a copy for reading, and it is regenerated from that source."
---

**Status: Solved.** The four sheets settle what the board is and how the host talks
to it: an **8088 in minimum mode** with its own clock, RAM and refresh, and a
**switch-set port decode into a two-port mailbox** with a doorbell. What the sheets
do not settle is the second status bit the drivers poll before a read (bit 7,
§"Protocol synthesis") and the base the *Osborne* variant's decode is set to.

The board is the closest thing in the archive to this project's own interposer: it
sits on the host's `IORQ` space with a **minimal signal set** — `BIORQ`, `RDB`,
`WRB`, one address bit and eight data lines — and it seizes the host bus with
`HOLD` when it needs to. Its host interface is a two-port mailbox whose **base is
set on the board, in units of 2**; the protocol that mailbox speaks is read out of
the drivers in [`docs/copower88-protocol.md`](https://github.com/Myrcurial/o1next/blob/main/docs/copower88-protocol.md) (#5), and the two agree. That matters
here twice: as prior art for our own interposer (#16/#19), and as the board a
CoPower-88 personality would have to emulate (#26).

Sources: `research/copower88/zorba/611-0003-{1..4}.pdf` ("SCHEMATIC 8088
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
  **The I/O base address is switch-selectable in units of 2**, and it is set on the
  board rather than by software. This matches RAMDISK.COM's "CoPower_88 port
  address or <CR>" prompt: Kaypro factory default 0x7E/0x7F, Zorba 0xFE/0xFF.
  (The one board photographed reads that package as a comparator with a hardwired
  reference instead — [`docs/photo-survey.md`](https://github.com/Myrcurial/o1next/blob/main/docs/photo-survey.md) §"CoPower-88 8088 board". The drawing
  is the primary source; the Osborne variant's setting is unrecorded either way.)
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
1. Host polls PORT1 (the odd port) and writes command byte(s) to PORT0 (the even
   one). The drivers test **bit 0** before a write — `IN A,(C)` / `RRA` / `JP C`,
   waiting while it is *set* — and **bit 7** before a read, waiting while it is
   *clear*. Bit 0 is the flag this sheet accounts for; what drives bit 7 is not
   shown here (read out of the drivers, [`docs/copower88-protocol.md`](https://github.com/Myrcurial/o1next/blob/main/docs/copower88-protocol.md)).
2. 8088 monitor (2732A ROM) services the request, fills the
   8088→host latch, toggles IRQOUT → status bit.
3. Host sees the flag change, streams data via OUTI/INI on PORT0. The two bytes
   RAMDISK.COM sends — 0x05 then 0x01 — are a **preamble** that opens the transfer
   in both directions, not a direction code.
4. **Two ways to ring the doorbell, and the drivers use the quieter one.** A write
   to PORT1 sets INTR (LS74 U14) outright; a write to PORT0 also clocks the D0 flag
   (LS74 U7) that the 8088 can see. Every write in both RAMDISK.COM builds goes to
   PORT0, so the 8088 is kicked without INTR being raised at all.

## Implications for the interposer (#16/#19)

- The CoPower-88 is itself a **bus interposer precedent**: it sits on
  the host IORQ space with a minimal signal set (IORQ, RD, WR, A0-A7,
  D0-D7, RESET) and steals bus cycles via HOLD for refresh. Our
  RP2354B design needs the same signals, plus WAIT for finer-grained
  interposition (the SWP board couldn't stretch cycles; it used HOLD).
- Emulating a CoPower-88 (#26): trap IORQ at the switch-configured base,
  implement PORT0/PORT1 with both status bits (bit 0 write-side, bit 7
  read-side), and run the 8088 side virtually (or stub the monitor protocol).
- For finding the Osborne CoPower-88's switch setting without a schematic:
  scan even/odd port pairs for the mailbox signature (write PORT0, read back after
  8088 echo; or observe INTR behavior). MSDOS.COM's "8088 DOES NOT RESPOND" path
  gives a detection oracle — and any such scan has to respect the host's `A1:A0`
  alias, because a write to a port `≡ 2 (mod 4)` sets `BIT 9` and maps the dim-bit
  bank over video ([`docs/o1-memory-io-map.md`](https://github.com/Myrcurial/o1next/blob/main/docs/o1-memory-io-map.md) §4).
