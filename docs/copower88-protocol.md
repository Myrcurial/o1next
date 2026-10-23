# SWP CoPower-88: host protocol (from the Kaypro + Zorba drivers)

**Status: Partially solved.** The port pair, the handshake and the block transfer
are read out of the two `RAMDISK.COM` builds and corroborated by the board's own
schematic; what is left is the 8088-side command set — the monitor ROM is in the
repo (`research/roms/swp-p88.rom`, #70) but has not been disassembled for it — and
the meaning of every status bit other than the two the drivers test.

The CoPower-88 is an **8088 co-processor board sitting on the host Z80's bus**, and
it presents the host with a **two-port mailbox**. The **even** address of the pair
is the data/command port; the **odd** address is status. Every transfer is a poll
of the status port followed by an `OUTI`/`INI` block. The pair is configurable
twice over, and both have to agree: the board takes it from an 8-position switch
(`docs/copower88-schematics.md`, §"Port decode"), and the driver is told the same
pair at install time, defaulting to the two bytes in the `.COM` header.

Serves #3 (the Z80 socket and pinout this board sits in), #4 (the CoPower-88's own
ROM, which is in the archive), #5 (the port decode) and #23 (the virtual
CoPower-88 personality this contract is written for).

| Port | Address | Direction | What it is |
|---|---|---|---|
| **Data / command** | even — `D` in the driver (Kaypro `7Eh`, Zorba `FEh`) | both | `OUT` latches host→8088; `IN` reads the 8088→host latch |
| **Status** | odd — `E` in the driver (`7Fh`, `FFh`) | read | bit 0 **set** = the host must wait before a write; bit 7 **set** = a byte is waiting for the host |
| **Doorbell** | the same odd address | write | sets `INTR` on the 8088 (sheet 4). **Neither RAMDISK driver uses it**: every write they make goes to the even port, and that write is itself the doorbell |

The pair is stored as one word at `0107h` — low byte (`E`) = status, high byte
(`D`) = data — so a port override has to keep that order. `RAMDISK.COM` asks for
it directly: `CoPower_88 port address or <CR> to use default`.

Sources: `research/copower88/kaypro/extracted_cpm/` (copwrcpm.td0) and
`research/copower88/zorba/extracted/` (swpdos.td0). Disassemblies in `*/disasm/`
(z80dasm, org 0x100). Schematics: `research/copower88/zorba/611-0003-{1..4}.pdf`
— the port decode is settled in `docs/copower88-schematics.md` (#5).

## The transfer protocol, instruction by instruction

Both drivers carry the same subroutine at `0B82h` (host → 8088) and `0BE9h`
(8088 → host) — the machine-specific parts of `RAMDISK.COM` are the port defaults
and the install-time patching, not the transfer:

| Step | The code | What it means |
|---|---|---|
| 1 | `LD DE,(0DB6h)` / `LD C,E` | load the port pair; `C` := the **status** (odd) port |
| 2 | `IN A,(C)` / `RRA` / `JP C` | **wait while status bit 0 is set** |
| 3 | `LD C,D` / `OUT (C),A` | write the command byte to the **data** port |
| 4 | `LD A,005h` … `LD A,001h` | the two-byte preamble `05h`, `01h`, each behind a fresh poll |
| 5 | `OUTI`, with `LD B,080h` | the block, **128 bytes at a time** — one poll per byte |
| 6 | `IN A,(C)` / `JP P` / `LD C,D` / `IN A,(C)` / `CP 005h` | on a read, **wait while status bit 7 is clear**, then expect `05h` |
| 7 | `CP 001h`, then `INI` | the same `05h`, `01h` preamble, then the block read |

Three consequences worth stating plainly:

- **`05h`/`01h` is a preamble, not a direction code.** Both directions open with
  it, so it frames the transfer rather than selecting it; what distinguishes a
  read from a write is which subroutine the driver called. The length lives in the
  driver's own work cell (`0CBDh`), and the `080h` in the block loop is CP/M's
  128-byte record.
- **The status port is read for two different bits at two different polarities** —
  bit 0 *set* means wait before a write, bit 7 *clear* means wait before a read.
  The schematic accounts for one host-visible flag, bit 0, toggled by the 8088's
  write (`docs/copower88-schematics.md` §"Mailbox registers"); what drives bit 7
  is not shown on the sheet.
- **The header bytes are the configuration** (identical in both images):
  `0103h` = the assigned drive number, zero-based — `SUB 41h` at `037Bh`,
  `ADD A,41h` at `0753h` — default `0Ch` = drive M; `0104h` = the
  erase-directory answer (`59h` = `Y`); `0107h`/`0108h` = the port pair above.
  `RAMDISK` asks for all three at install time: drive letter (A–P),
  erase-directory Y/N, load address (page-aligned, `??00`) and the port pair, then
  installs a BIOS wedge — *"not standard CP/M system, cannot install"* if the BIOS
  jump table is not where it expects it.

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

1. **The Osborne board's pair is not a free choice, and it is not the Kaypro
   default.** The CoPower-88 decodes the pair on its own board — it snoops only
   `IORQ`, one address bit and the data bus (`docs/copower88-schematics.md`) — but
   the host's decode sees the same write cycles, and the O1 decodes **only
   `A1:A0`** of an `OUT` (`docs/o1-memory-io-map.md` §4, measured), so every port
   aliases one of `00h`–`03h`. The member that matters is the **even** one, because
   that is the one written on every byte: `7Eh`/`FEh` alias `02h` = *set `BIT 9`*,
   which maps the dim-bit bank over video. A port override therefore has to land on
   a pair whose written address is harmless under `A1:A0` — `00` (bank-2 select,
   which the machine re-derives) or `11` (clear `BIT 9`, idempotent) — never `10`.
   `docs/mailbox-protocol.md` §2.1 dodges the same hazard by the same rule, and
   `docs/o1-memory-io-map.md` §7's "avoid `0x00`–`0x03` entirely" is the general
   form of it. **What the pair is set to on an Osborne board is a measurement, not
   a guess** — see "Open questions".
2. What *is* settled is that a port override needs no change to the driver's code:
   the pair is one word at `0107h`, so once the board's setting is known the
   existing driver talks to it with a different constant.
3. MSDOS.COM's Kaypro system-port access must be mapped to Osborne
   equivalents (bank-2 memory-mapped ACIA/PIA) — the BIOS-call
   translation layer is where the porting effort lives.
4. The 8088-side firmware is on the board's ROM (not on these disks); the DOS
   disks (copwrdos.td0, dos211-*.td0) are PC-side payloads. That ROM is in the
   repo as `research/roms/swp-p88.rom` (#70) — 8088 code, dumped from an SWP
   board.

## Open questions

- **The 8088-side command set** beyond the `05h`/`01h` preamble — sector
  read/write, identify, sync. `research/roms/swp-p88.rom` (#70) is that monitor,
  in 8088 code and already in the repo, so the answer is a disassembly away.
- **What drives status bit 7**, the read-side "data available" flag. Sheet 4 shows
  one host-visible flag, on bit 0; the read path waits for bit 7.
- **The Osborne variant's port pair** — and whether it could keep the Kaypro
  default at all, given the `A1:A0` alias above. The board photographed is a
  KAYPRO-88 (`docs/photo-survey.md` §"CoPower-88 8088 board" — the photo drop for
  **#9**), and that document
  reads the base as a comparator with a hardwired reference rather than the
  8-position switch the drawing shows; the drawing is the primary source here, and
  no Osborne board's setting is recorded either way.
- **The other six status bits** — the drivers never test them, and the schematic
  drives only one.
