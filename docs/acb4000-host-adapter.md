# The ACB-4000 host adapter — the register protocol, and why the MAME stub is blocked (#178)

**Status: Solved.** The register protocol is decoded from the driver, and the
"stub the ACB-4000 in MAME" route is blocked by MAME's I/O model rather than by
anything unknown about the controller — so the fix was a driver change, and #191's
`osborne1nx` machine is it. The one thing still inferred is the four status bits'
*names*: `02h`/`20h`/`40h`/`01h` behave as `REQ`/phase/end/select from the code,
but no controller trace names them. This note records the protocol (so #179 has the
bit map open question #2 asked for), and the measurement that shows why a Lua-side
stub cannot reach the adapter.

Serves #178 (the DPB mechanism) and #179 (the personality). Reads alongside
`docs/harddisk-decision.md` §6/§7.3, `docs/acb4000-firmware.md` and
`docs/md10-system.md`.

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
measurement `md10patch.py` stepped over, now with its meaning. On the built
machine (#191) `base+2` reads as a **read/write register** rather than a pure
status byte: `04h` is the controller-select field read back, and the *real* probe
is the ID scan that follows (`docs/osborne1nx-machine.md` §4). The driver's `CP 04h`
check is still the gate, which is why it is the symptom.

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
  PC is evaluated as an argument to `string.format`, the whole log line is lost —
  which is how a trace can appear to fire nothing.
- **Trap:** the taps **stop firing once the harness polls the program space from Lua**
  (observed: a standalone trace logs thousands of accesses across a run; the same trace
  through `o1keys.sh`, whose `rows()` reads 4 KiB of VRAM per poll, goes silent). A
  trace must therefore be a standalone `-autoboot_script`, not a run through the
  keystroke harness.

**Conclusion.** The "stub the ACB-4000 in MAME" route needs a MAME **driver
change** — a card device with its own full 8-bit I/O decode on `30h`–`33h` — not a
Lua script. That is a change to a host tool, so per `AGENTS.md` it is a question
for the maintainer rather than something to engineer around.

**That change is built — #191, `docs/osborne1nx-machine.md`.** The `osborne1nx`
machine (`tools/emulator-setup/mame-osborne1nx/`) widens the I/O decode to eight
bits while keeping the mainboard's 2-bit alias, and answers on `30h`–`33h` with an
ACB-4000 host adapter. The MD-10's presence probe reads `04h` unpatched, and the
drive-table editor (`MD10.COM`, shipped as `PREP.COM` in 2.01) runs. §1's bit map
reads as follows on that machine: `base+2` is a **read/write register**, and `04h`
is a controller-select field read back, not a status bit — the *real* probe is the
ID scan that follows it. Adaptec's "controller 01" is **SCSI ID 0**, and the select
byte is a one-of-eight mask.

## 3. Where the tables come from — not a system image

The tables at `0x055E`/`0x056E` are **not** carried by a system image. Reading the
ROM's own loader shows why, for the O1's layout:

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
tables cannot arrive that way — and they do not need to. They arrive **inside the
BIOS image**: `HARD.COM` carries a relocated copy of the MD-10 BIOS in its tail
(`0x053A`–`0x0AFF`) and installs it at `0xD800`, so `0x055E` is an offset from that
base and the tables land at `0xDD5E`/`0xDD6E` (`docs/harddisk-decision.md` §7.3;
`docs/md10-system.md` §4–§6).

The **"Osborne Hard Disk Control Software Version 2.01 (1984)"** disk is *bootable*,
but it carries a **stock** system (the ROM's Rev 1.44 banner, `0x055E` holding ordinary
code, no MD-10 BIOS in its system tracks — the MD-10 BIOS is a file on it, at image
offset `2C00h`). So the 2.01 disk is the 1.93 utilities content on a bootable stock
disk, and the archive holds no MD-10 system image *as a file*. It does not need one:
`PREP.COM` option 3 **configures an operating system onto a drive**, and what it
writes boots to a prompt (`docs/md10-system.md` §1, §7).

## 4. What this leaves

The tables are **installed with the BIOS**, not built in low RAM (§3). Both routes
the search left open are closed, and both closed inside this repo:

1. **A MAME driver change** to model the ACB-4000 card's full I/O decode — the
   blocker above. **Built: #191, the `osborne1nx` machine**
   (`docs/osborne1nx-machine.md`). The probe passes, the drive-table editor runs,
   and the *data* phase works: with a mounted PYXIS27 image the MD-10 system boots
   to a prompt with three partitions (`docs/md10-system.md` §7).
2. **A bootable MD-10 system disk.** The MD-10 BIOS's own `BOOT` (file `0x182`)
   reads a **5-byte block at `0x0559`–`0x055D`** and calls the SCSI routine at file
   `0x285`. That block is the MD-10 BIOS's own data at base+`0x559`, and it arrives
   inside `HARD.COM`, which carries a relocated copy of the BIOS at file offset
   `0x053A` and copies it to `0xD800` — so `0x0559` is `0xD800 + 0x559` = `0xDD59`
   and its writer is `HARD.COM`'s own data at file offset `0x0993`, not any low-RAM
   store. The values are the select byte `01`, LBA `5` and count `11`
   (`docs/md10-system.md` §4–§6). And the system itself is not needed *as a file*:
   `PREP.COM` option 3 writes one, and it boots (`docs/md10-system.md` §1, §7).

   The MD-10 `BOOT` also sets page zero to `JP 0003h` (warm vector) and
   `JP 0F206h` (BDOS entry) — neither matches the stock `CCP+1600h` layout, so **the
   MD-10's memory map is not the stock one**. That map is read in
   `docs/md10-system.md` §4–§6: the BIOS installs at `0xD800`, `HARD.COM` reads LBA 5
   for eleven blocks into `0xC200`, patches page zero, and CP/M runs.

What remains is the same narrow question `docs/harddisk-decision.md` §10 item 1
carries: **which copy of the tables a boot uses** — the static fallback inside the
BIOS image, or the drive's own copy of the geometry and type bytes at LBA 4
(`docs/md10-system.md` §3, §9.1).

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
- `docs/harddisk-decision.md` §6, §7.3, §10; `docs/acb4000-firmware.md`;
  `docs/md10-system.md` §4–§7, §9.
