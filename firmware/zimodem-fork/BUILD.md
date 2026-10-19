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

tools/build-o1next.sh                 # compile, merge into one image, verify
tools/flash-o1next.sh --console 20    # flash it, reset into it, watch it boot
```

Those two commands are the whole recipe. `build-o1next.sh` never needs a flag, and
`flash-o1next.sh` finds the board itself. **Neither needs a button.**

### The partition scheme, and why it is `min_spiffs`

**Two 1.875 MB application slots.** The app is **53%** of a slot, so there is room
for the panel state machine (#322), the SSH key store (#321) and the audio — and,
because there are two slots, for the firmware to **update itself over OTA** rather
than being re-flashed through the ROM's download mode at all (#334).

That last part is the reason for the change. `huge_app` gave 3 MB in a single slot
and no second one, which is the wrong trade for a device that gets power-cycled
constantly and will be updated often.

| scheme | application | this build |
|---|---|---|
| `default` | 1.25 MB × 2 | ~89% — too tight to grow into |
| `no_ota` | 2 MB × 1 | ~55%, and no second slot |
| `huge_app` | 3 MB × 1 | 32%, and no second slot |
| **`min_spiffs`** | **1.875 MB × 2** | **53%** |

The build refuses to pass **90%** of the application partition, so this is checked
rather than remembered.

### The board's console is its USB port

`CDCOnBoot=cdc` is in the FQBN, so the debug stream goes to the **native USB CDC**
as well as to UART0 — both, not either, because a board that does bring UART0 out
still wants it. This is not a convenience: the module's UART0 (GPIO43/44) is not
brought out to a connector and the board has no UART bridge, so without it there is
**no console at all** (#334).

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

**It builds, and it runs on hardware.** The board it was first brought up on is an
`ESP32-S2FNR2` (rev v1.0) — **4 MB embedded flash and 2 MB embedded PSRAM**, which
is the same silicon family as the `MINI-2U-N4R2` this build targets. It reports:

```
Zimodem 4.0.3 firmware starting initialization
SPIFFS Formatted.
Using BPS 1200, RXD 16, TXD 15
Baud 1200, Deque constant now: 4
Config changed.
Resetting...
Init complete.
```

**`RXD 16, TXD 15` is the firmware reporting this pin map back at us** — the check
that the profile is compiled in and *active*, not merely present. And the branch is
**taken**, which a successful build alone does not prove either: appending
`#error PROBE` to `o1next.h` fails the build with that text in the log, so the
`#elif defined(O1NEXT_BOARD)` branch is the one compiled and upstream's *"standard
ESP32 4 & 8MB boards"* fallback is not. `o1next.h` is **in** the build, not merely
beside it.

### One command, and one image to flash

```sh
tools/build-o1next.sh          # compile, merge, verify
tools/build-o1next.sh --clean  # ...without the previous build's objects
```

It writes `build/o1next-s2/`, and the file that matters is
**`zimodem-o1next-merged.bin`** — bootloader, partition table, otadata and
application in **one image, flashed at 0x0**:

```sh
esptool --chip esp32s2 write_flash 0x0 zimodem-o1next-merged.bin
```

That is the point of the script. Arduino's own build leaves three binaries plus a
fourth that lives in the core, and flashing them means getting four offsets right.
The script merges them and then **checks the offsets rather than trusting them**:
the app offset is cross-checked against the partition table the build just produced,
read back with the core's own `gen_esp32part.py`. A wrong app offset merges cleanly
and produces a board that does not boot, so it fails the build here instead.

It also refuses to build past **90% of the application partition**, because there is
no OTA path on this board and the panel (#322), the SSH key store (#321) and the
audio are all still to come. It sits at **53%** today.

`SHA256SUMS` and `BUILD-INFO.txt` are written beside the image: the git ref, the
arduino-cli version, the core version, the four offsets, and the checksums.

### Flashing, and what the hardware taught us

`tools/flash-o1next.sh` flashes and resets into the application, and **every one of
its behaviours was corrected by a real board** rather than reasoned out:

- **esptool's own reset works here**, and the warning it prints — *"esptool.py can
  not exit the download mode over USB. To run the app, reset the chip manually."* —
  is a generic USB-CDC one that does not apply. **No button is needed**, to enter
  download mode or to leave it.
- The **RTC_CNTL `SW_SYS_RST` write** (`0x3f408000` bit 31 — what `esp_restart()`
  does) **does not work on this board**: the write lands and the port drops, so it
  looks like a reset, but the chip comes back in download mode. `GPIO0` reads
  **high** (`GPIO_IN = 0x3c060001`), so it is not the strap — the board's auto-reset
  circuit holds GPIO0 low while the port is open, and only esptool's own sequence
  releases it. **Our own PCB is the case where this trick may be needed**, so it
  stays documented in the script rather than deleted.
- The flash is **retried**, because resetting *running* firmware into download mode
  changes the USB device and esptool's handle dies with it. Attempt one fails;
  attempt two finds the chip already in download mode. The script says so out loud
  rather than looking like a flake.
- The **console reader re-opens** across a reset, for the same reason — a reader
  that opens once misses every boot banner it was run to catch. Measured, twice.
- The console **waits for the host** once before its first line. Without that the
  banner goes into the void, because the host is re-enumerating during the reset;
  the first read of a booted board returned **zero bytes**.

### The same script runs in CI

**`.github/workflows/build.yml` in the fork** — not in this repository, and the
reason is the trigger. A job here could only build a *pinned* ref, which answers
"did the pin build once" and not "does what was just pushed build". It runs
`tools/build-o1next.sh`, so the CI build and the documented build are the same
build, and it uploads the merged image, the three parts, the ELF and the manifest
as a workflow artifact.

arduino-cli is pinned to **1.5.1** and the core to **2.0.17** — which is also the
cache key, so a cache miss is slow and never wrong.

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
