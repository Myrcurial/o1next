# Building the fork — ESP32-S2

The recipe for `Myrcurial/Zimodem@o1next`. Upstream documents an Arduino-IDE build
(rev 1.8.10, ESP32 core **2.0.17**, "ESP32 Dev Module", QIO / 8 MB / 80 MHz / 3 MB
app space). This is the same toolchain driven from the command line, aimed at the
**S2** and at **our** board's pin map.

**The toolchain is not on this machine.** It is recorded in `REQUIREMENTS.md`
§"Not installed yet" as an ask — do not hand-roll around it.

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
arduino-cli compile --fqbn esp32:esp32:esp32s2 zimodem
arduino-cli upload  --fqbn esp32:esp32:esp32s2 -p /dev/cu.usbmodem* zimodem
```

`esp32:esp32:esp32s2` is the plain S2 Dev Module. If the fitted module has
different flash or PSRAM, add the matching `--board-options`: a PSRAM-bearing part
wants `PSRAM=enabled`, and 8 MB of flash wants
`FlashSize=8M,PartitionScheme=default_8MB` so libssh2 plus the whole AT set fit.

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

### Pins — indicative, to be finalised with #324/#325

The authoritative map is the board schematic. In **role B** the same pins carry the
RP2354B link instead of the machine's ACIA (#323).

| Signal | Note |
|---|---|
| O1 UART TXD/RXD | **UART1** — `DEFAULT_PIN_TXD` / `DEFAULT_PIN_RXD` |
| Debug | UART0, the USB-serial console |
| I²C SDA/SCL | the AW9523B panel (#322/#325) |
| I²S BCLK/LRCLK/DIN | the audio amp (#325) |
| `DEFAULT_PIN_DCD` | carrier detect — the O1's real DCD comes through the ACIA |
| `DEFAULT_PIN_RI` | ring — **also P1 pin 9**, wired to the video-PIA UC15 CA2 |
| `DEFAULT_PIN_CTS` / `DEFAULT_PIN_RTS` | flow control |
| `DEFAULT_PIN_SND` | the beeper/piezo output |
| `DEFAULT_PIN_OTH` | stream/command-mode flag |
| `DEFAULT_PIN_DSR` / `DEFAULT_PIN_DTR` | **not used** — the O1's DE-9 has no DSR/DTR. Its DTR-equivalent is **MCB (pin 8)**, which is a *read* and belongs on the panel expander (#324) |

A `DEFAULT_PIN_*` of `-1` means "not fitted" — that is how upstream disables a
line. Prefer it to inventing a pin.

## Modifying upstream files

Apache-2.0 §4(b): a modified file carries a **prominent notice** that it was
changed. Put it at the top of the file, on the branch — not only in the commit
message.

## References

- #317 (the fork), #318–#326 (the work)
- upstream build notes: the `README` at the root of `bozimmerman/Zimodem`
- [`../../REQUIREMENTS.md`](../../REQUIREMENTS.md) — the toolchain row
