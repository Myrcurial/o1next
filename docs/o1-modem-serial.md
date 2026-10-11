# Osborne 1 MODEM (P1) and RS-232 (P2) serial interfaces

Source: Osborne 1 Technical Manual, ch. 4 "Osborne 1 Interface Design" —
§4.2 SERIAL RS232 INTERFACE, §4.3 MODEM — archived in-repo at
`research/osborne1/modem/o1techman-interface-extract.pdf` (manual pages 17–19).

This is the authoritative connector/pinout reference for the WiFi-modem work
(#21, extended by #56) and for the severable modem module (#56 §E / COMM PAC
variant). The memory-map and ACIA register detail live in
`docs/o1-memory-io-map.md` §"6850 ACIA detail"; this document adds only the
**physical connector** information that doc does not carry.

## 4.2 RS-232 serial interface (P2)

- Configured as **RS-232C-compatible DTE**, but *"certain of the RS-232C
  signals are held at +5 volts since they are not needed to control the
  Osborne 1."* A **6850 ACIA** drives the port.
- Port addresses: **status `2A00H`, data `2A01H`** (shadow mode). Status bits
  (Fig 4.2): `RDRF`, `TDRE`, `DCD`, `CTS`, `FE`, `OVRN`, `PE`, `IRQ` — see the
  6850 datasheet for full semantics.

### DB-25S pinout (Fig 4.2.2)

| DB-25 | RS-232 | Definition |
|---|---|---|
| 1 | AA | Frame ground (optional) |
| 2 | BA | Transmitted data (low = 1) |
| 3 | BB | Received data (low = 1) |
| 4 | CA | Request to send (high or no connection enables) |
| 5 | CB | Clear to send (**always high on OCC 1**) |
| 6 | CC | Data set ready (**always high on OCC 1**) |
| 7 | AB | Signal ground |
| 8 | CF | Received line signal detected (**always high**) |
| 20 | CD | Data terminal ready (high or no connection enables) |

Pins 9–19, 21–25: no connection. Only the listed pins are wired.

## 4.3 MODEM interface (P1) — **TTL levels, not RS-232**

> "The modem and RS-232 interfaces are basically one and the same. In addition
> to the serial port, **TTL-level signals may be directly input into the 6850
> ACIA using the modem port connection.**"

The MODEM jack is the clean way to attach a TTL-serial device (an ESP32 WiFi
modem, our module) **straight onto the ACIA** without an RS-232 level shifter.
Read/write it via the CP/M `IOBYTE` function, same as the serial port.

### 4.3.1 Signal direction

| Osborne 1 | dir | Modem device |
|---|---|---|
| GND | — | GND |
| TXDATA | → | TXDATA |
| RXDATA | ← | RXDATA |
| MSB | ← | MSB |
| CTS | ← | CTS |
| MCB | → | MCB |
| +12 | → | POWER IN |
| RI | ← | CD |

### 4.3.2 DE-9P pinout ("standard numbering of the DE-9P connector")

| Pin | Signal | Definition |
|---|---|---|
| 1 | GND | Signal ground |
| 2 | TXD | Transmitted data — **TTL logic, 1 = high** |
| 3 | — | Not used |
| 4 | MSB | Modem status bit — open collector, 50 µA sink = inactive |
| 5 | CTS | Clear to send |
| 6 | RXD | Receive data — **bipolar input, −0.5 V…−10 V = 1** |
| 7 | +12 V | Connected to power supply through **22 Ω** |
| 8 | MCB | Modem control bit — TTL, **low suppresses output** |
| 9 | RI | Ring indicator — TTL, high-to-low sets flag |

### Design notes for #56

- **Levels are asymmetric.** TXD/MCB/RI are plain TTL (drive/read directly from
  a 3.3 V MCU with the #12 level spec). **RXD is a bipolar input**
  (−0.5…−10 V = mark): on sheet 7 the RXDATA line enters receiver **UE3
  (LM1458 op-amp)** with zener clamp **CR1 (1N5231B, 5.1 V)** — a
  comparator-style front-end, not a plain TTL gate. So driving RXD with 0–5 V
  (or 0–3.3 V) leaves the mark (1) level at/below threshold. The module should
  swing TX-toward-O1 **negative** for a clean mark (a small charge-pump −5 V,
  or bias the comparator reference), and this must be **validated on real
  hardware** — see the open item below.
- **+12 V on pin 7 is current-limited by 22 Ω** (schematic sheet 7: R21 — the
  same R21 that feeds keyboard P4 pin 19 through jumper J6). Fine to sense,
  and marginal as a *sustained* source; the **interposer-onboard** module is
  therefore powered from the interposer's dedicated 5 V rail (research-gaps
  #5) rather than from P1. The **severable external** module is the reverse
  case — it exists because the port carries power at all. Its current budget
  is deliberately deferred until a board exists: see
  `hardware/wifi-modem-module/README.md` §Power.
- **MSB (pin 4) is open-collector** and **MCB (pin 8) low suppresses output** —
  together these are the modem's "hook"/enable handshake. RI (pin 9) falling
  edge sets the ring flag; the ESP32 can drive it to signal an incoming
  "call" (AT RING) to the O1.
- **CTS is the only hardware flow-control line** brought out (pin 5).

## On-board P1 header — schematic-confirmed

Schematic sheet 7 (SERIAL I/O, `OCC1_1A2011-00_Schem_RevE.pdf`) draws the P1
(MODEM) connector on the right edge with the **DE-9P pin numbers carried
through unchanged** — there is no renumbering between the case DE-9 and the
on-board P1 header:

| P1 pin | Net | P1 pin | Net |
|---|---|---|---|
| 1 | GND | 2 | TXDATA |
| 4 | MSB | 5 | CTS |
| 7 | +12V (via **R21 22Ω**) | 6 | RXDATA |
| 8 | MCB | 9 | RI |
| 3 | (NC) | | |

Physically P1 is a **2×5 IDC male header** on the board, cabled to the case
DE-9P with a straight ribbon (1:1, no conductor swap). A straight IDC crimp
interleaves the DE-9 rows, so on the 2×5 the signals land as: row A
(1-2-3-4-5) = DE-9 **1,3,5,7,9** = GND, NC, CTS, +12V, RI and row B
(6-7-8-9-10) = DE-9 **2,4,6,8,—** = TXDATA, MSB, RXDATA, MCB, NC.

> The schematic confirms the **signal→pin** mapping (the table above). The
> **physical orientation** of the 2×5 header on the board (which end is pin 1)
> is a layout detail not in the schematic — confirm against the PCB silkscreen
> / a real board before committing a PCB footprint. Same class of in-hardware
> validation as #47.

Also on sheet 7 (for the record): the ACIA baud clock comes from **UC3
(LS161)** dividing a `4USEC`/`2USEC` tap (jumper **J1** selects the rate), and
**MODEM RI** routes to the video-PIA **UC15 CA2** input (sheet 5) — consistent
with `docs/o1-memory-io-map.md`.

## Baud-rate options the archive documents (#21)

The stock machine gives 300/1200 (J1 in) or 600/2400 (J1 out), and the factory
documents 2400/9600 as a modification — the jumper and divider detail is in
`docs/o1-memory-io-map.md` §"6850 ACIA detail". Two further things come from
*The Portable Companion* #8 (July 1983).

### The factory modification, as the Companion cites it

The issue's "**The CRT Connection**" box (PDF p. 87, printed 85) tells a user who
wants an 80-column terminal to *"set your computer for 9600 baud using Osbaud or
the method shown on page 22 in the Technical Manual."* That page is the
manual's **Figure 4.4 "Baud Rate Hardware Modification"** — the LS161/LS163 at
C3, pin 2 moved, J2 fitted, J1 *"DON'T CARE"* — quoted in
`docs/o1-memory-io-map.md` §"6850 ACIA detail". So the Companion's
pre-SCREEN-PAC answer to "how do I get 80 columns?" was the **serial port plus
the factory's own baud mod**, not a video board.

### The CRT recipe itself

1. Set the machine for **9600 baud** (as above).
2. Connect a standard serial cable between the terminal and the computer. The
   cable is only **pins 1, 2, 3 and 7, straight through** (1–1, 2–2, 3–3,
   7–7).
3. Set the terminal's DIP switches to **1 start bit, 1 stop bit, 8 data bits,
   no parity, full duplex**.
4. `STAT CON: = CRT:` to make the terminal the console.
5. *"The end result is a 80-column, 9600 baud refreshed, block cursor
   screen."* The procedure is *"untested with terminals other than
   Televideo"* — the reviewer's was a **Televideo 920C**.

### Advent Products "Osbaud" — a clock substitution, not a bus interposer

Reviewed by **Brad Baldwin** in the same issue (PDF p. 87, printed 85; extract
at
`research/technical-articles/TPC-Issue08-1983-pp87-osbaud-baud-rate-generator.pdf`).
$59.95, **16 DIP-switch-selectable baud rates**, used by the reviewer at **110**
(an ASR33 Teletype), **9600** (the Televideo 920C) and **19200** (a $10,000
high-speed band printer), with mainframe up/downloads at high speed. It is
*"a small auxiliary circuit board … soldered to the main logic board **in the
area behind the serial port**"*, with the DIP switches reached through **a small
slot cut in the venting grill** and a self-adhesive rate chart stuck to the
keyboard. Advent even supplies the .050" Allen wrench for the brightness and
control knobs, and the package covers both case colours (blue/gray and
black/brown). Installation wants a Phillips screwdriver, an **Xacto knife to cut
across a circuit trace**, and a low-wattage soldering iron — and, like any such
product, **voids the warranty**.

#### The four solder points, decoded

*"Osbaud is soldered to **pins 4 and 12 of the 6850 UART**, **pin 7 of the
74LS32**, and **pin 7 of the 74LS04**."* Read against the schematic
(`docs/o1-mainboard-schematic.md` sheet 10, and §"6850 ACIA detail" in the
memory map):

| Solder point | Is | Why |
|---|---|---|
| 6850 **pin 4** | **TxCLK** — strapped on the board to pin 3 (RxCLK) | the clock *input*: one wire drives both halves of the ACIA |
| 6850 **pin 12** | **Vcc** | +5 V, taken from the ACIA's own supply pin |
| 74LS32 **pin 7** | GND | ground |
| 74LS04 **pin 7** | GND | ground — and this one is **UB3**, the inverter inside the ACIA's own baud divider |

So OSBAUD does not tap the bus, needs no address, and does not use the LS161's
socket: it **replaces the ACIA's clock**, powered and grounded from the ACIA's
immediate neighbourhood. That makes the Xacto knife unambiguous — the trace to
cut is the one carrying the factory clock (UC3's `QD`) to the ACIA's clock pins,
so that OSBAUD's oscillator is the only driver on that net.

#### What the design has to be

The review gives the connections and the rate count, not a schematic, so the
rest is inference — but tightly constrained:

- The ACIA still divides by 16 or 64 internally (the factory's Figure 4.4 is
  captioned *"SPEED SELECTED W/IN 6850"*), so OSBAUD's clock is **16× the marked
  rate** on the ÷16 setting — 800 Hz … 307.2 kHz across 50 … 19200 baud.
- Sixteen rates off a DIP code means sixteen selectable taps, but **a single
  binary chain from one crystal cannot produce the odd rates** of the standard
  16-rate list (110, 134.5, 2000), so the divider has to be
  **preset/programmable** — the same trick the factory divider next door uses,
  its LS161 being a preset-load counter (`RCO` → inverter → `/LD`).
- The three rates the reviewer names (110, 9600, 19200) all sit inside the
  classic 50/75/110/134.5/150/300/600/1200/1800/2000/2400/3600/4800/7200/9600/
  19200 set — the same list Nuevo's optional generator advertises ("16 baud
  rates from 50 to 19.2K", `docs/o1-upgrade-boards.md`).

**Open:** the crystal and divider topology, whether the ACIA is left in ÷16
mode, and where the **74LS32** sits on the board (the LS04 is UB3 on the serial
sheet; a 74LS32 near the serial port has not been located on the schematic yet).
The OSBAUD instruction sheet — which the review calls thorough — or a photo of a
fitted board would settle all three; worth watching for on the second-hand
market.

## Framing — the 6850 control byte in the BIOS (#21, #56)

Baud rate is only half of what a modem personality has to present. The other half
is the **frame** — data bits, stop bits and parity — and OCC documented how to
change it. "**Programming the serial port — modifying the serial port for
scientific test devices**", signed by the **Osborne Computer Corporation System
Technical Support Group**, in *The Portable Companion* #7 (June 1983, PDF
pp. 56–57 = printed 54–55; extract
`research/technical-articles/TPC-Issue07-1983-pp56-57-programming-the-serial-port.pdf`)
is a worked BIOS patch:

- The factory default is **8-bit data, 1 stop bit, no parity**.
- The change is a **single control byte written into the BIOS image**: build a
  relocatable CP/M (`MOVCPM 60 *` for a **1.3** BIOS, `MOVCPM 59 *` for **1.4**),
  `SAVE 39 CPM60.COM`, `DDT CPM60.COM`, then **`S1FE9`** and put the code in at
  **`1FE9H`/`1FEAH`**, and `SYSGEN` it to the target disk. So the ACIA's
  **control-register init byte lives at BIOS offset `1FE9H`** — a second,
  independent handle on the ACIA beyond the `2A00H`/`2A01H` port pair, and the
  address to watch for #21/#56.
- **Figure 1** is a "**Table of 6850 control codes**" covering all 16
  combinations at 1200 and 300 baud — e.g. **8-N-1 @1200 = `55H`**, **8-N-1 @300
  = `56H`**, 7-E-1 @1200 = `49H`, 8-N-2 @1200 = `51H`; arrows mark the factory
  default. Read as the 6850's control register (word-select bits 2–4, clock-divide
  bits 0–1) the values are exactly right, which is a useful cross-check on the
  `docs/o1-memory-io-map.md` §"6850 ACIA detail" claim that the ACIA divides by
  16 or 64 — the `55H`/`56H` default sits in the **÷16** field.
- **Figure 2** is a **which-BIOS-do-I-have** test: `DDT`, `DA900`, and look at the
  third byte after the `490` — `C3 xx E5` is a **1.3** BIOS, `C3 xx E1` a
  **1.4**.

The article does not touch the baud divider, so it is complementary to the
Hogan/Figure 4.4 rate modifications above: **rate from the divider, frame from
the BIOS control byte**. For the module (#56) both matter — a WiFi modem that
only ever presents 300/1200 8-N-1 will fail on a machine whose owner has patched
the frame for a lab instrument, which is exactly the case the article exists for.



