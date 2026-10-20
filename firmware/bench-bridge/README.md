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

## Stage 0 — measured, 2026-10-20

From the Mac, through the rig. **Items 1–3 pass. Item 4's instrument is built and
measured; its *report* is #319's.**

### 1. `AT` returns `OK` — ✅

Over the USB relay:

```
o1next> relay
AT
AT
OK
-- escaped to the console (3 bytes in, 8 out, 0 dropped)
```

and over the **TCP relay door**, which is the same relay through the other door:

```
$ ( printf 'AT\r'; sleep 3 ) | nc -w 6 192.168.2.3 2323
AT
OK
```

### 2. The dial reaches the harness's telnet server — ✅

> **The syntax is `ATDT <host>:<port>` — one token, with a colon — and NOT
> `ATDT <host> <port>`.** `ZCommand`'s `validateHostInfo()` fails any command whose colon
> is missing or doubled (`colonDex <= 0`), so the space-separated form fails validation and
> answers `NO ANSWER`. #342's acceptance and its handover both wrote the space-separated
> form. Measured on the bench.

```
o1next> relay
ATDT 192.168.2.1:2323
CONNECT 2
o1next harness telnet -- Cortexiphan
type `quit` to hang up
```

and the harness's own log, which is the other end of the same fact:

```
12:33:13  192.168.2.2      telnet session opened
```

### 3. The trace shows both directions with times — ✅

`trace dump` after that dial, 103 records, every byte carrying its own millisecond:

```
#o1next-trace 1 bench-bridge ms
676402 > 41 54 44 54 20 31 39 32 ... 0d      <- ATDT 192.168.2.1:2323 out
676618 < 43 4f 4e 4e 45 43 54 20 32 0d 0a    <- "CONNECT 2" back
676743 < 6f 31 6e 65 78 74 ...               <- "o1next harness telnet -- ..."
```

**And the Stage 1 shape works through the TCP door**, which is what that door is for:

```
$ ( printf 'ATDT 192.168.2.1:2323\r'; sleep 12 ) | nc -w 16 192.168.2.3 2323
ATDT 192.168.2.1:2323
CONNECT 3
o1next harness telnet -- Cortexiphan
```

Because that door is a **pure pipe** it passes the modem's own `+++` hangup straight
through — which is what to reach for when the USB door's escape would eat it:

```
$ ( sleep 1.5; printf '+++'; sleep 2.0; printf 'AT\r'; sleep 4 ) | nc -w 12 192.168.2.3 2323
+++OK
AT
OK
```

### 4. A paced 650-baud stream — the instrument is measured, the report is #319's

```
o1next> rate 650
rate 650 bps
         the MODEM must be at this rate too -- `send ATB 650` while both ends still agree
o1next> pace 128 55
pacing 128 bytes of 0x55 at 650 bps -- 2.0 s of wire
done
```

and the trace, which is where the pacing is *measured* rather than asserted:

```
records: 130
first: 865150 > 55 55 55 ... (64 bytes)
last : 867130
span : 1980 ms
ideal: 129 intervals x 10 bits / 650 baud = 1984.6 ms
```

**Within 5 ms of ideal**, which is the whole reason this is the rig's job and not the
emulator's: the UART hardware paces the bytes, so the waveform *is* the rate.

**What is not done is the modem reporting it.** Nothing on the modem measures the incoming
waveform yet — that is #319, and its 20-bit auto-baud counter is why the S2 was chosen for
the modem in the first place. The rig can be the precise host for that measurement today;
the measurement is not there to be taken.

Stage 1 (`-rs232 pty` through `tools/serial-relay-o1next.py` to the TCP relay door) is
#342's second half, and the door it needs is now proven working.

**And the relay has a second far end, for a host-level reason.** macOS's Local Network
privacy gates *outbound* LAN connections per binary: a Python process gets
`Errno 65 No route to host` reaching the rig on the local network while `ping`, `nc` and
`curl` reach it fine. So `tools/serial-relay-o1next.py` gained **`--serial <port>`** — the
rig's own USB door, with no network in the path at all, which cannot be refused that way.
Put the rig in `relay` first; its USB console is the console until you do.

```sh
tools/serial-relay-o1next.py --pty /dev/ttys001 --serial /dev/cu.usbmodem2144201
```

### Stage 1, attached — the two baud rates have to agree, 2026-10-20

The last hop is done: `AT` written to the emulated ACIA came back as `AT` echoed plus `OK`
from the real modem, through the rig. The relay log of the moment is the proof — `A` and
`T` out, and `O` and `K` coming back into the emulated machine:

```
pty -> far     1  A
far -> pty     1  A
pty -> far     1  T
far -> pty     1  T
pty -> far     1  .        <- CR
far -> pty     1  .        <- the modem echoes it
far -> pty     1  .        <- LF
far -> pty     1  O        <- the modem's answer, arriving in the ACIA
far -> pty     1  K
```

**It was blocked for a while on a baud mismatch that presents as a wiring fault**, so the
two numbers are written down here. A byte written to the pty reached the rig as
`78 f8 00 78 78 00` — which is what a **9600 pty sampling a 1200 ACIA** looks like, and
which reads as "the cable is wrong" when the cable is fine.

MAME's `pty` device is a `device_serial_interface`: it decodes the ACIA's TXD line at
`RS232_RXBAUD` and encodes onto RXD at `RS232_TXBAUD`, and **both default to 9600**. The
Osborne's ACIA does not run at 9600. The driver's `"Serial Speed"` config
(`osborne1.cpp`) offers 300/1200, 600/2400, 1200/4800 and 2400/9600, and **the default is
300/1200** — so a stock machine is 1200 at its high setting.

Those ports are **not settable on the command line** — `-rs232:pty:RS232_TXBAUD` is
rejected as an unknown option in every tag form tried. MAME reads and writes them in
`cfg/<machine>.cfg`. `tools/emulator-setup/mame-osborne1nx/rs232-pty-1200.cfg` is that
file, ready to copy into the directory MAME runs from; it sets both ports to
`value="4"` (1200) against a `defvalue="7"` (9600).

**And the guest has to select the same rate, from the ACIA's own control register.** Bits
CR0/CR1 are the 6850's clock division — 00 = ÷1, 01 = ÷16, 10 = ÷64, 11 = master reset —
and with the 300/1200 wiring the ACIA's clock is 19200 Hz, so ÷16 gives 1200 and ÷64 gives
300:

| control word | CR1 CR0 | division | rate |
|---|---|---|---|
| `0x15` | 0 1 | ÷16 | **1200** |
| `0x16` | 1 0 | ÷64 | 300 |

`0x16` is the one that is easy to reach for, because the two bits read as "16". It is the
300-baud word. **This is the "poke the low/high bit" step, and it is why a machine left at
its default behaves as a 300-baud machine.**

So the working sequence is: copy the cfg, boot with `-rs232 pty` **at real speed**, then
from the guest `poke 0x2A00 3` (master reset), `poke 0x2A00 0x15` (8N1, ÷16), and write
bytes to `0x2A01`. `peek 0x2A00` then reads `03` — TDRE and RDRF, i.e. it received.

**What is still open:** driving a *multi-byte* command (the `ATDT host:port` dial string)
out of the ACIA. Three bytes go — `AT` + CR — and the rest do not leave, so the write path
needs gating on TDRE between bytes rather than blind `poke`s. Stage 1's hop is proven;
the dial string is the next step, and it is a guest-side scripting question, not a rig one.

### Stage 1, complete — a real BBS on the machine's own screen, 2026-10-20

**End to end, and watchable.** The chain is

```
MAME -rs232 pty -> tools/serial-relay-o1next.py -> ESP32-C3 rig -> real modem
                -> WiFi -> bbs.8bitboyz.com:6502 -> back into the emulated ACIA
                -> MDM740 (the 1984 Osborne Comm-Pac terminal) -> the screen
```

and what the emulated machine displayed, read off its own video memory, is a real
BBS's ANSI banner:

```
r07| ZDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD?
r08|3 1 Welcome to 8-Bit Boyz BBS system                                          3
r09|@DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDY
r11| The account name you entered was not located in our account database.  If you
r12| wish to create a new account, answer YES below to continue on to the new
r13| account application.  If you've mistyped your account name, answer NO and you
r14| will be returned to the login prompt.
r16|Create an account with this BBS? No
r18|[~] Enter your user name:
```

`MDM740.COM` runs from **`B:`** of the MD-10 hard disk. The session is boot ->
`HARD` -> `B:` -> `MDM` -> **`T`** -> `ATDT bbs.8bitboyz.com:6502`.

**And that session runs the pty at 300, not the 1200 the shipped cfg carries.** The
Comm-Pac overlay's default is 300, so `cfg/osborne1nx.cfg` needs `value="2"` (300) for
it — MDM740 selects the rate itself and the pty has to match it. The rig is not the
constraint here: it re-times, and drives the modem at 1200 regardless. But the pty and
the ACIA must agree with each other, so **the pty's rate follows the guest's, and
`rs232-pty-1200.cfg` is the 1200 case (ACIA control `0x15`), not a universal file.**

#### `T` is the pass-through, and it is the whole trick

MDM740's own help text, read out of the overlay on the hard disk image, says it in
one line:

```
T = Terminal mode (full duplex, echo provided remotely)
```

At the `B>>COMMAND:` prompt, **`T` puts the program straight into terminal mode** —
a transparent keyboard-to-ACIA pipe. That is what makes this a *terminal* demo
rather than a serial demo: you type `ATDT ...` yourself and the **modem** dials.
Going the other way, `CAL` (Dial number) is the program's *helper*, and it is the
wrong tool here: it is a 1984 dialer that validates a **phone number** and rejects
a hostname outright, which is how `CAL bbs.8bitboyz.com:6502` ends back at the
prompt with nothing on the wire.

MDM740's three-letter commands are `CPM DIR ERA LOG SPD TCC TLC TLF TRB TXO SET
BYE CAL DSC DEL WRT`, and its terminal-mode local commands are `CTL-N` (disconnect),
`CTL-P` (toggle printer — the `LST:` device), `CTL-Y`/`CTL-R` (buffer copy),
`CTL-T` (send ASCII file) and `CTL-[` (send a local control character).

#### Watching it needs four things that headless does not

`tools/emulator-setup/mame-osborne1nx/` is where the launcher lives; a watching run
differs from a headless one in four ways, and each of them is a way to lose time:

- **`-skip_gameinfo`.** Without it MAME stops on its own *configuration display*
  with "press any key to continue" **before the emulated machine exists** — and the
  Lua key script posts to the emulated machine's natural keyboard, so it cannot
  press that key. The session deadlocks on a screen that is not the guest's.
- **`-window`, and no `SDL_VIDEODRIVER=dummy`, no `-video none`.** The headless
  launcher sets all three.
- **Real speed — never `-nothrottle`.** Otherwise a 300-baud modem does not look
  like one.
- **A keystroke before the first `wait`.** The Osborne stops at *"Insert disk in
  Drive A and press RETURN"*, so a script whose first instruction is `wait A>`
  waits forever on a machine that is waiting for it. Send `key cr` first.

#### The `CAL` library, as a period artifact

`CAL` presents the Comm-Pac's built-in dialing directory — a page of 1984 names and
numbers, `Kirk De Haan`, `Jack Kinn`, `Keith Petersen`, `Larry Snyder`, `Wayne
Masters`, `Bruce Ratoff` and more — and prompts `Enter library code or phone number`.
It is a nice thing to leave on the screen.

### Before you close the machine: hang the modem up

**A session that closes with the modem still in a call poisons the next one.** The
modem keeps the telnet session, so the next `ATDT` does not dial — the emulated
terminal comes up already *inside* the old BBS session, mid-application, and every
byte typed goes to the BBS instead of to the modem's command parser. That presents
as "the terminal is at the wrong prompt", and the terminal is innocent: nobody hung
up. On 2026-10-20 this cost a session that dialled into its own predecessor's
connection and could not tell.

`tools/hangup-o1next.sh` is that step, and it prints the proof:

```sh
tools/hangup-o1next.sh            # rig at the default address
```

Four things about it are worth knowing, and each is a way to get it wrong:

- **The door is the rig's TCP relay door, `:2323`, because it is always raw.** The
  USB door's `+++` escape would swallow the escape before the modem saw it.
- **One client at a time.** The rig is a pipe, not a hub: while
  `tools/serial-relay-o1next.py` holds the USB door, the modem's answers go *there*
  and a TCP client sees nothing. Stop the relay first.
- **`+++` then `ATH` — not `ATH0`.** `+++` is the Hayes escape (about a second of
  silence either side, **no trailing CR**) and is only needed if a call is up.
  Zimodem v4.0.3 accepts **`ATH`** and answers `OK`; **`ATH0` is answered `ERROR`**.
  The trailing-0 form is Hayes-standard and is the one you reach for, so an `ERROR`
  here does not mean the hangup failed — it means the command was not understood.
- **The proof is the rig's trace, not `nc`'s stdout.** The console (`:2325`) and
  trace (`:2324`) doors are independent of the relay, so the trace still records
  UART1 while the relay holds the USB door. `ATI` answers with a *banner* only when
  the modem is in command mode, so banner + `READY.` + `OK` is the proof that
  nothing is off-hook.

```
+++ATH
OK
ATI
Zimodem ESP32 Firmware v4.0.3
sdk=v4.4.7-dirty chipid=0 cpu@240
tot=4096k heap=94k fsize=110k
CONNECTED TO o1next (192.168.2.2)
READY.
OK
```

### Reading the guest's screen: the top rows are stale

MDM740's terminal mode does **not** clear the screen, so its own banner
(`B0>MDM`, `MDM740 modem pgm`, `Version for Osborne COMM-PAC modem`) stays in video
memory while the BBS writes over the lower rows. A screen dump taken in terminal
mode therefore shows a *mixture*, and reading the banner as "we are at the command
prompt" is exactly the mistake it invites. In terminal mode the live text is at the
bottom; the prompt you left is not where the cursor is.

### A rig bug worth its own issue

The rig's `help` output **truncates mid-word** at a fixed point — every run stops at
`relay raw   the same, with the e`, so the rest of the command list is unreachable
over the console. `status` is fine; it is `help` specifically.

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

> **Read this as a chronology.** When the notes below were taken the modem end was mute
> (a wire on the wrong pin), so the counters read `out 0` and that is called the diagnostic
> rather than the failure. It was: **the modem was fixed and Stage 0 then passed — the
> results are in the Stage 0 section above.**

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
