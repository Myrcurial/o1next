# wifi-comm-pac — the ESP32-S2 pin map

The module's own GPIO allocation. It is one map for **both roles** (the standalone
COMM PAC and the same circuit on the interposer/SFF board), because role B changes
only *what is on the other end of the UART*, not the module (#323).

Tracks: #56, #317 (the S2 decision), #324 (the P1 stage), #325 (panel/audio/power).

**This is a map, not a schematic.** It fixes which GPIO does what, so the firmware
can be written against it and the schematic can be drawn to it. It is deliberately
**conservative**: seven signals on the module's own GPIO, the panel and the handshake
on I²C, and a large margin left unused for things we have not thought of yet.

## The part, and the module

**The SoC is an ESP32-S2** (#317) — it is the variant whose auto-baud pulse counter
is 20-bit, which is what makes O1-side rate detection possible at all (#319).

**The module is an `ESP32-S2-MINI-2U`.** This is not a preference, it is what is
still orderable — checked against Espressif's own datasheets on 2026-10-19:

| Module | Status |
|---|---|
| **ESP32-S2-MINI-2 / MINI-2U** | **current** — no NRND or EOL marking |
| ESP32-S2-MINI-1 / MINI-1U | **NRND** (not recommended for new designs), variants EOL |
| ESP32-S2-WROOM / WROOM-I | **END OF LIFE** (2025-02-24) |
| ESP32-S2-SOLO / SOLO-U | **END OF LIFE** (2024-09-05) |

The **U** suffix is the external-antenna variant, and it is the one #56 §D needs:
the IPEX/U.FL connector takes a pigtail to the case edge, away from the floppy
drives and the CRT. It mates with Hirose **W.FL**, I-PEX **MHF III** or Amphenol
**AMMC**; the certified antenna is ≤ 3.86 dBi at 2.4 GHz, and a different antenna
is a re-test rather than a drop-in.

**Prefer the N4 (4 MB flash, no PSRAM) variant** unless the SSH work needs the
headroom. The reason is a pin, not a price: on the **N4R2** variants GPIO26 is the
PSRAM chip select. This map does not allocate GPIO26 either way.

## What the SoC gives us, and what it takes back

From the ESP-IDF GPIO reference and the SDK's own `soc_caps.h` (both on this
machine, `SOC_GPIO_PIN_COUNT (47)`):

- **GPIO22–25 do not exist**, and **GPIO46 is input-only** and fixed pull-down.
- **GPIO26–32 are the SPI0/1 flash/PSRAM set** — "not recommended for other uses".
  On this module they are simply not brought out.
- **GPIO33–38 are the *second* SPI0/1 pin set** (`FSPIHD`, `FSPICS0`, `FSPID`,
  `FSPICLK`, `FSPIQ`, `FSPIWP`), and this module does not use them: the in-package
  flash is on the 27–32 set, which is why those pins are absent and these are
  exposed as ordinary I/O. The arithmetic is the check — the module brings out
  **37 GPIO**, and 0–21 (22) + 26 (1) + 33–46 (14) is exactly 37. **These six are
  therefore free to allocate, and the map does.**
- **GPIO0, 45, 46 are strapping pins.**
- **GPIO39–42 are the JTAG pins** — usable, but they are the debug path.
- **GPIO1–10 are ADC1** — the only ADC that works while WiFi is on (ADC2 is
  unusable with the radio), plus touch.
- **GPIO17 and 18 are the two DACs** — and, awkwardly, they are *also* UART1's
  IO-MUX default pins. The IO MUX entry is literally `FUNC_DAC_1_U1TXD`.
- **GPIO19 and 20 are USB D−/D+** — the only USB pins there are.

That last pair is the reason this map looks the way it does, and it is worth
stating plainly, because it is the one non-obvious trade in the file:

> **UART1 is routed through the GPIO matrix to ordinary pins, not to its IO-MUX
> default of 17/18.** UART1 can go on any pin; the DACs can go on exactly two. So
> the movable function is put on movable pins and the two DAC pins are left free.
> The cost is one line of GPIO-matrix configuration in the fork's `#define` block.
> If a later revision wants the IO-MUX default instead, it can have it — and it
> loses the DACs.

## The allocation

Fourteen pins, of which four are fixed for us rather than chosen.

| GPIO | Function | Notes |
|---|---|---|
| **0** | BOOT button — and factory reset while running | a strapping pin, and the standard dual purpose: hold at reset for the ROM bootloader, hold 5 s while running for Zimodem's factory reset |
| **15** | UART1 **TX** → level stage → O1 RXD (role A) / → RP2354B (role B) | the machine-facing side |
| **16** | UART1 **RX** ← O1 TXDATA (TTL) / ← RP2354B | **RMT taps this same pin** for #319 — see below |
| **33** | I²C **SDA** → both AW9523B | | |
| **34** | I²C **SCL** → both AW9523B | | |
| **35** | I²S **BCLK** → audio amp | | |
| **36** | I²S **LRCLK** → audio amp | | |
| **37** | I²S **DIN** → audio amp | | |
| **38** | **INTN**, panel AW9523B | added 2026-10-20 — the expander needs an interrupt pin and the first map had none |
| **21** | **INTN**, interface AW9523B (`0x59`) | the second expander's interrupt; DNP if the second part is not fitted |
| **19** | USB **D−** | fixed — the only USB pins |
| **20** | USB **D+** | fixed |
| **43** | UART0 **TXD** — console and the ROM's own boot log | fixed by the ROM |
| **44** | UART0 **RXD** | fixed by the ROM |

Eight signals are ours to place (15, 16, 33, 34, 35, 36, 37, 38, 21); the rest are
where the silicon puts them. **`RESETN` on both expanders is strapped** (10 kΩ to
3.3 V + 100 nF), not a GPIO — a shared reset is not worth two pins.

The **module's own pin numbers are deliberately not restated here** — they are in
the MINI-2 datasheet's §3.2 pin layout, and a secondary source for them is a way
to lose a board. This file fixes *functions*; the layout fixes geometry.

**The schematic now carries the pad numbers**, in `U5`'s symbol: 73 pins numbered
with the module's own pads, taken from the datasheet and cross-checked against
SnapEDA's symbol for the part. That is deliberate and it is not a restatement of
this file — this file says *which GPIO*, the schematic says *which pad*, and the
two only agree because someone checked. The 33 ground pads are stacked behind one
visible pin — the vendor's own convention, and the reason a 73-pad module is a
readable symbol.

**The 26 GPIO left free here are not wasted.** They come out to **`J4`, a 2×13
header that is left unpopulated** — 2×13 because that is exactly 26, with the
module's own IO names on the silk so `IO43` reads as UART0 TXD without a datasheet.
That is what makes "left free" a decision rather than a dead end: the radio, the
DACs, the touch channels and the second SPI set are all reachable by soldering a
header on, without touching U5's footprint. `GPIO0`, `IO43` and `IO44` are among
them — the BOOT strapping pin and the UART0 console, which this map allocates but
the board does not otherwise wire.

## What is left free, and why

The module brings out 37 GPIO. Fourteen are allocated. **The other 23 are left
alone**, and the point of a conservative map is that the reason for each group is
written down:

| Left free | Why |
|---|---|
| **GPIO1–10** | **ADC1** — the only ADC that works while the radio is on (ADC2 is unusable with WiFi). A **rail monitor** was the plausible use. It is not allocated: pin 7 *is* behind `R21` (22 Ω), so the voltage the module sees moves with the load — an argument *for* a monitor rather than against one — but nothing needs it yet, and an unspent group is cheaper to keep than to regain (`README.md` §Power). |
| **GPIO11–14** | touch channels, and nothing here wants touch. Plain enough to spend later. |
| **GPIO17, 18** | **the two DACs** — see the trade above. |
| **GPIO39–42** | **JTAG**. The debug path is cheaper to keep than to regain. |
| **GPIO26** | the PSRAM chip select **on the R2 variants**. Not allocated, so the N4-vs-N4R2 choice stays open. |
| **GPIO45, 46** | strapping pins, and 46 is input-only. Not available to us. |

**GPIO38 and GPIO21 were spares and are now the two expander interrupts** — the
first version of this map gave both AW9523B parts an `INTN` pin and forgot to give
it anywhere to go.

## The panel and the handshake — two AW9523B, split by function

Two I²C pins carry eleven lamps and the four P1 handshake lines (#322, #325).
Both parts are on the same bus at **`0x58`** and **`0x59`**, and they are split by
*job* rather than by pin count — **both are fitted**, because the handshake is not
optional. The split is what buys the headroom: U6 keeps 5 spare channels for more
lamps, U7 keeps 12 for whatever the next idea is.

**U6 — panel (`0x58`).** P0 is push-pull and constant-current; **P1 is open-drain
only** on this part, which is why the last three lamps carry series resistors.

| Channel | Function | Direction |
|---|---|---|
| P0_0 | LED — **WiFi radio on** | out, CC |
| P0_1 | LED — **WiFi connected** | out, CC |
| P0_2 | LED — **HS** (≥ 9600) | out, CC |
| P0_3 | LED — **AA** auto answer | out, CC |
| P0_4 | LED — **CD** carrier detect | out, CC |
| P0_5 | LED — **OH** off hook | out, CC |
| P0_6 | LED — **RD** receive data | out, CC |
| P0_7 | LED — **SD** send data | out, CC |
| P1_0 | LED — **TR** terminal ready | out, open-drain + R |
| P1_1 | LED — **MR** modem ready | out, open-drain + R |
| P1_2 | LED — **RI** ring indicator | out, open-drain + R |
| P1_3–P1_7 | spare | — |

**U7 — interface (`0x59`).** Sits on the **3.3 V side** of the translators;
it gives the handshake a home and two spare channels so the next idea does not
need a respin.

| Channel | Function | Direction |
|---|---|---|
| P1_0 | **CTS** → 74LVC4T245 → P1 pin 5 | out |
| P1_1 | **RI line** → 74LVC4T245 → P1 pin 9 | out |
| P1_2 | **MSB** → 74LVC1G07 (open-drain) → P1 pin 4 | out |
| P1_3 | **MCB** ← 74LVC4T245 ← P1 pin 8 | **in** |
| rest | spare | — |

The expander **holds its outputs**, so a hung firmware leaves a readable frozen
panel rather than a dark one. Both `INTN` lines are open-drain with a 10 kΩ
pull-up, to GPIO38 and GPIO21. `RESETN` is strapped, not driven.

## The fork's `#define` block

Upstream has **no S2 profile** — the `#elif` chain in `zimodem.ino` covers the C3
and the S3 and then falls through to *"standard ESP32 4 & 8MB boards"*, whose pins
are not ours. So the fork supplies its own block, and `-1` means "not fitted",
which is how upstream disables a line:

```c
/* The profile is zimodem/o1next.h in the fork (#330), and this block is its
 * design statement -- the two must not drift.  `-1` is how upstream disables a
 * line. */
#define DEFAULT_PIN_TXD       GPIO_NUM_15  /* UART1, GPIO-matrix routed: NOT the IO-MUX default */
#define DEFAULT_PIN_RXD       GPIO_NUM_16
#define DEFAULT_PIN_DCD       -1   /* the DE-9 has no DCD: the machine sees MSB and RI */
#define DEFAULT_PIN_CTS       -1   /* on the AW9523B */
#define DEFAULT_PIN_RTS       -1   /* not fitted */
#define DEFAULT_PIN_RI        -1   /* on the AW9523B */
#define DEFAULT_PIN_DSR       -1   /* not fitted */
#define DEFAULT_PIN_DTR       -1   /* not fitted */
#define DEFAULT_PIN_SND       -1   /* the sound is I2S, not a beeper */
#define DEFAULT_PIN_OTH       -1   /* stream/command-mode flag: not wired */

/* Left as upstream has them, deliberately not redefined:
 *   PIN_FACTORY_RESET   GPIO_NUM_0   -- the BOOT strap, and the factory reset
 *   DEFAULT_BAUD_RATE   1200         -- upstream's default, and an O1 rate
 *
 * SUPPORT_LED_PINS is left undefined, which is how upstream disables it: the
 * panel is the AW9523B (#322), not three lamps on three GPIO. */
```

`DEFAULT_BAUD_RATE 1200` is upstream's default and it is also an O1 rate, so the
out-of-box case works before any auto-baud exists (#319).

## The two roles, on one map

| | **Role A** — standalone COMM PAC | **Role B** — interposer and SFF |
|---|---|---|
| GPIO15/16 face | the level stage → P1 | the RP2354B (its GP38/39 UART0) |
| Who owns the ACIA | the machine's own 6850 | the RP2354B serves the window |
| Panel and handshake | this board's AW9523B pair | **the same circuit, copied** |
| Audio | this board's I²S amp | **the same circuit, copied** |
| Web UI | the ESP32's own pages | the RP2354B's, bridged |

**Nothing in the allocation changes between roles**, which is the point of #323's
decision: **the schematic is copied, the layout is not**, and only the counterparty
at the far end of GPIO15/16 differs. There is no dock connector — the interposer
and the SFF each carry their own populated copy.

## Peripherals that cost no pins

- **RMT for the rate measurement (#319).** RMT is routed through the GPIO matrix,
  and several peripherals can read the same input, so **RMT RX listens to GPIO16 —
  the same pin as UART1 RX**. The measurement front end costs zero pins and needs
  no jumper, no switch and no second wire.
- **PCNT**, likewise, if it turns out to be the better measurement.
- **LEDC** is spare — the panel's dimming is the AW9523B's own.
- **The antenna** is the module's IPEX connector: no GPIO at all, and on the SFF
  board the module is already outside the case.

## Open before layout

1. ~~**The 2×5 IDC orientation**~~ — **settled 2026-10-21.** It was the board's
   one mechanical unknown: the cable is keyed, but which end was pin 1 was not in
   the schematic. It is now fixed by the footprint, and the answer is written down
   rather than left to whoever does layout — a **right-angle shrouded IDC box
   header** (`IDC-Header_2x05_P2.54mm_Horizontal`), whose own geometry at rotation
   0 puts the mating face at +X and **pin 1 on the left** when you face it.

   The shroud is not decoration: the cable is keyed, and a keyed socket cannot go
   on plain pins — which is exactly what the old footprint specified, so the
   connector could not have accepted the cable it was chosen for. The key is a rib
   inside the shroud between the third and fourth pin pairs, and the part must be
   fitted **key down, toward the PCB**. That last one is a build instruction and
   not a schematic fact: a footprint is 2D and has no "which way up".
2. **The RXD negative swing**, in hardware: the MAX3232 gives ±5.5 V, which is
   inside the machine's −0.5…−10 V window, but the receiving front end is a
   comparator with a 5.1 V clamp and it wants measuring, not assuming (#324).
3. **There is no DCD line on P1.** The DE-9 carries MSB (one status bit), CTS and
   RI — so the panel's **CD lamp is socket state**, and the machine-visible carrier
   indication is **MSB**.
4. **The speaker's placement** — J2 is settled as Same Sky CMS-151103-088SP
   (15 × 11 × 3 mm, 8 Ω, 0.7 W) and its footprint is **complete**, read off the
   datasheet's mechanical drawing: two **0.6 mm square pads on the left and right
   sides, flush with the frame edge**, 14.4 mm apart. **Audio quality is not a
   requirement** — the panel only has to make dial tone, DTMF and a ring cadence,
   and it runs in free air in an unsealed, perforated case, so there is no
   chamber, gasket or port to design. What is left is purely mechanical: that the
   speaker clears the other parts and faces a hole in the panel (#325).

## References

- `README.md` — the board, and the P1 pinout in `../../docs/o1-modem-serial.md`
- `../../firmware/zimodem-fork/BUILD.md` — the build, and the feature switches
- `../../firmware/zimodem-fork/o1modem/` — the rate table the measurement feeds
- #56 (the module), #317 (the S2), #319 (the measurement), #322 (the panel),
  #323 (the two roles), #324 (P1), #325 (panel/audio/power)
