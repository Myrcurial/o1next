# Building the fork — ESP32-S2

The recipe for `Myrcurial/Zimodem@o1next`. Upstream documents an Arduino-IDE build
(rev 1.8.10, ESP32 core **2.0.17**, "ESP32 Dev Module", QIO / 8 MB / 80 MHz / 3 MB
app space). This is the same toolchain driven from the command line, aimed at the
**S2** and at **our** board's pin map.

**Installed on Cortexiphan, 2026-10-19** (#317) — `arduino-cli` plus the
`esp32:esp32@2.0.17` core. `REQUIREMENTS.md` §Required carries the row, and
`tools/bootstrap.sh --check` probes both the tool and the core's *version*, so a
host with the wrong core says `MISSING` rather than `ok`. On a host that lacks
them:

## Toolchain

```sh
brew install arduino-cli
arduino-cli config init
arduino-cli config add board_manager.additional_urls \
  https://raw.githubusercontent.com/espressif/arduino-esp32/gh-pages/package_esp32_index.json
arduino-cli core update-index
arduino-cli core install esp32:esp32@2.0.17
```

**Pin the core version.** Upstream's README is explicit that 2.0.17 is what Zimodem
is built against, and the ESP32 core's API moves between majors.

## The sketch

Upstream's sketch root is `zimodem/` — the `.ino` plus its `.h`/`.ino` siblings,
with libssh2 vendored at `zimodem/src/libssh2/`.

```sh
git clone git@github.com:Myrcurial/Zimodem.git
cd Zimodem
arduino-cli compile --fqbn 'esp32:esp32:esp32s2:PartitionScheme=huge_app' zimodem
arduino-cli upload  --fqbn 'esp32:esp32:esp32s2:PartitionScheme=huge_app' -p /dev/cu.usbmodem* zimodem
```

`esp32:esp32:esp32s2` is the plain S2 Dev Module, and **`PartitionScheme=huge_app`
is not optional in practice.** The default scheme allows 1.25 MB of application and
this build uses **1,016,642 bytes of it — 77%**, which leaves no room for the panel
state machine (#322), the SSH key store (#321) or the audio. `huge_app` is 3 MB with
**no OTA**, and this board has no OTA path — it is flashed over USB. The same binary
then sits at **32%**.

| scheme | application | this build |
|---|---|---|
| `default` | 1.25 MB | **77%** — too tight to grow into |
| **`huge_app`** | **3 MB, no OTA** | **32%** |
| `no_ota` | 2 MB | ~48% |

If the fitted module is a PSRAM part, add `PSRAM=enabled`. The N4 has none and does
not need it.

## Configuration: what to set for our board

**Upstream has no S2 pin profile.** The `#elif` chain in `zimodem.ino` covers the
C3 and the S3, then falls through to *"standard ESP32 4 & 8MB boards"* — so our
build must supply its own `#define` block and must not inherit those pins.

Two things already fall out correctly and need **no patch**:

- **`MAIN_UART_NUM = UART_NUM_1`.** `pet2asc.h` has
  `#elif defined(ARDUINO_ESP32S3_DEV) || (!defined(UART_NUM_2))`, and the S2 has no
  `UART_NUM_2` — so the O1 side is **UART1** and `DEBUG_UART_NUM` is UART0.
  **Do not put the O1 on UART0**: the ROM bootloader's log would be sprayed into
  the machine's 6850 at every reset.
- **`ZIMODEM_ESP32`.** The S2 defines `ARDUINO_ARCH_ESP32`, which is the *first*
  branch of the chip test, so the ESP32 feature set is selected — `INCLUDE_SSH`
  included.

### Feature switches

| `#define` | Setting | Why |
|---|---|---|
| `INCLUDE_SSH` | **on** | the point of the S2 (#321) |
| `INCLUDE_SD_SHELL` | **off** | our board has no SD card. Also drop `INCLUDE_HOSTCM` and `INCLUDE_COMET64`, which require it |
| `INCLUDE_CBMMODEM` | **off** | Commodore 1650/1660/1670 emulation — not ours |
| `INCLUDE_IRCC`, `INCLUDE_PING`, `INCLUDE_FTP`, `INCLUDE_SLIP`, `INCLUDE_PPP` | per role | keep unless flash or RAM says otherwise |
| `INCLUDE_OTH_UPDATES` | **on** | comment it out only for an incompatible firmware; keeping it preserves upstream's update path |
| `SUPPORT_LED_PINS` | **off — replaced** | it is three LEDs on fixed GPIO. The 11-LED bank is the AW9523B (#322), and it is *new state*, not this switch |
| `DEFAULT_BAUD_RATE` | `1200` | upstream's default, **and an O1 rate** — so the out-of-box case works before any auto-baud exists (#319) |
| `DEFAULT_PIN_*` | **ours** | see below |

### Pins

**The pin map is [`../../hardware/wifi-comm-pac/pinmap.md`](../../hardware/wifi-comm-pac/pinmap.md)** —
twelve GPIO, the fork's `#define` block written out in full, and the reason each of
the module's other 25 GPIO is left alone. It is one map for both roles: role B
changes only what is on the far end of GPIO15/16 (#323).

Two things worth knowing without opening it:

- **UART1 is on GPIO15/16, not its IO-MUX default of 17/18.** Those two pins are
  also the only DACs, and UART1 can be routed anywhere — so the movable function
  goes on movable pins and the unique pins stay free.
- **A `DEFAULT_PIN_*` of `-1` means "not fitted"**, which is how upstream disables a
  line. Most of ours are `-1`: the panel and the handshake are on the AW9523B's I²C
  channels, not on GPIO.

### The board profile

The pins are implemented in the fork as **`zimodem/o1next.h`** — one file, selected
by `O1NEXT_BOARD`, which `zimodem.ino` defines for this fork. Upstream has no S2
profile: its chain covers the C3 and the S3 and then falls through to *"standard
ESP32 4 & 8MB boards"*, whose pins are not ours. The diff to upstream's
`zimodem.ino` is **eight added lines and no modified ones** — a modification notice
(Apache-2.0 §4(b)), the define, and the two-line branch — so a future merge from
upstream stays a merge.

The profile also carries the feature switches for a board with no SD card:
`INCLUDE_SD_SHELL` off, and with it `INCLUDE_HOSTCM` and `INCLUDE_COMET64`, which
require it; `INCLUDE_CBMMODEM` off. `INCLUDE_SSH` stays on — it is the point of the
S2.

**It builds.** Verified 2026-10-19 on Cortexiphan, with
`esp32:esp32:esp32s2:PartitionScheme=huge_app`:

```
Sketch uses 1016642 bytes (32%) of program storage space. Maximum is 3145728 bytes.
Global variables use 50812 bytes (15%) of dynamic memory, leaving 276868 bytes for local variables. Maximum is 327680 bytes.
```

And the branch is **taken** — which a successful build alone does not prove. Appending
`#error PROBE` to `o1next.h` fails the build with that text in the log, so the
`#elif defined(O1NEXT_BOARD)` branch is the one compiled and upstream's *"standard
ESP32 4 & 8MB boards"* fallback is not. `o1next.h` is **in** the build, not merely
beside it.

### Rosetta, and why the build needs it

**This machine cannot build an Arduino ESP32 sketch without Rosetta.** Every
compiler in the esp32 2.0.17 core is native arm64 — `xtensa-esp32s2-elf-gcc` is
`Mach-O 64-bit executable arm64` — but **four helper binaries are Intel-only
Mach-O**: `ctags` (arduino-cli's *own* builtin tool), `esptool`, `mklittlefs` and
`mkspiffs`. So a sketch build dies *inside a prebuild hook* with
`Bad CPU type in executable`, which reads like a source error and is not one.

```sh
sudo softwareupdate --install-rosetta --agree-to-license
```

`tools/bootstrap.sh --check` probes the two a compile actually needs and reports
them `DEAD` with that command, so the diagnosis is one line rather than an hour.
`REQUIREMENTS.md` §Required carries the row.

**Installed on Cortexiphan 2026-10-19** (#330), and the check now reads
`ok  arduino tools  ctags and esptool run`.

## Where the O1-specific core is

The parts that are *ours* — the rate table, the 6850 frame decoder and the
double-sided buffer — are **not** in the fork's tree. They are in
[`o1modem/`](o1modem/), plain C99 with no Arduino headers, host-tested by
`o1modem/run_tests.sh` in CI, and MIT like the rest of this repository.

The fork consumes them: the sketch includes the headers, and the Arduino-side glue
is the fork's own. That split is why the arithmetic is proven before the toolchain
is needed at all — the fork's README has the full argument.

## Modifying upstream files

Apache-2.0 §4(b): a modified file carries a **prominent notice** that it was
changed. Put it at the top of the file, on the branch — not only in the commit
message.

## References

- #317 (the fork), #318–#326 (the work)
- upstream build notes: the `README` at the root of `bozimmerman/Zimodem`
- [`../../REQUIREMENTS.md`](../../REQUIREMENTS.md) — the toolchain row
