# wifi-comm-pac — the O1NEXT WiFi COMM PAC (ESP32 Zimodem fork)

**Board:** `wifi-comm-pac` — the **O1NEXT WiFi COMM PAC** — the project's
**third deliverable**. See the register in [`../README.md`](../README.md). It
closely models the original Osborne 1 COMM PAC 300-baud modem and lives in the
left-hand floppy storage pocket, taking power and signal from the MODEM (P1)
9-pin port. The PCB also hosts ~10 indicator LEDs, a 15 × 11 mm speaker, the aux power
port for the keyboard adapter, and a USB-C port for programming or powering the
ESP32.

Hayes-compatible WiFi modem for the Osborne 1, built as **one design with two
physical instantiations**: the standalone COMM PAC in the machine's floppy
pocket, and the same schematic copied onto the interposer and the SFF board
(#323). It is not a daughterboard — the interposer carries its own copy of the
circuit, and only the thing on the far end of GPIO15/16 differs.

Tracks: #56 (extension of #21). Physical interface documented by #57.

## Definition

- **Base:** Zimodem fork targeting **ESP32-S2** (not ESP8266, and not the C-series)
  — the S2 is the variant whose auto-baud pulse counter is **20-bit**, which is what
  makes the machine-side rate detection work at all (#317, #319); it carries the
  SSH client (`INCLUDE_SSH`), and the ESP8266 lacks the headroom entirely.
- **New O1-specific work on top:**
  1. **SSH as first-class transport** — keys, host verification, session
     management via the web UI; `ssh` from the O1 into a modern host.
  2. **Baud-rate buffering/correction** — decouple O1-side ACIA rate
     from the far-end link rate; makes the 2× business turbo (#55)
     usable and quietly corrects the factory 600/2400 → 650/2600 quirk.

## The MCU, the module, and the pin map

**ESP32-S2**, in an **`ESP32-S2-MINI-2U`** module — the **U** for its IPEX/U.FL
connector, which is what lets the antenna go on a pigtail to the case edge, away
from the floppy drives and the CRT (#56 §D).

That is the *current* part rather than a preference. On 2026-10-19, against
Espressif's own datasheets: the **MINI-1/MINI-1U are NRND**, and the **WROOM and
SOLO/SOLO-U are end of life** (2025-02-24 and 2024-09-05). The MINI-2 line is what
is still recommended for new designs.

**The pin map is [`pinmap.md`](pinmap.md)** — fourteen GPIO allocated, the other 23 of
the module's 37 deliberately left free, the panel and the four P1 handshake lines on
two I²C pins, and the fork's `#define` block written out in full. It is **one map for
both roles**: role A and role B differ only in what sits on the other end of
GPIO15/16 (#323).

## Host interface — MODEM port (P1): DE-9 pigtail, 2×5 IDC on the board

**The module does not plug into the machine.** The COMM-PAC sits in the
**left floppy pocket**, a short **10-conductor ribbon** leaves it, and a **DE-9
plug** on the far end goes into the machine's MODEM socket. The board end of
that ribbon is a **2×5 IDC header** — which is why the connector and its
orientation are ours, not inherited (#324). The manual describes it exactly:
*"plug the small, rectangular connector on the modem cable into the 10-pin
socket on the modem… grooved to fit only one way"* (`research/osborne1/Comm-Pac_Users_Manual.pdf`).

Ten conductors carry nine DE-9 signals plus one spare; the original modem used
only six of them (no CTS, no RI), and ours uses all of the status lines.

**TTL levels, not RS-232** — the port feeds the 6850 ACIA directly (status
`2A00H` / data `2A01H`), bypassing the level shifters.

| P1 | Signal | Level | Direction |
|---|---|---|---|
| 1 | GND | — | — |
| 2 | TXD | **5 V TTL** | O1 → module |
| 3 | — | not used | — |
| 4 | MSB | **open-collector** ("50 µA sink = inactive") | module → O1 |
| 5 | CTS | TTL | module → O1 |
| 6 | RXD | **bipolar, −0.5…−10 V = 1** | module → O1 |
| 7 | **+12.6 V DC** | labelled `VDD` in the Comm-Pac manual | power |
| 8 | MCB | TTL, low = suppress output | O1 → module |
| 9 | RI | TTL, falling edge sets the flag | module → O1 |

### The level stage — five signal paths, three part types

**5 V TTL is not 3.3 V, and this board has to say so.** The 6850 and the PIA are
+5 V parts, so TXD and MCB arrive as a 0–5 V swing. The ESP32-S2's input limit
is `VDD + 0.3` — it is **not 5 V tolerant**. An earlier version of this file
said the receive direction needed "no level work"; it does.

| Path | Part | Why |
|---|---|---|
| TXD, MCB (5 V → 3.3 V) | **74LVC4T245** | dual-supply translator, 5 V-tolerant B side |
| CTS, RI (3.3 V → 5 V) | **74LVC4T245** | the second 4-bit half; one `DIR` per package, so mixed directions cost two packages, not one |
| MSB (3.3 V → open-collector) | **74LVC1G07** | open-drain, 5 V-tolerant output; a push-pull driver would violate the interface |
| RXD (3.3 V → bipolar) | **MAX3232 at 3.3 V** | on-chip charge pump gives **±5.5 V**, inside the machine's −0.5…−10 V window and under the 5.1 V clamp; at 5 V it would swing ±9–10 V, needlessly close to both limits |

The MAX3232's receivers are RS-232-threshold and must **not** be used for the
TTL lines. Its 3.3 V rail is taken **after** the diode-OR, so an unpowered board
can never drive the machine's RXD.

Still to confirm in hardware: the physical orientation of the 2×5 header, and
the RXD negative swing, both on a real machine (#324).

## Power

**DE-9 pin 7 is +12.6 V DC, and it is not behind the 22 Ω.** Reading sheet 7 of
9 at 600 dpi settles it: `R21 = 22 Ω` sits between the `+12V` net and
**`J6 pin 1 → J6 pin 2 → P4-19`** — the *keyboard* branch. P1 pin 7 is drawn on
the `+12V` net with **no series part on the sheet**. The Astec supply is rated
`+12 V @ 2.02 A` (11.40–12.60 V), and the Comm-Pac manual labels the pin
**+12.6 V**.

So the old "shared R21 budget" story is retired: the keyboard adapter's 22 Ω and
this port's supply are **separate**, and the port can supply what a period modem
drew. The maintainer's figure for the original COMM-PAC is **~500 mA at 12 V**;
the modern board is a small fraction of that.

- **Buck 12.6 V → 5 V**, then **5 V → 3.3 V**; USB-C VBUS is **5 V → 3.3 V only**.
  Two sources, **diode-OR** (Schottky pair, or a P-FET ideal diode if the drop
  matters) so neither back-feeds the other.
- **Switch ahead of the buck**, latching slide type, so "off" is genuinely dark.
  USB still runs the board with no machine attached (bench-prep, #207).
- **Bulk capacitance at the buck input** for WiFi TX bursts — a few hundred µF.
  With no 22 Ω in the path there is no inrush problem to design around.
- The machine's `−12 V` rail is rated **0.1 A**; the negative rail for RXD comes
  from the MAX3232's own charge pump, never from the machine.

## Panel

**Eleven lamps and the handshake, on I²C — two AW9523B, split by function.**
U6 (`0x58`) carries the lamps; U7 (`0x59`) carries the four P1 handshake lines.
Both are fitted, because the handshake is not optional: 16 channels each, 5 and
12 spare respectively, and the pin argument is closed for good.

- 8 lamps on **P0** — push-pull, constant-current, per-LED dimming.
- 3 lamps on **P1** (TR, MR, RI) — **P1 is open-drain only** on this part, so
  those three get series resistors and sink from 3.3 V.
- The handshake sits on the 3.3 V side of the translators: CTS and RI out,
  MSB through the `1G07`, MCB in.

The expander **holds its outputs**, so a hung firmware leaves a readable frozen
panel rather than a dark one. Two **INTN** lines go to GPIO38 and GPIO21, and
`RESETN` is strapped with an RC (or shares one GPIO) — the earlier map had no
pin for either, which the second expander forces us to fix.

LED states and semantics are #322; current is set to **2–3 mA** per lamp.

## Audio

An **I²S-input class-D amplifier with its own DAC** (MAX98357A class) on the
**5 V** rail, three pins (BCLK/LRCLK/DIN) plus gain/mode straps, driving a
**real speaker** — not a piezo buzzer, and not an active buzzer. Both are the
wrong part: an active buzzer knows one note, and a bare piezo element is
non-linear and thin across the band, where the panel has to make **the noise a
modem makes**.

**J2 is Same Sky CMS-151103-088SP** — 15 × 11 × 3 mm rectangular frame, 0.7 W
(1.0 W max), **8 Ω**, PEEK cone, Nd-Fe-B magnet, solder-pad terminals. **8 Ω is the
only number that matters** — it is the load the MAX98357A wants — and the part is
small enough for the floppy-pocket envelope. Pin 1 is the **`+`** terminal (the
datasheet's polarity: the cone moves forward with positive dc on `+`), so it takes
`SPK_P`.

**Audio quality is explicitly not a requirement.** The panel is a noise generator:
it has to make dial tone, DTMF and a ring cadence, and nothing more. It runs in
**free air** in an unsealed case with a perforated front panel — no chamber, no
gasket, no port — and no response curve, resonance or SPL figure is designed
around. The datasheet's Fo and SPL are 1 cc-box measurements and are deliberately
not repeated here as if they described this board.

Its footprint is ours (`o1next:Speaker_SameSky_CMS-151103-088SP`), and its geometry
comes off the datasheet's mechanical drawing: the 15 × 11 × 3 mm body, and **two
0.6 mm square solder pads on the left and right sides**. They are drawn 14.4 mm
apart, with each pad's outer edge flush with the 15 mm body end — that flush
offset is the one number read rather than stated, and it is what would change if
the drawing insets them. The part it replaced was a Multicomp Pro
MCKPT-G1340-3917 piezo buzzer; that footprint has been deleted.

Dial tone, DTMF and ring cadence are in #322; prior art is `na103/zimodem`
(CC BY 4.0 — method only).

## The schematic

`wifi-comm-pac.kicad_sch` (KiCad 7 format, A1) — **Rev A, captured**, which is
what the case STL and the placement drawing are sized against. It is
**generated**, not hand-drawn: `gen_wifi_comm_pac_sch.py` emits the sheet, and
`tools/check_schematics.py` re-generates it and asserts the invariant nets (which
P1 pin carries which signal, that the machine's 5 V never reaches a 3.3 V pin,
that the 12.6 V rail stops at the buck, and that no symbol or label collides).

**The nets are wired, not label-connected.** Every signal net is drawn as
orthogonal wire segments between the pins it joins; the supply rails use power
symbols, which is how a schematic normally shows GND/3V3/5V. Exactly **one net
label per net** is kept, so the net *names* survive — and because it is one
label and not fifteen, a missing or mis-routed wire breaks the netlist instead of
being papered over by a label.

A small Manhattan router does the drawing, on a 1.27 mm grid:

- symbol bodies are impassable;
- another net's wire may be **crossed** but not travelled **along** (that would be
  a collinear overlap, i.e. a short), and may not be **ended on** (that would make
  a junction);
- **another component's pin is impassable** — a wire routed through a pin is a
  short that no label ever reveals, and it is what the first wiring pass did wrong;
- nets are routed longest-first, so the long runs get the open corridors.

It is a *first-draft* drawing: correct, complete and readable in blocks, but the
long runs (USB to the MCU, the interface expander to the level stage) are routed
for clearance rather than for beauty. A placement pass — moving the USB block
next to the ESP32 — is what would make it read like a finished drawing, and it is
cosmetic, not electrical.

```sh
python3 hardware/wifi-comm-pac/gen_wifi_comm_pac_sch.py
python3 tools/check_schematics.py --board wifi-comm-pac
```

| Ref | Part | Why |
|---|---|---|
| J1 | 2×5 IDC | the P1 pigtail; pin *n* = DE-9 pin *n* |
| U1, U2 | 74LVC4T245 | 5 V ↔ 3.3 V, one package per direction |
| U3 | 74LVC1G07 | MSB, open-drain only |
| U4 | MAX3232 | RXD, bipolar, on 3.3 V |
| U5 | ESP32-S2-MINI-2U | the modem |
| U6, U7 | AW9523B ×2 | panel (0x58) and handshake (0x59) |
| U8 | MAX98357A | I²S class-D audio |
| U9, U10 | TPS54331, AP2112K | 12.6 V → 5 V → 3.3 V |
| D13, D14 | Schottky pair | the diode-OR between the port and USB |

**Footprints are now all assigned** — **71 of 71** component symbols carry one, so
`Update PCB from Schematic` transfers the whole board rather than nothing. What is
still true is that the **multi-pin ICs' pin numbers are logical placeholders**,
not the vendor footprints': they exist so the netlist checker can name a pin, and
binding them to the real package pinout is the first layout task. **J3 is the
exception** — it now uses the part's own numbers (A1–A12, B1–B12, SH1–SH6), because
its footprint has 30 pads and every one of them needed a net.

The 2×5 orientation and the RXD swing are the two hardware confirmations (#324).

## Enclosure

The case STL is **already designed and fit-tested** by the maintainer; the
apertures it currently cuts are **USB-C** and the **2×5 IDC**. Final placement,
left to right looking at the front of the machine:

1. **antenna connector** — RP-SMA bulkhead (reverse-polarity, as every WiFi
   pigtail is; the module end is U.FL), fed from the MINI-2U's IPEX connector
2. **power switch**
3. **2×5 IDC** — the P1 ribbon
4. **LED row** — 11 × 3528 with light pipes
5. **USB-C**

The schematic fixes the parts; the placement drawing that goes with it is what
lets the STL be finalised (#56 §E).


## References

- `pinmap.md` — the MCU, the module, and every GPIO
- `docs/o1-modem-serial.md` (authoritative pinout + levels)
- `docs/o1-memory-io-map.md` §"6850 ACIA detail"
- `hardware/interposer-upgrade/` — the interposer the module docks to (#323)
- Upstream: https://github.com/bozimmerman/Zimodem
