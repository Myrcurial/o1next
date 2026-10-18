# The picoem bridge — a real firmware binary inside `osborne1nx` (#286, part of #192)

**Status: it works, and the acceptance passes.** A Pico SDK firmware built from
this tree runs inside `rp2350-emu`; `osborne1nx`'s I/O cycles in the card's
window reach its GPIO; the byte it drives back comes into the machine; and the
whole exchange is in the MAME-side log:

```
picoem: HELLO  status 00  firmware pc=1000024A cycles=40000000
picoem: W 30 <- A5  firmware drove A5  hb=1 HB OE DRV  pc=1000029E
picoem: R 30      firmware drove A5  hb=1 -- OE DRV  (guest saw 00)
picoem: W 31 <- 5A  firmware drove 5A  hb=1 HB OE DRV  pc=1000029E
picoem: R 31      firmware drove 5A  hb=1 -- OE DRV  (guest saw FF)
```

One command proves it: `tools/emulator-setup/mame-osborne1nx/picoem-check.sh`.

**This is one half of a loop, and the loop does not close yet.** What the loop is,
what is missing from it (the guest cannot read the firmware's answer), the gap
register for *both* emulators and the plan for closing them are
**`docs/emulation-testbed.md`** — that document owns the loop; this one owns the
wire.

**And it took six workarounds to get there**, every one of them a gap in picoem
rather than in the firmware. §5 is the list, and it is the most valuable part of
this document: the emulator could not yet run a stock Pico SDK binary, and until
it can, every personality the interposer is for (#179, #277) is being written
against a chip that behaves differently from the real one in specific ways.

**Two of them are fixed** (2026-10-18): #5 (`ldaexb`) and #7 (the CP0 table, which
was also missing the whole MCRR family). The fixes are in
`tools/emulator-setup/picoem/`, the three firmware switches they forced are
retired, and the retirement is measured — see `docs/emulation-testbed.md` §4.2 and
§5 (Gate B). §5 below keeps the original measurements, with the fixed rows marked.

Reads alongside `tools/picoem-bridge/README.md` (the host process),
`firmware/picoem-smoke/README.md` (the firmware), `src/frame.rs` (the frame
format, with the tests that pin it) and `src/chip.rs` (the finding, in the code
where it is used).

---

## 1. The open question, answered

#192 asked: *does `rp2350-emu` expose a public API to observe or drive the
emulated chip's GPIO/PIO/bus from outside the crate?* It does — three of them,
and no patch to picoem was needed for the plumbing:

| Seam | What it is |
|---|---|
| `Emulator::gpio_read(pin)` / `gpio_read_all()` | the merged pin state; a 48-bit word, bank 1 in bits 32..47 |
| `Emulator::bus.gpio_external_in` / `gpio_external_mask` (+ `_hi`, and `Bus::set_gpio_external_in_hi`) | **the external stimulus overlay.** Masked bits of `gpio_in` come from the host instead of from SIO/PIO. This is how the host drives an input pin |
| `Emulator::mmio_read32` / `mmio_write32`, `peek` / `poke` | the memory-mapped peripheral level, for anything the overlay does not cover |

The second one is the one that matters, and it is not advertised as an external
API: `Emulator.bus` is a **public field** and the two stimulus fields are public
on `Bus`. picoem's own OneROM harness uses the same mechanism to drive an address
bus from outside (its HLD "OneROM Serving Oracle Fixture Generalization" drives
A0..A2 through `set_gpio_external_in_hi`), which is the precedent.

Two things are **not** there:

- **`Emulator::gpio_write(pin, value)` is a no-op stub** in the pinned commit —
  `pub fn gpio_write(&mut self, _pin: u8, _value: bool) {}`. Anything that trusts
  the name instead of reading the body will spend an afternoon wondering why its
  stimulus does nothing.
- **`Bus::gpio_external_mask` is a plain `u32`, not an atomic**, so it is written
  through `&mut Emulator` while `gpio_external_in` is atomic. Fine for a process
  that owns the chip and steps it single-threaded; not fine for a design that
  steps on one thread and pokes pins from another. That is the reason the bridge
  is a **process that owns the emulator** rather than a device inside MAME.

**Reading the answer needs one more step, and it is easy to get wrong.** The
overlay masks bits of `gpio_in`, so while the host is driving the data pins,
`gpio_in` holds the *host's* byte and the chip's answer is invisible there.
`Chip::merged_out()` recomputes the word the chip is *driving* — SIO
`gpio_out & gpio_oe`, with each PIO block's `pad_out & pad_oe` overlaid — from
public fields only, exactly as `Emulator::update_gpio` does internally. That is
the measurement.

## 2. The channel is a pair of FIFOs, not a socket

#192's option 3 says "a socket/pipe protocol", and the pipe is **not** a socket
here. That is a measurement, not a preference:

- **MAME's Lua has no socket library.** `src/frontend/mame/luaengine.cpp`
  preloads exactly four modules — `zlib`, `lfs`, `linenoise`, `lsqlite3` — and
  `3rdparty/` has no luasocket at all. Measured on MAME 0.289, the tree this
  project patches.
- The alternatives are both **changes to MAME**: vendor luasocket into it (a
  change to its Lua surface, and the single thing most likely to get the
  `osborne1nx` patch refused upstream), or write a C++ device that opens a real
  socket (a second patch to the same tree, and a rebuild).

A FIFO costs neither. Lua's `io` can open a path, and a FIFO opened `O_RDWR` by
both ends is a blocking byte stream with no open-order deadlock — the semantics a
socket would have given, without the socket. And **blocking is not a
compromise**: the ACB-4000 needs the Z80's cycle *answered before it continues*,
which is exactly what a blocking request/response gives and a frame-quantised
socket would not.

**The one hazard, stated:** a blocking read on a FIFO never returns if the peer
dies. The bridge holds both ends open for the life of the run, so a MAME that
exits frees the bridge, but a bridge that exits leaves MAME blocked until it is
killed. `picoem-check.sh` kills both on every exit path, and `--frames N` gives
the bridge a way to finish on its own.

## 3. The frame

24 bytes each way, fixed length, with a magic and a checksum — the transport is a
byte stream with no message boundaries, so a reader that has drifted must be able
to *see* that it has. `src/frame.rs` is the reference copy; `o1next-picoem.lua`
is the Lua copy; the Rust tests pin the layout.

Request (MAME → bridge):

| off | size | field |
|---|---|---|
| 0 | 4 | magic `"O1B1"` |
| 4 | 1 | `op`: 0 HELLO, 1 BUS_WRITE, 2 BUS_READ |
| 5 | 1 | `flags`: bit0 0 = I/O cycle, 1 = memory cycle |
| 6 | 1 | `port` |
| 7 | 1 | `data` — the byte the Z80 drove |
| 8 | 2 | `addr` u16 LE (memory cycles) |
| 10 | 2 | `seq` u16 LE, echoed back |
| 12 | 4 | `cycles` u32 LE for this transaction; 0 = the bridge's default |
| 16 | 4 | reserved |
| 20 | 2 | checksum u16 LE = sum of bytes 0..19 |
| 22 | 2 | reserved |

Reply (bridge → MAME):

| off | size | field |
|---|---|---|
| 0 | 4 | magic `"O1B1"` |
| 4 | 1 | `status`: 0 OK, 1 no firmware running, 2 bad request |
| 5 | 1 | `data` — the byte the chip drove on GP0–GP7 |
| 6 | 1 | `hb` — GP26 edges during the transaction; **1 = the firmware handled it** |
| 7 | 1 | `flags`: bit0 GP26 level, bit1 GP24 (DATA_OE), bit2 GP0–GP7 driven |
| 8 | 2 | `addr` echo |
| 10 | 2 | `seq` echo |
| 12 | 4 | `pc` — the firmware's PC after the transaction |
| 16 | 4 | `cycles` — the emulated chip's total cycle count |
| 20 | 2 | checksum |
| 22 | 2 | reserved |

`pc` and `cycles` are in **every** reply rather than in a HELLO exchange only:
"the firmware is running" is the first thing that goes wrong and the hardest
thing to see from the MAME side, and two fields cost nothing.

**Only I/O cycles are modelled.** A memory cycle is *refused* (`status` 2) rather
than answered wrongly: the frame carries the address, but v1 does not drive the
address bus. The ROM window is memory-mapped, and that is what #179's growth
needs.

## 4. The bus cycle, and the two ways it is easy to get wrong

`Chip::bus_write` / `bus_read` drive the Rev B control strobes as external
stimulus and read the chip's answer from `merged_out()`:

- **write** — phase A: `/IORQ` and `/WR` low, the data pins masked to the Z80's
  byte. Phase B: every strobe released, the data pins handed back to the chip.
- **read** — `/IORQ` and `/RD` low, data pins *not* masked (the chip owns them).

Two mistakes cost real time here, and both are now in the code as comments:

1. **The idle state has to be *driven*, not left alone.** An undriven pin reads 0
   in picoem exactly as it does on a board with no pull-up, and 0 is *asserted*
   for `/MREQ`, `/IORQ`, `/RD` and `/WR` — every one of them active low. A bridge
   that leaves the pins floating presents the firmware with a write cycle that
   never ends, and the firmware sits in its `/WR` release loop forever. Measured:
   PC 0x100002d8, no fault, no bus activity — which looks exactly like a firmware
   bug and is not. On Rev B the board's pull-ups do this job.
2. **Sample the answer while the strobe is open**, not after it closes. A first
   version ran phase B first and then read: the firmware had already released the
   bus and the answer was gone — `data 00`, `flags 00`, on a firmware that was
   working perfectly.

## 5. The picoem gaps — the real finding

**A stock Pico SDK binary did not run in picoem at the pinned commit.** It was not
one bug; it was seven, in a chain, and each one had to be worked around before the
next appeared. Every one is measured, and the measurement is in the log or in the
code.

| # | Gap | Where it bites | Worked around by | State |
|---|---|---|---|---|
| 1 | The **bootrom boot path does not complete** | nothing boots through the mask ROM | start at the image's own vector table (`Entry::Image`) | open |
| 2 | **CPACR is never enabled** (the bootrom does it) | the SDK's *first* initializer calls the ROM's `reset`, whose first instruction is `mrc2 p7, …` → UsageFault | `Chip::new` enables CP0–CP7, CP10/CP11 | open |
| 3 | **every UsageFault is reported as `UFSR.UNDEFINSTR`** | #2 reads as a bad opcode, not a disabled coprocessor | nothing — a diagnostic trap, recorded here | open |
| 4 | `runtime_init_bootrom_locking_enable` **polls `0x400E0828` forever** | the firmware spins in the SDK's own init | `PICO_RUNTIME_SKIP_INIT_BOOTROM_LOCKING_ENABLE` | open |
| 5 | **`ldaexb` is mis-decoded as a load/store dual** | the core loads PC from memory and jumps to garbage | `PICO_RUNTIME_SKIP_INIT_DEFAULT_ALARM_POOL` | **FIXED** — `tools/emulator-setup/picoem/` |
| 6 | **SIO is GPIO bank 0 only** | GP32–47 can be neither driven nor observed | keep the heartbeat in bank 0 (GP26) | open |
| 7 | **CP0's encoding table does not match SDK 2.3.1 — and there is no CP0 MCRR dispatch at all** | every `gpio_set_dir` is a silent NOP; `gpio_get_all` reads the wrong register; **`gpio_put` and `gpio_set_dir` are MCRR and were not decoded at all** | `PICO_USE_GPIO_COPROCESSOR=0` | **FIXED** — same series |

**Row 7 was understated when it was written.** This section's own patch list
(§"What a picoem patch would have to do") says *"re-derive `cp0_mcr_mrc_family`'s
table from `hardware/gpio_coproc.h`"*, and that is **necessary and not
sufficient**: the SDK's `gpio_put()` is `gpioc_bit_out_put` (`mcrr p0, #4, gpio,
value, c0`) and `gpio_set_dir()` is `gpioc_bit_oe_put` (`mcrr p0, #4, gpio, out,
c4`) — a *different encoding family*, and picoem had no CP0 MCRR dispatch at all.
Re-deriving the MCR/MRC table alone would have left the two most-used GPIO calls
in any firmware as silent NOPs. `docs/emulation-testbed.md` §3.4 is the record.

### 1 — the bootrom never finishes

picoem's own `crates/rp2350-emu/src/tests.rs::test_flash_boot_blinky` is
**`#[ignore]`d** at the pinned commit, and its reason is the finding:

> the bootrom's first `rcp_iequal` mismatch occurs at `PC=0x000039b6` inside
> `___step4_init_rcp_seeds` (bootrom) … our CP7 ancillary state (canary flag
> semantics, count-sequence invariants) doesn't exactly match silicon.

Reproduced here: 40 M cycles of settle leaves the PC at `0x000003ee`, inside the
mask ROM, forever. So the bridge starts the core at the **image's own vector
table** — which is what the bootrom would have done, word for word, because an
image for this chip begins with the vector table at offset 0 (there is no boot2
stage). `--via-bootrom` keeps the real path reachable, so that the day the CP7
work lands "does it boot through the bootrom yet?" is one flag.

### 2 — CPACR, and 3 — the fault that lies about itself

With the bootrom bypassed, `CPACR` is still 0. The SDK's first runtime
initializer is `runtime_init_bootrom_reset`, which does
`rom_func_lookup(0x5253)` and calls the ROM's `reset` function — and that
function's first instruction is:

```
0000008c:  fe16 373c    mrc2  p7, 0, r3, cr6, cr12, {1}
```

A CP7 access with the coprocessor disabled is a UsageFault, and picoem sets
**`UFSR.UNDEFINSTR` for every UsageFault** (`core/exceptions.rs`). So the failure
arrives as `CFSR=0x00010000` at a bootrom address and reads as "undefined
instruction". It is not: the opcode is fine, `CPACR` is the problem. That cost an
hour, and it will cost the next reader the same hour unless it is written down.
The bridge now enables CP0–CP7 and CP10/CP11 before entering the image.

### 4 — the boot lock that only the bootrom sets

`runtime_init_bootrom_locking_enable` is three instructions:

```
10000e3a:  ldr.w  r3, [r2, #2088]   ; r2 = 0x400E0000, so 0x400E0828
10000e3e:  cmp    r3, #0
10000e40:  beq.n  10000e3a          ; spin until it is non-zero
```

Only the bootrom ever writes it. Measured: the PC pinned at `0x10000e3e` for
200 M instructions, no fault, no bus activity.

### 5 — `ldaexb`, mis-decoded as a load/store dual

The SDK's `hw_claim_or_assert` → `next_striped_spin_lock_num` uses
`ldaexb`/`strexb`. picoem implements `LDREX`/`STREX`/`LDREXB`/`STREXB` but **not
the acquire/release forms**, and the Thumb-32 dispatch classifies `LDAEXB`
(`hw0 = 0xE8Dx`, `hw1[11:4] = 0xC`) as `thumb32_load_store_dual`. Its `Rd` field
is 15, so the emulator performs an `LDRD` into **`{r2, pc}`** — and the core jumps
to the halfword it read out of the spinlock byte:

```
PC  0x1000041e (ldaexb r2, [lr])
 -> 0x00000000, then 0x00000002, 0x00000004 …  (the mask ROM's vector table,
    executed two bytes at a time)
 -> a precise BusFault (CFSR=0x00008200), forced to HardFault (HFSR=0x40000000)
```

The firmware that hits it is not exotic: `runtime_init_default_alarm_pool` claims
a hardware alarm. **Any** firmware that claims a PIO block, a DMA channel or an
alarm goes through the same path. `--trace-fault` is the tool that found it.

### 6 — SIO is bank 0 only

`Sio` has `gpio_out` and `gpio_oe` and **no `GPIO_HI_OUT` / `GPIO_HI_OE`**, and
`update_gpio` composes `gpio_in_hi` from PIO outputs alone. So GP32–GP47 can be
neither driven nor observed through SIO. That matters to this project: the Rev B
map puts **GP38/39 on the ESP32 UART** and **GP47 on the debug LED**, and both
are in bank 1. The smoke firmware's heartbeat therefore sits on **GP26** — the
595/165 shift fabric's `SR_SCK`, borrowed — rather than on the Rev B map's spare
GP37, because a heartbeat that toggles on hardware and is invisible in the
emulator proves nothing.

### 7 — the GPIO coprocessor, which is the big one

The SDK's GPIO access goes through CP0 (GPIOC) by default, and the two sides
disagree about the encoding:

```
the SDK emits   mcr p0, #<op>, Rt, c0, c<reg>      (hardware/gpio_coproc.h)
                op  0=put 1=xor 2=set 3=clr
                CRn is always c0; CRm selects the register:
                c0 = LO OUT, c1 = HI OUT, c4 = LO OE, c5 = HI OE

picoem reads    opc1 as the *bank* (OUT/OE/IN), and treats (CRn,CRm) as
                "bulk if (0,0), else the pin number (CRn<<4)|CRm"
```

So `gpioc_lo_oe_xor(x)` — `mcr p0, #1, r, c0, c4` — arrives as *"opc1=1, pin 4,
op 0"*, which picoem's per-bit table does not have, and it is a **silent NOP**;
`gpioc_lo_oe_get()` reads the wrong register. Only the `c0,c0` (LO OUT) forms
work, which is why `gpio_put` half-works and `gpio_set_dir` does not. Measured,
with the switch left at its default: the firmware reached its main loop and
answered nothing, with **`sio_oe = 0` after 40 M cycles**.

The fix is picoem's, and it is small: re-derive `cp0_mcr_mrc_family`'s table from
`hardware/gpio_coproc.h`, where `opc1` is the operation and `CRm` is the
register. Until then the bridge builds the smoke firmware with
`PICO_USE_GPIO_COPROCESSOR=0`, which makes the SDK use the SIO registers directly
— the registers picoem models exactly. **That is a workaround, not a design:**
the coprocessor path is the fast one and the interposer will ship with it on.

### What a picoem patch would have to do

In rough order of value, and none of them large:

1. **`cp0_mcr_mrc_family`: re-derive the table from `hardware/gpio_coproc.h`.**
   Until this lands, no Pico SDK firmware's GPIO works by default.
2. **Decode the acquire/release exclusive forms** (`LDAEX`/`LDAEXB`/`LDAEXH`,
   `STLEX`/`STLEXB`/`STLEXH`) instead of letting them fall into
   `thumb32_load_store_dual`. This is a correctness bug, not a gap: the emulator
   executes an `LDRD` nobody wrote.
3. **Model SIO's high bank** (GPIO_HI_OUT/OE/IN and the CP0 HI banks), so GP32–47
   exist. Rev B needs GP38/39 and GP47.
4. **Report the UsageFault cause** (`NOCP` vs `UNDEFINSTR`) instead of setting
   `UFSR.UNDEFINSTR` for all of them.
5. **The bootrom's CP7 seed path**, which is already tracked upstream by the
   `#[ignore]`d test. Until then `Entry::Image` is the bridge's route.

## 6. Running it

```sh
# once: the two host tools (REQUIREMENTS.md has the pins)
git clone https://github.com/0x4D44/picoem.git "$HOME/Documents/O1NEXT/picoem-286"
git clone --depth 1 --branch 2.3.1 https://github.com/raspberrypi/pico-sdk.git \
    "$HOME/Documents/O1NEXT/pico-sdk-2.3.1"

# the firmware (needs the Arm GNU Toolchain; see REQUIREMENTS.md)
firmware/picoem-smoke/build.sh

# the host process
(cd tools/picoem-bridge && cargo build --release)

# the acceptance
tools/emulator-setup/mame-osborne1nx/picoem-check.sh
```

And by hand, which is what a session debugging a new personality will do:

```sh
# 1. the bridge, in one terminal
tools/picoem-bridge/target/release/picoem-bridge \
    --flash firmware/picoem-smoke/build/picoem-smoke.bin \
    --bootrom "$HOME/Documents/O1NEXT/picoem-286/roms/rp2350/bootrom-combined.bin"

# 2. the machine, in another
SDL_VIDEODRIVER=dummy mame <osborne1nx> -rompath tools/emulator-setup/roms \
    -video none -sound none -nothrottle -seconds_to_run 4 \
    -autoboot_script tools/emulator-setup/mame-osborne1nx/o1next-picoem.lua

# 3. or just the chip, with no MAME at all
tools/picoem-bridge/target/release/picoem-bridge --flash … --bootrom … --self-test
```

The bridge's own tools, which are the ones to reach for when a new firmware
misbehaves:

| flag | what it is for |
|---|---|
| `--self-test` | no FIFOs, no MAME: boot the firmware, drive one write and one read, print what the chip drove, exit 0 only if the round trip worked |
| `--trace-fault` | one instruction per step until the core latches a fault, then the faulting PC, the fault registers, and the last 24 PCs. **This is how the `ldaexb` bug was found.** |
| `--via-bootrom` | start at the mask ROM's reset vector instead of the image's — the path that does not work yet, kept testable |
| `--frames N` | answer N requests and exit |
| `RUST_LOG=debug` | picoem's own diagnostics; `warn` is the default and already shows every unmodelled MMIO access |

## 7. What is measured, what is guesswork, and what is not done

**Measured** — `picoem-check.sh` passes seven checks, and each of §5's seven gaps
was found by running something and reading the result.

**Guesswork, and it should not be quoted as fact:**

- The **cycles per phase** (20000) are generous rather than derived. The firmware
  is a polled loop, so the number only has to exceed one loop iteration; nobody
  has measured the emulator's worst-case latency to answer.
- **The `hb` edge count** samples GP26 every 1/32 of a phase. A firmware that
  toggled twice inside one sample would be counted once. For this firmware the
  count is exactly one per cycle, which is the point of it.
- **The 40 M-cycle settle** is likewise generous. It is 0.2 s of wall clock, so
  it costs nothing, and nobody has found the true minimum.
- **The Rev B timing claim** — that the 688's combinational `ADDR_HIT` plus a
  ~50 ns PIO response fits inside T2 — is not tested here at all. This bridge
  models the *bus*, not the timing.

**Not done, and named:**

- **PIO.** The smoke firmware polls GPIO; the pin map's PIO path is what the real
  personality will use, and nothing here exercises a PIO state machine against
  the bus.
- **Memory cycles.** Refused by design (§3). The ROM window and the Drive C
  mapping are memory-mapped, so #179 needs this.
- **The guest reading the answer.** The reply is logged and can be written to a
  guest scratch byte (`O1_PICOEM_SCRATCH`), but the Z80's own `IN` still returns
  the card device's byte, not the firmware's — the read tap deliberately returns
  nothing (a read tap that returns data segfaults once the guest polls in a tight
  loop; `tools/research/acb4000.lua`, GOTCHAS). Carrying the answer to the guest
  belongs to the card's own device.
- **A frame wider than one byte per cycle.** `MODE SELECT`, the CDB and the data
  phase need a burst or a window, not one byte per frame. The frame's `addr` and
  `cycles` fields are the seam for it.
- **#277** (the RP2354B as the display) is unblocked by this bridge in principle
  and untouched in fact: the animation is played out of the RP2354B's flash, and
  the bridge has no HSTX and no display path.


`Chip::bus_write` / `bus_read` drive the Rev B control strobes as external
stimulus and read the chip's answer from `merged_out()`:

- **write** — phase A: `/IORQ` and `/WR` low, the data pins masked to the Z80's
  byte. Phase B: every strobe released, the data pins handed back to the chip.
- **read** — `/IORQ` and `/RD` low, data pins *not* masked (the chip owns them).

Two mistakes cost real time here, and both are now in the code as comments:

1. **The idle state has to be *driven*, not left alone.** An undriven pin reads 0
   in picoem exactly as it does on a board with no pull-up, and 0 is *asserted*
   for `/MREQ`, `/IORQ`, `/RD` and `/WR` — every one of them active low. A bridge
   that leaves the pins floating presents the firmware with a write cycle that
   never ends, and the firmware sits in its `/WR` release loop forever. Measured:
   PC 0x100002d8, no fault, no bus activity — which looks exactly like a firmware
   bug and is not. On Rev B the board's pull-ups do this job.
2. **Sample the answer while the strobe is open**, not after it closes. A first
   version ran phase B first and then read: the firmware had already released the
   bus and the answer was gone — `data 00`, `flags 00`, on a firmware that was
   working perfectly.
