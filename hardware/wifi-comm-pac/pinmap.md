# wifi-comm-pac — the ESP32-S2 pin map

The module's own GPIO allocation. It is one map for **both roles** (the standalone
COMM PAC and the module docked to the interposer/SFF board), because role B changes
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

Twelve pins, of which four are fixed for us rather than chosen.

| GPIO | Function | Notes |
|---|---|---|
| **0** | BOOT button — and factory reset while running | a strapping pin, and the standard dual purpose: hold at reset for the ROM bootloader, hold 5 s while running for Zimodem's factory reset |
| **15** | UART1 **TX** → level stage → O1 RXD (role A) / → RP2354B (role B) | the machine-facing side |
| **16** | UART1 **RX** ← O1 TXDATA (TTL) / ← RP2354B | **RMT taps this same pin** for #319 — see below |
| **33** | I²C **SDA** → AW9523B | |
| **34** | I²C **SCL** → AW9523B | |
| **35** | I²S **BCLK** → audio amp | |
| **36** | I²S **LRCLK** → audio amp | |
| **37** | I²S **DIN** → audio amp | |
| **19** | USB **D−** | fixed — the only USB pins |
| **20** | USB **D+** | fixed |
| **43** | UART0 **TXD** — console and the ROM's own boot log | fixed by the ROM |
| **44** | UART0 **RXD** | fixed by the ROM |

Seven signals are ours to place (15, 16, 33, 34, 35, 36, 37); the other five are
where the silicon puts them.

The **module's own pin numbers are deliberately not restated here** — they are in
the MINI-2 datasheet's §3.2 pin layout, and a secondary source for them is a way
to lose a board. This file fixes *functions*; the layout fixes geometry.

## What is left free, and why

The module brings out 37 GPIO. Twelve are allocated. **The other 25 are left
alone**, and the point of a conservative map is that the reason for each group is
written down:

| Left free | Why |
|---|---|
| **GPIO1–10** | **ADC1** — the only ADC that works while the radio is on (ADC2 is unusable with WiFi). The plausible use is a **rail monitor**: a divider on the +12 V from P1 pin 7 would let the firmware *measure* the sag through R21 rather than argue about it, which is exactly the open question in #324/#325. |
| **GPIO11–14** | touch channels, and nothing here wants touch. Plain enough to spend later. |
| **GPIO17, 18** | **the two DACs** — see the trade above. |
| **GPIO21, 38** | plain spares, kept plain on purpose. |
| **GPIO39–42** | **JTAG**. The debug path is cheaper to keep than to regain. |
| **GPIO26** | the PSRAM chip select **on the R2 variants**. Not allocated, so the N4-vs-N4R2 choice stays open. |
| **GPIO45, 46** | strapping pins, and 46 is input-only. Not available to us. |

## The panel and the handshake — the AW9523B, all 16 channels

Two I²C pins carry eleven lamps and the four P1 handshake lines (#322, #325).
Every channel is spoken for, which is the argument for the part:

| Channel | Function | Direction |
|---|---|---|
| P0_0 | LED — **WiFi radio on** | out |
| P0_1 | LED — **WiFi connected** | out |
| P0_2 | LED — **HS** (≥ 9600) | out |
| P0_3 | LED — **AA** auto answer | out |
| P0_4 | LED — **CD** carrier detect | out |
| P0_5 | LED — **OH** off hook | out |
| P0_6 | LED — **RD** receive data | out |
| P0_7 | LED — **SD** send data | out |
| P1_0 | LED — **TR** terminal ready | out |
| P1_1 | LED — **MR** modem ready | out |
| P1_2 | LED — **RI** ring indicator | out |
| P1_3 | **CTS** → P1 pin 5 | out |
| P1_4 | **RI line** → P1 pin 9 (also the video-PIA UC15 CA2) | out |
| P1_5 | **MSB** → P1 pin 4, through an open-drain N-FET | out (sink) |
| P1_6 | **MCB** ← P1 pin 8 | **in** |
| P1_7 | **spare** | — |

Eleven lamps plus four lines is fifteen; the sixteenth is the spare, kept because
a spare on a part that is already fitted costs nothing.

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
| Panel and handshake | the module's AW9523B | **the same** |
| Audio | the module's I²S amp | **the same** |
| Web UI | the ESP32's own pages | the RP2354B's, bridged |

**Nothing in the allocation changes between roles**, which is the point of #323's
decision: the module is the same module, and only the counterparty at the far end
of GPIO15/16 differs.

## Peripherals that cost no pins

- **RMT for the rate measurement (#319).** RMT is routed through the GPIO matrix,
  and several peripherals can read the same input, so **RMT RX listens to GPIO16 —
  the same pin as UART1 RX**. The measurement front end costs zero pins and needs
  no jumper, no switch and no second wire.
- **PCNT**, likewise, if it turns out to be the better measurement.
- **LEDC** is spare — the panel's dimming is the AW9523B's own.
- **The antenna** is the module's IPEX connector: no GPIO at all, and in role B the
  pod is already outside the case.

## Open before layout

1. **MCB is the one handshake line we *read*** (P1 pin 8), so it needs a port with
   input capability — and an interrupt, if the "host suppressed output" edge is to
   be prompt. Confirm against the AW9523B datasheet that the chosen port supports
   input. **If it does not, MCB moves to a direct GPIO — GPIO38 is the spare — and
   the expander gains a second spare channel.**
2. **MSB needs an open-drain sink** (P1 pin 4 is open-collector, "50 µA sink =
   inactive"), so it is an N-FET on an expander channel, never a push-pull pin
   (#324).
3. **There is no DCD line on P1.** The DE-9 carries MSB (one status bit), CTS and
   RI — so the panel's **CD lamp is socket state**, and the machine-visible carrier
   indication is **MSB**. Confirm that reading against schematic sheet 7 in #324.
4. **The rail monitor** on GPIO1–10 is left *free*, not built. If #324/#325 wants
   it, it is one divider and one pin — and it would turn the R21 budget argument
   into a measurement.
5. **The audio part** is #325's: an I²S-input class-D amplifier with its own DAC,
   three pins, and no GPIO beyond BCLK/LRCLK/DIN.

## References

- `README.md` — the board, and the P1 pinout in `../../docs/o1-modem-serial.md`
- `../../firmware/zimodem-fork/BUILD.md` — the build, and the feature switches
- `../../firmware/zimodem-fork/o1modem/` — the rate table the measurement feeds
- #56 (the module), #317 (the S2), #319 (the measurement), #322 (the panel),
  #323 (the two roles), #324 (P1), #325 (panel/audio/power)
