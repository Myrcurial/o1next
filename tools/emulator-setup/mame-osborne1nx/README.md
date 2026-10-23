# `osborne1nx` — the emulated interposer, as a MAME machine (#191)

A **fourth `osborne1` machine in MAME** whose Z80 sits behind a card that decodes
the full 8-bit I/O address, so the MD-10's ACB-4000 host adapter can answer on
ports `30h`–`33h`. The stock `osborne1` cannot reach them: its `io_map` is
`map(0x00, 0x03).w(bankswitch_w)` with `global_mask(0x03)`, so `OUT (30h)` is
erased to offset `0` before any handler sees it. That measurement is
`docs/acb4000-host-adapter.md` §2; this machine is the answer to it.

The machine and the device are written as a real MAME machine and a real MAME
device, so the patch is shaped to be sent upstream — and so that the same
device, on hardware, is the RP2354B firmware's personality (#179, #192).

**Its video is the interposer's video personality, and that is the SCREEN-PAC
(#24).** The machine derives from `osborne1sp`, so it answers `2400h`'s presence
bit as *fitted*, takes the SCREEN-PAC's register there and draws its window — and
it **boots in the 104-column one**, the widest of the board's three. What does
*not* change is the screen's text: see "The video personality" below.

**It is a patch, so `mame` on `PATH` has no such machine.** To build it,
`apply.sh` puts the machine into a MAME source tree and rebuilds the subtarget;
to test it, run the harnesses in this directory (each is one command, and prints
what it checked); to *use* it, run `./boot-o1next.sh` — video and sound on, real
time, up to two floppy images on the command line and a hard disk through
`O1_HARD`.

## What is in here

| File | What it is |
|---|---|
| `osborne1nx.patch` | the change, as a `git apply` / `patch -p1` diff against MAME 0.289 |
| `apply.sh` | apply it to a source tree, optionally build the subtarget, optionally run the probe |
| `picoem-link.patch` | the **second** patch (#192, Gate A): the `osborne1nxp` machine and the `picoem_link_device` that answers the card's window out of a real RP2354B firmware. Separate from the first because it is a separate unit of work with its own acceptance — and a tree that only wants the card need not take it |
| `o1next-probe.lua` | the headless check: the I/O decode, and the card's presence probe |
| `o1next-dataphase.lua` | the headless check of a *transfer* — the card driven at the register level |
| `o1next-softrom.lua` | the headless check of the **ROM window** — all 8 KB read back and compared (#247) |
| `softrom-check.sh` | **the two-way acceptance** of that window — the window three ways, the **window width** against `osborne1`'s, and the boot against `osborne1` (#247) |
| `o1next-romservice.lua` | the headless check of the **ROM service's door** and of **page 1** — the mailbox transaction the ROM drives, the measurement that settles the door's address, and `PRESENT(0)`, the one content id left (#247, #278) |
| `romservice-check.sh` | **the door's acceptance** — that the animation is a valid asset, that the door answers (ECHO, INFO, NOP, an unknown opcode, the abandon rule), that page 1 is the payload, and the address, all in one command (#247, #278) |
| `o1next-bootscreen.lua` | the headless check of **the screen itself** — the two video planes read back off the machine after the monitor's own screen code has run, and the fallback text that is the trigger the RP2354B watches for (#247, #278) |
| `bootscreen-check.sh` | **the screen's acceptance** — the fallback on both planes, at its own rows and its own dim runs, with nothing mounted beside the monitor (#247, #278) |
| `rom2boot.lua` | the headless check of **ROM 2.0's `HCBOOT`** — the chain read back stage by stage (#247) |
| `rom2-check.sh` | **the chain's acceptance** — ROM 2.0's image in the window, RETURN, and what the monitor then does; `O1_BSH=6` re-runs the same nine checks on 8 KiB blocks (#247) |
| `rom2trace.lua` | **where the boot goes after the chain** — the PC sampled finely, the stack unwound, and the two cells the hand-over turns on (#247) |
| `rom2bank.lua` | the same question from the other side — **taps**: the IOBYTE read, and the bank selects, on this machine and on a stock boot (#247) |
| `rom2handover.lua` | **the fix, proved before it is built** — poke `CCPADR` and the machine reaches `A0>` (#247) |
| `rom2drives.lua` | **the N-drive acceptance** — `A0>`..`N0>`, a file written and read back on every drive, each drive's own ALV, and the LBA the *card* was asked for (#247) |
| `boot-o1next.sh` | **the windowed one** — boot it and use it, with up to two floppy images and an optional hard disk (#247) |
| `stage.sh` | **stage a self-contained test machine** outside the repo — binary + ROMs + launcher in one directory (#247) |
| `o1next-picoem.lua` | **the picoem bridge's MAME half** (#286) — the card window's taps, and the 24-byte frame that carries each cycle to a real RP2354B firmware running inside picoem and back. A pair of FIFOs, not a socket: MAME's Lua has no socket library, and `docs/picoem-bridge.md` §2 has the measurement |
| `picoem-check.sh` | **the bridge's acceptance** (#286) — a firmware binary built from this tree running inside picoem, `osborne1nx`'s bus cycles reaching its GPIO, and the answers coming back into the machine. Seven checks, and the firmware's own PC and cycle count are two of them |
| `o1next-picoem-guest.lua` | **the guest harness** (#192, Gate A) — pokes an 11-byte Z80 routine (`DI / LD A,A5h / OUT (30h),A / IN A,(30h) / LD (4020h),A / HALT`) into the guest's RAM and lets *the guest* run the I/O, then reads the result back through the guest's own program space. Unlike the Lua tap above, nothing here can fake the answer |
| `picoem-guest-check.sh` | **Gate A's acceptance** (#192) — the loop closed: the Z80's own `OUT`/`IN` reaches a real RP2354B firmware through `osborne1nxp`'s `picoem_link_device`, and the byte comes back into guest memory. Twelve checks over three ports, and the three-port part is load-bearing (see below) |

The patch touches seven files:

- `src/mame/osborne/osborne1.cpp` — the `osborne1nx` machine, its I/O map, its ROM window, the door's address, and its SCREEN-PAC video
- `src/mame/mame.lst` — registers the machine (MAME builds its driver list from this)
- `scripts/src/machine.lua` — registers the new devices' sources
- `src/devices/machine/acb4000_host_adapter.{h,cpp}` — the card, new
- `src/devices/machine/softrom.{h,cpp}` — the ROM window and the ROM service's door, new

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
`osborne1`; with `tools/research/rom2image.py`'s 7695-byte image mounted it boots
identically too, because that image's monitor is still the stock 1.44. See "The
softROM window" below, and `softrom-check.sh` for the acceptance.

```sh
tools/research/rom2image.py -o /tmp/rom2.rom
mame osborne1nx -rompath tools/emulator-setup/roms -softrom /tmp/rom2.rom
```

**There are no asset slots (#278).** `-frame` and `-bootsplash` mounted the
interposer's own flash — the boot frame's two halves, and the screen's code as one
window page — and the ROM asked for them through the **ROM service's door**
(`docs/rom-pico-protocol.md` §4 and §5). The ROM-side frame path retired: the
RP2354B is the display, it plays the animation out of its own flash, and the Z80's
whole role is the *trigger*, so the ROM asks the interposer for nothing at the
sign-on, page 1 is the payload always, and `PRESENT(1)`, `PRESENT(2)` and
`PRESENT(3)` answer `09h` and leave page 1 alone. `PRESENT(0)` is the one content id
left.

The boot screen's asset is the animation: `firmware/rom-service/boot-animation.bin`,
which the **RP2354B** plays out of its own flash. `frame.bin` — the served frame,
which `tools/research/bootanim.py --resting` derived from the animation's resting
frame — and `screen.bin` — the screen's code, served as a window page — retired with
the frame path (#278), and the tool's `--resting` with them.

So the ROM side has exactly one thing to say about the asset: that it is **valid** —
the container's own sum, its declared geometry and flags, and every frame's own
trailer (`bootanim.py --check`). Nothing on this side looks at the animation's
*content*, because the RP2354B is what draws it.

```sh
python3 tools/research/bootanim.py --check firmware/rom-service/boot-animation.bin

mame osborne1nx -rompath tools/emulator-setup/roms -softrom /tmp/rom2.rom
```

**That is the headless shape.** To actually *use* the machine rather than test it,
run `./boot-o1next.sh` — see its header, and AGENTS.md.

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
| banking **unchanged** from `osborne1` | **yes** — the boot probe's output is byte-identical (`diff` clean, modulo the machine name) |
| the **video** — the SCREEN-PAC's 104-column window | **yes** — `softrom-check.sh` reads both machines' geometry (`osborne1` is 52 columns, `osborne1nx` is 104) and the screen text row for row |
| the mainboard's 2-bit decode survives | **yes** — `00h`–`03h` still bank-switch, and `05h`/`3Dh` still alias `01h` |
| the card owns `30h`–`33h` | **yes** — writes there do not bank-switch |
| the MD-10 presence probe | **yes** — `IN (32h)` reads `04h`; after `OUT (32h),00h` it reads `00h` |
| the ID scan | **yes** — `PREP.COM` finds the controller at select byte `01h` only |
| **`PREP.COM` (the MD-10 drive-table editor) runs unpatched** | **yes** — its main menu, the drive-table submenu, *and* its initialize/format flow, which then loops on the verify pass (see "What is left") |
| `HARD.COM` reaches the controller | **yes** — real commands (`TEST UNIT READY`, then `READ` LBA 5 ×11 — the `CCP`+`BDOS` it boots) |
| the **data phase** (`INQUIRY`, `MODE SENSE`, `READ CAPACITY`, `READ`) | **yes** — 22/22 checks, `o1next-dataphase.lua` |
| the **data-out** phase (`MODE SELECT`, `SEND DIAGNOSTIC`) | **yes** — both complete |
| the **softROM window** — all 8 KB of `0000-1FFF`, three ways | **yes** — `o1next-softrom.lua`, all 8192 bytes, in `softrom-check.sh` |
| the **ROM service's door** — ECHO, INFO, NOP, an unknown opcode, the abandon rule | **yes** — `o1next-romservice.lua`, in `romservice-check.sh` |
| **page 1** — `PRESENT(0)`, the payload, which is where page 1 already is | **yes** — the same harness: the served page byte-compared against the image |
| **the retired ids** — `PRESENT(1/2/3)`, the frame's halves and the screen's code | **yes** — `romservice-check.sh`: each answers `09h` and leaves page 1 alone (#278) |
| **`INFO`'s flags byte** | **yes** — the harness checks it is `00h`: there is no asset slot left to report (#278) |
| **the door's address** — `0x2301` is the floppy's track register, so the door is at `2800h` | **yes** — measured in the harness: `0x2301` reads what `0x2101` reads, and a request written to `0x2300` never reaches the door |
| **no image mounted ⇒ boots as `osborne1`** | **yes** — the boot probe's screen dump is byte-identical, row for row (`diff` clean, modulo the machine name and the window geometry) |
| **`-softrom` (the 7695-byte image) ⇒ boots as `osborne1`** | **yes** — byte-identical too, page 1 reading the payload |
| **ROM 2.0's `HCBOOT`** — the CBIOS, the MD-10 BIOS, its patch, the bank, the read | **yes** — `rom2boot.lua`, five checks, in `rom2-check.sh` |
| ROM 2.0 booting the hard disk to `A0>` | **yes** — nine checks in `rom2-check.sh` including the prompt, and again on 8 KiB blocks with `O1_BSH=6` (`docs/md10-system.md` §9.3) |
| the **hard-disk boot** (`HARD.COM` → `A0>`/`B0>`/`C0>`) | **yes** |
| the **N-drive driver** — 11 drives `A0>`..`K0>`, a file on each, each its own ALV, each read landing inside its own partition | **yes** — `rom2drives.lua`, 27 checks, `docs/md10-system.md` §9.4 |
| `peek 0x055E` / `0x056E` (the DPH/DPB tables) | **not yet** — the drive needs an MD-10 system on it; see below |

### The video personality — the SCREEN-PAC, in its 104-column window

The interposer's video personality **is** the SCREEN-PAC (#24), so this is an
`osborne1sp` with a card in it rather than an `osborne1` with a wider I/O decode:
`osborne1nx_state` derives from `osborne1sp_state`, which is where the board's
register, its presence bit and its two widths already live. Three consequences,
all of them visible from outside:

| | |
|---|---|
| `2400h`, bank 2 | reads **bit 2 LOW** — fitted. The stock machine reads `FFh` there, and that bit is how period software detects the board with no ROM change (`docs/mame-emulation.md` §2) |
| the window | **104 columns at reset** — `machine_reset()` sets the board's own register, so the machine boots in the widest width the board has |
| the geometry | `832x240`, as `osborne1sp`; the stock machine is `416x240` |

**Why 104 and not 80.** The board has three widths — 52 / 80 / 104 — and MAME can
express two of them: `osborne1sp` offers 52 and 104, not 80 (#274). 104 is
therefore the stand-in until that is fixed, and moving to 80 is one line in
`machine_reset()` when it is. The guest is not caged by it: `2400h` is the
board's own register, the power-on value is only a default, and a
52-column-prepared floppy still switches the window to 52 by writing it —
measured, 16-pixel characters filling the 832-pixel screen.

**And the text does not move.** The window's left edge coincides with the stock
machine's for the guest's normal boot state, so the same disk draws the same
screen in the same place with 52 more columns of the video buffer visible to the
right — measured off the rendered frames: `osborne1` at 416x240 and `osborne1nx`
at 832x240 have the *same* ink runs, character for character, from `x = 0`.
`softrom-check.sh` asserts both halves: the two geometries, and the screen dump
row for row against `osborne1`.

**One thing this fixed on the way.** That boot comparison ran `osborne1nx` for
the "stock machine" run as well, so "boots identically to `osborne1`" was
comparing the machine against itself and could not fail. It runs `osborne1` now
— and the geometry check is what says so, because a run of the wrong driver
would report 52 columns for both.

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

`tools/research/rom2image.py`'s image is **7695 bytes** — the stock monitor plus
the 3599-byte payload — so the 497 bytes it does not cover are the payload's
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

Measured, with the hand-over in the image: `PASS` on all five, with the 7695-byte
image reading `C3 ED E4 …` at `1000h` (the CBIOS's first bytes) against
`31 C1 EF …` at `0000h` (the monitor's), the hand-over stub at `1E01h`, and `FF`
from `1E0Fh` to `1FFFh`.

### The ROM service's door

The ROM asks the interposer for things through a bank-2 register pair
(`docs/rom-pico-protocol.md` §4 and §5): write the opcode then its operands to
`2800h`, read the reply from `2801h` (`0` = not ready, else the length, then the
bytes), with the mailbox protocol's result codes and its abandon-a-pending-reply
recovery rule. Page 1 is the payload always — `PRESENT(0)` is the one content id
left, and the three that retired with the frame path answer `09h` (#278).

```sh
tools/emulator-setup/mame-osborne1nx/romservice-check.sh
```

**And the address is a measurement, not a preference.** The protocol proposed
`2300h`/`2301h`; this machine says no, and `romservice-check.sh`'s first two
checks are why: `0x2301` reads exactly what `0x2101` reads, because the onboard
selects check two address bits each and the floppy's track register is selected
there too — so a reply ANDed with a track register sitting at `00h` never becomes
ready, and a request written to `0x2300` is a floppy command. It is the same
aliasing `tools/o1_mame_probe.lua`'s C9 report and
`docs/o1-mainboard-schematic.md` §7a already record; what is new is that it
matters *here*, and `2800h` is the fix — the part of
`docs/o1-memory-io-map.md` §7's recommended block that nothing selects.

`romservice-check.sh` is one command, and it runs the animation's validity check
beside the door's own.

**And the screen itself has an acceptance, which is the one that reads the
*result* rather than a door.** ROM 2.0's monitor calls its own screen code at the
sign-on — fill the attribute array bright, print the fallback, return — and
`bootscreen-check.sh` reads the two video planes back off the machine and compares
them against the animation's own two lines and its own bright/dim runs: the
character plane by value, and the attribute plane's dim runs, whose total is
checked too, so the fill cannot come up short.

```sh
tools/emulator-setup/mame-osborne1nx/bootscreen-check.sh
```

**The fallback is not decoration — it is the trigger.** The RP2354B plays the
animation out of its own flash and stops on the Z80's first video-RAM write, so the
text the monitor prints is what says when to stop, and it is the one thing the
frame path's retirement must not disturb (`docs/rom-pico-protocol.md` §5.1,
`docs/o1-rom-2.0.md` §4.9).

`tools/research/rom2asm.sh` assembles ROM 2.0's monitor — the vendor's 1.44 with
the new code in the free tail of it — with the vendor's own ACT80, and
`rom2-check.sh` measures what the new code *does*: with the image in the window and
no floppy, **RETURN** at the sign-on prompt is the monitor's `HCBOOT` entry
(`:` is floppy A and `"` is floppy B — #247 step 4), and the harness reads the
chain back stage by stage:

```
  PASS  the sign-on dispatch is ROM 2.0's key map (RETURN = the hard disk, ':' = floppy A, '"' = floppy B)
  PASS  the CBIOS is at 0E100h, and it is the window's 1000h
  PASS  the MD-10 BIOS's own jump table is at 0D800h
  PASS  it is patched from the CBIOS's vectors (5 LDIRs, 90 bytes)
  PASS  the bank switched to RAM at some point after RETURN
  PASS  the hand-over stub is in RAM at 0E0F0h, and it is the window's 1E01h
  PASS  CCPADR (0EFD2h) is CB00h, the store the ROM's own CBOOT makes
  PASS  the system was read off the drive into 0C200h     (with O1_HARD)
  PASS  the machine reached A0> -- the ROM booted the hard disk, no floppy
```

The chain *and* the prompt are what the ROM is responsible for, and both are
complete: with a drive mounted the machine reaches `A0>` **with no floppy in it**.
The last piece was one cell, `CCPADR` (`0EFD2h`) — the cell the ROM's own `CBOOT`
writes and `HCBOOT` was lifted without (`docs/o1-rom-2.0.md` §4.6, §8 item 10):

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
same instrument, before the store was built and after:

| | stock boot | ROM 2.0, before the store | **ROM 2.0, with it** |
|---|---|---|---|
| reads of `0003h` | 858, **all `80h`** (RAM → CRTOUT) | **1, returning `D3h`** (the ROM → IEEE) | **11, all `80h`** (RAM → CRTOUT) |
| bank selects | 454 `OUT 0`, 492 `OUT 1` | 1 `OUT 1` (HCBOOT), 1 `OUT 0` (the trampoline) | 6 `OUT 0`, **44 `OUT 1`** |
| `CCPADR` → the handler's exit | **`CB00h` → `E133h`**, the CBIOS's `RRI` | **`0000h` → `1633h`**, the payload | **`CB00h` → `E133h`** |

**The store is built.** `rom2handover.lua` proved it first by poking `CCPADR` into
RAM from outside; `HCBOOT` now does it itself — it copies a 14-byte stub out of the
payload's spare into RAM at `0E0F0h`, pushes *that* address instead of `0D800h`,
and `SW2RAM`'s `RET` enters it. `rom2boot.lua` reads the stub's bytes back and
checks `CCPADR`, so a build that lost the store fails the run rather than sitting
at the sign-on prompt for ever.

**A stale `/tmp/rom2.rom` looks exactly like `HCBOOT` not working.** The image is
two steps (`rom2asm.sh`, then `rom2image.py`); reuse an older `/tmp/rom2.rom` and
the window serves the *stock* monitor, whose `0F67h` is still `JMP START` — so
RETURN takes the stock floppy-A path and the machine never enters `HCBOOT`.
`rom2-check.sh` builds the image itself, so it cannot hit this; a hand-run trace
can. Check the image before believing a negative: `0F67h` must be `21 00 10`
(`LD HL,1000h`), not `C3 00 00`.

**The boot key is RETURN, and it is a plain carriage return (#247 step 4).** The
monitor's sign-on dispatch boots the machine's own hard disk on RETURN, `:` is
floppy A and `"` is floppy B, and ESC is released — it falls through to the
prompt's `JR START` like any unclaimed key. ESC is also the one key that cannot be
posted as a character: on this machine it is a *key* code
(`PORT_CHAR(UCHAR_MAMEKEY(ESC))`), so `natkeyboard:post("\27")` matches no port and
presses nothing — silently, and the code has to be read out of the natkeyboard's
own table (`natkeyboard:dump()`: `0010003B (Escape)`).
`tools/research/o1keys.lua`'s `key esc` still exists and still reads the code from
the table, because `PREP.COM`'s menus need it — see `docs/md10-system.md` §2.

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
problem, and the reason is measured: `HARD.COM` is a **hard-disk boot
loader**, not an installer. It reads LBA 5 for 11 blocks (`0x1600` bytes = the
`CCP`+`BDOS` of the O1 system layout), patches page zero to point at itself and
jumps into what it read — so the drive has to *already* carry an MD-10 system.

`PREP.COM` option 1 would write one, but it cannot finish: the verify pass after
the format is `VERIFY` (`2F`), which `t10spc`/`t10sbc` do not
implement at all, so the driver never sees its match and loops (measured: 600
emulated seconds at *"Verifying disk (first pass)..."*, 1 772 618 `2F` commands
over LBA `0`–`0xFF`). That is why the drive is **built** rather than formatted —
`tools/research/mkdrive.py`.

**What the drive has to carry is settled.** The on-disk
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
