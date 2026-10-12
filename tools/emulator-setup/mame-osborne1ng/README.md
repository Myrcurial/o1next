# `osborne1ng` — the emulated interposer, as a MAME machine (#191)

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
| `osborne1ng.patch` | the change, as a `git apply` / `patch -p1` diff against MAME 0.289 |
| `apply.sh` | apply it to a source tree, optionally build the subtarget, optionally run the probe |
| `o1ng-probe.lua` | the headless check: the I/O decode, and the card's presence probe |
| `o1ng-dataphase.lua` | the headless check of a *transfer* — the card driven at the register level |

The patch touches five files:

- `src/mame/osborne/osborne1.cpp` — the `osborne1ng` machine and its I/O map
- `src/mame/mame.lst` — registers the machine (MAME builds its driver list from this)
- `scripts/src/machine.lua` — registers the new device's sources
- `src/devices/machine/acb4000_host_adapter.{h,cpp}` — the card, new

## Applying it

```sh
tools/emulator-setup/mame-osborne1ng/apply.sh /path/to/mame --build --probe
```

`/path/to/mame` must be a **source** tree (a checkout, or an unpacked release
tarball) — the patch adds a device and a machine, so it has to be rebuilt.
Nothing new has to be installed: GNU make and a C++20 compiler are all it wants,
and on macOS `apply.sh` passes `OSD=mac` because a source build otherwise wants
SDL3 (see `REQUIREMENTS.md`).

Then run it:

```sh
mame osborne1ng -rompath tools/emulator-setup/roms \
    -flop1 research/shipped-software/OS1UTLS.IMD
```

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

`osborne1ng` runs the **1.44 ROM only** (`3a10082-00rev-e.ud11`, with the
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
| the **data phase** (`INQUIRY`, `MODE SENSE`, `READ CAPACITY`, `READ`) | **yes** — 22/22 checks, `o1ng-dataphase.lua` |
| the **data-out** phase (`MODE SELECT`, `SEND DIAGNOSTIC`) | **yes** — both complete |
| `peek 0x055E` / `0x056E` (the DPH/DPB tables) | **not yet** — the drive needs an MD-10 system on it; see below |

### Driving a transfer

The data phase needs a drive image mounted, and the slot's option is **`-hard`**
(not `-scsi:1:harddisk:image` — `-listxml` gives the device tree path
`:scsi:1:harddisk:image`, but the command line wants the instance's brief name):

```sh
tools/research/mkdrive.py --out /tmp/md10/hd.chd                # PYXIS13, 321/4/18
O1NG_LOG=/tmp/o1ng-dataphase.log SDL_VIDEODRIVER=dummy mame osborne1ng \
  -rompath tools/emulator-setup/roms -hard /tmp/md10/hd.chd \
  -video none -sound none -window -nothrottle -seconds_to_run 6 \
  -autoboot_script tools/emulator-setup/mame-osborne1ng/o1ng-dataphase.lua
```

`mkdrive.py` is how the drive gets there: it writes a **blank but formatted**
ST-506/MFM image — the ACB-4000's own fill byte (`6C`) in every data field,
which is what the controller's `FORMAT` writes — for any geometry, without the
1984 tools (MAME's `SCSIHD` cannot finish a format; see "What is left" below).
`--chs 306,4,17` gives an `ST412`, and the period list of drive geometries is
archived at `research/adaptec/compatible-drives-1991-usenet.txt`.

### The handshake details that cost the time

Four of them, all read out of the driver and all of them a hang until they were
right (`docs/osborne1ng-machine.md` §3):

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

`PREP.COM` option 1 would write one, but it cannot finish: MAME's `SCSIHD` drops
the `MODE SELECT` parameters and its `FORMAT UNIT` is a status-only no-op, and
the verify pass after it is `SEARCH DATA EQUAL` (`2F`) — which `t10spc`/`t10sbc`
do not implement at all, so the driver never sees its match and loops (measured:
600 emulated seconds at *"Verifying disk (first pass)..."*, 1 772 618 `2F`
commands over LBA `0`–`0xFF`). That is why the drive is **built** rather than
formatted — `tools/research/mkdrive.py` — and why what is still missing is the
MD-10's own on-disk structure, which is written by the part of `PREP.COM` we
cannot reach.

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

See `docs/osborne1ng-machine.md` for the disassembly these come from.
