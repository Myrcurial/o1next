# `osborne1ng` — the emulated interposer, and the ACB-4000 host adapter (#191)

**Status: the machine boots, the card answers, and a transfer works.**
`osborne1ng` is a fourth `osborne1` machine in MAME whose Z80 sits behind a card
that decodes the full 8-bit I/O address, so the MD-10's host adapter can answer
on ports `30h`–`33h` — the ports its driver demands and the stock machine cannot
reach. The drive-table editor that #178 had to *patch around* now runs unpatched,
`HARD.COM` issues real commands against a mounted drive, and `PREP.COM`'s
initialize/format flow runs its whole bring-up — four bugs in the card's
handshake were found and fixed getting there (§3, §4). What is left is the
low-RAM DPB tables, and §5 has the reason it is not a card problem.

Serves #191; unblocks #178's `peek` and is the emulated half of the personality
(#179). Reads alongside `docs/acb4000-host-adapter.md` (the protocol and the
blocker), `docs/acb4000-firmware.md` (the controller) and
`docs/harddisk-decision.md` §5 (the three layers).

The patch, the apply script and the two probes live in
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
`tools/emulator-setup/mame-osborne1ng/o1ng-probe.lua` (decode and card),
`tools/emulator-setup/mame-osborne1ng/o1ng-dataphase.lua` (transfers) and the
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
| `peek 0x055E` / `0x056E` (the DPH/DPB tables) | **not yet** — §5 |

### The data phase, driven at the register level

`o1ng-dataphase.lua` is the check that made all four findings above: it drives
the card's four registers exactly as the driver's routine does, so a failure is
the card's and not the driver's. With a drive image mounted — the slot's option
is **`-hard`** (`-scsi:1:harddisk:image` is *not* a MAME option; the device tree
path in `-listxml` is `:scsi:1:harddisk:image`, but the command line uses the
instance's brief name):

```sh
chdman createhd -o /tmp/md10/hd.chd -c none -chs 321,4,18 -ss 512
O1NG_LOG=/tmp/o1ng-dataphase.log mame osborne1ng \
  -rompath tools/emulator-setup/roms -hard /tmp/md10/hd.chd \
  -video none -sound none -nothrottle -seconds_to_run 6 \
  -autoboot_script tools/emulator-setup/mame-osborne1ng/o1ng-dataphase.lua
```

`SDL_VIDEODRIVER=dummy` is what makes this headless, and it works because the
machine is built with the tree's default OSD (`sdl3` on macOS) — which needs
`pkg-config` so MAME can find SDL3 (`REQUIREMENTS.md`). `-video none` alone is
not enough: it picks the renderer, not the window, and MAME's default is full
screen (`docs/mame-emulation.md` §6).

`321/4/18` is `PYXIS13` — the drive-table entry `MD10.COM` offers a new drive
(`docs/harddisk-decision.md` §7.2), and the geometry the DPB is built from:

```
mounted geometry (O1NG_CHS): 321/4/18, 512-byte sectors
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
| `2F 00 00 …` | `SEARCH DATA EQUAL` (the verify pass) | — |

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

1. **Nothing writes through the card, so `PREP.COM` cannot finish a format.**
   `MODE SELECT` and `SEND DIAGNOSTIC` complete their data-out phases, but MAME's
   `SCSIHD` drops what it is given (`t10sbc.cpp` `case
   T10SPC_CMD_MODE_SELECT_6: break;`) and its `FORMAT UNIT` is a status-only
   no-op. The verify pass that follows is `SEARCH DATA EQUAL` (`2F`), which
   `t10spc`/`t10sbc` have no constant for at all — so the card answers with a
   status phase and no data phase, the driver never sees the match it is looking
   for, and it loops. Measured: `PREP.COM` option 1 reaches *"Verifying disk
   (first pass)..."* and stays there for 600 emulated seconds, issuing 1 772 618
   `2F` commands over LBA `0`–`0xFF` — walking that range and starting again.
   The card's part of a write is exercised; the *store* is MAME's gap, not the
   card's.

   So the formatted disk is built rather than formatted:
   `tools/research/mkdrive.py` writes the ACB-4000's own fill byte (`6C`) into
   every data field and gives `chdman` the geometry, which is the same blob the
   controller would have produced. `docs/harddisk-decision.md` §7.2 has it.
2. **`peek 0x055E` / `0x056E` is not reached, and the reason is now measured.**
   `HARD.COM` is not an installer — it is a **hard-disk boot loader**: it reads
   LBA 5 for 11 blocks (5632 bytes = `0x1600`, exactly the `CCP`+`BDOS` of the
   O1 system layout, `docs/acb4000-host-adapter.md` §3) into `0xC200`, patches
   page zero to point at itself (`JP 0xD803`, the body's own jump table, which is
   its install entry) and jumps into the buffer. On a blank drive that code is
   all zeros, so the guest NOPs to the top of memory, wraps, and the patched warm
   vector runs the loader again — the `READ LBA 5 ×11` loop, seen 4 673 times in
   one run. So the drive has to already carry an MD-10 system, and nothing in the
   archive writes one: `PREP.COM` option 1 formats (all of its writes are MAME
   no-ops) and option 3, *Configure operating system*, refuses a drive whose first
   two sectors are not a format it recognises (`Disk has unrecognizable format
   (or none)`). This is a *media* question — what the system tracks of an MD-10
   disk contain — not a card question.
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
- `tools/emulator-setup/mame-osborne1ng/` — the patch, `apply.sh`,
  `o1ng-probe.lua`, `o1ng-dataphase.lua`.
- `tools/research/{acb4000.lua,mame-boot-probe.sh,o1keys.sh,md10patch.py}`.

