# tools/picoem-bridge — the host half of the picoem bridge (#286, part of #192)

A Rust process that **owns an `rp2350-emu` instance** and answers the bus cycles
MAME's `osborne1nx` sends it. It is the host side of the wire described in
`docs/picoem-bridge.md`, which is also where the finding lives — read that first.

```
  osborne1nx (MAME)                    picoem-bridge (this process)
  +--------------------+               +------------------------------+
  | Z80 OUT/IN 30h-33h |               | rp2350-emu, one Emulator     |
  |  tap -> 24-byte    |--> in FIFO -->|  gpio_external_* = the Z80   |
  |  frame             |<- out FIFO <--|  gpio_out/oe  = the answer   |
  +--------------------+               +------------------------------+
```

## Why this is not in Python

`tools/` is Python stdlib only (AGENTS.md), and this is the exception, written
down here and in `tools/README.md`: the thing being driven is a Rust library, and
the only way to own an `rp2350-emu` instance is to link it. Nothing else in this
crate is unusual — two dependencies, both of them deliberate:

- `libc`, for `mkfifo(3)`.
- `rp2350-emu`, **pinned to a fork commit**. picoem is a personal research project
  whose issue tracker is **disabled** (the API reports `has_issues: false`) and
  which **refuses pull requests** (`CreatePullRequest` returns a permissions
  error; the REST endpoint returns 404), so upstream contribution is closed
  rather than merely slow. We pin and re-pin deliberately rather than tracking
  `main`, and the two decode fixes that stock SDK firmware needs live in a fork —
  `tools/emulator-setup/picoem/` carries them as a patch, with the measurements.
  The commit, the reason and the re-pin procedure are in `REQUIREMENTS.md`.

## Build and run

```sh
cargo build --release

# the whole acceptance, with no MAME in it
./target/release/picoem-bridge \
    --flash ../../firmware/picoem-smoke/build/picoem-smoke.bin \
    --bootrom "$HOME/Documents/O1NEXT/picoem-286/roms/rp2350/bootrom-combined.bin" \
    --self-test

# or serve the machine
./target/release/picoem-bridge --flash … --bootrom …
```

`cargo test` runs the frame-format tests and a real FIFO round trip; that is the
check CI runs (`.github/workflows/picoem-bridge.yml`), and it needs no MAME, no
SDK and no firmware.

## The flags that matter when something goes wrong

| flag | what it is for |
|---|---|
| `--self-test` | boot the firmware, drive one write and one read, print what the chip drove **and how long it took**, exit 0 only if the round trip worked |
| `--assert-cycles N` | the cycle budget the personality declares: every transaction's answer time is asserted against `N`, and the process exits non-zero if any is outside (#293, `docs/emulation-testbed.md` §7) |
| `--trace-fault` | one instruction per step until the core latches a fault; prints the faulting PC, the fault registers and the last 24 PCs |
| `--via-bootrom` | the path that does not work yet (picoem's bootrom boot is broken at the pinned commit), kept testable |
| `--frames N` | answer N requests and exit |
| `RUST_LOG=debug` | picoem's own diagnostics; `warn` is the default and already shows every unmodelled MMIO access |

## The cycle budget (#293)

Every transaction reports **how long the firmware took to answer** — the cycles from
the strobe going low to the first heartbeat edge. It is logged as `ans=` on each
transaction line, printed by `--self-test`, and summarised (min, max, mean) at the
end of a run; `--assert-cycles N` turns the declared budget into an exit code. That
is the second half of `docs/emulation-testbed.md` §7's definition of
emulation-complete, and the number itself is the personality's
(`ACB4000_CYCLE_BUDGET` in `firmware/acb4000-scsi/acb4000.h`).

**The resolution is picoem's, not this code's.** `Emulator::run` runs whole quanta
and `DEFAULT_STEP_QUANTUM` is **64 cycles**, so 64 is the smallest answer that can be
measured at all — and `--cycles 20000` really advances 20 032, because the phase is
quantised too. Measured 2026-10-19 through the smoke firmware, in `--self-test` and
through MAME: **one quantum**, at every phase length from 64 to 20 000.

`src/chip.rs` carries the finding — what the crate exposes, what it does not, and
why the process owns the chip instead of MAME holding a handle to it.
