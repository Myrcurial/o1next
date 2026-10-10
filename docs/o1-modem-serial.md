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
