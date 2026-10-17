# The ROM↔Pico channel, and the boot screen — ROM 2.0's client (#247 step 8)

**Status: design — a proposal.** The ROM side of #247 is built and measured
(steps 1–7: the banked window, `HCBOOT`, the hand-over, the 11-drive driver). The
screen's *mechanism* is measured in the machine. **The firmware side does not
exist**, and this is the contract it is written against — except for the door
itself, which the *emulated* interposer now implements (`softrom_device`'s
selector and transaction, `romservice-check.sh`) so that the ROM's screen code
can be written and proved against it. See §2 for the address, which the machine
corrected, and §7 item 1 for what is left open.

Answers **#247 step 8**. Reads alongside `docs/mailbox-protocol.md` (the
*host*↔firmware channel, #155 — this is a different client of the same firmware),
`docs/o1-rom-2.0.md` §4.1b, §4.6, §4.9 and §8, `docs/o1-memory-io-map.md` §4 and
§7, and `docs/virtual-peripherals-block-diagram.md` §2–§3.

## 1. What this is, and what it is not

The **ROM's** way to ask the Pico for something. `docs/mailbox-protocol.md`
already defines one channel for a CP/M program; this defines the *second client*
of the same firmware — the monitor, which runs before any CP/M exists, in a
different address space, and whose first requirement is a **4096-byte picture**.

Two things are deliberately *not* here:

- **Not a bulk channel.** `mailbox-protocol.md` §3 is emphatic — *"No bulk
  channel, ever"* — and that rule is what decides this document's shape: the
  boot screen's 8192 bytes of frame **cannot** cross the command door. The door
  says *which* content to present; the **ROM window** carries the bytes. §5.
- **Not a second protocol.** Same opcodes, same replies, same result codes, same
  recovery rule. A firmware module that implements one implements both.

## 2. Where it lives: two doors, one protocol

The two clients cannot share a door, and the reason is each one's address space —
not a preference.

| Client | Runs in | Can reach | Door |
|---|---|---|---|
| `MOUNT.COM` (#27), the clock publisher (#18) | **bank 1** — the TPA, at `0100h` | I/O ports only | **`0E7h`/`0EBh`** — `mailbox-protocol.md` §2 |
| **ROM 2.0's monitor** | **bank 2**, with the window mapped over `0000–3FFF` | bank-2 memory, and I/O | **`2800h`/`2801h`** — a bank-2 register pair |

**The pair was `2300h`/`2301h` in this document's first draft, and the machine
corrected it (2026-10-15).** `o1-memory-io-map.md` §7 calls `2300–23FF` the
largest clean block, and the block's *edges* are clean — but the onboard selects
check two address bits each, so `0x2301` is the floppy's **track register** as
well as the keyboard's row 0, and `0x2300` is the floppy's command/status
register. That is measured, not inferred: `docs/o1-mainboard-schematic.md` §7a
records it ("`0x2301` is keyboard *and* floppy"), `tools/o1_mame_probe.lua`'s C9
report prints it, and `o1next-romservice.lua` re-measures it in the machine that
has the door — the reply register reads what `0x2101` reads, and a reply ANDed
with a track register sitting at `00h` reads *not ready* for ever. **`2800h` is
inside the same recommended region and is the part of it that nothing selects**:
no device mask matches A11 set with A8/A9/A10 clear, so the stock decode reads
`FFh` there and the door answers alone. §7 item 1 and `o1-memory-io-map.md` §7
carry the same correction. (The other clean part of that region, `2400–27FF`, is
the SCREEN-PAC's own decode — presence bit included — which the video
personality needs.)

**And the door is not in Drive C's space, because Drive C has none.** Its
exclusivity with the interposer is real (`mailbox-protocol.md` §1) and was checked
before the address was chosen: the Drive C connector (P3) is a **parallel port**,
not GPIB, and the host drives it by bit-banging the **mainboard's own** PIA at
`2900–2903` (`drive-c-protocol.md` §1–§2) — machine hardware, always fitted. No
Drive C document names a bank-2 window, so there was nothing of its to reuse for a
*memory* register; what its exclusivity frees is the drive-`2` identity in the
mailbox. `2800h` is this document's own region, taken from the blocks that nothing
selects.

**Why the ROM cannot use the ports as its primary door.** The machine's
**bank/video latch is written on the console path**: `OUT (02h)` and `OUT (03h)`
toggle the 9th video bit, and the monitor's own reset code wrote the latch
**301 times in the first second** — `02h` ×150, `03h` ×151 — measured. On a
comparator-decoded board (Rev B: the 74AHCT688 watches `A8–15`) an I/O claim has
to see every I/O cycle, and the console path is the busiest I/O this machine has.
A **bank-2 register is decoded precisely** — `2800h` puts `28h` on `A8–15`, so
`ADDR_HIT` is exact and the console path is untouched.

**Why `MOUNT.COM` cannot use the memory door.** A program at `0100h` cannot
select bank 2 without its next instruction fetch coming back as ROM
(`mailbox-protocol.md` §2). That is not a limitation to work around; it is why
every onboard device on this machine is reached through the ROM.

**`2800–28FF` is inside the recommended block** — `o1-memory-io-map.md` §7 names
`2300–28FF` free between the keyboard (`2201–2280`) and IEEE-488 (`2900–2903`),
and its clean 256 bytes are the ones from `2800h` up. This document claims two
bytes of it.

**The door's own register layout** is the only thing that differs between them:

| Door | write (`OUT` / store) | read (`IN` / load) |
|---|---|---|
| userland | `0E7h` — request: opcode, then operands | `0EBh` — reply: `0` = not ready, else the length, then the bytes |
| romland | `2800h` — the same request | `2801h` — the same reply |

Both numbers are **firmware constants**, and the protocol is base-relative: if a
measurement on hardware says otherwise, one line in the firmware and one in each
client move, and nothing else does.

## 3. The transaction

**Identical to `mailbox-protocol.md` §3** — polled, byte-at-a-time, single-master.
The Z80 is the only thing on the bus that initiates anything, so there are no
interrupts, no DMA and no FIFOs to size.

1. The client writes the **opcode**, then its **operands**, one write per byte.
2. The client polls the reply register. `0` means *not ready, poll again*. `N > 0`
   is the **reply length**, and the next `N` reads are the reply bytes.
3. `reply[0]` is always a **result code** (§4.2); `reply[1..]` is the payload.
4. Writing the request register while a reply is pending **abandons it** and
   starts a new transaction — so a wedged ROM cannot wedge the firmware. An
   unknown opcode answers `01h` and resets the operand count, so `NOP` is always
   a way back to a known state.

**Presence probe.** The same **echo**: send `ECHO` (`01h`) with one operand and
require it back, twice, with two different patterns. There is no "device present"
bit, because an absent interposer leaves the register answering the floating bus.

## 4. The command set

The opcode space is partitioned by **device class**, so this client adds a class
and does not require a protocol revision (`mailbox-protocol.md` §4).

| Opcode | Name | Operands | Reply payload (after the result code) |
|---|---|---|---|
| `40–4Fh` | *ROM service* | | |
| `40h` | `PRESENT` | content id `u8` | — |
| `41h` | `INFO` | — | format version `u8`, flags `u8` |

**`PRESENT` is the whole of step 8.** It is the one command the monitor needs, and
it is what ROM 2.0's `BANKSEL` extension (`o1-rom-2.0.md` §4.7, extension 1 —
"`A` = the payload slot, write the selector", whose selector §4.1a left open)
becomes. The content ids:

| id | Content | Who needs it |
|---|---|---|
| `0` | **the payload** — CBIOS + MD-10 BIOS image + the hand-over stub, 3599 bytes | the hand-over (§4.1 step 7), and `BANKSEL` generally |
| `1` | **the frame's character half** — 4096 bytes | the screen (§5) |
| `2` | **the frame's attribute half** — 4096 bytes, the 9th bit | the screen (§5) |
| `3` | **the screen's own code** — 4096 bytes, one window page, which the monitor's stub copies to RAM at `4000h` and jumps into | the monitor's stub (§4.1). **Chosen 2026-10-15**, from §4.1's three candidate homes: the code is firmware like the frame and no payload change is needed. Built and measured — 183 bytes of code in the page, `0F67h`–`40B7h` for the monitor and the blob together, 19 bytes free to the guard |

`INFO` is for the web UI and for a human, not for the ROM: **the ROM never asks
whether a frame exists** — the trailer *is* the query (§6). It is here so that a
firmware with no frame and a firmware with a frame can be told apart by something
that is not the ROM.

### 4.1 The boot sequence in full

Everything below is measured on `osborne1nx` unless marked.

1. `OUT (03h)` — **clear BIT 9**, so `F000–FFFF` is the character RAM. The machine
   *leaves* it clear at the sign-on (measured), but the monitor's own reset code
   writes the latch ~150 times, so the ROM must not assume a state.
2. **Fill the attribute array bright**: `OUT (02h)`, 4096 stores of `FFh`,
   `OUT (03h)`. 21.5 ms. This is **not** optional: the array is not a blank slate
   — 4072 of 4096 cells already read `FFh`, but **24 read `7Fh`**, which is dim,
   and they would show as scattered dim cells in a 4096-cell frame.
3. Print the fallback text — the animation's own two lines and bright/dim runs, at
   its own rows and columns, 72 bytes against `IMSG`'s 182 (`o1-rom-2.0.md` §4.9).
   **It positions itself**, with `VCLRS` first: `CURS` is 0 when this code runs, so a
   message that does not is written to address 0 and never appears. Its dim runs are
   the vendor's `ESC,VSHI` … `ESC,VEHI` half-intensity mode.
4. `PRESENT(1)`; read the frame's character half out of the window; check the
   trailer (§5).
5. If it validates: `LDIR 1000h → F000h`, 4096 bytes, 21.5 ms — over the text.
6. `PRESENT(2)`; if the attribute half validates, `OUT (02h)` then
   `LDIR 1000h → F000h`; otherwise the bright fill from step 2 stands.
7. `OUT (03h)`; `PRESENT(0)` — **the payload back.** The frame and the payload are
   the same 4096 bytes of window page 1, so presenting the frame evicts the
   payload, and the hand-over needs it (§5).

Two 4096-byte passes ≈ **43 ms**, against a floppy boot measured in seconds. **The
ROM cost does not fit the monitor's tail, and the assembler's own guard is what
said so** (2026-10-15, #247 turn 3): the 1.44 layout leaves 150 bytes above
`0F67h`, `HCBOOT` took 77 of them (`0F67h`–`0FB3h`), and the screen's code — the
fill, the text, the door, the trailer and the two blits — is **212 bytes** (182 when
it was first measured, on 2026-10-15; #247's W3 gave the fallback the screen's own two
lines and their bright/dim runs):

```
I 1021  .9   ERROR   CODE TOO LARGE..      Program LWA = 1102h.
```

That is the guard `IF RLWA > 0FFBH / .9 ERROR CODE TOO LARGE` doing its job, and
it settles §4.7's "does the monitor code fit" question in the negative. The code
is written and measured — `research/source-code/BIOS-200-source/rom2-screen.asm` —
and it needs a home: **a third content id in the softROM** (`PRESENT(3)` serving a
4096-byte blob in the Pico's flash, beside the frame, with a ~21-byte stub in the
monitor that copies page 1 to RAM and jumps into it — the recommended one, because
the screen code is firmware like the frame and no payload change is needed), the
**payload's spare** (497 bytes at `1E0Fh`, where the hand-over stub already lives),
or §4.7's **Plan B** (a banked loader). All three fit; the choice is the
maintainer's, and the code is home-agnostic. **Chosen 2026-10-15: the first one** —
built and measured: the monitor's new code runs `0F67h`–`0FE6h`, 128 bytes of the
tail's 149 to the vendor's guard at `0FFBh`, with 21 free, and the stub itself is
`0FB4h`–`0FE6h` — 51 of the 72 bytes HCBOOT left (`docs/o1-rom-2.0.md` §4.7). The
asset is served by `PRESENT(3)`, content id 3 in §4's table.

### 4.2 Result codes

`mailbox-protocol.md` §4.1's table, plus one:

| Code | Meaning |
|---|---|
| `09h` | no such content — `PRESENT` with an id the firmware does not serve |

`06h` (media error) covers a flash read that failed. The ROM treats any non-`OK`
as "no frame" and keeps its text; it does not retry, because a boot screen is not
worth a boot delay.


## 5. The frame: 8192 bytes, and the 9th bit is real

**The frame is two 4096-byte halves** — characters, then attributes — held in the
**Pico's own flash**, compiled in as a firmware asset. There is **one frame**; the
default ships with the firmware, and swapping it means rebuilding the firmware
(which is the point: it is a product's face, not user data — but somebody will
want to swap it, so the format is public and the default is in the repo).

**Why two halves, when v1.0's screen is all-bright.** The O1's video cell is
**9 bits** — 8 for the character, 1 for brightness — and the 9th bit is not in the
video RAM. It lives in a *separate* 4K×1 array that `OUT (02h)` pages into
`F000–FFFF`; `OUT (03h)` pages the character RAM back. Measured on the machine:

| | |
|---|---|
| with BIT 9 set, writing `00h` reads back | **`7Fh`** — the array is one bit wide, and its low 7 bits read high |
| the palette (`palette_init_monochrome_highlight`) | 0 = black, 1 = `C0C0C0`, 2 = white |
| the renderer (`BIT(attr,7) ? 2 : 1`) | **bit 7 set = bright, clear = dim** |
| the array at the sign-on | 4072 × `FFh`, 24 × `7Fh` |
| the 116 character cells at the sign-on | all bright |

So **"all bright" is not a limitation of the format** — it is a frame whose
attribute half is `FFh`. The format retains the 9th bit by construction, and a
later frame can carry dim accents with **no ROM change**, because the ROM blits
the attribute half whenever it validates. That is the answer to "we retain the
ability to ship a frame that has a 9th bit": yes, and it costs the v1.0 frame
nothing.

**The trailer**, unchanged from `o1-rom-2.0.md` §4.9, at the **character half's**
`0FF8h`:

| offset | content |
|---|---|
| `0FF8h` | `O1NEXT` — the magic, **six** bytes |
| `0FFEh` | the 16-bit sum of `0000h–0FF7h`, little-endian |

The attribute half carries the **same trailer at its own `0FF8h`**, so each half
validates itself. The ROM checks the character half *before* it blits — so the
fallback text survives a bad frame — and the attribute half after: a bad attribute
half costs the bright fill, which has already happened, and nothing else.

**And the frame's bulk is why it is a page, not a port.** A 4096-byte half cannot
cross a command door that carries commands and metadata by design. So the door
names the content and the **window carries it**: `PRESENT(1)` puts the character
half at `1000h`, and one `LDIR` moves it to `F000h`.

**The frame is not the art.** `research/boot-screen/` holds the authored art
(153 × 27 cells for the wordmark, or 125 × 28 for the 1NG one), and
`tools/research/rom2strokes.py --frame` places it into the 128 × 32 grid with the
trailer — the art's rows 24–31 are off-screen and carry it. It writes **both
halves**, each with its own trailer, so one command produces the whole 8192-byte
artifact; `--half chars|attrs` writes one, `--verify` checks one or both off the
disk with nothing but the file. **That artifact is no longer a committed asset:**
the single frame at `firmware/rom-service/frame.bin` was retired on 2026-10-16, when
the boot screen became the animation the RP2354B plays (§5.1, and #247's W5), and
the byte-for-byte check that re-built it went with it. The art stays, because the
site masthead is still drawn from it.

### 5.1 The animation: a container, and the two bits that pace it

The screen above is **one** frame, and the frame format is settled. #247's last note
hands the **pacing** to the RP2354B, so the asset becomes a *sequence*, and a
sequence needs a container to say how long each frame lasts. The container is
`tools/bootsplash/README.md`'s proposal — the firmware side of it is not written —
and it is a 32-byte header and then the frames back to back, each already sealed, so
frame *n* of a one-frame file **is** the 8192-byte asset above:

| offset | bytes | what |
|---|---|---|
| 0 | 8 | `O1SPLASH` |
| 8 | 1 | version, 1 |
| 9 | 1 | **flags** |
| 10 | 2 | width, `u16` LE, 128 |
| 12 | 2 | height, `u16` LE, 32 |
| 14 | 2 | fps, `u16` LE |
| 16 | 4 | frames, `u32` LE |
| 20 | 4 | body, `u32` LE = frames × 8192 |
| 24 | 2 | header sum, `u16` LE over bytes 0–23 |
| 26 | 6 | reserved, zero |

**The flags byte is two independent bits**, because they answer two different
questions and a reader can test either one alone:

| bit | | means |
|---|---|---|
| 0 | `LOOP` | after the last frame, go back to the first |
| 1 | `PINGPONG` | at the ends, reverse direction instead of jumping |

So **all four combinations are a mode**, and all four are what the designer picks
between:

| flags | mode | for frames `1 2 3` |
|---|---|---|
| 0 | once | `1 2 3`, stop on the last frame |
| 1 | loop | `1 2 3 1 2 3 …` |
| 2 | ping-pong once | `1 2 3 2 1`, stop on frame 1 |
| 3 | ping-pong repeat | `1 2 3 2 1 2 3 2 …` |

**A bounce does not play the ends twice.** Frame 3 is *turned on* once and reversed
from, so a repeating bounce is `2n − 2` frames a cycle, not `2n`. A bounce also
**ends where it started**, which is the whole difference between flags 2 and 3: the
one-shot plays the return to frame 1 and stops there (`2n − 1` frames), and the
repeating one leaves that return to the wrap into the next cycle. **Bit 0 is
therefore the only thing that answers "does it keep going"** — a reader must not ask
"is it `once`", because a one-shot bounce stops too.

That is not only a look: it is the firmware's work. A bounce has to blit the way back
as well, which is the forward transitions again in reverse and therefore **twice**
the forward cost, and a loop has one transition a once-through does not: last →
first. Both ping-pongs cost the same, because the one-shot's last blit is the return
to frame 1 and the repeating one's is the wrap into the next cycle — the same
transition, taken once either way. `tools/bootsplash/` counts all four modes, so the
number a designer reads is the number the Pico is asked for.

**What is still not decided is how the ROM asks for frame *n*.** `PRESENT(1)` and
`PRESENT(2)` name the two halves of *the* frame (§4.1 step 4), and a sequence needs
the door to name which one — whether `PRESENT` grows a frame index, or the firmware
advances its own sequence and the ROM keeps asking for "the frame" as it does today.
That is #247's, and it is not settled here.

**What the emulator does meanwhile (2026-10-17, #247's W5).** `osborne1nx`'s frame
slot still takes one two-half frame, and the harnesses now **derive** it from the
animation's resting frame — `tools/research/bootanim.py --resting`, the last frame of
a `once` animation — rather than mounting the committed `frame.bin` that was retired
on 2026-10-16. So the ROM is served exactly the frame the animation settles on, and
nothing in the tree can drift from the asset it came from. The *pacing* stays the
RP2354B's, which is why the ROM side only ever validates the container: the same
tool's `--check` is the whole of the ROM-side acceptance (the header's sum, the
declared geometry and flags, and every frame's own trailer).


## 6. The memory map at the moment the screen runs, and what happens when it fails

The screen runs **before `CBOOT`**: no page zero, no CBIOS, no CCP, no `DIRBUF`,
no MD-10 BIOS. From `o1-rom-2.0.md` §4.4 and §4.2, confirmed in the machine:

| Range | What it is when the screen runs | Safe to write? |
|---|---|---|
| `0000–0FFF` | the monitor, in the ROM window, **bank 2** | **no** — it is executing |
| `1000–1FFF` | window page 1 — the payload, or the frame while the screen is up | yes, and the door owns which |
| `2000–2FFF` | bank-2 onboard I/O window (memory-mapped) | **no** — it is the machine's I/O |
| `2800–2801` | **this channel's registers**, inside that window | the firmware's |
| `4000–EFFF` | bank-1 RAM, mirrored in bank 2 | yes — nothing has claimed it yet |
| `F000–FFFF` | the video RAM, or the attribute array when BIT 9 is set | yes — this is the target |

**Failure semantics, and why there is only one of them.** The trailer *is* the
"is there a frame?" query, so a missing frame, an erased frame and a frame with a
bad sum are **the same case**: the magic does not match, and the ROM leaves the
text on screen. There is no error path to write, no retry to tune, and a firmware
built with no frame is indistinguishable from a flash failure — which is the right
default, because the fallback text is what the screen shows when the machine is
working and the art is not.

The recovery rule is `mailbox-protocol.md` §3's: an unknown opcode answers `01h`
and resets the operand count, so a wedged ROM recovers with `NOP`.

## 7. What is not decided

1. ~~**The two register addresses.**~~ **Settled by measurement (2026-10-15): the
   door is at `2800h`/`2801h`, not `2300h`/`2301h`.** The first draft chose
   `2300–23FF` on `o1-memory-io-map.md` §7's word that it was the largest clean
   block. It is not clean: the onboard selects check two address bits, so
   `0x2301` is the floppy's track register *and* the keyboard's row 0
   (`docs/o1-mainboard-schematic.md` §7a, `tools/o1_mame_probe.lua` C9) — and a
   reply ANDed with a track register reading `00h` never becomes ready, while a
   request written to `0x2300` is a floppy command. `2800h` is the part of the
   same recommended region that nothing selects. Measured in the emulated
   interposer itself by `o1next-romservice.lua`, whose first check is exactly
   that comparison; the protocol is base-relative, so the correction moved one
   constant in the device, one in the machine's map, and the numbers here.
2. **Whether the attribute half wants a trailer.** It costs eight bytes of the
   ROM's budget to check. The alternative is to trust it whenever the character
   half validates, which is defensible — a bad attribute half is 24 dim cells, not
   a black screen. The assembler's guard is the arbiter.
3. **Whether `PRESENT` and `BANKSEL` stay separate.** `BANKSEL` is
   `o1-rom-2.0.md` §4.7's extension 1 and `PRESENT` is its implementation; a
   program that wants to page the payload in itself calls the extension, not the
   opcode. Whether the extension should expose the frame halves too is a
   ROM-interface question, not a firmware one.
4. **Whether the frame's default art is the O1NEXT wordmark.**
   `research/boot-screen/` holds two, and the choice is a product decision.
5. **The firmware's "from moment one" list.** The splash frame is one item; the
   MD-10/ACB-4000 personality with two disks is the other, and it is larger. The
   order they land in is #179's and the storage work's, not this document's.
6. **The viewport slide.** The hardware's default behaviour is that slide, and it
   is **not** this channel's business: it is a video-personality feature, the
   screen the ROM draws is static, and the trigger is a user's `CTRL`+arrow. See
   `docs/virtual-peripherals-block-diagram.md` §5 and #24.

## Sources

- `docs/mailbox-protocol.md` — the sibling channel, its transaction, its opcode
  partitioning and its "no bulk channel, ever" rule, which is what decides §5.
- `docs/o1-rom-2.0.md` §4.1b (the window, measured), §4.3 (the payload's size),
  §4.6 (`HCBOOT` and the hand-over), §4.7 (the 150-byte budget and the extension
  table), §4.9 (the screen, the trailer and the fallback), §8 (the open items this
  closes).
- `docs/o1-memory-io-map.md` §4 (the bank/video latch, measured) and §7 (the free
  bank-2 windows, and why the interposer should decode memory rather than ports).
- `docs/virtual-peripherals-block-diagram.md` §1 (the three taps), §2 (the
  window), §3 (the port strategy).
- `research/boot-screen/` — the authored art, and its authoring rules.
- Measured 2026-10-15 in `osborne1nx`: the BIT 9 polarity and the attribute
  array's content, the latch's ~150 set/clear pairs in the first second, and the
  window's state at the sign-on. Scratch harnesses in `/tmp/md10-11/`
  (`bit9-probe.lua`, `bit9-probe2.lua`, `latch3.lua`).

