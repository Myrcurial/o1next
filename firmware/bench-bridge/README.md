# bench-bridge — the rig that puts the emulator's 6850 on a real wire

A second ESP32 wired as a **three-wire null modem** to the WiFi COMM PAC, so the
emulated Osborne's MODEM port can be plugged into the **real** modem — a virtual →
real serial port, with no Osborne on the bench.

Tracks: **#342**, part of #334. Adjacent: #319 (the rate ladder), #322 (the panel),
#323 (the RP2354B bridging the ACIA window), #303/#304 (the trace).

## Why it exists

Two walls were hit in one session (#334), and they are the same wall:

- the modem's command interface is on the **O1 side** (UART1), and a board on a bench
  has no machine on the other end of it, so `AT` cannot be typed at anything;
- `ZStream` is a `ZMode` but **not** `Stream`-parameterised, so the USB console cannot
  drive the modem's parser either — that is #323's shape, not a switch to flip;
- and the harness's telnet server (`tools/harness-o1next.py`, #334) therefore has
  nothing that can dial it.

Everything modem-side — the AT command set, telnet dialling, SSH once #321 lands, the
DCD/CTS semantics, the rate ladder (#319), the panel (#322) — needs *something* on the
O1 side. This is that something.

## Why a reprogrammable bridge rather than a USB-TTL adapter

A CP2102 would prove the same wire today and could only ever be a wire. The *shape* is
the point: the same board can be a transparent relay, a trace, a precise rate source,
later a driver for the AW9523B handshake lines and the +12 V rail monitor (#322), and
eventually the stand-in for the RP2354B's serial side (#323).

## The wire — three wires, crossed, 3.3 V, no level shifting

| COMM PAC side | Bridge side | why |
|---|---|---|
| **GPIO15** — UART1 **TX** | bridge **RX** | the machine-facing side. P1's level stage is *not* in this path: the rig lands on the module's UART1 pins, at 3.3 V. |
| **GPIO16** — UART1 **RX** | bridge **TX** | **and RMT taps this same pin** for #319 — so the rig drives the very pin the rate measurement listens to. |
| **GND** | **GND** | the third wire. **No power wire between the boards**: each is powered from its own USB port. |

On the **COMM PAC** side, touch nothing else: GPIO0/45/46 are straps, 19/20 are the USB
pins, 26 is the PSRAM chip select on R2 parts, 33/34 are the AW9523B's I²C, 35 is the
I²S clock, 39–42 are JTAG, 43/44 are UART0. `hardware/wifi-comm-pac/pinmap.md` is the
authority.

**On the bridge side any two free pins will do**, which is why the sketch takes them as
`-D` defines — the wiring has to follow whatever the dev board actually brings out to
its header. The pins in use on each board are in the build script's table, and the
defaults there are UART1's own IO-MUX pair on each part.

> **A caution that cost a session, so it is written down.** GPIO9 and GPIO10 are UART1's
> IO-MUX default on a **classic ESP32**, and they are also the SPI flash's D2/D3 lines on
> an ESP32-WROOM module. They are free with DIO flash and not free with QIO. If a board
> wired to 9/10 boot-loops or its console dies, move the two wires to a plain spare pair
> and rebuild with `BRIDGE_PINS`. **On an ESP32-C3, do not use the default pair at all** —
> GPIO18/19 are its USB pins.

## The two doors, and why the console is one of them

| Door | Where | What |
|---|---|---|
| **the relay** | the USB CDC (after `relay`) | byte-transparent to UART1, no framing, no rewriting |
| **the relay** | **TCP 2323**, always | the same bytes, a pure pipe, never inspected |
| **the trace** | **TCP 2324**, always | live `#o1next-trace` records |
| **the console** | the USB CDC at boot, and **TCP 2325** | `o1next> `, commands, the counters |

The TCP relay door exists because the Stage 1 emulator attaches over TCP (MAME's
bitbanger, or a host relay), while Stage 0 is a person with a terminal.

The **USB CDC cannot be a pure pipe**, because it must answer the probe: the board
identifies itself by answering a bare CR with a prompt and `status`, and a `status` that
went down the wire to the modem would be a different board's answer. So the CDC has two
states and the default is the console:

```
boot        -> console.  `o1next> `, and `status` names the role and the MAC.
`relay`     -> the CDC becomes the relay's host end.  Byte-transparent.
`+++`       -> back to the console: one second of silence, then three pluses.
`relay raw` -> the same, with the escape OFF.
```

**The escape is Hayes' own, with the guard it needs.** A `+++` in the middle of a file
transfer is the one thing that would look like an escape, and one second of silence
mid-transfer is exactly when you want out — so the guard is the whole of the safety
argument. Use **`relay raw`** when the modem must see the `+++` itself: the modem's own
parser hangs a connection up on `+++`, and a bridge that ate it would make that
impossible. The TCP relay door is always raw, for the same reason.

## Which board

**Any ESP32 with two UARTs and WiFi.** The rig is not the product, and it needs none of
the things the modem's part was chosen for — the 20-bit auto-baud counter (#319) is a
*modem* requirement, and a rig that only has to **emit** a paced rate can do it on
anything with a UART.

| `--board` | part | host door | UART1 pins | note |
|---|---|---|---|---|
| `esp32` | classic ESP32, 38-pin devkit | UART0 via a **CP2102** | 9 / 10 | **the host must match the baud** |
| `c3` | ESP32-C3 | **native USB** | 6 / 7 | the baud is a decoration |
| `s2` | ESP32-S2 | **native USB** | 18 / 17 | the baud is a decoration |

The one thing that is *not* the same shape across boards is the **host door**, and it
matters to the probe:

- On a **native-USB** board (C3, S2, and our own PCB), `Serial` is a USB endpoint, there
  is no wire, and the host cannot get the baud wrong. `identify-o1next.py` works
  unchanged.
- On a **bridged-UART** board (the classic ESP32's CP2102/CH340), `Serial` is UART0 and
  **there is a wire**. macOS gives a fresh CP2102 port **9600** by default, and the probe
  does not set a baud — so reaching this console needs `identify-o1next.py --baud 115200`.
  Without it the tool still identifies the board, via `esptool read_mac`, at the price of
  a reset.

`BRIDGE_HOST_BAUD` (default 115200) is the firmware's side of that. 115200 rather than
9600 deliberately: the host door also carries the relay, and 9600 would cap the whole rig
at the fastest rate the machine side can run.

## Build

```
firmware/bench-bridge/build-bench-bridge.sh                  # the board on the bench
firmware/bench-bridge/build-bench-bridge.sh --board c3
firmware/bench-bridge/build-bench-bridge.sh --board s2 --clean

BOARD=esp32 BRIDGE_PINS='-DBRIDGE_RXD=9 -DBRIDGE_TXD=10' \
  firmware/bench-bridge/build-bench-bridge.sh
```

One image lands in `build/bench-bridge-<board>/`, flashable at **0x0**:

```
esptool --chip esp32 write_flash 0x0 bench-bridge-merged.bin
```

The merge is the point of the exercise, exactly as it is for the modem: Arduino's own
build leaves three binaries plus a fourth from the core, and flashing them means getting
four offsets right. The script then **checks** the offsets against the partition table it
just built, and checks that each image's magic bytes really landed where it was put — a
wrong app offset merges cleanly and does not boot.

### Flashing a board with no auto-reset circuit

A classic ESP32 devkit and any C3 have the DTR/RTS an auto-reset circuit needs, so
`esptool` resets them itself. **A native-USB S2 with no button does not**, and the
sequence is the one the modem's `flash-o1next.sh` documents:

```
hold BOOT, tap EN/RST, release BOOT      -> the ROM's download mode
```

After that, `esptool --before no_reset` reaches it, and — once this firmware is running
— the console's **`bootloader`** command gets back there with no finger at all. That
command works differently on the two families, and the sketch says so where it matters:
the S2/S3/C3 have an RTC-domain force-download bit that survives a software reset; the
classic ESP32 has no such bit (`RTC_CNTL_OPTION1_REG` does not exist in its register
map), so there the command holds the BOOT strap low and asks for a hardware reset.

## The console

```
o1next> status
bench-bridge -- the o1next bench rig (built Oct 20 2026 10:50:16)
board    ESP32-C3 rev 4, 1 core(s), flash 4194304 bytes, MAC 88:56:a6:62:3b:94
role     bridge -- the wire's host end; the machine end is the modem
serial   O1 side is UART1: RXD 6, TXD 7, 1200 bps
link     relay idle
doors    OPEN -- relay :2323, trace :2324, console :2325
clients  tcp relay free, console attached, trace reader free
counters in 3, out 0, dropped 0, escapes 1
trace    recording, 1 of 256 records
wifi     o1next, 192.168.2.3
uptime   171.9 s
```

| command | what it does |
|---|---|
| `status` | role, MAC, pins, rate, the doors, and the byte counters — **the same probe answer the modem's console gives**, so `identify-o1next.py` identifies both boards |
| `relay` / `relay raw` / `relay off` | the USB CDC becomes the wire; `raw` turns the escape off |
| `rate [bps]` | report or set the O1-side rate. The O1's own are 300/650/1200/2600/9600; anything 50…2000000 is accepted |
| `send <text>` | write `<text>` and a CR to UART1 at the current rate |
| `pace <n> [hh]` | emit `n` bytes (default `0x55`) at the current rate — **the paced source #319 measures against**. It blocks until done; capped at 4096 |
| `trace on\|off\|clear\|dump` | the record: toggling, emptying, or reading it back over the console |
| `wifi` / `wifi <ssid> <password>` / `wifi off` | join and save a network (NVS), so the TCP doors come back on their own |
| `reboot` / `bootloader` | reset into the application / ask the ROM for download mode |
| `help` | the list |

`pace` is the part the emulator cannot do, and the reason it is here: **the UART
hardware paces the bytes, so the waveform *is* the rate.** The default byte is `0x55`
because `0101…` is a square wave at half the baud rate, which is what a
period-measuring front end wants to see.

Walking the rate ladder needs both ends told, and only one of them is this console:

```
o1next> rate 1200                # both ends still agree
o1next> send ATB 650             # the MODEM changes its own O1-side rate
o1next> rate 650                 # now this end follows
o1next> pace 1024 55             # 1024 bytes of 0x55 at 650 baud
```

## The trace format

**One definition, in this file, shared rather than invented twice.** The envelope is:

```
#o1next-trace <version> <source> <unit>
<time> <kind> <payload…>
```

- A line beginning with `#` is a comment or the header. **A reader skips it**, and that is
  how the format grows.
- `<version>` is `1`. `<source>` names the producer (`bench-bridge`, `bus-analyzer`).
  `<unit>` is the time unit the producer counts in — `ms` here, `ns` for a cycle-accurate
  bus capture — so a reader can convert without guessing.
- Every other line is: an integer time, a **single-character kind**, then payload fields
  separated by single spaces. The time is monotonic from the producer's own epoch, not
  wall clock: `millis()` here.
- **The payload is per-source; the envelope is what is shared.** That is the whole point
  of writing it down — `firmware/bus-analyzer/` (#17, #303, #304) emits Z80 bus cycles, not
  byte runs, and `tools/trace-analyzer/` should carry one reader for the envelope and one
  decoder per source, rather than a second format.

For this rig the kind is a direction, and the payload is the bytes:

```
#o1next-trace 1 bench-bridge ms
812 > 41 54 0d
829 < 0d 0a 4f 4b 0d 0a
```

`>` is toward the machine (the bridge's TXD → the modem's RXD); `<` is from it. A record
is a **run** of bytes, not one byte: at 9600 baud a byte-per-record trace is 960 lines a
second, which is unreadable and unbounded. A run ends when the line goes quiet (3 ms) or
when it fills (64 bytes), and **the timestamp is the first byte's** — so a run reads as
"these bytes arrived together", which is what a serial trace is for. At 1200 baud that is
one or two bytes per record, which is what makes it readable byte by byte.

Read it live on **TCP 2324** (the header arrives on attach), or after the fact with
`trace dump` on the console, which prints the same lines out of the 256-record ring.
Because it is line-oriented text, `grep '^[0-9]* <'` is a valid way to read the
machine's half of a conversation.

## Stage 0 — what this rig has to prove

From the Mac, through the rig:

1. **`AT` returns `OK`.** Type `relay` at the console, then `AT`.
2. **`ATDT 192.168.2.1 2323` reaches the harness's telnet server** and the banner comes
   back — `tools/harness-o1next.py`, on the Mac.
3. **The trace shows both directions with times** — `nc <bridge> 2324`.
4. **A paced 650-baud stream makes the modem report that rate** — `pace 1024 55` after
   walking the ladder above.

> **Item 4 is not this rig's to finish.** The modem cannot *report* a measured rate until
> #319 lands — today its O1 side receives at `baudRate` (`DEFAULT_BAUD_RATE`, 1200) and
> nothing measures the incoming waveform. What this rig can do today is be the *precise
> host* the measurement will be taken against, and it can do that now.

Stage 1 (`-rs232 pty` through `tools/serial-relay-o1next.py` to the TCP relay door) is
#342's second half.

## Testing the rig without the modem

**A software loopback, which needs no jumper and no second board.** UART1's RX and TX
can both be routed to the *same* pin, and then the rig hears exactly what it sends:

```
BRIDGE_PINS='-DBRIDGE_RXD=7 -DBRIDGE_TXD=7' \
  firmware/bench-bridge/build-bench-bridge.sh --board c3
esptool --chip esp32c3 --port /dev/cu.usbmodem2144101 \
  write_flash 0x0 build/bench-bridge-c3/bench-bridge-merged.bin
```

Then `relay`, and type. Measured on the C3 rig 2026-10-20:

```
o1next> relay
-- relaying.  `+++` after a second of silence comes back to this console
   1200 bps on UART1 (RXD 7, TXD 7).  Nothing else is printed here until you leave.
AT                        <- typed here
AT                        <- came straight back
+++
-- escaped to the console (3 bytes in, 3 out, 0 dropped)
o1next> trace dump
#o1next-trace 1 bench-bridge ms
16215 > 41 54 0d
16223 < 41
16231 < 54
16239 < 0d
-- 4 records
```

`3 in, 3 out` with the exact bytes is the whole proof: **the UART, the pin, the relay, the
escape, the counters and the trace all work, with no cable in the path.** It is the first
thing to run when a wire is suspect, because it removes the rig from the list of suspects
in about a minute — and because it is the only way to test the rig's TX without an
instrument.

**A jumper between the two UART1 pins does the same thing and additionally tests the
physical path** — with the *normal* firmware (RX 6, TX 7), a dupont from GPIO6 to GPIO7
makes the rig echo. That is the test to run when the rig's own loopback passes but a
counterparty stays silent.

## Measured on the bench — 2026-10-20, ESP32-C3

The rig's board is an **ESP32-C3**, wired `GPIO6 (RX) ← modem GPIO15`,
`GPIO7 (TX) → modem GPIO16`, `GND — GND`. Everything below is a measurement, not a plan.

**The console answers, and the probe finds it with no `--baud`.** `identify-o1next.py`
reports the rig on its own line, because the C3's host door is native USB and there is no
wire for the host to get the rate wrong on:

```
PORT                   MAC                WHAT ANSWERED  DETAIL
/dev/cu.usbmodem2144101 88:56:a6:62:3b:94  console        Oct 20 2026 10:47:36; RXD 6, TXD 7
```

**The relay, the escape, the counters and the trace all behave.** `AT\r` sent through the
relay, then the escape, then `trace dump`:

```
o1next> relay
-- relaying.  `+++` after a second of silence comes back to this console
   1200 bps on UART1 (RXD 6, TXD 7).  Nothing else is printed here until you leave.
                        <- `AT\r` sent here; no echo, which is the transparency working
+++                     <- one second of silence, then the escape
-- escaped to the console (3 bytes in, 0 out, 0 dropped)
o1next> trace dump
#o1next-trace 1 bench-bridge ms
84433 > 41 54 0d
-- 1 records
```

**`out 0` is the diagnostic, and it is the correct one**: the modem end is mute (see #342),
so the outbound path is proven and the inbound path has nothing to carry yet. That
difference — bytes in, none out — is the whole reason the counters are on the `status`
line.

**All three TCP doors work**, from the Mac at `192.168.2.1`, rig at `192.168.2.3`:

```
nc -w 5 192.168.2.3 2324        ->  #o1next-trace 1 bench-bridge ms
nc -w 5 192.168.2.3 2325        ->  bench-bridge console, over TCP / o1next> status / ...
nc -w 5 192.168.2.3 2323        ->  accepts AT\r, sends it down the wire
```

### Four things the bench taught, which the code and this file now say

1. **A full-image flash at 0x0 erases NVS.** The merged image spans 0x0…0x10000 and
   `merge_bin` fills the gaps with 0xFF, so the NVS partition at **0x9000** — where the
   WiFi credentials live — is overwritten every time. `wifi <ssid> <password>` has to be
   typed again after a reflash. This is the same trap the modem's handover recorded for
   its own board ("the flash erased the chip, so its WiFi config is gone"), arrived at
   from the other direction.
2. **The board cannot always name itself.** `USB_PRODUCT` is honoured by exactly one file
   in the core — `cores/esp32/USB.cpp`, the **TinyUSB** stack — so it works on an S2 or an
   S3. A C3 with `CDCOnBoot=cdc` gets the **USB Serial/JTAG** peripheral instead, whose
   product string is its own and cannot be renamed. A C3 bridge is identified by its
   **MAC on the console** and by the label on the board; the build script deliberately
   sets no `-D` there rather than one that reads like it does something.
3. **`status` must say whether the doors are OPEN**, not just whether a client is
   attached. The first C3 build had a real bug — joining WiFi *from the console* left the
   three listeners never `begin()`n, because the join function set the flag that
   `bridgeNetPoll` uses to decide whether to open them. The board answered `ping` with
   every port closed and nothing said why. The fix is one deleted line; the `doors` line
   is what makes the next one of those visible.
4. **macOS's Local Network privacy gates *outbound* LAN connections, per binary.** A
   Python process (Homebrew *or* `/usr/bin`) gets `OSError: [Errno 65] No route to host`
   reaching `192.168.2.3` while `ping`, `nc` and `curl` — Apple's own — reach it fine, and
   the same Python reaches `1.1.1.1:443` without complaint. So: **test the doors with
   `nc` or `curl`, and grant Local Network access to whatever interpreter a host script
   runs under.** This is the outbound twin of the inbound application-firewall prompt
   that `harness-o1next.py` documents, and it fails the same way — a connection that does
   not happen and no message that says why.

## References

- `../../hardware/wifi-comm-pac/pinmap.md` — the modem's pin map, and the authority on
  what may not be touched
- `../../docs/o1-modem-serial.md` — P1 TTL levels, the ACIA at `2A00`/`2A01`, the pinout
- `../zimodem-fork/BUILD.md` — the modem's own build, and the toolchain this shares
- `../../tools/serial-relay-o1next.py` — pty ↔ TCP, for Stage 1
- `../../tools/trace-analyzer/` — the host side of the trace
- `../bus-analyzer/` — the other producer of `#o1next-trace`
