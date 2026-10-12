# `osborne1ng` — the emulated interposer, and the ACB-4000 host adapter (#191)

**Status: partially solved — the machine boots and the card answers.** `osborne1ng`
is a fourth `osborne1` machine in MAME whose Z80 sits behind a card that decodes
the full 8-bit I/O address, so the MD-10's host adapter can answer on ports
`30h`–`33h` — the ports its driver demands and the stock machine cannot reach.
The drive-table editor that #178 had to *patch around* now runs unpatched; the
data phase and the low-RAM tables it would build are the next slice (§5).

Serves #191; unblocks #178's `peek` and is the emulated half of the personality
(#179). Reads alongside `docs/acb4000-host-adapter.md` (the protocol and the
blocker), `docs/acb4000-firmware.md` (the controller) and
`docs/harddisk-decision.md` §5 (the three layers).

The patch, the apply script and the probe live in
`tools/emulator-setup/mame-osborne1ng/`.

## 1. Why a new machine rather than a script

`docs/acb4000-host-adapter.md` §2 measured this and it is worth restating,
because it is the whole reason the machine exists:

- MAME's `osborne1` I/O map is `map(0x00, 0x03).w(bankswitch_w)` with
  `map.global_mask(0x03)` — the on-board decode looks at **A0 and A1 only**.
- `OUT (30h)` is therefore erased to offset `0` and lands on `bankswitch_w`;
  `OUT (32h)` is bit-9 set.
- The CBIOS drives those same ports on **every console character**, so a Lua-side
  stub is indistinguishable from the console's own writes.

A tap installed on `30h`–`33h` against the stock machine says so out loud:

```
install_write_tap: In range 30-33 mirror 0, start address is outside of the
global address mask 3, did you mean 0 ?
```

That is the blocker, and it is not something a script can work around. It needs
a machine whose I/O space decodes eight bits.

## 2. The decode — widening it without breaking the mainboard

The requirement is two-sided, and the second side is the one that breaks things
if it is got wrong: the card has to own `30h`–`33h`, **and** the mainboard's
coarse 2-bit decode has to keep working, because the CBIOS banks and drives the
video attribute bit through `0x00`–`0x03` on every character.

`osborne1ng`'s I/O map:

```cpp
void osborne1ng_state::osborne1ng_io(address_map &map)
{
	map.unmap_value_high();

	// The mainboard's own decode looks at A0-A1 only, so its four bank/video
	// ports alias across the whole low port page -- and the CBIOS drives them on
	// every console character, so that behaviour has to survive untouched.  Keep
	// the 2-bit alias and put the card's window on top of it: 30h-33h is the
	// one place where the card, not the mainboard, owns the bus.
	map.global_mask(0xff);
	map(0x00, 0x03).mirror(0xfc).w(FUNC(osborne1ng_state::bankswitch_w));
	map(0x30, 0x33).rw(m_acb4000, FUNC(acb4000_host_adapter_device::read), FUNC(acb4000_host_adapter_device::write));
}
```

Three things make that the right shape rather than a hack:

- **`global_mask(0xff)`** says what the machine actually does: the low port page
  is decoded and A8–A15 are ignored. The stock driver's `0x03` said "two bits",
  which is true of the *mainboard*, not of the bus.
- **`mirror(0xfc)`** reproduces the mainboard's alias exactly: `0x00`–`0x03`
  repeats every four bytes across the page, so `0x04`–`0x07` alias `0x00`–`0x03`,
  and so on. That is the behaviour the video and banking depend on.
- **the card's entry comes second**, and in MAME a later entry overrides an
  earlier one for the range it covers (the driver relies on this itself: `.ram()`
  then `.w(videoram_w)` then a view over the same range). So `30h`–`33h` goes to
  the card and everything else keeps aliasing the bank switch.

The collision the issue flagged is real and is why this is the first thing to get
right: `0x04`–`0x07` alias `0x00`–`0x03`, and the MD-10's presence probe writes
`04h` to `base+2` — which is a *port write*, not a bank switch, so it only works
once the card owns the window.

### Measured

`tools/emulator-setup/mame-osborne1ng/o1ng-probe.lua`, headless:

```
bank: rom=31 ram=00 alias05=00 alias3d=00 rom_again=31
  mainboard 2-bit decode preserved: yes
card window: 30h-33h left the bank alone: yes (00/00)
presence probe: IN 30h=00  IN 32h=04  -> one controller on-line
  register clears: IN 32h=00 -> yes
```

`rom=31` is the ROM's first byte with bank 2 selected, `ram=00` is RAM with bank
1 selected, and `05h` and `3Dh` both reach the bank switch through the alias.
Then a boot comparison, on the same disk, `osborne1` against `osborne1ng`:
`diff` clean, `416x240` (52 columns), `RESULT: BOOTED`.

## 3. The card — read out of the driver, not guessed

The host adapter is a MAME device
(`src/devices/machine/acb4000_host_adapter.{h,cpp}`), a `legacy_scsi_host_adapter`
with the MD-10's register profile on top. Its behaviour was **not** inferred from
`docs/acb4000-host-adapter.md` §1 alone — the routine that drives it is the MD-10
overlay's own code, and the copies of it that matter are:

| Copy | Where | Address |
|---|---|---|
| the BIOS overlay | `HARDBIOS.SPR` file offset `0x285` | `0xE285` |
| the utilities overlay | `CNTLRCOD.OVL` file offset `0x51` | `0x8051` |
| the probe inside it | `CNTLRCOD.OVL` file offset `0x100` | `0x8100` |
| the installer's own copy | `HARD.COM` (2.01) | `0x02E6` / `0x0441` |

`HARDBIOS.SPR` maps to `0xE000 + offset`; `CNTLRCOD.OVL` loads at `0x8000`. Both
were extracted from the archive's images with `tools/cpmfs.py` and disassembled
with `z80dasm`.

### The registers

| Port | Role |
|---|---|
| `base+0` | data — and the block port (`OUTI`/`INI`/`OTIR`/`INIR`, `C = base`) |
| `base+1` | control (write only) |
| `base+2` | **read/write** register — controller select, read back |
| `base+3` | control (write only) |

### The probe (`CNTLRCOD.OVL` 0x8100)

```
810d  ld a,08fh / out (031h),a        ; wr 1 <- 8F
8111  ld a,007h / out (031h),a        ; wr 1 <- 07
8115  ld a,0cfh / out (033h),a        ; wr 3 <- CF
8119  ld a,06bh / out (033h),a        ; wr 3 <- 6B
811d  ld a,007h / out (033h),a        ; wr 3 <- 07
8123  in a,(030h) / in a,(032h) / or a / jr z,812c / djnz 8123
812c  ld a,004h / out (032h),a        ; wr 2 <- 04
8130  xor a    / out (032h),a         ; wr 2 <- 00
8138  in a,(030h) / in a,(032h) / or a / jr z,8141 / djnz 8138
8141  ld a,004h / out (032h),a        ; wr 2 <- 04
8145  in a,(032h)                     ; read
8147  cp 004h
8149  jp z,823fh                      ; == 04h -> good
814c  cp 02dh                         ; 2Dh = cable connected backwards
814e  jp nz,8206h                     ; else "Interface board or software not
                                      ;       addressed properly"
```

and the good path:

```
823f  xor a / out (032h),a            ; wr 2 <- 00
8242  in a,(032h)
8244  or a
8245  jr nz,8206h                     ; must read ZERO, else the same error
8247  ld bc,0b44ah / call 82bfh       ; settle
8250  ld bc,00801h                    ; B = 8 tries, C = 01h
8256  ld a,c / out (030h),a           ; select byte
8259  ld a,010h / out (032h),a        ; assert the select handshake
825e  ld b,028h                       ; 40 polls
8260  in a,(032h) / and 001h / jr nz,82aah
8266  djnz 8260
8268  pop bc / sla c / inc d / djnz 8256   ; next ID bit
826e  ld a,e / or a / ret nz          ; found -> carry on
8271  call 8001h                      ; "No controller on-line"
```

**Two findings fall out of that listing, and both are easy to get wrong:**

1. **`base+2` is a read/write register, and `04h` is a controller-select field
   read back — not a status bit.** The probe writes `04h`, reads `04h`; the good
   path writes `00h` and *requires* `00h`. Modelling it as a pure status byte
   ("one controller on-line") passes the first check and then fails at `0x8244`
   with `Interface board or software not addressed properly` — which is exactly
   what happened here first, and what the device log showed: a probe that passed,
   an ID scan that started, and a good path that was never reached.
   `docs/acb4000-host-adapter.md` §1's "base+2 = 04h ⇒ one controller on-line"
   is the *symptom*; this is the mechanism.
2. **The real probe is the ID scan, and the select byte is a one-of-eight mask.**
   `C` starts at `01h` and `sla c` walks it — `01h`, `02h`, `04h`, … `80h`. So
   the select byte written to `base+0` is `1 << id`, and Adaptec's "controller
   01" (the OEM manual's Appendix A) is **SCSI ID 0**. `HARD.COM` does not scan
   at all: it reads its select byte from a configured byte at `0x0A93`, and that
   byte is `01h`.


### The transaction (`HARDBIOS.SPR` 0x285 / `CNTLRCOD.OVL` 0x51)

```
e28b  in a,(032h) / and 001h / jr nz,e28b     ; wait for the handshake to clear
e291  ld a,(00557h) / out (030h),a            ; the select byte
e296  ld a,010h / out (032h),a                ; assert
e29a  in a,(032h) / and 001h / jr z,e29a      ; ... and wait for the card
e2a0  xor a / out (032h),a                    ; release: the command phase starts
e2a8  in a,(032h)                             ; command phase
      bit 6,a / jr nz,e2ba                    ; 40h -> phase over
      bit 1,a / jr z,e2a8                     ; 02h = REQ
      and 020h / jr z,e2ba                    ; 20h = phase (C/D)
      outi                                    ; one CDB byte
e2ba  ld b,000h / ld hl,(0172h)               ; data phase: 512 bytes per pass
e2bf  in a,(032h) / bit 6,a / jr nz,e2cf
      and 002h / jr z,e2bf
      otir / otir                             ; 2 x 256 bytes out
e2cf  and 020h / jr nz,e2e6                   ; bit 5 set -> status
      ld a,(01fah) / cp 008h / jr z,e2f4      ; READ -> 2 x INIR = 512 bytes in
e2da  ini / ...                               ; otherwise a byte at a time
e2e6  in b,(c)                                ; the status byte
e2e8  in a,(032h) / and 040h / jr z,e2e8      ; wait for 40h
e2ee  in a,(030h)                             ; discard
      ld a,b / and 002h / ret                 ; 0 = good, 2 = check condition
```

So the card has to present four states and the driver's own loops do the rest:
the command phase moves **one CDB byte per REQ** with `C/D` set, the data phase
moves **512-byte blocks** (`2 × OTIR`/`INIR` with `B = 0`), and the status phase
hands over **one status byte**. The status bit map the device drives:

| Bit | Meaning |
|---|---|
| `01h` | selection handshake — clear at rest, set while selected |
| `02h` | REQ — move a byte, or a 512-byte block |
| `04h` | the controller field of the `base+2` register (one on-line) |
| `20h` | phase — `1` = command/status, `0` = data |
| `40h` | the current phase is complete, act on it |

The CDB is built at `0x01FA` (the opcode first, so `OUTI` walks it), the data
buffer pointer is passed in `HL`, and the caller gets `status & 02h` back — `0`
for good, `2` for check condition. `HARDBIOS.SPR`'s own `BOOT` (file `0x182`)
is the worked example: it builds a 6-byte `READ` (`08h`) at `0x01FA` with a
block count of `1` and calls the routine with `HL = 0xEA00`, then retries until
it succeeds.

### Wiring

```cpp
scsi_port_device &scsi(SCSI_PORT(config, "scsi"));
scsi.set_slot_device(1, "harddisk", SCSIHD, DEVICE_INPUT_DEFAULTS_NAME(SCSI_ID_0));

ACB4000_HOST_ADAPTER(config, m_acb4000);
m_acb4000->set_scsi_port("scsi");
```

The card is a `legacy_scsi_host_adapter`, so the SCSI half is MAME's: the device
drives `send_command` / `get_phase` / `get_length` / `read_data` / `write_data`
against whatever is in the slot. For this slice that is a stock `SCSIHD`;
#179's ACB-4000 target replaces it without touching the shim, which is the point
of splitting the personality into three layers (`docs/harddisk-decision.md` §5).


## 4. What is validated

Measured on MAME 0.289, macOS, `OSD=mac`, against the tree the patch was cut
from. The evidence for each row is a headless run; the harnesses are
`tools/emulator-setup/mame-osborne1ng/o1ng-probe.lua` and the repo's own
`tools/research/mame-boot-probe.sh`.

| Check | Result |
|---|---|
| boots the **1.44 ROM** and a bootable disk | **yes** — `BANNER: true`, `A>`, `RESULT: BOOTED` |
| banking and video **unchanged** from `osborne1` | **yes** — the boot probe's output on `OS1UTLS.IMD` is byte-identical to `osborne1`'s, `diff` clean, `416x240` (52 columns) |
| the mainboard's 2-bit decode survives | **yes** — `00h`–`03h` bank-switch; `05h` and `3Dh` alias `01h` |
| the card owns `30h`–`33h` | **yes** — writes there do not bank-switch |
| the presence probe | **yes** — `IN (32h)` → `04h`; after `OUT (32h),00h` → `00h` |
| the ID scan | **yes** — `PREP.COM` answers at select byte `01h` only |
| **`PREP.COM` runs unpatched** | **yes** — main menu and drive-table submenu both come up |
| `HARD.COM` reaches the controller | **yes** — it issues `TEST UNIT READY` (`CDB 00 …`) and gets a status phase back |

`MD10.COM`'s predecessor in this work was stepped over by
`tools/research/md10patch.py` precisely because the presence check could not
pass — *"Interface board or software not addressed properly"*. It now passes,
unpatched:

```
A>PREP
PREP version 2.01
Copyright (c) February 1984, NeuRahn, Inc.
Configured for standard interface at port 30H
READ YOUR MANUAL before attempting to use this program
Press the ESC key to exit any function
     Main function menu:
          (1) - Initialize, check, and partition disk drive
          (2) - Drive table display and edit
          (3) - Configure operating system
          ESC - Exit program
     Enter selection:
```

(`PREP.COM` is the 2.01 build of the same drive-table editor that the 1.93
utilities disk ships as `MD10.COM` — 2.01 renamed it. The 2.01 disk is the one
that is *bootable*; see `docs/acb4000-host-adapter.md` §3.)

## 5. What is not, yet

1. **The data phase has not been exercised end to end.** The card implements
   it (512-byte blocks, the READ/`INIR` path and the byte-at-a-time path), and
   `TEST UNIT READY` — which has no data phase — completes, but no `MODE SENSE`,
   `READ CAPACITY` or `READ` has been driven through it and had its bytes
   checked.
2. **`peek 0x055E` / `0x056E` is not reached.** Those are the DPH/DPB tables,
   and they are built by the MD-10 BIOS's `SELDSK` from the geometry the
   controller reports. Getting there needs two things this slice does not do:
   the MD-10 system installed (`HARD.COM`) and booted, and a **drive image
   mounted in the SCSI slot** — with nothing mounted, `SCSIHD` answers
   check-condition and `HARD.COM` sits at *"Waiting for drive to become ready"*.
   The slot's image option is
   `-scsi:1:harddisk:image` in MAME's device tree; the exact command-line
   spelling was not pinned down here, and the internal UI works.
3. **`2Dh` — "cable connected backwards" — is not modelled.** Both overlays test
   for it; it is a wiring condition, and it is recorded rather than invented.

## 6. Open questions this leaves

- **The `base+2` register's full bit map.** Bit 2 is the controller field and
  bits 0/1/5/6 are the card's handshake, which is what the two overlays and the
  BIOS use. Whether the other bits mean anything is unread.
- **`0x0557`/`0x0559` — the select byte's source.** `HARDBIOS.SPR`'s `BOOT`
  loads `0x0557` from `0x0559`, and `0x0559`–`0x055D` is the 5-byte block
  `docs/acb4000-host-adapter.md` §4 flags as unwritten by anything in the
  archive. `HARD.COM` keeps its own copy at `0x0A93`, and it is `01h`.
- **Whether the real MD-10 board decoded eight bits** — this machine assumes it
  did, because `docs/acb4000-host-adapter.md` §2 shows the driver needs it and
  §5 argues the board was a Z80-socket device. The hardware has not been seen.

## Sources

- `research/adaptec/MD Utilities … 1.93 Osborne - MD-10 MD-20.img` —
  `CNTLRCOD.OVL` (probe 0x8100, transaction 0x8051), `HARDBIOS.SPR`
  (transaction 0xE285, `BOOT` 0xE182), `MD10.COM`, `DRIVETBL.DAT`.
- `research/adaptec/Osborne Hard Disk Control Software Version 2.01 (1984).img`
  — `PREP.COM`, `HARD.COM`, `CNTLRCOD.OVL` (896-byte build).
- MAME 0.289 `src/mame/osborne/osborne1.cpp`, `src/devices/machine/legscsi.{h,cpp}`,
  `src/devices/bus/scsi/{scsi,scsihd,scsihle}.{h,cpp}`,
  `src/devices/machine/t10sbc.cpp`, `src/emu/addrmap.cpp` (entry precedence).
- `docs/acb4000-host-adapter.md` §1–§2 (the protocol and the blocker);
  `docs/acb4000-firmware.md`; `docs/harddisk-decision.md` §5–§6, §7.2–§7.3.
- `tools/emulator-setup/mame-osborne1ng/` — the patch, `apply.sh`, `o1ng-probe.lua`.
- `tools/research/{acb4000.lua,mame-boot-probe.sh,o1keys.sh,md10patch.py}`.

