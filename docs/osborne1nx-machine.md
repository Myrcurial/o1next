# `osborne1nx` — the emulated interposer, and the ACB-4000 host adapter (#191)

**Status: Partially solved.** The machine boots, the card answers, and a transfer
works; the DPB and drive tables are read out of `HARD.COM` rather than peeked
(`docs/md10-system.md` §9), and the MD-10's on-disk header is read out of
`PREP.COM` and reproduced on the emulated drive (§6). What is left is the
controller personality (#179), not the machine.

`osborne1nx` is a fourth `osborne1` machine in MAME whose Z80 sits behind a card
that decodes the full 8-bit I/O address, so the MD-10's host adapter can answer
on ports `30h`–`33h` — the ports its driver demands and the stock machine cannot
reach. The drive-table editor that #178 had to *patch around* now runs unpatched,
`HARD.COM` issues real commands against a mounted drive, and `PREP.COM`'s
initialize/format flow runs its whole bring-up — four bugs in the card's
handshake were found and fixed getting there (§3, §4).

**The DPB tables need no `peek`.** `0x055E`/`0x056E` are offsets from the MD-10
BIOS's base `0xD800`, so the tables are at `0xDD5E`/`0xDD6E` and are read straight
out of `HARD.COM` at file offsets `0x998`/`0x9A8` (`docs/md10-system.md` §9). What
stops `PREP.COM` putting a *system* on the drive is the verify pass, and §5 has
that reason.

Serves #191; answers #178's table question (`docs/md10-system.md` §9) and is the
emulated half of the personality (#179). Reads alongside
`docs/acb4000-host-adapter.md` (the protocol and the blocker),
`docs/acb4000-firmware.md` (the controller) and
`docs/harddisk-decision.md` §5 (the three layers).

**This machine is one half of the emulation testbed.** `docs/emulation-testbed.md`
owns the loop between it and the RP2354B firmware running in picoem, the gap
register for both emulators, and the plan for closing each gap; this document owns
the machine.

The patch, the apply script and the two probes live in
`tools/emulator-setup/mame-osborne1nx/`.

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

`osborne1nx`'s I/O map:

```cpp
void osborne1nx_state::osborne1nx_io(address_map &map)
{
	map.unmap_value_high();

	// The mainboard's own decode looks at A0-A1 only, so its four bank/video
	// ports alias across the whole low port page -- and the CBIOS drives them on
	// every console character, so that behaviour has to survive untouched.  Keep
	// the 2-bit alias and put the card's window on top of it: 30h-33h is the
	// one place where the card, not the mainboard, owns the bus.
	map.global_mask(0xff);
	map(0x00, 0x03).mirror(0xfc).w(FUNC(osborne1nx_state::bankswitch_w));
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

`tools/emulator-setup/mame-osborne1nx/o1next-probe.lua`, headless:

```
bank: rom=31 ram=00 alias05=00 alias3d=00 rom_again=31
  mainboard 2-bit decode preserved: yes
card window: 30h-33h left the bank alone: yes (00/00)
presence probe: IN 30h=00  IN 32h=04  -> one controller on-line
  register clears: IN 32h=00 -> yes
```

`rom=31` is the ROM's first byte with bank 2 selected, `ram=00` is RAM with bank
1 selected, and `05h` and `3Dh` both reach the bank switch through the alias.
Then a boot comparison, on the same disk, `osborne1` against `osborne1nx`:
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

Four details of that handshake are load-bearing, and every one of them came out
of a *measurement* rather than from the listing — each was a bug that made a
real program hang (§4 has the runs):

1. **The status phase asserts `20h` and `40h` but *not* `02h`.** The driver's
   data-out loop writes a byte for every REQ it sees (`CNTLRCOD.OVL` `0x808d`:
   `outi` then `bit 1,a / jr nz,808dh`), so a REQ left up while the status byte
   waits has it write for ever. `MODE SELECT` is the command that finds this: it
   is a data-out transfer, and `PREP.COM` stops dead at it.
2. **The status byte stays on the data register for two reads.** The routine
   reads it into `B` (`in b,(c)`) and then reads the register again to
   acknowledge (`0x80cc`). A *byte-at-a-time* data-in transfer reads it once
   more, because its loop takes a byte before it notices the phase has changed
   (`0x80b8`). Handing over one status byte and then a `00` makes the routine's
   final `and 002h` see a stale zero — the card silently loses its check
   condition.
3. **The CDB index resets when the command phase starts.** The driver
   re-selects and re-enters the routine for *every* command, so a CDB index left
   over from the previous command must not be carried into the next one. It
   cannot be seen with a single command: the first command works, and every
   command after it sends one byte and the card re-runs the *stale* CDB. That is
   what had `HARD.COM` sitting at *"Waiting for drive to become ready"* — it was
   issuing a `READ`, and the card kept answering a leftover `TEST UNIT READY`.
4. **A select byte is accepted whenever the card is not mid-command** — including
   while the previous command's status byte is still up. The overlay's ID scan
   selects the next candidate without ever acknowledging the previous status; if
   that select byte is dropped, the *previous* one stays in the register and
   every candidate looks on-line (the scan then reports
   `Addresses of on-line controllers: 0, 1, 2, 3, 4, 5, 6, 7`).

A transfer also ends at the target's length, not only at a 512-byte boundary:
the driver's READ moves 512 bytes per pass, but every other command moves one
byte at a time until the phase changes, so a short transfer (`MODE SENSE`'s 36
bytes, `READ CAPACITY`'s 8) has to end where the target said it would.

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
`tools/emulator-setup/mame-osborne1nx/o1next-probe.lua` (decode and card),
`tools/emulator-setup/mame-osborne1nx/o1next-dataphase.lua` (transfers) and the
repo's own `tools/research/mame-boot-probe.sh`.

| Check | Result |
|---|---|
| boots the **1.44 ROM** and a bootable disk | **yes** — `BANNER: true`, `A>`, `RESULT: BOOTED` |
| banking and video **unchanged** from `osborne1` | **yes** — the boot probe's output on `OS1UTLS.IMD` is byte-identical to `osborne1`'s, `diff` clean, `416x240` (52 columns) |
| the mainboard's 2-bit decode survives | **yes** — `00h`–`03h` bank-switch; `05h` and `3Dh` alias `01h` |
| the card owns `30h`–`33h` | **yes** — writes there do not bank-switch |
| the presence probe | **yes** — `IN (32h)` → `04h`; after `OUT (32h),00h` → `00h` |
| the ID scan | **yes** — `PREP.COM` answers at select byte `01h` only |
| **`PREP.COM` runs unpatched** | **yes** — main menu, drive-table submenu, and its whole initialize/format flow |
| `HARD.COM` reaches the controller | **yes** — it issues real commands (`TEST UNIT READY`, then `READ` LBA 5 for 11 blocks — the `CCP`+`BDOS` it boots) |
| the **data phase**, byte-at-a-time | **yes** — `INQUIRY` 36 B, `MODE SENSE` pages 4 and 3, `READ CAPACITY` 8 B; all status `00` |
| the **data phase**, 512-byte blocks | **yes** — `READ` of one block returns 512 bytes and the phase ends |
| the **data-out** phase | **yes** — `MODE SELECT` (22 B) and `SEND DIAGNOSTIC` (4 B) both complete |
| the DPH/DPB tables — `0xDD5E`/`0xDD6E`, read out of `HARD.COM` at file `0x998`/`0x9A8` | **read** — `docs/md10-system.md` §9; no `peek` needed |

### The data phase, driven at the register level

`o1next-dataphase.lua` is the check that made all four findings above: it drives
the card's four registers exactly as the driver's routine does, so a failure is
the card's and not the driver's. With a drive image mounted — the slot's option
is **`-hard`** (`-scsi:1:harddisk:image` is *not* a MAME option; the device tree
path in `-listxml` is `:scsi:1:harddisk:image`, but the command line uses the
instance's brief name):

```sh
chdman createhd -o /tmp/md10/hd.chd -c none -chs 321,4,18 -ss 512
O1NEXT_LOG=/tmp/o1next-dataphase.log mame osborne1nx \
  -rompath tools/emulator-setup/roms -hard /tmp/md10/hd.chd \
  -video none -sound none -nothrottle -seconds_to_run 6 \
  -autoboot_script tools/emulator-setup/mame-osborne1nx/o1next-dataphase.lua
```

`SDL_VIDEODRIVER=dummy` is what makes this headless, and it works because the
machine is built with the tree's default OSD (`sdl3` on macOS) — which needs
`pkg-config` so MAME can find SDL3 (`REQUIREMENTS.md`). `-video none` alone is
not enough: it picks the renderer, not the window, and MAME's default is full
screen (`docs/mame-emulation.md` §6).

`321/4/18` is `PYXIS13` — the drive-table entry `MD10.COM` offers a new drive
(`docs/harddisk-decision.md` §7.2), and the geometry the DPB is built from:

```
mounted geometry (O1NEXT_CHS): 321/4/18, 512-byte sectors
TEST UNIT READY (00)
  ok   6 CDB bytes sent -- sent 6
  ok   no data phase -- 0 bytes
  ok   status GOOD -- 00
INQUIRY (12)
  ok   36 bytes, phase ended -- 36 bytes
  ...
MODE SENSE (1A), page 4 -- geometry
  ok   page 4 returned, phase ended -- 24 00 00 08 00 00 5A 47 00 00 02 00 04 16 00 01 41 04 00 00
  ok   cylinders match the CHD -- 321 vs 321
  ok   heads match the CHD -- 4 vs 4
  ok   rotation rate 3600 -- 3600 rpm
MODE SENSE (1A), page 3 -- format parameters
  ok   sectors/track match the CHD -- 18 vs 18
  ok   512 bytes/sector -- 512 bytes
  ok   soft-sectored -- format 80
READ CAPACITY (25)
  ok   8 bytes, phase ended -- 8 bytes
  ok   last LBA = c*h*s - 1 -- 23112 vs 23112
  ok   block size 512 -- 512 bytes
READ (08), LBA 0, 1 block
  ok   512 bytes, phase ended -- 512 bytes
  ok   status GOOD -- 00
22 checks, 0 failed -- DATA PHASE OK
```

The `MODE SENSE` page-4 bytes are the whole point: `00 01 41` = 321 cylinders,
`04` = 4 heads — the card reporting the geometry of the drive behind it, which
is what the MD-10 BIOS's `SELDSK` turns into the DPB.

At the guest level the same thing shows up as `PREP.COM`'s option 1 running its
whole flow. The commands it issues, in order, are the bring-up the ACB-4000
manual's §4.4 describes:

| CDB | Command | Phase |
|---|---|---|
| `00` | `TEST UNIT READY` | status |
| `08 00 00 00 02 00` | `READ` LBA 0, 2 blocks | data in, 1024 B |
| `25` | `READ CAPACITY` | data in, 8 B |
| `04 1E D9 00 00 00` | `FORMAT` | status |
| `15 00 00 00 16 00` | `MODE SELECT`, 22 B | **data out** |
| `1D 00 00 00 04 00` | `SEND DIAGNOSTIC`, 4 B | **data out** |
| `2F 00 00 …` | `VERIFY` (the verify pass) | — |

and the screen reaches `Formatting disk (first pass)...` /
`Verifying disk (first pass)...` with the drive table's own geometry:

```
Enter drive address, 0 or 1 <0>: 0
Disk has unrecognizable format (or none)
Enter drive name (press RETURN to abort): PYXIS13
PYXIS13 (RO202): Rodime PLC model RO 202/Ampex model Pyxis 13
  Cyl=321, Head=4, Reduc=132, Lz=+0, Step=2, Cap=11556K
```


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

1. **`PREP.COM` cannot finish a format — but the card writes, and the store
   works.** A write through the card lands on the drive, and `PREP.COM`'s own
   writes are *not* MAME no-ops (its label write and its format fill both reach the
   CHD). What stops it is the *verify* pass that follows the format: it is
   `VERIFY` (`2F`), which `t10spc`/`t10sbc` have no
   constant for at all — so the target answers with a status phase and no data
   phase, the driver never sees the match it is looking for, and it loops.
   Measured: `PREP.COM` option 1 reaches *"Verifying disk (first pass)..."* and
   stays there for 600 emulated seconds, issuing 1 772 618 `2F` commands over LBA
   `0`–`0xFF` — walking that range and starting again. `MODE SELECT` and
   `SEND DIAGNOSTIC` do complete their data-out phases, and MAME's `SCSIHD`
   drops what `MODE SELECT` is given (`t10sbc.cpp` `case
   T10SPC_CMD_MODE_SELECT_6: break;`) — but the format fill is the *driver's*,
   not the controller's, so that loss does not stop a format either.

   So the formatted disk is built rather than formatted:
   `tools/research/mkdrive.py` writes the ACB-4000's own fill byte (`6C`) into
   every data field and gives `chdman` the geometry, which is the same blob the
   controller would have produced. `docs/harddisk-decision.md` §7.2 has it.
2. **The DPH/DPB tables are a file read, not a `peek`.** `0x055E`/`0x056E` are
   offsets from the MD-10 BIOS's base, so the tables are at `0xDD5E`/`0xDD6E` and
   are read straight out of `HARD.COM` at file offsets `0x998`/`0x9A8`
   (`docs/md10-system.md` §9). The one thing still needed is an MD-10 **system** on
   the drive, and that is a media question rather than a card one.

   `HARD.COM` is not an installer — it is a **hard-disk boot loader**: it reads
   LBA 5 for 11 blocks (5632 bytes = `0x1600`, exactly the `CCP`+`BDOS` of the
   O1 system layout, `docs/acb4000-host-adapter.md` §3) into `0xC200`, patches
   page zero to point at itself (`JP 0xD803`, the body's own jump table, which is
   its install entry) and jumps into the buffer. On a blank drive that code is
   all zeros, so the guest NOPs to the top of memory, wraps, and the patched warm
   boot vector runs the loader again — the `READ LBA 5 ×11` loop, seen 4 673 times
   in one run.

   It is also a **carrier**: its tail `0x053A`–`0x0AFF` is a relocated copy of the
   MD-10 BIOS, which it installs at `0xD800` and patches from the **running
   CBIOS** (`page zero+1` is `0E103H`), so the "boot loader" is a boot loader
   **and** the BIOS. `docs/md10-system.md` §4–§5 has the chain.

   So the drive has to already carry an MD-10 system, and `PREP.COM` option 1 does
   not write one: it formats, and every path that would put a system on the drive
   refuses a disk whose header is not one it recognises (`Disk has unrecognizable
   format (or none)` — the check is a `READ` of LBA 2 into `0x32CD`, §6). Option 3
   *does* write one, and what it writes boots to a prompt
   (`docs/md10-system.md` §1–§3). §6 below reads the header `PREP.COM` writes out
   of the program and confirms it on the emulated drive.
3. **`2Dh` — "cable connected backwards" — is not modelled.** Both overlays test
   for it; it is a wiring condition, and it is recorded rather than invented.

## 6. The MD-10's on-disk header, read out of `PREP.COM` (#191 → #178)

`PREP.COM` **does** write the header, and the structure it writes is read out of
the program and confirmed against the emulated drive. This is the handoff's step 1
for #191.

### What it writes, and where

`PREP.COM`'s Initialize ends in the routine at `0x1238`, whose message is
*"Initializing disk header..."*. It issues three writes back to back, in this
order. Addresses are memory addresses (`PREP.COM` loads at `0x0100`; the
overlay's CDB is the six bytes at `0x8013`):

| # | at | CDB (`0x8013`) | LBA | blocks | buffer | what |
|---|---|---|---|---|---|---|
| 1 | `0x125A` | `0A 00 00 01 01 00` | 1 | 1 | `0x38CE` | the block after the label |
| 2 | `0x126B` | `0A 00 00 02 02 00` | 2 | 2 | `0x32CD` | the 1 KiB partition block |
| 3 | `0x1282` | `0A 00 00 00 01 00` | 0 | 1 | `0x36CE` | **the disk label** |

So the header is four 512-byte blocks at **LBA 0–3**.

There are two checks in that path, and only one of them decides "recognisable".
`0x0FF4` — `READ` of LBA 2 into `0x32CD` — only has to *succeed*; its result is
never looked at. The check that prints *"Disk has unrecognizable format (or
none)"* is at `0x1B37`, and it is read out below.

The CDB is six bytes at the overlay's `0x8013`: **opcode, byte 1, byte 2, LBA
low, block count, control**. `0x8016` is the LBA's low byte and `0x8017` the
block count, which is why the three writes are `LD HL,0101h` / `0202h` / `0100h`
straight into `0x8016` (`0x125D`, `0x126E`, `0x1285`). The commands this driver
uses are `READ` `08`, `WRITE` `0A`, `FORMAT` `04`, `MODE SELECT` `15` and
`WRITE EXTENDED` `2A` — and for `FORMAT` the same two bytes are reused:
byte 1 (`0x8014`) gets `1Eh` OR'd in (the "unique fill byte" flag) and byte 2
(`0x8015`) is the fill (`6Ch` at `0x167C`, `D9h` at `0x15C6`), while byte 4 is
the interleave the operator was asked for (`0x1676`).

### The label, field by field

The label is built at `0x36CE` (512 bytes; `0x1200`–`0x1238`) and its tail is a
partition table:

| offset | set at | what |
|---|---|---|
| `+0` | `0x120D` | `M`,`D` — the signature |
| `+6` | `0x1213` | zero |
| `+14` | `0x1468` | the label text, up to 11 characters, NUL-padded |
| `+25` | `0x121A` | zero |
| `+26` | `0x1063`, `0x168D` | a word the format uses (`× 8` → the FORMAT CDB's block address) |
| `+27` | `0x1599`, `0x1676` | the interleave, straight into the FORMAT CDB's byte 4 |
| `+28` | `0x1221` | zero |
| `+29`–`+38` | `0x1227` | ten bytes copied from `0x4332` |
| `+39` | `0x122F` | zero |
| `+40`–`+47` | `0x1231` | eight zero bytes |
| `+48` | `0x121E` | `FFh` — the end marker of the partition table |
| `+48`… | | N × **28-byte partition records**, walked by `0x23E6` (`ADD IX,1Ch`, stopping on a record whose first byte is `FFh`) |

The 28-byte record is also the program's scratch unit: `0x4332` is one record and
`0x434E` the next (`0x4332 + 0x1C`), and the password buffer *is* that second
record borrowed (`0x14E1`). The label text and that scratch record share a
11-byte field — `0x0C53` block-copies eleven bytes from `0x4332` to `0x433D`.

The block written to LBA 1 (`0x38CE`) is the 512 bytes that follow the label in
the same 1 KiB work area; the only other reference to it is the write itself, and
the tail `0x3A47`–`0x3ACD` is zeroed by the same routine (`0x1200`). Its fields
are not read anywhere in the archive, so nothing is claimed for them here.

### What "recognisable" actually means

`0x1B37`, read out and then measured against three drives:

```
1b37  ld hl,03ACEh / ld a,025h / call 08028h   ; READ CAPACITY
1b3f  jr nz,l1BA7h                             ; no answer -> unrecognizable
1b41  ld hl,(03AD4h) / ld bc,0002h / sbc hl,bc
1b49  jr nz,l1BA7h                             ; block size != 512 -> unrecognizable
1b4b  ld a,002h / ld (08017h),a                ; 2 blocks ...
1b50  ld hl,036CEh / ld a,008h / call 08030h   ; ... READ of LBA 0 into the label
1b58  jr nz,l1BA7h                             ; no answer -> unrecognizable
1b5a  ld hl,(036CEh) / ld bc,0444Dh / sbc hl,bc
1b62  jr nz,l1BA7h                             ; label[0:2] != "MD" -> unrecognizable
1b64  ld a,(036EAh) / cp 020h / ret c          ; label[+28] < 20h -> OK
```

`(03AD4h)` is the low half of the 4-byte big-endian block size the controller
returns, so `block size / 256 == 2` is just "512-byte blocks". `0444Dh` is `M`,`D`
little-endian.

Measured, by building drives and asking the **unpatched** `PREP.COM`:

| drive | LBA 0 | LBA 2–3 | verdict |
|---|---|---|---|
| PREP's own header | the label | zeros | **recognisable** |
| LBA 0 = PREP's label, everything else the `6C` fill | the label | `6C` | **recognisable** |
| LBA 0 = `6C` fill, LBA 2–3 = zeros | `6C` | zeros | *unrecognizable* |

So **LBA 0 is the only sector that matters**, and what matters in it is `M`,`D` at
`+0` (with `+28 < 20h`). `tools/research/mkdrive.py --label TEXT` writes exactly
that — which is what turns a built drive into one `PREP.COM` will initialise
rather than reject, and it is the precondition the handoff's step 2 was waiting
on.

### Confirmed on the drive, not only in the listing

The card's **select byte is a run-time variable**, and that is the trap. The
overlay reads `0x8023` before every transaction (`0x8042`) and the program sets
it in the controller/drive-address path (`0x1A85`). Patch past that path and it
stays `00h`, which is not a one-of-eight ID mask: **every transaction is accepted
by the card and delivered to no target.** The program runs on, reports no error,
and the drive is untouched — which is how a write test can conclude that
`PREP.COM`'s writes are no-ops.

With it set (`poke 0x8023 01` — now a directive in `tools/research/o1keys.lua`)
and `PREP.COM` patched at `0x0FE4` to enter the *Disk initialization* menu
directly, the menu's **Change disk label** writes 512 bytes to LBA 0 and the
label comes straight back out of the CHD:

```
0000  00 00 00 00 00 00 00 00 00 00 00 00 00 00 54 45   ..............TE
0010  53 54 4c 41 42 45 4c 00 00 00 00 00 00 00 00 00   STLABEL.........
```

— the text at `+14`, NUL-padded, exactly as the listing says.

That test used the *menu* landing point, which writes LBA 0 alone. The label
build at `0x1200` writes all four blocks, and its output is in *What that leaves*
below.

The **format is not a no-op either.** The menu's format-only option runs the
whole flow — password (`It's OK to destroy all data`, compared at `0x1528`),
interleave, `FORMAT`, then *"Initializing all partitions..."* — and writes `E5h`
(CP/M's empty record) over LBA `0`–`3369` before stopping with a `WRITE
EXTENDED` (`2Ah`) outstanding. Reproduced twice on fresh drives, so it is the
program's own doing and not the controller's.

### The recipe, so it reproduces

```sh
# 1. build the patched disk.  One 8-byte patch over PREP.COM's main-menu option 1
#    handler and the echo string behind it: CALL sub_19a8h (the probe, the drive
#    address prompt, and the card's select byte) then JP 1200h -- the label build
#    and the header write, with the format/verify in front of it skipped.
tools/research/o1prep-patch.sh /tmp/o1prep

# 2. a drive to write on
CHDMAN=/path/to/chdman tools/research/mkdrive.py --out /tmp/o1prep/hd.chd

# 3. run it: main-menu 1 runs the probe, asks the drive address, then writes the
#    header and stops at the Disk initialization menu.  The pokes are the CDB's
#    LBA high half, which nothing has set by then.
printf 'wait A>\ntype PREP\nwait Main function\npoke 0x8014 00\npoke 0x8015 00\nkey 1\nsleep 1\nkey cr\nsleep 8\ndump header\n' > /tmp/o1prep/keys.txt
cd /tmp && O1_MACHINE=osborne1nx O1_FLOP1=/tmp/o1prep/prep.imd \
  O1_KEYS="$(cat /tmp/o1prep/keys.txt)" SDL_VIDEODRIVER=dummy \
  /path/to/osborne1nx osborne1nx -flop1 /tmp/o1prep/prep.imd -hard /tmp/o1prep/hd.chd \
  -video none -sound none -nothrottle \
  -autoboot_script /path/to/o1next/tools/research/o1keys.lua \
  -seconds_to_run 90 -rompath /path/to/o1next/tools/emulator-setup/roms

# 4. read the header back: LBA 0 is the label ('M','D' at +0, FFh at +48)
chdman extracthd -i /tmp/o1prep/hd.chd -o /tmp/o1prep/hd.raw -f
xxd -l 64 /tmp/o1prep/hd.raw
```

The screen at step 3 reads *"Initializing disk header... Disk initialization
complete"* and then the Disk initialization menu. Two traps in getting there:

1. **Landing on the menu is not enough.**
   The menu path never builds the label, so the partition table at `0x36FE` is
   left uninitialised — not the `FFh` terminator the walker at `0x23E6` stops on
   — and *"Initializing all partitions..."* walks off the end of memory for ever,
   writing `E5h` with a block count derived from garbage (measured: `E5h` over
   LBA `0`–`3369`, twice, on fresh drives). It looks exactly like a card or
   emulator failure and is neither: it is the harness skipping an initialiser.
2. **Do not read guest memory from a `frame_done` callback.** A sampler that
   polled `0x8013`/`0x8314` every 30 frames segfaulted MAME's Lua layer within
   seconds, twice. `o1keys.lua`'s `peek` directive is fine — it reads *between*
   directives, when the guest is idle — but a per-frame read is not.

`o1prep-patch.sh` also writes `/tmp/o1prep/prep.recipe.txt` with the same steps,
and prints the bytes it changed — the patched image is a 100 KiB derivative that
regenerates in under a second, so it is not committed (`research/` is for primary
sources).

The path to `osborne1nx` is the built binary, not `mame osborne1nx` (the machine
is not in a stock MAME's driver list). `-nothrottle` keeps the run to seconds, and
`SDL_VIDEODRIVER=dummy` is what makes it headless — `docs/mame-emulation.md` §6.
The format path adds `key 1` after the poke and then the password
`It's OK to destroy all data` followed by a bare RETURN for the interleave.

### What that leaves

**The header is now *written*, not just read.** `PREP.COM` runs its own label build
and header write to completion on the emulated card — *"Initializing disk header…
Disk initialization complete"* — and the drive comes out carrying it:

```
LBA 0  4d 44 00 00 00 00 00 6c 6c 6c 6c 6c 6c 6c 00 6c   MD.....lllllll.l
       ...                                          ff   ...  FFh at +30h
LBA 1  6c 6c ...                                          the 6Ch fill
LBA 2  00 00 ...  LBA 3  00 00 ...                        zeros
```

and a drive carrying that header is accepted by the **unpatched** `PREP.COM` —
which is the precondition the handoff's step 2 was waiting on.
`mkdrive.py --label TEXT` builds one.

Note what the label's bytes *are*: `M`,`D`, the fields the build sets, and
elsewhere the `6C` fill and zeros that happened to be in RAM. **`PREP.COM` does
not zero the label before building it**, so its own labels differ run to run —
which is the other reason the check can only be looking at `M`,`D` and a
threshold, and not at a checksum or a magic block.

The DPH/DPB tables are not a `peek` question. `0x055E`/`0x056E` are offsets from
the MD-10 BIOS's base, so the tables are at `0xDD5E`/`0xDD6E` and are read straight
out of `HARD.COM` at file offsets `0x998`/`0x9A8` (`docs/md10-system.md` §9). A
*system* on the drive is a separate matter, and `PREP.COM` option 3 produces one
(`docs/md10-system.md` §1–§3). The two things that stop `PREP.COM` putting one
there belong to `#179`:

- the verify pass (`2F`) has no handler, so "Format and verify" cannot finish; and
- the partition initialiser (`2Ah`, `WRITE EXTENDED`, `E5h` as its fill) needs the
  label built first — now understood, and it is what the patch does.

So the card and the disk header are both done. The controller personality is the
next thing, and it is a firmware deliverable rather than more archaeology.

## 7. Open questions this leaves

- **The `base+2` register's full bit map.** Bit 2 is the controller field and
  bits 0/1/5/6 are the card's handshake, which is what the two overlays and the
  BIOS use. Whether the other bits mean anything is unread.
- **The select byte's source at run time.** `HARDBIOS.SPR`'s `BOOT` loads `0x0557`
  from `0x0559`, and that five-byte block is the MD-10 BIOS's own data at
  base+`0x559` = `0xDD59` — inside `HARD.COM` at file offset `0x0993`, holding
  select `01`, LBA `5`, count `11` (`docs/md10-system.md` §4–§6). The *run-time*
  select byte is a different cell: `HARD.COM` keeps its own copy at `0x0A93`, and
  it is `01h`. Which one a given boot path reads is unread.
- **Whether the real MD-10 board decoded eight bits** — this machine assumes it
  did, because `docs/acb4000-host-adapter.md` §2 shows the driver needs it and
  §5 argues the board was a Z80-socket device. The hardware has not been seen.

## Sources

- `research/adaptec/MD Utilities Adaptec 4000 Controller Ver. 1.93 Osborne - MD-10 MD-20.img` —
  `CNTLRCOD.OVL` (probe 0x8100, transaction 0x8051), `HARDBIOS.SPR`
  (transaction 0xE285, `BOOT` 0xE182), `MD10.COM`, `DRIVETBL.DAT`.
- `research/adaptec/Osborne Hard Disk Control Software Version 2.01 (1984).img`
  — `PREP.COM`, `HARD.COM` (its routine 0x0221, its relocated body 0x053A →
  0xD800), `CNTLRCOD.OVL` (the 896-byte build, routine 0x8030).
- `research/adaptec/acb4000/400003-00A_ACB-4000A_Users_Manual_Oct85.ocr.txt` §4.4
  — the bring-up order `PREP.COM` follows (REZERO, TEST UNIT READY, MODE SELECT,
  FORMAT, READ CAPACITY) and "the FORMAT command writes the drive parameters in
  the ID fields".
- MAME 0.289 `src/mame/osborne/osborne1.cpp`, `src/devices/machine/legscsi.{h,cpp}`,
  `src/devices/bus/scsi/{scsi,scsihd,scsihle}.{h,cpp}`,
  `src/devices/machine/t10sbc.cpp`, `src/emu/addrmap.cpp` (entry precedence).
- `docs/acb4000-host-adapter.md` §1–§2 (the protocol and the blocker);
  `docs/acb4000-firmware.md`; `docs/harddisk-decision.md` §5–§6, §7.2–§7.3.
- `tools/emulator-setup/mame-osborne1nx/` — the patch, `apply.sh`,
  `o1next-probe.lua`, `o1next-dataphase.lua`.
- `tools/research/{acb4000.lua,mame-boot-probe.sh,o1keys.sh,md10patch.py}`.

