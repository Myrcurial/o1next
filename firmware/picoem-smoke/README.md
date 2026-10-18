# firmware/picoem-smoke — the bridge's smoke firmware (#286, part of #192)

The smallest firmware that can prove the picoem bridge end to end: a Z80 bus
cycle arriving on the interposer's pins, an answer leaving on the same pins, and
both visible from the MAME side. It is **not** a personality — #179 is — and it
is deliberately **not PIO**, because the question it answers is "does a real Pico
SDK binary, built from this tree, run inside picoem and answer the bus?", and a
polled GPIO loop answers that with the fewest moving parts.

## What it is

A **one-byte register**, addressed by the Z80's own I/O strobes. Write a byte and
it latches it; read and it drives the latched byte back out. That is the
ACB-4000's data register in miniature (`docs/acb4000-host-adapter.md`), so the
shape of the firmware is the shape the personality will keep. **GP26 toggles once
per handled cycle** — the liveness signal the bridge counts, so "the firmware saw
the cycle" is a number in the reply frame rather than an inference.

The pins are the Rev B map (`hardware/interposer/revb/README.md`): GP0–7 data,
GP8–11 the control strobes, GP24 `DATA_OE`, GP25 `DATA_DIR`. **GP26 is the
heartbeat and it is borrowed** from the 595/165 shift fabric — see the header
comment in `smoke.c` for why it is not the Rev B map's spare GP37.

## Building it

```sh
firmware/picoem-smoke/build.sh          # -> build/picoem-smoke.bin
```

Two host tools, both pinned in `REQUIREMENTS.md`:

- the **Pico SDK** (2.3.1), from `$PICO_SDK_PATH` or a clone under
  `$HOME/Documents/O1NEXT/`. Submodules are **not** needed — only `pico_stdlib`
  with stdio off is linked.
- the **Arm GNU Toolchain**, from `$PICO_TOOLCHAIN_PATH` or a downloaded official
  toolchain under `$HOME/Documents/O1NEXT/toolchain/`. **Not** Homebrew's
  `arm-none-eabi-gcc` formula, which ships no C library at all and fails at link
  time in a way that reads like a broken linker. `build.sh` checks for the libc
  and says so.

The board is our own (`board/o1next_interposer.h`): the bare RP2354B, 2 MB of
in-package flash, 48 GPIO, no module and no invented LED pin.

## The six switches, and they are all about picoem

`CMakeLists.txt` carries a long comment for each. In short — **picoem cannot run
a stock Pico SDK binary**, and each of these is a documented gap rather than a
preference:

| define | why |
|---|---|
| `PICO_USE_GPIO_COPROCESSOR=0` | picoem's CP0 encoding table does not match SDK 2.3.1's, so every `gpio_set_dir` is a silent NOP. **The big one.** |
| `PICO_RUNTIME_SKIP_INIT_BOOTROM_RESET` | calls the ROM's `reset` function, which the bootrom would have set up |
| `PICO_RUNTIME_SKIP_INIT_PER_CORE_BOOTROM_RESET` | the same, per core |
| `PICO_RUNTIME_SKIP_INIT_BOOTROM_LOCKING_ENABLE` | polls `0x400E0828`, which only the bootrom ever sets — **spins forever** |
| `PICO_RUNTIME_SKIP_INIT_DEFAULT_ALARM_POOL` | the claim path uses `ldaexb`, which picoem **mis-decodes as an `LDRD` into `{r2, pc}`** |
| `PICO_TIME_DEFAULT_ALARM_POOL_DISABLED` | the SDK's own way of saying the same thing |

**None of these is what the interposer will ship.** On real silicon the
coprocessor path is the fast one and the bootrom has run. They are here so that
the bridge can prove itself today, and `docs/picoem-bridge.md` §5 lists what
picoem would have to fix to make them unnecessary.

## Testing it

```sh
tools/emulator-setup/mame-osborne1nx/picoem-check.sh   # the acceptance
tools/picoem-bridge/target/release/picoem-bridge --flash build/picoem-smoke.bin \
    --bootrom "$HOME/Documents/O1NEXT/picoem-286/roms/rp2350/bootrom-combined.bin" --self-test
```
