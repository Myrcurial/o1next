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

## The schematic — two directories

**Two directories, and the generator writes into only one of them.**

| | |
|---|---|
| `wifi-comm-pac-generated/` | the generator's output. Regenerated at will. |
| `wifi-comm-pac-edited/` | the copy a person works on. Never written by the generator. |

`gen_wifi_comm_pac_sch.py` is the **first take** — the mathematical proof that the
circuit is what the netlist says it is. It is not a finished drawing and it cannot
be one: turning it into something a person can read and work on takes a person.
So both exist, and the rule between them is one line:

> if `-edited/` holds a schematic, **the copy is aborted** and the generator says
> so; if `-edited/` is empty, the generated schematic is copied across.

A regeneration therefore cannot overwrite anybody's work, and the first person to
pick the board up gets a starting point without running anything. To deliberately
re-seed, empty `-edited/` first — which discards what is in it.

`tools/check_schematics.py` asserts the **generated** file: the invariant nets
(which P1 pin carries which signal, that the machine's 5 V never reaches a 3.3 V
pin, that the 12.6 V rail stops at the buck), that no symbol or label collides,
that no symbol pin is without a footprint pad, and that the file matches a fresh
regeneration.

### Four sections, and parts sit next to what they connect to

The sheet is A1 (841 × 594 mm) divided into four regions, because the complaint a
reader actually has is not that things are unconnected — it is that they are
connected *across the page* and so cannot be followed:

| Section | Holds |
|---|---|
| **POWER** (bottom band) | the P1 12.6 V rail and the USB-C front end — diode-OR, buck, LDO, polyfuse, the CC pulldowns, the ESD clamp, and the 5 V out |
| **LOGIC** (left, upper) | J1, the level stage, the ESP32 and its support parts, both expanders, and the free-GPIO header |
| **PANEL** (right, upper) | the 11 lamps, one row each: resistor and LED side by side |
| **AUDIO** (right, lower) | the MAX98357A and the speaker |

### The free-GPIO header, J4 — and why it is 2×13

U5 leaves **26 GPIO** unused. They were marked no-connect, which is correct but
*terminal*: the pad is on the module's footprint, the header is not, and reaching
it later means redoing the board. **J4** brings all 26 out to a **2×13 header** —
2×13 exactly, because that is the 26 GPIO and not 2×14 with grounds.

**It is left unpopulated, and marked `dnp`** so KiCad keeps it out of the BOM and
off the placement file. That is the difference between "left unfitted on purpose"
and "we forgot to order it". The pads cost nothing and mean somebody can solder a
header on later and use the radio, the DACs, the touch channels and the second SPI
set without touching U5's footprint.

Pins are numbered the way a 2×13 is — odd on row 1, even on row 2 — and **named
with the module's own IO names**, so the silk says `IO43` and that is UART0 TXD
without a datasheet lookup:

| | row 1 (odd) | row 2 (even) |
|---|---|---|
| | IO0 IO1 IO2 IO3 IO4 IO5 IO6 IO7 IO8 IO9 IO10 IO11 IO12 | IO13 IO14 IO17 IO18 IO26 IO39 IO40 IO41 IO42 IO43 IO44 IO45 IO46 |

One table in the generator builds U5's symbol, names these nets, *and* labels the
header, and `check_schematics.py` asserts each of the 26 as an **exact pair** — one
U5 pad and one J4 pin. Three separate lists would drift, and the first thing to
drift would be a header pin labelled `IO18` that is really `IO17`, which is the
worst possible bug on a header a hobbyist is meant to use.

### 5 V out to the keyboard adapter

**J5** is a **JST PH, side entry, SMD** (`S2B-PH-SM4-TB`). It is fully shrouded
with a polarising slot, so the plug cannot go in the wrong way round and **there is
no reverse-voltage case to design for**. Side entry means the cable leaves parallel
to the board, straight out the front of the floppy pocket. 2 A, 100 V, 2.0 mm
pitch; KiCad carries the footprint, so nothing is drawn here.

It is fed from the **diode-OR output** (`+5V`), so whichever source is present —
the machine's 12.6 V through the buck, or USB VBUS — feeds the port. That is what
lets the keyboard adapter drop its 12 V→5 V buck and keep only its LDO.

**U11 is the current limit on it.** `D13`/`D14` are SS14 — **1 A each** — so the
5 V rail cannot source more than about an amp, and a port labelled "5 V out"
invites somebody to plug in a load that wants three. `U11` is a **TPS2553**
current-limited power-distribution switch, and `R28` sets the limit: `I_OS = 25.6 /
R_ILIM`, so **27 kΩ gives about 0.95 A** — under the diodes, and 15× the ~60 mA the
adapter draws. It limits rather than latches, so nothing needs to know when it
does; `FAULT` is unused for that reason.

### ESD on the USB-C input

**`D15`** is a `PESD5V0S1BA` on `VBUS_IN`, upstream of the diode-OR, so it is the
first thing a transient meets. 5 V standoff, so it does not conduct on a 5.25 V
VBUS, and it clamps low enough not to overstress the `AP2112K` downstream. The
port is *meant* for a computer; "meant for" is not a protection.


### The wiring, and the defect it fixes

Every signal net is drawn as orthogonal wire segments; the rails use power
symbols; every pin ends on a wire, a power symbol, or a deliberate no-connect
marker. Nothing floats — the generator fails loudly if a pin does.

The router builds a **spanning tree** per net (each pin joined to the nearest
point already on the net, so branches share a trunk) and then **normalises** the
result: every segment is split wherever any point of the same net lies on it, the
duplicates that leaves are dropped, and a junction is placed wherever three or
more wire ends meet.

That normalisation is not cosmetic, and it is the answer to a real failure. The
earlier **star** router drew each pin back to the first pin, which produced
**overlapping collinear segments** — 15 of them, plus 2 exact duplicates. KiCad
tolerates that until it saves the file, at which point its own cleaner normalises
the geometry, and pins that had been attached *only* by sitting inside an overlap
come adrift, because a pin in the middle of a wire is not connected without a
junction. That cost **14 pins across 10 nets** the first time anybody opened the
sheet in KiCad. **A wire KiCad would rewrite is a wire drawn wrong**, so the
generator now does the normalisation itself.

It is checked, not asserted: `kicad-cli sch upgrade` re-saves the schematic in the
current format — the operation that broke the old file — and the netlist before
and after is identical (70 nets, 248 nodes, 0 single-node nets, 317 wires and 8
junctions unchanged). The old file went from 15 overlaps to a broken netlist under
the same operation.

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
`Update PCB from Schematic` transfers every part rather than nothing.

**But the board is not yet correct, and this is the first layout task.** The
**multi-pin ICs' pin numbers are logical placeholders**, not the vendor packages'.
They exist so the netlist checker can name a pin. The footprints are real; the
pin↔pad correspondence is not. **U5 is the dangerous one:** its symbol has 18
pins numbered 1–18, the `ESP32-S2-MINI-2U` footprint has 73 pads numbered 1–65
plus `61_1`…`61_9`, and the numbers *collide by name* while disagreeing in
meaning — symbol pin 1 is `+3V3`, the module's pin 1 is **`GND1`**. So a transfer
today puts 3.3 V on a ground pad. The other multi-pin parts are merely incomplete
rather than wrong: U1/U2 (9 pins against 16 pads, two of four channels modelled),
U8 (9 against 17), U3 (5 against 6), U6/U7 (24 against 25 — pad 25 is the exposed
pad), SW1 (2 against 7 — the five mounting tabs). U4, U9 and U10 are exact.

**J3 is the exception** that shows the fix: it now uses the part's own numbers
(A1–A12, B1–B12, SH1–SH6) because its footprint has 30 pads and every one of them
needed a net. Doing the same for the others means binding each signal to a real
module pin, which is a **GPIO allocation decision** for U5 rather than a datasheet
lookup.

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
