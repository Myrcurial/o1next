# zimodem-fork — WiFi modem firmware (ESP32-S2)

The fork of [Zimodem](https://github.com/bozimmerman/Zimodem) that carries the
O1-specific modem work. One codebase serves both the severable module and the
interposer/SFF onboard ESP32.

Tracks: #21, #56. Work list: #317–#326.

## The fork

| | |
|---|---|
| Repository | **`Myrcurial/Zimodem`** |
| Branch | **`o1next`** — the fork's default |
| Forked from | upstream **`a534e512`** — `master`, 2026-10-06 |
| Licence | **Apache-2.0** (upstream's), retained as-is |

**The code lives in the fork.** This directory carries the pin, the licence
obligations, the build recipe and the reason for every choice — not a copy of
upstream's source. Each unit of work is a branch and a PR in the fork, and
[`BUILD.md`](BUILD.md) is how it is built.

## Why a fork, and not an upstream PR (#317)

Measured 2026-10-19: **0 merged pull requests, ever** (18 closed unmerged, 2 open),
and **0 of the last 100 commits lack a `git-svn-id` trailer** — the GitHub
repository is a `git-svn` mirror of a private SVN server
(`svn://192.168.1.10/public/Zimodem`). The maintainer works in SVN and
`git svn dcommit`s outward, so **a GitHub PR cannot be merged by construction**.
He does sometimes re-implement a PR's content himself — two of the last fifteen
commits are exactly that — which is why upstream PRs read "NOT-MERGED" while
their fixes are in the tree.

**Fork, then offer.** Three pieces are generic enough to be worth sending anyway —
the double-sided baud buffer (#318), the multi-LED bank (#322) and the
`Stream`-abstracted console (#323) — and each is worth having whether or not it is
ever taken. This is #208's posture applied to a repo where refusal is the default.

### Apache-2.0 obligations

- `LICENSE` **and `NOTICE`** are retained in the fork.
- A modified file carries a **prominent notice of modification** — Apache-2.0
  §4(b). Put it at the top of the file, on the branch, not only in the commit
  message.
- **This project stays MIT** (#298). Apache-2.0 is permissive and MIT-compatible,
  so the fork forces no relicence; the fork's own files stay Apache-2.0.

## Target: ESP32-S2

Chosen 2026-10-19 (#317). The S2 is the variant that makes O1-side rate detection
possible **in hardware**:

- **20-bit** auto-baud pulse counter → floor ≈ 80 MHz / 2²⁰ ≈ **76 baud**. C3 and
  S3 are **12-bit** (floor ≈ 9600) and cannot see 300/1200/2400 at all
  (`espressif/arduino-esp32` #9261).
- **2 UARTs, and upstream already picks the right one.** `pet2asc.h` sends any
  target without `UART_NUM_2` to `MAIN_UART_NUM = UART_NUM_1` and
  `DEBUG_UART_NUM = UART_NUM_0`, so the O1 side lands on **UART1** and the ROM
  bootloader's log stays on UART0 — with no patch.
- **I²S** (audio, #325), **RMT + PCNT** (rate measurement, #319), **USB OTG** (the
  board's USB-C), and the headroom libssh2 needs (#321).

**Use the U-variant (IPEX/U.FL) module, not the PCB-antenna one.** #56 §D keeps
the antenna away from the floppy drives and the CRT, and a pigtail to the case edge
is how that is done — the C64 Ultimate pattern.

## What the fork adds on top of upstream

1. **The double-sided baud buffer** (#318) — decouple the O1-side ACIA rate from
   the link. This *replaces* upstream's `dequeSize` throttle, which is the
   **opposite** coupling: `serout.ino` paces the network→serial path to `baudRate`
   (`INTERNAL_FLOW_CONTROL_DIV 380`), so a slow terminal back-pressures the socket.
2. **O1-side rate detection** (#319) — measure, snap to the **actual** rates
   (**650/2600**, not 600/2400), verify, ladder. Upstream has no auto-baud of any
   kind; the rate is set by `ATB` and saved.
3. **The "feel" rate** (#320) — a user-chosen 300…9600 experience, independent of
   what the machine's hardware is doing. `HS` (≥ 9600) follows it.
4. **SSH as a first-class transport** (#321) — upstream's libssh2 client is
   **password-only** with no host verification and no session store
   (`wifisshclient.h`: `setLogin(user, password)`); keys, known-hosts and sessions
   are new work.
5. **The panel and the noise** (#322) — 11 Hayes LEDs on an AW9523B and the
   modem's sound. Upstream's `SUPPORT_LED_PINS` is three LEDs, commented out by
   default, and keys `HS` to `baudRate >= 38400`.
6. **Role B** (#323) — the console becomes a `Stream`, so one codebase serves the
   standalone module (UART to the machine's ACIA) and the interposer/SFF (UART to
   the RP2354B, which serves the ACIA window).

## Kept from upstream

Hayes AT command set + telnet (period comm software: Kermit, XMODEM, …), and the
ESP32 extras (SD shell, FTP, SLIP/PPP) — though the SD-dependent features are
switched off for our board, which has no SD card. See [`BUILD.md`](BUILD.md).

## References

- [`BUILD.md`](BUILD.md) — toolchain, board target, feature switches, pin map
- [`../README.md`](../README.md) — the firmware component table
- [`../../docs/o1-modem-serial.md`](../../docs/o1-modem-serial.md) — the P1 pinout and levels
- [`../../hardware/wifi-comm-pac/README.md`](../../hardware/wifi-comm-pac/README.md) — the board
- upstream <https://github.com/bozimmerman/Zimodem> · fork <https://github.com/Myrcurial/Zimodem>
