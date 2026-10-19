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

### The console you can type at

That CDC was **write-only** until #334: `debugPrintf()` mirrored the firmware's log
out of it and nothing ever read it back, so there was no way to type at a running
board and no way to ask it what it had loaded, which slot it booted from, or
whether the firmware was the one we thought we had flashed. The read half is
`zimodem/o1next_console.ino` in the fork — declared by `o1next_console.h`, polled
from `loop()` behind the same guard the CDC half of `debugPrintf` uses.

**It is not the modem's serial port.** The O1 side is UART1 (GPIO15/16) and the
ROM bootloader's own log is UART0; the console is a third, independent stream on
the native USB. Nothing in it reads or writes `HWSerial`, so a command typed here
cannot be mistaken for a byte the Osborne sent, and no byte the Osborne sent can be
eaten by the console.

```
o1next console -- Zimodem 4.0.3.  Type help for the commands.
o1next> status

Zimodem 4.0.3  (built Oct 19 2026 17:15:10)
board    ESP32-S2, flash 4194304 bytes, MAC 80:65:99:ef:c7:82
serial   O1 side is UART1: RXD 16, TXD 15, 1200 bps
         handshake DCD -1, CTS -1, RTS -1, RI -1, DSR -1, DTR -1
         console is this USB CDC; ROM log is UART0
strap    GPIO0 (BOOT / factory reset) reads HIGH
slot     running app0 at 0x010000, 1966080 bytes
         next update would go to app1 at 0x1f0000
uptime   227.2 s
heap     free 155416, min free since boot 154772
o1next>
```

| command | what it does |
|---|---|
| `status` | version and build time, MAC, the pins in use, what GPIO0 reads right now, the running slot and the slot an update would go to, uptime, heap |
| `reboot` | `esp_restart()` — back into the application |
| `bootloader` | the ROM's download mode, with **no button** (below) |
| `update <bytes>` | receive an application image of that many bytes into the inactive slot, verify it, and reboot into it (below) |
| `help` | the list, and the note that this is not the modem's port |

`tools/console-o1next.py` is the writing half of `tools/read-console.py`:

```sh
tools/console-o1next.py '/dev/cu.usbmodem*' status
tools/console-o1next.py '/dev/cu.usbmodem*' bootloader   # then tools/flash-o1next.sh
```

It re-opens across the resets `reboot` and `bootloader` cause, for the same reason
`read-console.py` does: a reader that opens once misses everything after the
command it was run to send.

#### `bootloader` — and it is *not* the obvious implementation

The only programming port on this board is the ESP32-S2's own USB, and the ROM
cannot reset the chip over it. esptool's own reset papers over that on a board with
an auto-reset circuit, which is the board we brought up on. **Our own PCB will not
have one**, so there the button is the only way into the ROM — unless the running
firmware can do it.

The obvious implementation is the BOOT strap: drive GPIO0 low, call `esp_restart()`,
let the ROM sample it. **Measured 2026-10-19, and it does not work**: the port drops
and the *application* comes back, banner and all. An SW system reset does not
re-sample the BOOT strap — the mode latched by the last hardware reset persists.

That also settles an older mystery in `tools/flash-o1next.sh`. esptool's
`write_mem` of `SW_SYS_RST` to `0x3f408000` "worked" only in the sense that the port
dropped; the chip came back in download mode, and the note there blamed the board's
auto-reset circuit. It was never the circuit: the chip was *already* in download
mode, so the latched mode was download mode.

What does work is the RTC domain's `RTC_CNTL_FORCE_DOWNLOAD_BOOT` bit
(`RTC_CNTL_OPTION1_REG`, `0x3f408128`, bit 0), which survives the SW reset — and
which is the mechanism the Arduino core itself uses in `usb_persist_restart()`
(`cores/esp32/esp32-hal-tinyusb.c`). GPIO0 is still driven low, because it is the
half that matters if the reset that follows is a *hardware* one.

The evidence, on the board:

- `bootloader` → the port drops, **no banner follows**, and esptool with
  `--before no_reset` then syncs to it:
  ```
  Features: WiFi, Embedded Flash 4MB, Embedded PSRAM 2MB, ...
  Crystal is 40MHz
  MAC: 80:65:99:ef:c7:82
  Uploading stub... Running stub... Stub running...
  Staying in bootloader.
  ```
  The discriminator is the control: against a *running* application the same probe
  fails with *"Failed to connect to ESP32-S2: No serial data received."*
- `bootloader` → `tools/flash-o1next.sh` → the application is back and answering,
  with **no cable moved, no button, no download-mode dance**. That is the whole
  point of the command, and it is the loop our PCB will need.
- `status` while the chip is in the ROM's stub → silence, which is what a dead
  application looks like from here.

#### `update` — the firmware updates itself

The second slot has existed since the partition scheme changed to `min_spiffs` and
nothing used it. `update` uses it: the application image arrives on this console,
goes into the **inactive** slot, is verified there, otadata is pointed at it, and
the board reboots into it. No cable moved, no button, no download mode — and
`bootloader` above is what is still there if the new image does not come up.

**The artifact is the application `.bin`** (`zimodem.ino.bin`, 1,052,992 bytes) and
never the merged image: an OTA must not write the bootloader and the partition
table, because they are what is doing the writing. The fork's CI already uploads
it, so it is one step from a release asset.

```sh
tools/update-o1next.py '/dev/cu.usbmodem*' build/o1next-s2/zimodem.ino.bin
```

##### The protocol, and why it is one ack byte per chunk

The USB CDC's receive queue is **256 bytes deep** (`USBCDC.cpp` — the default in
`setRxBufferSize`), and a flash write stalls the console's loop for tens of
milliseconds while a 4 KB sector is erased. A sender that pushes a megabyte as fast
as the port takes it overruns that queue, and an overflowed queue **drops bytes
silently**. So the sender waits for one byte per chunk and is never more than one
chunk ahead; while the flash is being written the sender is idle and the queue is
empty. The acknowledgement *is* the progress — `.` per chunk, and nothing else is
printed during a transfer — and a chunk is one flash sector, 4096 bytes.

```
ready: send 1052992 bytes in 4096-byte chunks, one ack byte each
   32/258 chunks, 131072 of 1052992 bytes, 3.0 s
   ...
   258/258 chunks, 1052992 of 1052992 bytes, 24.4 s
1052992 bytes in 258 chunks, verifying
update ok: written, verified, and otadata now points at it
```

1,052,992 bytes in **24.4 s**, about 43 KB/s, measured 2026-10-19 — and then the
board is running the new image, which `status` reports as the other slot with a new
build time. Both directions were measured, app0 → app1 and back.

##### A failed transfer is not a brick

`Update.end()` verifies the image before it touches otadata, so every failure ends
with the running slot still running, and the console says so:

| what went wrong | what the board said |
|---|---|
| truncated image (600,000 of 1,052,992 bytes) | `update failed: Could Not Activate The Firmware -- the running slot is untouched` |
| the sender died mid-chunk | `update failed: 0 of 4096 bytes of a chunk arrived in 5000 ms` |
| `update`, `update abc`, `update 0`, `update 99999999` | each refused in its own sentence, naming the inactive slot and its size |

After the truncated image, `status` still read `running app0, built 17:56:57` with
an unbroken uptime. That is the property the whole thing rests on.

##### Two things learned by doing it

- **A bare CR was being swallowed by the console.** "A terminator after a terminator
  is the second half of a CRLF" also swallows a bare CR, so pressing Enter after a
  command printed nothing — and `update-o1next.py` asks for a prompt by sending
  exactly that. It now swallows a terminator only when it is the *other* one from
  the one that ended the line: CRLF is one line, two Enters are two lines.
- **The board erases the inactive slot before it says ready.** `esp_ota_begin()`
  erases the whole partition, and 1.875 MB of flash takes seconds, so the sender
  waits for the word `ready` and not for a newline: the echo of the command is a
  line too, and it arrives first.

**And a property worth keeping:** an OTA keeps what a full-chip flash throws away.
SPIFFS survives it, so the modem's stored config and phonebook do — visible as the
absence of `SPIFFS Formatted.` in the boot banner after an update.

##### Still open: the same thing over WiFi

`update` takes a byte count, so the cable is still the wire. Taking a URL instead —
`WiFiClient` streaming into the same verified write path — is what makes the cable
unnecessary, and it reuses this slot handling, this verification and these failure
semantics. It needs an SSID and a password to test against, which is why it is a
separate step rather than a hopeful one.


#### Two things the console does that look like bugs

- **esptool's sync filler is `0x55`, which is `'U'` and printable.** Point
  `--before no_reset` at a *running* application and the console reads a few
  thousand of them, fills its line buffer, and answers `line too long (max 63) --
  dropped` to the next command sent. Send a bare newline first, or just retype; the
  console says what it did rather than silently truncating into a different command.
- **`uptime` is `millis()`, and not every reset zeroes it.** `esp_restart()` does —
  measured 6703.5 s, `reboot`, 9.6 s — and so does esptool's own reset on a running
  application (20.0 s after a flash that began with one). **The reset esptool
  performs at the end of a *stub* session does not**: after one, a freshly started
  application reported 6664.9 s, and after a flash driven from that stub, 346.5 s.
  So `uptime` is a real number and not always "how long has this application been
  up" — the `built` line is what answers "is this the firmware I just flashed".


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
ESP32 4 & 8MB boards"*, whose pins are not ours.

**The diff to upstream's `zimodem.ino` is 53 added lines and 2 modified**, measured
against upstream `a534e51` with `git diff --numstat`. (An earlier version of this
paragraph said *"eight added lines and no modified ones"*, and both halves of that
were wrong by the time #334 landed — the notice and the CDC half of `debugPrintf`
are lines too, and the two fixed arrays are upstream lines that changed.) The added
ones are a modification notice (Apache-2.0 §4(b)), the define, the two-line branch,
the CDC half of `debugPrintf`, the notice above the two fixed arrays, and the
console's one call from `loop()`. The two modified are the `pinSupport[]` and
`pinCache[]` declarations, which gained their padding in #334. The fork's own files
— `o1next.h`, `o1next_console.h`, `o1next_console.ino` — are new, so they cost a
future merge from upstream nothing.

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

It also refuses to build past **90% of the application partition**, because the
panel (#322), the SSH key store (#321) and the audio are all still to come, and
because the OTA path (#334, item 2) writes into the *other* slot and wants the room.
It sits at **53%** today.

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
  **high** (`GPIO_IN = 0x3c060001`), so it is not the strap — and the explanation
  this note used to carry, *"the board's auto-reset circuit holds GPIO0 low while
  the port is open"*, **is wrong**. #334 settled it: an SW system reset does not
  re-sample the BOOT strap at all, so the chip simply came back in the mode the
  last *hardware* reset had latched — which, from esptool, is download mode. The
  console's `bootloader` command is the same mechanism, deliberately; see
  **The console you can type at** above.
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
