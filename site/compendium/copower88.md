---
layout: page
title: "CoPower-88: the host protocol"
subtitle: "Peripherals and storage · partially solved"
draft: "Draft &mdash; assembled from the working notes by `tools/build_book.py`. The source document is the authority; this page is a copy for reading, and it is regenerated from that source."
---

Sources: research/copower88/kaypro/extracted_cpm/ (copwrcpm.td0) and
research/copower88/zorba/extracted/ (swpdos.td0). Disassemblies in
*/disasm/ (z80dasm, org 0x100). Schematics: 611-0003-1..4.pdf (Zorba
site) — TODO: extract port decode details (#5).

## The headline facts

1. **Two adjacent I/O ports**: a STATUS port (E) and a DATA/COMMAND
   port (D), consecutive addresses. All transfers use Z80 block I/O
   (`OUTI`) with bit-0 polling of the status port.
2. **The port base is software-configurable**: RAMDISK.COM prompts
   "CoPower_88 port address or <CR> to use default". Defaults are
   stored in the .COM header:
   - Kaypro: status **0x7F**, data **0x7E** (bytes at 0x107: `7F 7E`)
   - Zorba:  status **0xFF**, data **0xFE** (bytes at 0x107: `FF FE`)
   - header byte at 0x103 stored to a work cell (function TBD; 0x0C?)
3. **Transfer protocol** (identical code at 0x0B82 in both RAMDISKs):
   - poll status port bit 0 (wait while set)
   - write command byte 0x05 to data port
   - poll, write 0x01
   - poll, then a sequence of `OUTI` block transfers (sector data)
   Inter-command handshaking on both directions via the same bit.
4. RAMDISK asks: drive letter (A-P), erase dir Y/N, load address
   (page-aligned, "??00"), port pair. Installs a BIOS wedge
   ("not standard CP/M system, cannot install" if the BIOS jump table
   isn't where expected).

## Machine glue differences (Kaypro MSDOS.COM vs Zorba PCDOS.COM)

- Kaypro MSDOS.COM touches Kaypro motherboard system ports
  (0x10-0x14 SIO/CTC/system, 0x1C/0x1D/0x1F heavily) IN ADDITION to the
  CoPower ports — screen/keyboard/clock glue for the "BIOS calls only"
  PC emulation environment.
- Zorba PCDOS.COM error strings show the watchdog protocol:
  "INVALID 8088 REQUEST #XX AT XXXX", "8088 DOES NOT RESPOND",
  "8088 SYNC ERROR, PRESS R TO RETRY" — the Z80 host polls the 8088's
  request queue; the 8088 ROM monitor services requests asynchronously.
- Both drivers are the same vintage SWP codebase (identical io
  subroutine offsets) — the machine-specific parts are: port defaults,
  console/screen BIOS glue, and install-time BIOS vector patching.

## Implications for the Osborne 1 port (#26)

1. The Osborne CoPower-88 board likely decodes yet another port pair;
   candidates: any free O1 port pair (O1 uses few ports; the DD
   upgrade uses 0xF1? TBD from schematics #5 / photos #9). The
   configurability in RAMDISK.COM means once we know the Osborne
   board's decode, the existing driver may work AS-IS with a port
   override.
2. MSDOS.COM's Kaypro system-port access must be mapped to Osborne
   equivalents (bank-2 memory-mapped ACIA/PIA) — the BIOS-call
   translation layer is where the porting effort lives.
3. The 8088-side firmware is on the board's ROM (not on these disks);
   the DOS disks (copwrdos.td0, dos211-*.td0) are PC-side payloads.

## Open questions

- Exact status-bit semantics (bit0=busy both directions? other bits?)
- Command set beyond 05/01 (sector read/write, identify, sync)
- Header byte at 0x103 (0x0C): drive count? IRQ enable?
- Osborne port decode on the actual CoPower-88 (from 611-0003
  schematics + board photos)
