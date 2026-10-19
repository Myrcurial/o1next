# The emulation testbed — MAME, picoem, and the RP2354B firmware (#192)

**Status: the loop closes.** A real RP2354B firmware binary runs in `picoem`;
`osborne1nx`'s I/O cycles reach its pins; and **the guest reads the answer** —
`picoem-guest-check.sh` runs a Z80 `OUT`/`IN` pair in the card's window and
asserts the byte the firmware drove, read back out of the guest's own memory
(12 PASS / 0 FAIL). This document is the single place that says what the testbed
is, what is missing from it, who owns each missing piece, and what "done" means
for each one.

It is also the **gap register** for both emulators. Two lists existed before this
document and neither was complete: `docs/picoem-bridge.md` §5 has the picoem
gaps, `docs/mame-emulation.md` §7 has MAME's open items, and several of the
statements in both are stale relative to the code. §4 is the one list.

**The child documents, and the relationship.** This document owns the *loop*, the
gap register and the plan. It does not restate measurements that live elsewhere:

| Document | Owns |
|---|---|
| `docs/picoem-bridge.md` | the **wire** — the frame, the FIFO, the bus cycle, and the seven picoem gaps as they were found |
| `docs/osborne1nx-machine.md` | the **machine** — the widened I/O decode, the ACB-4000 host adapter, the `softrom` window |
| `docs/mame-emulation.md` | running the stock Osborne machines, and the disk/ROM matrix |
| `docs/image-library-design.md` | the library's layout and media decision (#283, #285) |
| `docs/rom-pico-protocol.md` | the ROM↔Pico door, and the two doors' addresses |
| **this document** | **the loop, the gap register, the plan, and what cannot be emulated at all** |

Where this document corrects one of them, the correction is marked, and the child
document keeps its own measurement.

## 1. What the testbed is

Two emulators model two halves of one board, and one wire joins them:

```mermaid
flowchart LR
    subgraph MAME["osborne1nx / osborne1nxp (MAME 0.289 + the patch)"]
        Z80[Z80 / ROM / video / floppy]
        CARD["acb4000_host_adapter_device<br/>(C++ stand-in, the oracle)"]
        SOFT["softrom_device<br/>(the ROM window, from a file)"]
        LINK["picoem_link_device<br/><b>Gate A, landed</b>"]
    end
    subgraph PICOEM["picoem-bridge (Rust, owns one Emulator)"]
        CHIP["rp2350-emu<br/>the RP2354B"]
        FW["the firmware"]
    end
    Z80 --> CARD
    Z80 --> SOFT
    Z80 -->|"IN returns the firmware's byte"| LINK
    LINK <-->|"24-byte frames over a FIFO pair"| CHIP
    CHIP --- FW
```

The window has **one owner at a time**, and that is a machine in MAME rather than
a switch: `osborne1nx` hands `30h`–`33h` to the C++ card, and `osborne1nxp` hands
it to `picoem_link_device`. Two machines is how MAME says "the same hardware,
wired differently", and it means the card's own acceptance is untouched.

The wire is built and it passes: `tools/emulator-setup/mame-osborne1nx/picoem-check.sh`
reports **7 PASS / 0 FAIL**, driving `W30=A5, R30, W31=5A, R31` and getting the
firmware's bytes back with a heartbeat edge count. `docs/picoem-bridge.md` is that
work, and §2 of it is the measurement that the channel is a **FIFO pair, not a
socket** (MAME's Lua preloads exactly four modules and `3rdparty/` has no
luasocket).

**And the loop closes.** `picoem-guest-check.sh` reports **12 PASS / 0 FAIL**: it
pokes an 11-byte routine into the guest's RAM, sets the PC, and the Z80 runs

```
DI / LD A,A5h / OUT (30h),A / IN A,(30h) / LD (4020h),A / HALT
```

against the firmware — then reads `4020h` back **through the guest's own program
space**. Nothing on the harness side can fake that: a device that returned the
wrong byte, or nothing, fails. It runs the routine on three ports, because a
device that forgot to reconstruct the 8-bit port from MAME's window-relative
offset would pass on `30h` alone and be wrong everywhere else — which is exactly
what happened, and how it was caught.

## 2. The four things that are not real

"Fake" is the right word for some of this and not for the rest, and the
distinction decides the plan. In order of how real they are:

| | What | State |
|---|---|---|
| **Real** | The firmware's own contracts and logic — the image library, the mailbox engine, the media layer over FatFS | host-tested, in CI (#283, #285) |
| **Real** | The RP2354B's **bus** half in picoem — core, FPU, GPIO/CP0, SIO, PIO, XIP flash, clock tree, NVIC | it works; `osborne1nx`'s cycles reach the pins and the answer comes back |
| **Real, and closed** | The wire | the guest reads the bytes: `picoem-guest-check.sh`, 12 PASS / 0 FAIL (§1) |
| **Not real** | The MAME-side stand-ins: `acb4000_host_adapter_device` is a C++ re-implementation of the ACB-4000, and `softrom_device` answers the ROM door out of a file | both are *good* — the card was read out of the driver and four handshake bugs were found against it — but they are not the firmware |
| **Not real, and named as such** | The storage **transports**. `#285` delivered FatFS, the seam and three real FAT volumes; the SPI flash, microSD and USB devices behind `blockdev.h` do not exist, in emulation or on a board | this is the "fake storage" of the last few sessions, and §4.3 decides what to do about it |

## 3. Four corrections to what the tree currently says

These are the most valuable output of the survey that produced this document,
because three of them are places where a document or an issue is **stale relative
to the code**, and one of them changes the plan.

### 3.1 picoem's issue tracker is **disabled**, and PRs against it are refused

**Corrected 2026-10-18.** This section previously said the tracker had "never had an
issue filed — 0 open and 0 closed, for all time". That was an **inference from a
disabled feature written down as a fact**: the GitHub API reports
`has_issues: false` on `0x4D44/picoem`, so the Issues feature is switched off and
the `0 open / 0 closed` count says nothing at all about the project's history.
Nobody could have filed one.

The same check turned up the second half, which is the stronger fact: **a pull
request cannot be opened against it either.** Measured:

```
gh pr create --repo 0x4D44/picoem --base main --head Myrcurial:…
  -> GraphQL: Myrcurial does not have the correct permissions to execute
     `CreatePullRequest`

gh api repos/0x4D44/picoem/pulls -X POST …
  -> 404 Not Found
```

and the repository grants `pull` but not `push` to a third party. So upstream
contribution is not a route that is merely slow or unread — it is **closed**, and
the fix that came out of this work went onto a fork as a result
(`Myrcurial/picoem` #1, open and deliberately unmerged).

Its `CONTRIBUTING.md` says, verbatim: *"I'm happy to look at issues and pull
requests, but I'm not making any commitments about response times, triage, or
whether things will get merged or fixed. If you need certainty around a fix or
feature, the safest path is to fork."* — which is the advice the repository's own
settings then enforce.

**So "document the gap upstream" is not a strategy, and neither is "send a PR".**
The community-useful artifact is a patch series this project owns — and the
repository already has exactly that pattern for exactly that reason:
`tools/emulator-setup/mame-osborne1nx/osborne1nx.patch` is a 1210-line patch to a
source tree we do not own. `tools/emulator-setup/picoem/` is the second one.

### 3.2 Upstream `main` **is** the commit we pin

Measured this pass: `git ls-remote origin HEAD` → `8e20a82…`, byte-identical to
the `rev` in `tools/picoem-bridge/Cargo.toml` (2026-06-27, four months old).

**The six switches in `firmware/picoem-smoke/CMakeLists.txt` cannot be waited
out.** `REQUIREMENTS.md`'s re-pin procedure has no candidate, so every gap in §4.2
has to be fixed, forked around, or documented as permanent.

### 3.3 "UART, SPI, I2C, DMA and timers are stubs" is stale — and the real gap is different

`#192`'s plan comment and `firmware/library/README.md` both say the storage path
*"can never be exercised in the emulator"* because those peripherals are stubs.
That came from picoem's README status table. **The code at the pinned commit says
otherwise**, and the difference matters because it moves the work:

| File | Lines | What is actually there |
|---|---|---|
| `peripherals/spi.rs` | **610** | a real PL022: TX/RX FIFOs, `SSPSR` TFE/TNF/RNE/RFF/BSY, baud-rate `tick()`, loopback (`LBM`), DMA DREQs, IRQ routing |
| `peripherals/uart.rs` | **1040** | FIFOs, `UARTIFLS` thresholds, DREQs, drain cadence, loopback |
| `dma.rs` | **2616** | channels, DREQ matrix, `needs_tick()`/`tick_dma`, IRQ routing — with *named* exclusions (BSWAP, two-tier priority, CRC sniff, DMA-to-DMA narrow) |
| `peripherals/timer.rs`, `i2c.rs`, `pwm.rs`, `adc.rs` | — | wired into `Bus` and **ticked** in `tick_peripherals()` |
| `peripherals/io_bank0.rs` | **331** | 48 pins, `GPIOn_CTRL`/`STATUS`, INTR/PROCE/PROCF groups — **plain storage** |

So the storage path is not blocked by a missing SPI. It is blocked by two things,
and the first is stated by picoem's own module doc:

> `GPIOn_CTRL` … plain-storage 32-bit word covering FUNCSEL, OUTOVER, OEOVER,
> INOVER, IRQOVER … **No active pin routing** — peripherals do not drive pin state
> through FUNCSEL in V5.

confirmed in `Emulator::update_gpio()`: the merged pin word is SIO + PIO +
external stimulus, and **`FUNCSEL` is never consulted**.

- **There is no pad mux.** A firmware that configures SPI and writes `SSPDR` gets
  a TX FIFO that drains into the void. This is *one layer*, and every transport
  needs it.
- **There is no device behind any peripheral.** Loopback is the only thing SPI can
  talk to: no microSD, no W25Q, no USB stick.
- **There is no USB controller model at all** on the RP2354B — only clock-tree
  entries (`CLK_USB_CTRL/DIV/SELECTED`, `PLL_USB`). TinyUSB host MSC for the USB
  stick medium is the largest single piece in this document, and §4.3 argues it
  should never be built.

**And a fidelity gap worth recording on its own:** because `FUNCSEL` is not
enforced, PIO and SIO drive pins *regardless of the mux*. That is precisely why
the smoke firmware works, and it means **pin mis-configuration and pin conflicts
are invisible in emulation**. A personality that passes in picoem can still be
wrong on silicon because two functions share a pad. That is a known
**false-negative source**, not a bug.

### 3.4 The picoem gap list was seven rows and two fixes were missing from it

`docs/picoem-bridge.md` §5 lists seven gaps and then proposes a five-item patch
list, of which item 1 is *"re-derive `cp0_mcr_mrc_family`'s table from
`hardware/gpio_coproc.h`"*. That is **necessary and not sufficient**: the SDK's
`gpio_put()` and `gpio_set_dir()` are not MCR/MRC at all. They are **MCRR**:

```c
static inline void gpio_put(uint gpio, bool value)   { gpioc_bit_out_put(gpio, value); }
static inline void gpio_set_dir(uint gpio, bool out) { gpioc_bit_oe_put(gpio, out); }
/*   gpioc_bit_out_put -> mcrr p0, #4, gpio, value, c0
     gpioc_bit_oe_put  -> mcrr p0, #4, gpio, out,   c4  */
```

and picoem had **no CP0 MCRR dispatch at all**. So the two most-used GPIO calls in
any firmware were silent NOPs, and re-deriving the MCR/MRC table alone would have
left them that way. Both fixes are now in
`tools/emulator-setup/picoem/rp2350-coproc-and-exclusive.patch` — see §4.2 and
that directory's README.

## 4. The gap register

One row per gap: what the emulator does, what it costs, the measurement, the fix,
and who owns it. Sizes are **estimates**, and marked as such; everything else is
measured or read from a source.

### 4.1 MAME-side — ours, no upstream dependency

| # | Gap | Cost | Size (est.) | Blocked on |
|---|---|---|---|---|
| **M1** | ~~The guest cannot read the firmware's answer~~ | — | — | **LANDED (Gate A)** — `picoem_link_device` plus the `osborne1nxp` machine, `picoem-guest-check.sh` 12 PASS / 0 FAIL |
| **M2** | **Memory cycles are refused.** The frame carries `addr` but v1 does not drive the address bus (`status` 2) | the ROM window and the Drive C mapping are memory-mapped, so #179 and the ROM door need this | medium | M3, and the personality that needs it |
| **M3** | **One byte per cycle.** `MODE SELECT`, the CDB and the data phase need a burst or a window | a real SCSI transfer cannot be modelled | small–medium — the frame's `addr` and `cycles` fields are the seam | M1, which has landed |
| **M4** | **No staged test machine.** `stage.sh` copies the binary, ROMs and launcher into one directory; the picoem-backed machine has no such stage | "boot the emulated interposer and play" is a hand-built command line | small | #295 |
| **M5** | **The address never reaches the firmware.** The frame carries `port` and `addr`, and the *bridge* knows both — but the personality sees only the data bus and the four strobes, so it cannot tell **which register** a cycle is for. On Rev B the low bits are reachable only through the **165 snapshot chain**: the 688 gives `ADDR_HIT` for a *window* (`30h`–`33h`), not for a register | **no register-selected personality can be written at all** — #179 is base `30h`, four registers (`docs/acb4000-host-adapter.md` §1), and every personality with a port block is the same shape | **the board decides it, and it is not free**: 48 of 48 GPIO are allocated and `GP12–19` is HSTX. Three fits, and the trade is in #303 | **#303** (the decision) then **#304** (the model) |

### 4.2 picoem-side — a fork, because there is no tracker

| # | Gap | Cost | Size (est.) | State |
|---|---|---|---|---|
| **P1** | **CP0's MCR/MRC table is transposed, and MCRR is not decoded.** `gpio_set_dir` and every `set`/`clr`/`xor` were silent NOPs | the firmware runs and drives nothing | — | **FIXED** — `tools/emulator-setup/picoem/` |
| **P2** | **`LDAEX`/`STLEX` not decoded**, so an unhandled `LDAEXB` executed `LDRD {Rt, pc}` and the core loaded its PC out of the lock byte it was reading | any firmware that claims a hardware resource dies | — | **FIXED** — same series |
| **P3** | **Every UsageFault is reported as `UFSR.UNDEFINSTR`**, so a disabled coprocessor arrives looking like a bad opcode at a bootrom address | cost a full hour of the #286 session | **trivial** — report `NOCP` vs `UNDEFINSTR` | open |
| **P4** | **SIO is bank 0 only** — no `GPIO_HI_OUT`/`GPIO_HI_OE`, so GP32–47 can be neither driven nor observed | Rev B needs GP38/39 (the ESP32 UART) and GP47 (the debug LED) | small — `Bus` already has `gpio_external_mask_hi` and PIO already samples the high bank, so it is the SIO register file that is short | open |
| **P5** | **No pad mux.** `FUNCSEL` is stored and never consulted (§3.3) | no peripheral can reach a pin; pin conflicts are invisible | medium | open |
| **P6** | **No device behind any peripheral.** No microSD, no W25Q, no USB stick; SPI has loopback only | the transports cannot be exercised | medium (NOR + microSD) / **large** (USB MSC, and no controller model exists) | P5 |
| **P7** | **The bootrom boot path does not complete** — `___step4_init_rcp_seeds`'s `rcp_iequal` mismatch; upstream's own `test_flash_boot_blinky` is `#[ignore]`d for it | nothing boots through the mask ROM; the bridge starts at the image's vector table | **unknown** — CP7 ancillary-state parity with silicon | open, and **not on the critical path** |
| **P8** | **No HSTX**, so no display output | #277 (the RP2354B as the display) is gated on it | medium | open, and also a design question (#264) |

### 4.3 The storage question, decided

`#288` is "the board storage transports and the NOR flash FTL", and it is
**hardware-gated as one lump**. That is wrong, and the difference is worth an
order of magnitude of effort:

- **The FTL is not hardware-gated.** Its four properties — a program only clears
  bits, no sector is rewritten in place, a power cut between any two operations
  leaves a mountable volume, erases are spread — are provable **on the host**,
  against a `nor` that enforces NOR semantics, which is exactly what `#288` says.
  Emulation adds little: it would prove the *transport*, not the FTL. **Do it
  host-first.**
- **The transports are hardware-gated, and now for a named reason**: no pad mux
  (P5) and no device behind SPI (P6).
- **The USB stick medium is permanently hardware-only.** There is no USB
  controller model on the RP2354B in this crate, and building one to test a
  file-copy path is not a trade worth making. Record it as a decision, not as a
  gap.

## 5. The path

Six gates, in dependency order, each with a checkable definition of done.

### Gate A — close the loop (MAME-side; no upstream dependency)

**Landed and measured.** `picoem_link_device`
(`tools/emulator-setup/mame-osborne1nx/picoem-link.patch`) owns the FIFO pair and
returns the firmware's byte from its `read()`; the new `osborne1nxp` machine hands
it the window, so the C++ card keeps its own machine and its own acceptance.

- **Done when:** the *guest* reads the firmware's byte. `picoem-guest-check.sh`
  does exactly that — **12 PASS / 0 FAIL** — with the Z80 running its own `OUT`/`IN`
  and the result read back through the guest's program space.
- **Two measurements worth keeping**, because both cost time:
  - MAME hands an address-map handler the offset **relative to the window**, not
    the 8-bit port: a guest `OUT (31h),A` in a `map(30h,33h)` window arrives as
    offset 1. The firmware decodes the full port, so the device reconstructs it
    from the window base — and the check runs three ports, because a device that
    forgot would pass on `30h` alone. That is exactly what happened.
  - The machine has to be registered in `src/mame/mame.lst`, or MAME answers
    *"Unknown system 'osborne1nxp'"* with no hint as to why.
- **M3 is still open** (#292): one byte per cycle cannot model a real SCSI
  transfer. It belongs with the first personality that needs it.

### Gate B — the picoem patch set (fork; small, and the criterion is a file)

**P1 + P2** are done, pushed and **measured**. **P3** and **P4** are the next two,
and **P5** only if Gate E wants it.

- **Done when:** `firmware/picoem-smoke/CMakeLists.txt` no longer needs the
  switches it currently needs. **The switch list is the acceptance criterion** —
  that is the elegant part of the existing design and it should be stated as
  such.

**P1 and P2 are through that gate.** Three of the six switches are gone —
`PICO_USE_GPIO_COPROCESSOR`, `PICO_RUNTIME_SKIP_INIT_DEFAULT_ALARM_POOL` and
`PICO_TIME_DEFAULT_ALARM_POOL_DISABLED` — and the firmware still runs, measured
through `picoem-bridge --self-test` (which needs no MAME):

```
with the switches:   settled -> pc=0x1000024a  sio_oe=0x07000000   echo ok  heartbeat ok  => PASS
without them:        settled -> pc=0x10000260  sio_oe=0x07000000   echo ok  heartbeat ok  => PASS
```

`sio_oe` being non-zero is the point: those bits are set by `gpio_set_dir`, which
goes through **CP0** — the path that used to drop them.

What is left is the bootrom's own three, which are **one** gap (P7) and not three.

- **The end state worth naming:** *a stock Pico SDK binary runs unmodified.* One
  file, falsifiable, and it is the whole of "can a personality be developed
  here".

### Gate C — the first personality, diffed against the stand-in

Build **#179**'s ACB-4000 personality on `firmware/library/` and run the same
guest against MAME's `acb4000_host_adapter_device`.

- **Done when:** the MD-10 system that already boots in `osborne1nx` reaches the
  same outcome with the cycles answered by the real firmware, **and the two bus
  traces agree**. The C++ card stops being the thing under test and becomes the
  **oracle** — unusually strong, because it was read out of the driver
  (`docs/osborne1nx-machine.md` §3) and four handshake bugs were found and fixed
  against it.
- **Why #179 first:** it is the only personality with a complete reference
  implementation, a booting system, and a host-tested firmware module already
  written.

**And it is gated on M5, which is a board question rather than an emulation one.** The
ACB-4000 is register-selected, so "the same guest reaches the same outcome" cannot be
reached until the firmware can tell *which register* a cycle is for — and today it
cannot (§4.1, M5). **#303** decides how the board tells it (2–4 bits of register select
on the spare pins, a parallel slice, or the 165 snapshot); **#304** models that decision
in the bridge so that firmware written against it runs on the board unchanged. Writing
the personality before #303 lands is the one thing this testbed exists to prevent: code
that runs in the emulator and not on the board.

### Gate D — retire the stand-ins, one at a time

**M2** (memory cycles), then **#284** (the ROM service C module), so the ROM's
door is answered by firmware instead of `softrom_device`'s C++ implementation.
`softrom_device` stays as the fallback and as the oracle.

- **Done when:** `romservice-check.sh` passes with the door answered by firmware
  in picoem, and `softrom_device` is mounted only when the bridge is absent.

### Gate E — the storage transports, if they are wanted

**P5 + P6**, and only for the NOR flash — where a device model with a
**power-cut injector** does something hardware makes hard. The USB leg is not
built (§4.3).

- **Done when:** the line in §4.3 is recorded in `firmware/library/README.md` and
  on `#288`, so the seam stops implying that all of it waits on a board.

### Gate F — the community artifact

1. **`tools/emulator-setup/picoem/`** — done. The patch series, the script, and
   the measurement behind each fix, in the shape `osborne1nx.patch` already uses.
2. **This document** — the gap register, and the never-emulatable list (§6).
3. **M4** — a `boot-o1next.sh` for the picoem-backed machine, because the repo's
   rule is that when an emulated machine reaches a milestone, the launcher goes in
   beside it.

**Why this is worth more than it looks.** P2 (`LDAEXB` mis-decoded as `LDRD` into
`{Rt, pc}`), P3 (every UsageFault reported as `UNDEFINSTR`) and P1 (the CP0 table
vs SDK 2.3.1) are **not o1next bugs**. Every project emulating an RP2354B and
running stock Pico SDK firmware hits all three. Those three findings, written up
as a patch, are the most generally useful thing this project has produced about
emulation, and they cost an afternoon between them.

## 6. What cannot be emulated, ever

| Not emulatable | Why | Where it belongs |
|---|---|---|
| **Electrical timing** — the Rev B T2 claim (~50 ns PIO response), propagation, bus loading, 74AHCT level shifting, Z80 setup/hold | emulation gives **cycle counts**, not nanoseconds. Neither emulator models a wire | **#29** (Phase 4). The cycle-budget assertion in §7 is the *partial* substitute and must be labelled as one |
| **Bus-cycle timing finer than one quantum** | `Emulator::run` runs whole quanta (`DEFAULT_STEP_QUANTUM`, **64 cycles**), so a firmware that answers in 20 cycles and one that answers in 60 measure the same: one quantum. Measured 2026-10-19 (#293) — see §7 | this document, §7 — the budget is a **bound**, and the floor of the bound is 64 cycles. A budget below that can never be met, which is why the personality's declared number is checked against it |
| **The machine's own wait-state generator, and how it composes with the interposer's** | **MAME omits it.** `o1-mainboard-schematic.md` §8 records the wait-state generator on sheet 2/9 (`UC1`, `UC2`, `UD1`–`UD3`) as unmodelled, and `o1-memory-io-map.md` §1 measures what it does: ≈375 ns of wait on non-M1 RAM cycles, 188 ns on the first M1, none on ROM. So the *composition* of the machine's stretch with the interposer's cannot be exercised in the emulator at all | **#29** — and it is hardware-gated **by construction**. It is also the strongest argument for *scheduling* `/WAIT` from the clock phase rather than racing `ADDR_HIT` (**#297**): the one behaviour a race cannot survive is the one the testbed cannot test |
| **Pin-mux correctness** | `FUNCSEL` is not enforced (P5), so a personality that shares a pad wrongly *passes* | this document, §3.3 — a named **false-negative source** |
| **A real W25Q, SD card, USB stick, ESP32 radio** | quirks, timing, and radio | #288, #21/#56, #29 |
| **A card a PC formatted mounts** | needs a card or a faithful model | #288 |
| **Composite video eject (#264), the physical keyboard, printer mechanics** | analogue / mechanical | #264, #47, #19 |
| **The bootrom boot path** | P7, of unknown size | the gap register, explicitly **not** on the critical path — `Entry::Image` is a legitimate route for a chip with no boot2, and it costs four SDK defines rather than a bootrom fix |

## 7. The acceptance a personality must meet

This is the thing that was missing: a definition of "the firmware works in
emulation" that is automatable and falsifiable, rather than "it seemed to run".

> **A personality is emulation-complete when the same guest reaches the same
> result with its cycles answered by MAME's stand-in and by the real firmware in
> picoem, and the firmware's reported cycle count is inside the budget the
> personality declares.**

Three things make that worth writing down:

- **It converts every existing C++ stand-in into an oracle** instead of a rival.
  The `acb4000_host_adapter_device` is already measured against the real driver;
  diffing against it is stronger than diffing against nothing.
- **It is checkable from data that already crosses the wire.** The reply frame
  carries the chip's cycle count in *every* reply (`docs/picoem-bridge.md` §3),
  which is what makes the second half possible.
- **It answers the timing question honestly.** MAME cannot model nanoseconds and
  neither can picoem — but a cycle budget *is* measurable, so "the firmware
  answered within N emulated cycles" is a real assertion, and "the firmware meets
  T2 on silicon" is not, and stays in #29.

**The second half is built (#293).** The bridge reports, per transaction, the cycles
the firmware took to answer (`ans=`), summarises the worst case at the end of a run,
and asserts it against the number the personality declares: `--assert-cycles`, which
`picoem-check.sh` reads out of `ACB4000_CYCLE_BUDGET` in
`firmware/acb4000-scsi/acb4000.h` rather than repeating it. Measured 2026-10-19, the
smoke firmware answers in **one quantum — 64 cycles**, in `--self-test` and through
MAME, at every phase length from 64 to 20 000.

**And 64 cycles is a floor rather than a speed.** The resolution of the whole loop is
picoem's step quantum (`DEFAULT_STEP_QUANTUM`), because `Emulator::run` runs whole
quanta — so no answer can be measured more finely, and a declared budget below 64
could never be met. The check refuses a budget its own phase cannot exceed, for the
same reason: a bound that cannot be broken is not an assertion.

## 8. Running it

The acceptance that exists today, and what each piece needs:

```sh
# 1. the firmware (needs the Pico SDK, the Arm GNU Toolchain, cmake/ninja/picotool)
firmware/picoem-smoke/build.sh

# 2. the host process (needs Rust; fetches the pinned picoem -- REQUIREMENTS.md)
(cd tools/picoem-bridge && cargo build --release)

# 3. the chip alone, no MAME -- the fastest loop when a firmware misbehaves
tools/picoem-bridge/target/release/picoem-bridge \
    --flash firmware/picoem-smoke/build/picoem-smoke.bin \
    --bootrom "$HOME/Documents/O1NEXT/picoem-286/roms/rp2350/bootrom-combined.bin" \
    --self-test

# 4. the whole loop, driven from Lua -- needs a *patched* osborne1nx
tools/emulator-setup/mame-osborne1nx/picoem-check.sh

# 5. the whole loop, driven by the GUEST -- needs the second patch applied, and
#    gives you the osborne1nxp machine
tools/emulator-setup/mame-osborne1nx/picoem-guest-check.sh
```

`--self-test` is the one to reach for first: it boots the firmware, drives one
write and one read, prints what the chip drove, and exits non-zero unless the
round trip worked. It needs no MAME, which is what makes it usable as a firmware
regression check.

## Sources

- `docs/picoem-bridge.md` — the wire, the frame, and the seven gaps as found.
- `docs/osborne1nx-machine.md` — the machine, the card, and the widened decode.
- `docs/mame-emulation.md` — the stock machines, §7 open items.
- `docs/image-library-design.md`, `docs/mailbox-protocol.md`,
  `docs/rom-pico-protocol.md` — the firmware's contracts.
- `tools/emulator-setup/picoem/` — the patch series carried against picoem, and
  its README.
- picoem at the pinned commit: `README.md` (the status table), `tech_debt.md`,
  `crates/rp2350-emu/src/{core/coprocessor.rs, core/execute_thumb32.rs,
  peripherals/{spi,uart,io_bank0,timer}.rs, dma.rs, lib.rs, sio/mod.rs}`.
- The SDK's own `hardware/gpio_coproc.h` and `hardware/gpio.h` (2.3.1), and the
  Arm GNU toolchain's output for every encoding in the patch.

## Where the *research* gaps live instead

`docs/research-gaps.md` is a different register: it tracks **Phase 0 research
questions** (what a source does not answer). This document tracks **emulation
gaps** (what an emulator does not model). They are not the same list and should
not be merged — a question can be fully answered by research and still
unemulatable, and the reverse.
