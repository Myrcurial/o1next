# `osborne1nx` — the emulated interposer, as a MAME machine (#191)

A **fourth `osborne1` machine in MAME** whose Z80 sits behind a card that decodes
the full 8-bit I/O address, so the MD-10's ACB-4000 host adapter can answer on
ports `30h`–`33h`. The stock `osborne1` cannot reach them: its `io_map` is
`map(0x00, 0x03).w(bankswitch_w)` with `global_mask(0x03)`, so `OUT (30h)` is
erased to offset `0` before any handler sees it. That measurement is
`docs/acb4000-host-adapter.md` §2; this machine is the answer to it.

The machine and the device are written as a real MAME machine and a real MAME
device, so the patch is shaped to be sent upstream — and so that the same
device, on hardware, is the RP2350 firmware's personality (#179, #192).

## What is in here

| File | What it is |
|---|---|
| `osborne1nx.patch` | the change, as a `git apply` / `patch -p1` diff against MAME 0.289 |
| `apply.sh` | apply it to a source tree, optionally build the subtarget, optionally run the probe |
| `o1next-probe.lua` | the headless check: the I/O decode, and the card's presence probe |
| `o1next-dataphase.lua` | the headless check of a *transfer* — the card driven at the register level |
| `o1next-softrom.lua` | the headless check of the **ROM window** — all 8 KB read back and compared (#247) |
| `softrom-check.sh` | **the two-way acceptance** of that window — the window three ways, and the boot against `osborne1` (#247) |
| `rom2boot.lua` | the headless check of **ROM 2.0's `HCBOOT`** — the chain read back stage by stage (#247) |
| `rom2-check.sh` | **the chain's acceptance** — ROM 2.0's image in the window, ESC, and what the monitor then does (#247) |
| `rom2trace.lua` | **where the boot goes after the chain** — the PC sampled finely, the stack unwound, and the two cells the hand-over turns on (#247) |
| `rom2bank.lua` | the same question from the other side — **taps**: the IOBYTE read, and the bank selects, on this machine and on a stock boot (#247) |
| `rom2handover.lua` | **the fix, proved before it is built** — poke `CCPADR` and the machine reaches `A0>` (#247) |
| `boot-o1next.sh` | **the windowed one** — boot it and use it, with up to two floppy images and an optional hard disk (#247) |
| `stage.sh` | **stage a self-contained test machine** outside the repo — binary + ROMs + launcher in one directory (#247) |

The patch touches six files:

- `src/mame/osborne/osborne1.cpp` — the `osborne1nx` machine, its I/O map and its ROM window
- `src/mame/mame.lst` — registers the machine (MAME builds its driver list from this)
- `scripts/src/machine.lua` — registers the new devices' sources
- `src/devices/machine/acb4000_host_adapter.{h,cpp}` — the card, new
- `src/devices/machine/softrom.{h,cpp}` — the ROM window, new

## Applying it

```sh
tools/emulator-setup/mame-osborne1nx/apply.sh /path/to/mame --build --probe
```

`/path/to/mame` must be a **source** tree (a checkout, or an unpacked release
tarball) — the patch adds a device and a machine, so it has to be rebuilt.
Nothing new has to be installed: GNU make and a C++20 compiler are all it wants,
and on macOS `apply.sh` passes `OSD=mac` because a source build otherwise wants
SDL3 (see `REQUIREMENTS.md`).

Then run it:

```sh
mame osborne1nx -rompath tools/emulator-setup/roms \
    -flop1 research/shipped-software/OS1UTLS.IMD
```

**`-softrom` mounts a ROM image over the machine's own** — the interposer's
softROM, serving the 8 KB window `0000-1FFF` (#247). With none mounted the
window is the machine's stock 1.44, so an image-less `osborne1nx` *is* an
`osborne1`; with `tools/research/rom2image.py`'s 7681-byte image mounted it boots
identically too, because that image's monitor is still the stock 1.44. See "The
softROM window" below, and `softrom-check.sh` for the acceptance.

```sh
tools/research/rom2image.py -o /tmp/rom2.rom
mame osborne1nx -rompath tools/emulator-setup/roms -softrom /tmp/rom2.rom
```

**That is the headless shape and `mame` on `PATH` has no such machine** — it is a
patch, so the binary is the one `apply.sh` built. To actually *use* the machine
rather than test it, run `./boot-o1next.sh` instead: same machine, video and sound
on, real time, up to two floppy images on the command line and a hard disk through
`O1_HARD`. See `boot-o1next.sh`'s header, and AGENTS.md.

**Headless means an SDL build.** `-video none` picks the *renderer*, not the
window: the window belongs to the OSD, and MAME's default is full screen
(`-window`: *"otherwise, full screen mode is assumed"*). `SDL_VIDEODRIVER=dummy`
is what makes a run headless, and it only works for an SDL build — so the build
must be the tree's default OSD (`sdl3` on macOS), which needs **`pkg-config`**
for MAME to find SDL3 (`REQUIREMENTS.md`). Without pkg-config the build falls
back to the mac OSD, which has no such switch and takes the whole display until
it exits; `apply.sh` says so when it falls back, and `-window` is the only thing
that keeps it off the display (`-numscreens 0` is rejected). Full note in
`docs/mame-emulation.md` §6.

`osborne1nx` runs the **1.44 ROM only** (`3a10082-00rev-e.ud11`, with the
`7a3007-00.ud15` character generator). It does not carry the `osborne1` family's
other BIOS slots, on purpose: the MD-10's software is what it exists to run.

## What is validated, and what is not

Measured on MAME 0.289, macOS, `OSD=mac`:

| Check | Result |
|---|---|
| boots the 1.44 ROM and a bootable disk | **yes** — `BANNER: true`, `A>`, identical screen text to `osborne1` |
| banking and video unchanged from `osborne1` | **yes** — the boot probe's output is byte-identical (`diff` clean, modulo the machine name) |
| the mainboard's 2-bit decode survives | **yes** — `00h`–`03h` still bank-switch, and `05h`/`3Dh` still alias `01h` |
| the card owns `30h`–`33h` | **yes** — writes there do not bank-switch |
| the MD-10 presence probe | **yes** — `IN (32h)` reads `04h`; after `OUT (32h),00h` it reads `00h` |
| the ID scan | **yes** — `PREP.COM` finds the controller at select byte `01h` only |
| **`PREP.COM` (the MD-10 drive-table editor) runs unpatched** | **yes** — its main menu, the drive-table submenu, *and* its whole initialize/format flow |
| `HARD.COM` reaches the controller | **yes** — real commands (`TEST UNIT READY`, then `READ` LBA 5 ×11 — the `CCP`+`BDOS` it boots) |
| the **data phase** (`INQUIRY`, `MODE SENSE`, `READ CAPACITY`, `READ`) | **yes** — 22/22 checks, `o1next-dataphase.lua` |
| the **data-out** phase (`MODE SELECT`, `SEND DIAGNOSTIC`) | **yes** — both complete |
| the **softROM window** — all 8 KB of `0000-1FFF`, three ways | **yes** — `o1next-softrom.lua`, all 8192 bytes, in `softrom-check.sh` |
| **no image mounted ⇒ boots as `osborne1`** | **yes** — the boot probe's screen dump is byte-identical (`diff` clean, modulo the machine name) |
| **`-softrom` (the 7681-byte image) ⇒ boots as `osborne1`** | **yes** — byte-identical too, page 1 reading the payload |
| **ROM 2.0's `HCBOOT`** — the CBIOS, the MD-10 BIOS, its patch, the bank, the read | **yes** — `rom2boot.lua`, five checks, in `rom2-check.sh` |
| ROM 2.0 booting the hard disk to `A0>` | **not yet** — one store short, and the store is measured and the fix proved (`rom2trace.lua`, `rom2bank.lua`, `rom2handover.lua`); see below |
| the **hard-disk boot** (`HARD.COM` → `A0>`/`B0>`/`C0>`) | **yes** — re-measured after the window change, unchanged |
| `peek 0x055E` / `0x056E` (the DPH/DPB tables) | **not yet** — the drive needs an MD-10 system on it; see below |

### The softROM window

`-softrom` mounts an image over the machine's ROM window, which the interposer
serves itself (docs/o1-rom-2.0.md §4.1b). The window is **8 KB — `0000-1FFF`** —
because the mainboard never decoded `A12`: the stock machine reads its 4 KB
monitor twice across it, and MAME's own map says so in one line
(`.mirror(0x1000)` *is* the undecoded `A12`). The softROM decodes it, so:

| Image | The window |
|---|---|
| none | the machine's own ROM region, mirrored — a stock machine |
| 4 KB or less | the image, mirrored — the image *is* the stock part |
| larger | two pages: `0000-0FFF` and `1000-1FFF`; past the image's end, `0xFF` (erased flash) |

`tools/research/rom2image.py`'s image is **7681 bytes** — the stock monitor plus
the 3585-byte payload — so the 511 bytes it does not cover are the payload's
spare, and they read `0xFF`.

**Why the boot alone is not the acceptance.** The stock monitor never reads page
1, so a softROM that failed to take over that page would boot identically and
silently — an override that only reached `0000-0FFF` looks exactly like a working
one. `o1next-softrom.lua` therefore reads the window back and compares all 8192
bytes against what the device says it should be; `softrom-check.sh` runs that
three ways and the boot comparison three ways, and is one command:

```sh
tools/emulator-setup/mame-osborne1nx/softrom-check.sh
```

Measured on 2026-10-14: `PASS` on all five, with the 7681-byte image reading
`C3 ED E4 …` at `1000h` (the CBIOS's first bytes) against `31 C1 EF …` at `0000h`
(the monitor's), and `FF` from `1E01h` to `1FFFh`.

### ROM 2.0's monitor, and `HCBOOT`

`tools/research/rom2asm.sh` assembles ROM 2.0's monitor — the vendor's 1.44 with
the new code in the free tail of it — with the vendor's own ACT80, and
`rom2-check.sh` measures what the new code *does*: with the image in the window and
no floppy, **ESC** at the sign-on prompt is the monitor's `HCBOOT` entry, and the
harness reads the chain back stage by stage:

```
  PASS  the CBIOS is at 0E100h, and it is the window's 1000h
  PASS  the MD-10 BIOS's own jump table is at 0D800h
  PASS  it is patched from the CBIOS's vectors (5 LDIRs, 90 bytes)
  PASS  the bank switched to RAM at some point after ESC
  PASS  the system was read off the drive into 0C200h     (with O1_HARD)
```

The chain is what the ROM is responsible for, and it is complete. The machine does
**not** then reach `A0>`, and the reason is measured — it is one cell, `CCPADR`
(`0EFD2h`), which the ROM's own `CBOOT` writes and `HCBOOT` was lifted without
(`docs/o1-rom-2.0.md` §4.6, §8 item 10):

- The ROM's 60 Hz interrupt handler ends by returning *through the CBIOS* —
  `ROMJP1` = `CCPADR + 1633h`, the CBIOS's `RRI`, whose `OUT (C),A` restores the
  bank.
- With `CCPADR = 0` that exit jumps to `1633h`, which in bank 2 is the softROM's
  page 1 — the payload's own copy of the CBIOS's console dispatch. It reads
  `IOBYTE` at page zero+3, and in ROM mode page zero *is* the ROM: `D3h`, the
  opcode of the `OUT (03h),A` at `0004h`, whose low two bits are **3, the IEEE
  device**.
- The dispatch trampolines into the ROM's IEEE input routine and waits for a
  handshake no device answers, for ever.

`rom2trace.lua` samples the PC and unwinds the stack to show where the machine
went; `rom2bank.lua` taps the IOBYTE read and the bank selects to show why. The
contrast is the finding:

| | stock boot | ROM 2.0's hand-over |
|---|---|---|
| reads of `0003h` | 858, **all `80h`** (RAM → CRTOUT) | **1, returning `D3h`** (the ROM → IEEE) |
| bank selects | 454 `OUT 0`, 492 `OUT 1` | 1 `OUT 1` (HCBOOT), 1 `OUT 0` (the trampoline) |
| `CCPADR` → the handler's exit | **`CB00h` → `E133h`**, the CBIOS's `RRI` | **`0000h` → `1633h`**, the payload |

**The fix is that one store, and it is proved before it is built.** Poke
`CCPADR = CB00h` (and the CBIOS's own IOBYTE, `80h`, at page zero+3) into RAM just
after the hand-over and the machine boots to `A0>` **with no floppy in the
machine**. What is left is where that code lives — it must run after the bank
switch, so from RAM.

**A stale `/tmp/rom2.rom` looks exactly like `HCBOOT` not working.** The image is
two steps (`rom2asm.sh`, then `rom2image.py`); reuse an older `/tmp/rom2.rom` and
the window serves the *stock* monitor, whose `0F67h` is still `JMP START` — so ESC
does nothing and the machine sits at the sign-on prompt for ever. `rom2-check.sh`
builds the image itself, so it cannot hit this; a hand-run trace can. Check the
image before believing a negative: `0F67h` must be `21 00 10` (`LD HL,1000h`), not
`C3 00 00`.


**ESC needs the key code, not the character.** The Osborne's ESC key is
`PORT_CHAR(UCHAR_MAMEKEY(ESC))`, so `natkeyboard:post("\27")` matches no port and
presses nothing — silently. Both harnesses here find the code in the
natkeyboard's own table (`natkeyboard:dump()`: `0010003B (Escape)`), and
`tools/research/o1keys.lua`'s `key esc` had the same bug until #247.

### Driving a transfer

The data phase needs a drive image mounted, and the slot's option is **`-hard`**
(not `-scsi:1:harddisk:image` — `-listxml` gives the device tree path
`:scsi:1:harddisk:image`, but the command line wants the instance's brief name):

```sh
tools/research/mkdrive.py --out /tmp/md10/hd.chd                # PYXIS13, 321/4/18
O1NEXT_LOG=/tmp/o1next-dataphase.log SDL_VIDEODRIVER=dummy mame osborne1nx \
  -rompath tools/emulator-setup/roms -hard /tmp/md10/hd.chd \
  -video none -sound none -nothrottle -seconds_to_run 6 \
  -autoboot_script tools/emulator-setup/mame-osborne1nx/o1next-dataphase.lua
```

`mkdrive.py` is how the drive gets there: it writes a **blank but formatted**
ST-506/MFM image — the ACB-4000's own fill byte (`6C`) in every data field,
which is what the controller's `FORMAT` writes — for any geometry, without the
1984 tools (MAME's `SCSIHD` cannot finish a format; see "What is left" below).
`--chs 306,4,17` gives an `ST412`, and the period list of drive geometries is
archived at `research/adaptec/compatible-drives-1991-usenet.txt`.

### The handshake details that cost the time

Four of them, all read out of the driver and all of them a hang until they were
right (`docs/osborne1nx-machine.md` §3):

1. **The status phase asserts PHASE and END but not REQ** — the driver's data-out
   loop writes a byte per REQ, so a REQ left up while the status waits writes for
   ever. `MODE SELECT` is where it bites.
2. **The status byte survives two reads** — the routine reads it into `B` and
   then reads the register again to acknowledge, and a byte-at-a-time data-in
   transfer reads it once more.
3. **The CDB index resets when the command phase starts** — otherwise the first
   command works and every later one re-runs the *stale* CDB. That was
   `HARD.COM`'s "Waiting for drive to become ready": a `READ` answered by a
   leftover `TEST UNIT READY`.
4. **A select byte is accepted whenever the card is not mid-command** — the ID
   scan selects the next candidate without acknowledging the previous status.

A transfer also ends at the target's length, not only at a 512-byte boundary, so
a short one (`MODE SENSE`'s 36 bytes, `READ CAPACITY`'s 8) ends where the target
said it would.

### What is left: the low-RAM DPB tables

`peek 0x055E` / `0x056E` — the DPH/DPB tables the MD-10 BIOS's `SELDSK` builds
from the geometry above — is the one acceptance item still open. It is not a card
problem any more, and the reason is measured: `HARD.COM` is a **hard-disk boot
loader**, not an installer. It reads LBA 5 for 11 blocks (`0x1600` bytes = the
`CCP`+`BDOS` of the O1 system layout), patches page zero to point at itself and
jumps into what it read — so the drive has to *already* carry an MD-10 system.

`PREP.COM` option 1 would write one, but it cannot finish: the verify pass after
the format is `VERIFY` (`2F`), which `t10spc`/`t10sbc` do not
implement at all, so the driver never sees its match and loops (measured: 600
emulated seconds at *"Verifying disk (first pass)..."*, 1 772 618 `2F` commands
over LBA `0`–`0xFF`). That is why the drive is **built** rather than formatted —
`tools/research/mkdrive.py`.

**What the drive has to carry is no longer the open question.** The on-disk
header `PREP.COM` writes is read out of the program and confirmed on the emulated
drive: four 512-byte blocks at LBA 0–3 — the **disk label** at LBA 0 (built at
`0x36CE`, `M`/`D` at `+0`, the label text at `+14`, a 28-byte partition table
from `+48`), a block at LBA 1, and a 1 KiB partition block at LBA 2–3. The
recognisability check is a `READ` of LBA 2 into `0x32CD`. `docs/osborne1nx-machine.md`
§6 has the field map, the CDB layout, and the recipe that produced it — including
the trap that made it look like a no-op (the card's select byte at `0x8023` is a
run-time variable; if the flow skips the routine that sets it, every transaction
is delivered to no target and the drive stays untouched).

## The two findings worth not rediscovering

1. **`base+2` is a read/write register, not a status byte.** `04h` is what the
   host *wrote*: both overlays write `04h`, read `04h`, then write `00h` and
   require `00h` (`CNTLRCOD.OVL` 0x8244, and the same path in `HARD.COM`). So
   `04h` is a controller-select field read back — "controller 01" — and the
   *real* probe is the ID scan that follows. Reading it as a pure status bit
   passes the first check and fails the second.
2. **Adaptec's "controller 01" is SCSI ID 0.** `HARD.COM` does not scan: it
   reads its select byte from a configured byte (`0x0A93`), and that byte is
   `01h`. The overlay's scan starts at `C = 01h` and does `sla c`, so the select
   byte is a one-of-eight ID mask and `01h` is the first controller. Mount the
   target at `SCSI_ID_0`, not `SCSI_ID_1`.

See `docs/osborne1nx-machine.md` for the disassembly these come from.
