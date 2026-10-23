# picoem — the fixes o1next carries against the RP2354B emulator (#192)

**picoem** (`0x4D44/picoem`, the `rp2350-emu` crate) is the RP2354B emulator the
picoem bridge owns. It is where a real firmware binary runs while `osborne1nx`
drives its pins — `docs/emulation-testbed.md` is the plan, `docs/picoem-bridge.md`
is the wire.

This directory is the **patch series o1next carries against it**, in the same
shape as `tools/emulator-setup/mame-osborne1nx/`: a diff against a pinned commit,
a script to apply it, and the measurement behind every change. It is three
commits, and with them applied `cargo test -p rp2350-emu` is **3674 passed,
0 failed**.

## Why here and not upstream

Not a preference — a constraint, and it is worth being exact about it:

- **Its issue tracker is disabled and its pull requests are refused.** Measured:
  the API reports `has_issues: false`, so there is no tracker to file into — the
  `0 open / 0 closed` count is a property of a switched-off feature, not a
  history — and opening a PR against it fails (`CreatePullRequest` returns a
  permissions error, the REST endpoint returns 404, and the repository grants
  `pull` and not `push`). Upstream contribution is **closed**, not merely slow,
  which is why the fix went onto this fork (`Myrcurial/picoem` #1) rather than
  being offered.
- **Its `CONTRIBUTING.md` says to fork.** Verbatim: *"I'm happy to look at issues
  and pull requests, but I'm not making any commitments about response times,
  triage, or whether things will get merged or fixed. If you need certainty
  around a fix or feature, the safest path is to fork — the dual MIT/Apache-2.0
  license places no obligations on you."*
- **Upstream `main` is the commit we pin** (`8e20a82`, 2026-06-27), so there is
  nothing to re-pin to and no way to wait a gap out.

So the fixes live in a **fork** — `Myrcurial/picoem` — and are recorded here as a
patch so that this repository stays self-describing: a session with no fork and
no network can still read what changed and why. A pull request upstream is a
courtesy, not a dependency.

## What is in here

| File | What it is |
|---|---|
| `rp2350-correctness.patch` | the series, as a diff against `8e20a82` — three commits |
| `apply.sh` | apply it to a picoem checkout, optionally build and test |

## The series

Three commits, and the third is worth reading before the first two: the *same* 30-pin
assumption turned out to be in **two places**, and fixing only the first changed nothing
measurable. Bugs 1 and 2 were found by running a **stock Pico SDK 2.3.1 binary** on the
emulator and watching it not work; bug 3 by driving a real firmware against the
interposer's **shift fabric** — and then re-running it after the first fix, which is the
only reason the second site was found.

| # | Bug | Why it cost real time |
|---|---|---|
| 1 | **`LDAEX`/`LDAEXB`/`LDAEXH` and `STLEX`/`STLEXB`/`STLEXH` were not decoded.** | They did not fail as unknown instructions. `LDAEXB`'s `hw1` low nibble is `0xF`, so the `LDRD`/`STRD` fall-through read `Rt2 = 15` and executed `LDRD {Rt, pc}` — the core loaded **its own PC out of the lock byte it was reading**. Measured: PC `0x1000041e` → `0x00000000`, then the mask ROM's vector table executed two bytes at a time until a precise BusFault escalated to HardFault. The SDK's `hw_claim_or_assert` → `next_striped_spin_lock_num()` path uses exactly this pair, so **any** firmware that claims a hardware resource — an alarm, a PIO block, a DMA channel — went through it. |
| 2 | **CP0 (GPIOC)'s MCR/MRC table was transposed, and the MCRR family was not decoded at all.** | The table read `opc1` as the bank and `(CRn, CRm)` as a pin; the SDK puts the **operation** in `opc1` and the **register** in `CRm`. A transposed decode is self-consistent, which is why it survived: `put`/`put_all` worked by accident and every `set`, `clr` and `xor` was dropped as a silent NOP. And with no MCRR dispatch, `gpio_put(gpio, value)` (`mcrr p0, #4, gpio, value, c0`) and `gpio_set_dir(gpio, out)` (`mcrr p0, #4, gpio, out, c4`) — the two most-used GPIO calls in any firmware — were silent NOPs. The symptom, *"the firmware runs, reaches its main loop, drives nothing"*, reads exactly like a firmware bug. |

| 3 | **The SIO's bank 0 was 30 pins, not 32.** `PIN_MASK` was `0x3FFF_FFFF` and ten `if pin >= 30` guards dropped GP30 and GP31 on every write and read them back as zero — while the crate models the 48-GPIO part everywhere else (`Emulator::read_all_gpio` returns a 48-bit physical mask), and the B part's bank 0 is **32** pins. | **GP30 is the interposer's `SR_RCK` and GP31 is `/OE_ADDR`** — two of the five shift-fabric pins. A firmware that shifted a match value into the '595 and latched it appeared to have done **neither**: the bridge counted all 8 of its `SR_SCK` edges and **0 latches**. It fails as a *zero*, which reads like a firmware bug, and that is where the #304 session looked first. |

**The second site is the lesson, and it is why the third commit exists.** `sio/mod.rs`'s
mask was not the whole bug: `cp0_bit_op` bounds-checked `pin >= 30` as well, and *that* is
the path `gpio_set_dir(gpio, out)` takes — the SDK emits `gpioc_bit_oe_put`, not the
masked form. So the first fix was **measurably a no-op**, and the only reason the second
site was found is that the bridge's fabric test was re-run rather than assumed fixed. No
test above pin 29 existed, which is how a deliberate 30-pin assumption survived being
tested.

The 30-pin width was **not an oversight** — two tests asserted it by name
(`gpio_bit_out_masked_at_or_above_30`, `gpio_bit_oe_masked_at_or_above_30`). They are
renamed to `…_real_at_30_and_31_masked_at_or_above_32` and now assert the *positive*
case, because GP30 and GP31 working **is** what the change is for. The two coprocessor
tests that masked their expectations with `0x3FFF_FFFF` did so incidentally and no
longer do, and the width now lives in one constant (`BANK0_PINS`) that `PIN_MASK` and
the guards share.

**What it does not fix:** bank 1 (GPIO32–47) is still unmodelled — this SIO has no
`GPIO_HI_*` registers at all. That is a separate gap (`docs/emulation-testbed.md` §4.2
**P4**), and it is why a firmware cannot yet drive or observe GP32–47.

Both tables are now taken from the SDK's own `hardware/gpio_coproc.h` and
**measured**: every form was assembled with the Arm GNU toolchain 15.3
(`-mcpu=cortex-m33 -mthumb`) and the encodings read out of the object file. The
tests pin the raw `hw0`/`hw1` as literals rather than through an encoder,
because the previous table's own encoder agreed with its own decoder and both
were wrong — an encoder cannot catch that. Five of the eight CP0 tests in
`tests.rs` were passing for reasons unrelated to what they claimed.

## Using it

```sh
# a picoem checkout at the pinned commit
git clone https://github.com/0x4D44/picoem.git "$HOME/Documents/O1NEXT/picoem-286"

# apply, then build and test
tools/emulator-setup/picoem/apply.sh "$HOME/Documents/O1NEXT/picoem-286" --test
```

Or take the fork directly, which is what `tools/picoem-bridge/Cargo.toml` pins:

```sh
git clone -b fix/rp2350-gpio-coproc-and-exclusive \
    https://github.com/Myrcurial/picoem.git
```

## What is *not* here, and why

The remaining gaps are picoem's, not ours to fix by preference — the bootrom boot
path, `UFSR` fault-cause reporting, SIO bank 1 (GP32–47), the pad mux
(`FUNCSEL` is stored and never consulted, so peripherals cannot reach a pin), and
the device models behind SPI. `docs/emulation-testbed.md` §"the gap register" is
the single list, with the measurement and the cost of each.

Two of those are deliberately **not** in this series:

- **SIO bank 1** is a *different layer* from the CP0 encoding. The series above
  makes the HI-bank access reach the right register; that register does not exist
  in this crate's `Sio` yet. Conflating the two would make both harder to review.
- **The pad mux** is the one gap that would pay off across every peripheral, and
  it is only worth building if the storage transports are wanted in emulation —
  which `docs/emulation-testbed.md` argues they mostly are not.

## Re-pinning

`tools/picoem-bridge/Cargo.toml` carries the `rev`. To move it:

1. change the `rev`, run `cargo build` and `cargo test` in `tools/picoem-bridge`;
2. re-run `tools/emulator-setup/mame-osborne1nx/picoem-check.sh`;
3. re-read `docs/picoem-bridge.md` §5 — a re-pin can retire one of the six
   switches in `firmware/picoem-smoke/CMakeLists.txt`, and if the series above is
   merged or re-derived upstream, retire this patch with it.

`REQUIREMENTS.md`'s picoem row is the authoritative note on the pin.
