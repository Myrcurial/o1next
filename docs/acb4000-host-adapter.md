# The ACB-4000 host adapter — the register protocol, and why the MAME stub is blocked (#178)

**Status: the register protocol is decoded; the "stub the ACB-4000 in MAME" route is
blocked by MAME's I/O model, not by anything unknown about the controller.** This
note records the protocol (so #179 has the bit map open question #2 asked for), and
the measurement that shows why a Lua-side stub cannot reach the adapter.

Serves #178 (the DPB mechanism) and #179 (the personality). Reads alongside
`docs/harddisk-decision.md` §6/§7.3 and `docs/acb4000-firmware.md`.

## 1. The protocol, decoded from the driver

All offsets are file offsets; `CNTLRCOD.OVL` loads at `0x8000`, `HARDBIOS.SPR`
maps to `0xE000 + offset`.

**Registers** (base `30h`, 4-aligned and relocatable — this is what `PORTCHNG.COM`
patches, §6):

| Port | Role |
|---|---|
| `base+0` | data — also the `OUTI`/`INI`/`OTIR`/`INIR` block port (`C = 30h`) |
| `base+1` | control |
| `base+2` | status (read) / control (write) |
| `base+3` | control |

**The presence probe** — the overlay's init at `0x80D2` (`CNTLRCOD.OVL` file `0xD2`);
`MD10.COM` calls it at `0x8025` and stores the returned byte at `0x2FFB`, which the
check at `0x15AF` then reads and expects to be `1`:

```
LD A,8Fh : OUT (31h),A     ; control
LD A,07h : OUT (31h),A
LD A,CFh : OUT (33h),A
LD A,6Bh : OUT (33h),A
LD A,07h : OUT (33h),A
LD A,04h : OUT (32h),A
IN A,(30h)                 ; data
IN A,(32h)                 ; status
CP 04h  ->  one controller on-line
CP 2Dh  ->  "cable connected backwards"
```

So **`base+2` reading `04h` is "exactly one controller on-line"** — the same
measurement `md10patch.py` stepped over, now with its meaning.

**A transaction** — the overlay at `0x8030` and the BIOS at file `0x285` are the same
routine. In outline:

1. wait `(base+2 & 01) = 0`;
2. `OUT base+0, (8023h)` — the select/command byte the caller parked at `0x8023`;
3. `OUT base+2, 10h`; wait `(base+2 & 01) = 1`; `OUT base+2, 0`;
4. send the CDB (at `0x8013`, opcode first) with `OUTI` while `(base+2 & 02)` is set
   and `(base+2 & 20)` is set;
5. the data phase, chosen by the CDB opcode (`& 1Fh`): `08h` READ → `INIR`×2,
   `0Ah` WRITE → `OTIR`/fill loop, otherwise `INI`/`OUTI`;
6. finish: `IN base+0` (status byte) → wait `(base+2 & 40)` → `IN base+0` →
   return `status & 02`.

The four status bits the driver polls are therefore `01h`, `02h`, `20h`, `40h`.
That closes open question #2's *shape* — `02h` behaves as `REQ`, `20h` as the phase
(`I/O`-like) line, `40h` as the end/`BSY` line, `01h` as the select handshake — though
the *names* are still inferred from the code rather than read from a controller trace.

## 2. Why the MAME stub is blocked

The MD-10 host adapter answers on I/O ports `30h`–`33h`. On the O1 those **alias onto
the ROM-bank ports**:

- MAME's `osborne1` `io_map` is `map(0x00, 0x03).w(bankswitch_w)` — the on-board I/O
  decode uses **only the low two address bits** (`src/mame/osborne/osborne1.cpp`).
- The CBIOS drives the bank / video bit-9 lines through the same ports on **every
  console character**. Measured with `tools/research/acb4000.lua` in `trace` mode: a
  plain boot emits one write per character to I/O ports `0`–`3` (the character code
  on the data bus, which the decode ignores).

So `OUT (30h)` is `OUT (00h)` (activate bank 2) and `OUT (32h)` is bit-9 set. **The
MD-10 host adapter must therefore decode the full 8-bit I/O address itself** — it is
not a card behind the mainboard's decode but a device that owns the bus for
`30h`–`33h`. That is exactly open question #5 ("a Z80-socket device or a port card"),
and the answer is now: it has to be one that replaces the decode, i.e. a Z80-socket
device (or a card that pulls the mainboard's decode off those addresses).

MAME's `osborne1` models only the mainboard's 2-bit decode, so a Lua stub on
`30h`–`33h` **cannot address the adapter**: its writes land on `bankswitch_w`, and the
console's own writes are indistinguishable from them.

What was actually measured (`tools/research/acb4000.lua`, MAME 0.289):

- Lua I/O **write** taps fire — for Lua-initiated writes *and* for guest `OUT`s.
- They only ever report offsets `0`–`3`; `write_u8(0x30, …)` reports offset `0`.
- The guest's console output floods them, so a value-based disambiguation is not
  viable.
- A **read** tap installs without error (the reads were not reached in a run where the
  utility did not start, so its firing is untested).
- **Trap:** a tap callback that touches `cpu.state["PC"]` **throws**, and because the
  PC is evaluated as an argument to `string.format`, the whole log line is lost — which
  is why an earlier trace appeared to fire nothing.

**Conclusion.** The "stub the ACB-4000 in MAME (try this first)" route from §7.3 needs
a MAME **driver change** — a card device with its own full 8-bit I/O decode on
`30h`–`33h` — not a Lua script. That is a change to a host tool, so per `AGENTS.md` it
is a question for the maintainer rather than something to engineer around.

## 3. A system image does not carry the low-RAM tables

§7.3 assumed the tables at `0x055E`/`0x056E` "must live" in the system image, because
nothing in the archive writes them. Reading the ROM's own loader shows that assumption
does not hold for the O1.

`rom144.asm` `CBOOT` (lines 641–726):

- reads sector 1 of track 0 to `0xD000`;
- takes the CCP address from **byte 2** of that sector: `(byte2 − 3) × 100h`;
- loads **60 blocks (7680 bytes)** starting at the CCP;
- jumps to `CCP + 1600h` — the BIOS jump table.

So an O1 system image is `[CCP][BDOS][BIOS]` laid out at `CCP … CCP+1E00h`. The stock
CBIOS fixes the shape (`occbio15.asm`): `CCP = 0CB00h`, `BDOS = CCP+806h`,
`BIOS = CCP+1600h`, `BIOS` RAM from `CCP+1E00h`.

Measured on the two bootable images in hand:

| Image | sector-1 byte 2 | CCP | BIOS jump table |
|---|---|---|---|
| `OS1UTLS.IMD` | `D2h` | `0CF00h` | `0E500h` |
| `…Hard Disk Control Software Version 2.01 (1984).img` | `CEh` | `0CE00h` | `0E400h` |

(In both, the 17-entry `JP` table sits at image offset `1600h`, confirming the base.)

**Low RAM is far below the CCP and is not part of any system image.** So the DPB
tables cannot arrive that way for a *stock* layout — the previous session's
"the system image is where the tables must live" was an inference, and it is wrong for
the O1's loader.

The **"Osborne Hard Disk Control Software Version 2.01 (1984)"** disk is *bootable*,
but it carries a **stock** system (the ROM's Rev 1.44 banner, `0x055E` holding ordinary
code, no MD-10 BIOS in its system tracks — the MD-10 BIOS is a file on it, at image
offset `2C00h`). So the archive still holds **no MD-10 system image**; the 2.01 disk is
the 1.93 utilities content on a bootable stock disk.

## 4. What this leaves

The tables are still built at run time (or pre-loaded by something outside the
archive). §7.3's two routes stand, with the first now carrying a dependency:

1. **A MAME driver change** to model the ACB-4000 card's full I/O decode — then the
   stub becomes possible. This is the blocker above.
2. **A bootable MD-10 system disk.** One observation keeps this alive: the MD-10 BIOS's
   own `BOOT` (file `0x182`) reads a **5-byte block at `0x0559`–`0x055D`** and calls the
   SCSI routine at file `0x285`; nothing in the archive writes `0x0559`–`0x055D`
   either. If the MD-10's CCP is low enough, that block *and* the tables at `0x055E`
   would be part of its system image — which is exactly what a bootable MD-10 disk
   would carry.

   The MD-10 `BOOT` also sets page zero to `JP 0003h` (warm vector) and
   `JP 0F206h` (BDOS entry) — neither matches the stock `CCP+1600h` layout, so **the
   MD-10's memory map is not the stock one**. Pinning that map down is the cheapest
   next step, and it is static work on `HARDBIOS.SPR`.

## Sources

- `research/adaptec/MD Utilities … 1.93 Osborne - MD-10 MD-20.img` — `CNTLRCOD.OVL`,
  `MD10.COM`, `HARDBIOS.SPR`.
- `research/adaptec/Osborne Hard Disk Control Software Version 2.01 (1984).img` — the
  bootable stock-system utilities disk.
- `research/source-code/BIOS-144-source/rom144.asm` — `CBOOT` (system load) and
  `HCBOOT` (a `JMP START` stub).
- `research/source-code/BIOS-144-source/occbio15.asm`, `occram15.asm` — the CCP/BDOS/BIOS
  layout and the BIOS RAM origin.
- `tools/research/acb4000.lua` — the trace used for the I/O-decode measurement.
- `docs/harddisk-decision.md` §6, §7.3, §10; `docs/acb4000-firmware.md`.
