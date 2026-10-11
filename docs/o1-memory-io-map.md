# Osborne 1 — Mainboard Memory & I/O Map

Authoritative memory map, I/O decode, and bank-switch behavior extracted from
the Osborne 1 mainboard schematic (OCC `1A2011-00` Rev E) and cross-checked
against the Osborne 1 Technical Manual (`2F00153-01`, 1982) and the MAME
`osborne1.cpp` driver.

Closes issue #40. Unblocks: #11 (hardware), #16–#24 (firmware), the
memory-resident vs pure-I/O decision (gap #15), 6850 ACIA modem (#21, gap #10),
WD179x floppy interposer (#20, gap #11), and ScreenPac personality (#24).

---

## 1. CPU and clocking

| Item | Value |
|---|---|
| CPU | NEC μPD780C (≡ Zilog Z80A), DIP-40, location **UC11** |
| Crystal | 15.9744 MHz (X1) |
| CPU clock | 4 MHz (÷4 via UD3 LS161) |
| Dot clock | 8 MHz |
| Memory / char clock | 2 MHz / 1 MHz |
| Bus width | 8-bit data (DATA0–7), 16-bit address (ADR0–15) |

Wait-state generation: RAM accesses insert wait states (≈375 ns for non-M1
Wait-state generation: RAM accesses insert wait states (≈375 ns for non-M1
cycles, 188 ns for the first M1); ROM executes without added delay.

### 1a. One crystal, no free lunch — and the 2× "business turbo"

Per Lee Felsenstein's rule of thumb — *"the number of crystals in a machine design
is equivalent to the number of designers"* — the O1 has **one** oscillator, and the
whole timing economy (video, ACIA baud, floppy data separator, DRAM refresh,
software delay loops) is divided down from it. Consequences:

- **Serial quirk already visible:** the J1 600/2400 jumper is ~8.3% fast (650/2600
  actual) because the video-tap ÷13 ÷(16|64) chain can't land exactly on 600/2400
  from 15.9744 MHz. The factory's own alternate baud rate shows the seams.
- **No clean general turbo:** 3× has no integer relationship to the video chain
  (breaks video), and any CPU speedup drags the ACIA baud rate, the FDC data
  separator, and software timing loops along with it.
- **The clean-ish 2×:** doubling the CPU clock to 8 MHz keeps the ÷2 dot-clock tap
  coherent (15.9744 ÷ 2 = 8 MHz), so **video timing survives**. It is viable *for
  business apps* if the three side effects are engineered around:
  1. **Floppy** — the WD1793 data separator is timed for 4 MHz; in turbo mode
     physical floppies are out. Use the interposer's storage instead (#20/#22:
     image-library / IEEE-488 storage answers on the bus at whatever speed the
     host runs), or gate turbo off when the FDC is selected.
  2. **Timing loops** — accept that games/delays run double-speed; scope the
     feature to calculation-bound work (SuperCalc recalc, dBASE II, compilers,
     assemblers). A classic PC-era **"TURBO" switch** selects 4 MHz ↔ 8 MHz.
  3. **Serial** — no clean fix at the ACIA. Mitigation: build a **baud-rate
     buffering corrector** into the WiFi modem (#21). The modem's RP2350 talks to
     the far end at a rock-solid standard rate (2400/9600) and tolerates whatever
     the O1 ACIA is actually doing: on **send** it buffers until a batch accumulates
     before transmitting; on **receive** it buffers a frame, then re-clocks it out
     to the O1 at the rate the O1 expects. The O1-side rate drift becomes the
     modem's problem, not the link's.
- **Net:** a 2× business turbo is a *documented, buildable option* (mostly on the
  replica #49, where SRAM removes the DRAM-refresh constraint); it is not a general
  speedup and doesn't pretend to be.

cycles, 188 ns for the first M1); ROM executes without added delay.

## 2. Memory banks

The 64 KB address space is overlaid by **three banks**, selected by the
`ROM MODE*` signal and the `BIT 9` latch (see §4).

### Bank 1 — main RAM ("normal mode")
64 KB of 4116 dynamic RAM. The top 4 KB is dual-purpose as video RAM.

| Range | Contents |
|---|---|
| `0000–3FFF` | RAM (boot ROM overlays the low 16 KB when bank 2 is active) |
| `4000–EFFF` | RAM — CP/M TPA, BDOS/CCP, BIOS live here |
| `F000–FFFF` | Video RAM low 8 bits (128 cols × 32 rows char data) |

**Page zero.** CP/M owns `0000–00FF` while a program runs, but the *Osborne 1
User's Guide* "Memory Allocation" chart (p. R-243) marks **`0050H–005BH` — 12
bytes — as "not used"**, and at least one published program relied on that: the
date facility in *The Portable Companion* #7 keeps the system date there in both
binary and ASCII form (`docs/rt60a-analysis.md`). Treat it as documented free
scratch space — worth remembering for the interposer (#12).

### Bank 2 — BIOS ROM + memory-mapped I/O ("shadow mode")
Selected when `ROM MODE*` is active (low). Only `0000–3FFF` is affected;
`4000–FFFF` still reads bank 1 RAM.

| Range | Contents |
|---|---|
| `0000–0FFF` | Monitor ROM (4 KB, 2732 at **UD11**; earlier 2× 2716) |
| `1000–1FFF` | Unused — reads as mirror of the ROM |
| `2000–2FFF` | Memory-mapped I/O window (see §3) |
| `3000–3FFF` | Unused — reads as mirror of `2000–2FFF` |
| `4000–FFFF` | Mirrors bank 1 RAM |

### Bank 3 — video attribute bit ("dim bit")
Selected when `BIT 9` latch is set. A 9th bit per video cell, stored in a
dedicated 4116. Only `F000–FFFF` is affected.

| Range | Contents |
|---|---|
| `F000–FFFF` | Video attribute RAM, 4K×1 (dim attribute = bit 8 of each cell) |

### 2a. Video memory geometry — 128 columns wide, 52 displayed (#97)

The 4 KB at `F000–FFFF` is **32 rows of 128 characters**, of which **24 rows of
52 characters are displayed at a time**:

> Memory from 0F000 hex to 0FFFF hex is used for the video memory map. That
> memory is considered to be 32 rows of 128 characters, even though only 24 rows
> of 52 characters are actually displayed on the monitor screen at a time. The
> character matrix is 7 × 9 in an 8 × 10 box.
> — *Osborne 1 Technical Manual*, §5.2 "Video Memory", p. 23

**This is the answer to the "64 vs 52" question in #97.** The screen is a
*window* onto a buffer 2.5× wider and 1.3× taller than what is shown, and the
displayed width is a property of the window, not of the memory. That is why the
same 4 KB shows 52 columns on stock hardware, 80 on Nuevo and 104 with the
ScreenPac (`mame-emulation.md` §2) — the text layout is the CBIOS's, the window
is the machine's.

It is also why the scrolling feels different from a terminal's. Holding Ctrl and
using the arrow keys slides the window over the memory rather than moving the
memory, which is a register change and not a rewrite of the buffer — the same
mechanism `mame-emulation.md` §6 calls a ring buffer. A terminal scroll *does*
move the lines, which is why that stays chunky while the viewport slide is
smooth. (The Ctrl+arrow slide is a hardware observation, reported on the real
machine; the geometry above is the manual's.)

**Bit fields** (§5.2, figure): bits 0–6 are the **ASCII character**, **bit 7 is
the underline attribute**, **bit 8 is dim**. Bits 0–7 are the byte in the video
RAM proper; bit 8 is the separate 4116 in bank 3. This is why the MAME probe
masks with `% 128` to read characters (`tools/o1_mame_probe.lua`).

**The window width is software-selectable.** The SCREEN-PAC user guide (p. 13)
gives the mechanism, and it is in the stock BIOS rather than on the board:

> At BIOS location **E1A5H**, POKE or store **0 for 52 columns / 1 for 104
> columns / 3 for 80 columns**. CALL BIOS location **E4E5H**. … In these same
> formats, SCREEN-PAC provides **horizontal scrolling by 32 column blocks**.

So 52, 80 and 104 are three widths of one window onto the same 128×32 buffer,
and the 32-column blocks are why the slide lands on round numbers. Without the
SCREEN-PAC only 52 is available, because the wider windows need the board's
dual-port video RAM — the ROM contains the routine either way.

**Logical width is not physical width — this is what "64 vs 52" turns on.** The
SCREEN-PAC guide (p. 13) separates the two, and it is the piece the technical
manual's geometry leaves implicit:

> **Logical screen size** refers to the number of characters you can enter on a
> line without automatically inserting a carriage return. Logical screen size can
> range from 1 up to a **maximum of 128 characters**.
>
> **Physical screen size** refers to the number of columns actually displayed on
> your screen. With SCREEN-PAC, this will be 52, 80, or 104.
> — *Osborne 1 SCREEN-PAC User Guide*, p. 13

So a program's line width is a **software** choice up to 128 — the width of the
video memory row — while the window is 52, 80 or 104. A drawing 64 columns wide
is a *logical* line of 64 characters: it fits the row, and the window slides over
it. The guide also warns against the obvious mistake, which is worth knowing
before writing anything that sets a width: "logical screen size should NOT be
less than physical screen size", or the display scrambles.

The width is set from the configuration screen (Item C, "Screen Size", in the
Osborne 1 Configuration Program) or from software by poking `E1A5H` and calling
`E4E5H` as above. Both do the same thing.

**The cursor is hardware, and it can be reversed** (#24). The stock cursor is an
**underline**, and OCC knew it was poor — Thom Hogan argued against it while at
the company and was refused twice (*The Portable Companion* #13, June/July 1984,
"Reverse Video and a Faster Serial Port", p. 24): he could not get the change made
permanent, and could not get permission to publish it, *"as the company was
worried about the legal implications of publishing modifications"*. The
modification makes the cursor a **solid white block**, and the article locates the
circuit precisely: a **74LS86 piggybacked on the 74LS00 at E22**, with **pin 1 of
the 74LS74 at UE21 lifted**, plus changes around the VIDEO and DIM signals.

So **the cursor is generated in hardware** — not by the character generator, and
not by the attribute bit — which matters to a video personality: it has to
reproduce a cursor the machine makes outside video RAM, and the block cursor is
the variant OCC's own engineer preferred. Extract:
`research/technical-articles/TPC-Issue13-1984-pp26-31-reverse-video-and-9600-baud.pdf`.

**And it works with the SCREEN-PAC fitted, leaving the board in place.** Hogan's
version is for a stock machine. A reader's fix, printed in *The Portable
Companion* #15 (Jan/Feb 1985, letters, PDF p. 32), makes the block cursor work on
a machine with the **SCREEN-PAC 80** installed — *"and it can be carried out
without removing the piggy-back board containing the Screen-Pac 80
electronics"*. What changes is **where** the logic is: the modification is done
on the *upgrade board's* own chips — **U2 (74HC00)** and **U23 (74HC74)** — not
the main board's, and the letter warns in capitals that *"THESE PINS ARE NOT THE
SAME ONES LISTED IN THOM HOGAN'S ARTICLE!"*.

That the SCREEN-PAC carries a 74HC00 and a 74HC74 of its own is useful in itself:
the cursor logic is **duplicated on the piggy-back board**, which fits the service
manual's description of the upgrade as an IC-harness board soldered over the main
logic (`2F00040` §6.12, the source used by `firmware/screenpac-video/`). Extract:
`research/technical-articles/TPC-Issue15-1985-pp32-block-cursor-with-screenpac.pdf`.

## 3. I/O decode (bank 2, "memory-mapped I/O")

All onboard peripherals are **memory-mapped**, reached through the bank-2
window. Chip-selects are generated from address lines within `2000–2FFF`.

| Address | Device | Chip | Registers |
|---|---|---|---|
| `2100–2103` | Floppy disk controller | Fujitsu MB8877 ≡ WD1793 (**UB7**) | 2100 stat/cmd, 2101 track, 2102 sector, 2103 data |
| `2201–2280` | Keyboard (read) | 81LS95 + 74LS05 (**UE12/13/14**) | One address bit per row: 2201=row0 … 2280=row7; columns on DATA0–7 |
| `2900–2903` | IEEE-488 PIA | MC6821 (**UC7**) | 2900 PA data/dir, 2901 PA ctrl, 2902 PB data/dir, 2903 PB ctrl |
| `2A00–2A01` | Serial / modem ACIA | MC6850 (**UC4**) | 2A00 status(R)/control(W), 2A01 RX(R)/TX(W) |
| `2C00–2C03` | Video PIA | MC6821 (**UC15**) | scroll/offset latches, bell, brightness, dim control |
| `2400` (read) | SCREEN-PAC presence | — | **bit 2 LOW = SCREEN-PAC fitted**, HIGH = stock machine (user guide p. 13). Read-only status bit, not a register |

### 6850 ACIA detail (#21 modem, gap #10)
- Base `2A00`: read = status, write = control. `2A01`: read = RX, write = TX.
- Baud clock from divider **UC3** (÷13) fed by a 2/4 µs tap off the video
  counter (UA13). ACIA (UC4) divides by 16 or 64 → **1200 or 300 baud**.
- Jumper **J1** selects 300/1200; Rev E+ can be re-jumpered to 600/2400.
- **Faster rates, from inside OCC** (#21): *The Portable Companion* #13
  (June/July 1984), "Reverse Video and a Faster Serial Port" by **Thom Hogan** —
  the same Hogan whose `AUTOCPM.ASM` is the source of the site wordmark (#97) —
  written as former OCC manager of software and publications: *"developed
  internally by the company, [but] not promoted … the primary … was the problem of
  warranty repair on modified machines."*
  - Removing **J1** doubles 300/1200 to **600/2400** — exactly as above — and he
    adds a detail the schematic cannot show: **the SETUP program cannot sense
    J1**, so it still displays 300/1200 after the modification.
  - For **2400/9600** the mod is to the baud divider: the **LS161/LS163 at C3**,
    with **pin 2 moved to the middle pin of J2** ("for 2400/9600 baud rates rather
    than 1200/4800") and pins 3, 7 and 10 lifted. Figure 3 in the article has the
    detail. Extract:
    `research/technical-articles/TPC-Issue13-1984-pp26-31-reverse-video-and-9600-baud.pdf`.
- **Pin level, from the schematic** (sheet 7/9 of 9, read at 600–1200 dpi): the
  ACIA's **RxCLK (pin 3) and TxCLK (pin 4) are strapped together** on the board
  and driven by **UC3's `QD` (pin 11)**. UC3 is a **74LS161 preset-load
  counter** — `RCO` (pin 15) is inverted by **UB3 (74LS04)** into `/LD` (pin 9)
  — so the count length comes from the preset pads rather than being a power of
  two; that is where the ÷13 of the stock 19.2 kHz clock lives. Pin numbers as
  drawn: `RXDATA` 2, `RxCLK` 3, `TxCLK` 4, `/RTS` 5, `TXDATA` 6, `/IRQ` 7,
  `CS2` 8, `/CS1` 9, `CS0` 10, `RS` 11, `R/W` 13, `E` 14, `D7…D0` 15–22,
  `/DCD` 23, `/CTS` 24 (Vcc/Vss, pins 12/1, are not drawn on the symbol).
- **The factory's own 9600/2400 modification is documented**, which the archive
  had only from inside OCC: *Osborne 1 Technical Manual* **Figure 4.4 "Baud Rate
  Hardware Modification", p. 22** (PDF page 36 — the manual's printed-page
  offset of **+14** holds here too, see `docs/o1-chargen-graphics.md`). It draws
  the LS161/LS163 at **C3** with **pin 2** moved between a *"FOR 9600/2400
  BAUD"* pad and a *"FOR 4800/1200 BAUD"* pad, jumpers **J2** and **J3**,
  **J1** marked **"DON'T CARE"**, and the caption box
  `300/1200 NO MOD - J1 IN` / `600/2400 NO MOD - J1 OUT` /
  `1200/4800 MOD W/O PIN 2 (J1 = X)` / `2400/9600 MOD W/PIN 2 (J1 = X)`,
  bracketed *"**SPEED SELECTED W/IN 6850**"*. That is the same modification
  Hogan describes from inside OCC in #13 — the 6850 choosing within each pair
  (÷64/÷16). It is also the "method shown on page 22 in the Technical Manual"
  that *The Portable Companion* #8 points a would-be 80-column terminal user at
  (see `docs/o1-modem-serial.md`).
- **A fifth route, and a third-party one:** Advent Products' **Osbaud**
  (1983, $59.95, 16 DIP-switch rates) is soldered to the ACIA's own clock and
  supply pins and replaces the clock net outright — see
  `docs/o1-modem-serial.md`.
- **The ACIA's control-register init byte is in the BIOS at `1FE9H`.** The
  vendor's own "Programming the serial port" patch (*The Portable Companion* #7,
  June 1983, PDF pp. 56–57) rewrites `1FE9H`/`1FEAH` to move off the 8-N-1
  default, with a table of 6850 control codes (`55H` = 8-N-1 @1200). A second
  handle on the ACIA besides the port pair — see `docs/o1-modem-serial.md`
  §"Framing".
- Modem status (DTE): MSB (pin 4), MCB (pin 8), RI (pin 9); BIOS `LISTST`
  at `0E12D` returns `0FFH`/`00H`.
- **IRQ0** = ACIA interrupt (one of three IRQ sources; see §5).

### WD179x floppy detail (#20 floppy interposer, gap #11)
- Controller **UB7**, registers `2100–2103` as above.
- Drive-select / density lines are driven from the **video PIA (UC15)**
  outputs (DRIVE1/DRIVE2/DDEN), **not** a dedicated latch — see schematic
  sheet 5. `DDEN` selects double density when the add-on DD board is present.
- Stock format: single-sided single-density, 40 tracks × 10×256-byte sectors
  (102 KB/drive), FM. DD option board adds 5×1024 Osborne-DD, 8×512 IBM,
  18×128 Xerox-820, 9×512 DEC-182 formats.

### Keyboard detail
- 8×8 keyswitch matrix; rows driven on address lines A0–A7 (one-hot),
  columns returned on DATA0–7.
- Read strobes at `2201, 2202, 2204, 2208, 2210, 2220, 2240, 2280`
  (i.e. `2200 + (1<<row)`).
- 14 programmable keys (Ctrl-0…9, four arrows) via BIOS + SETUP.

| `F000–FFFF` | Video attribute RAM, 4K×1 (dim attribute = bit 8 of each cell) |
## 4. Bank switching (the mechanism)

Banking is controlled by **writes to I/O space**, decoded by **UD10**
(LS138) on the two low address bits; the data bus value is **ignored**.

| I/O write | Effect |
|---|---|
| `0x00` | Clear UB4 → `ROM MODE*` low → **select bank 2** (ROM+I/O). Also forced by CPU reset. |
| `0x01` | Preset UB4 → `ROM MODE*` high → **select bank 1** (main RAM), if `MREQ` low. |
| `0x02` | Set `BIT 9` latch (UE10A) high → map **bank 3** (dim bit) into `F000–FFFF`. |
| `0x03` | Clear `BIT 9` latch → map bank 1/2 back into `F000–FFFF`. |

`ROM MODE*` is *also* set by hardware: power-on reset, and the NMI flip-flop
chain (UB6/UB4). Bank selection between 1 and 2 is additionally qualified by
M1 and IRQ-acknowledge conditions via three flip-flops — so interrupt
acknowledge and the front-panel RESET reselect the ROM bank automatically.

> **Interposer note:** because only the two low address bits are decoded and
> data is ignored, *any* `OUT (0),A` / `OUT (1),A` toggles banks. The
> interposer must **never** drive I/O addresses `0x00–0x03`.

**Measured on the running machine** (`tools/check_o1_map.sh`, #64). All four
writes behave exactly as tabulated — the *port number* selects, the data byte is
ignored, and ports `0x04`–`0x07` alias `0x00`–`0x03` (MAME's I/O space reports
`mask=0x0003`, i.e. only A0/A1 reach the decode). The M1/IRQACK qualification
above is not a footnote: write `0x01` and the RAM bank is selected *immediately*,
but 10 ms of emulated time later the machine is back in the ROM bank, because
the bank is re-derived on every instruction fetch and the video PIA interrupts at
60 Hz.

Consequences for an interposer:

- The bank state **cannot be latched and assumed** — it has to be sampled per
  bus cycle, and a bank-2 I/O access is only meaningful while the CPU is
  actually running with bank 2 selected.
- At the idle `A>` prompt the machine is parked in a ROM polling loop with
  **bank 2 live**, which is why a peek at `0x0000` during CP/M returns ROM
  bytes, not CP/M's page zero.

## 5. Interrupts

Three IRQ sources into the Z80:
- **IRQ0** — serial ACIA (UC4)
- **IRQ1** — video PIA IRQA (UC15)
- **IRQ2** — IEEE-488 PIA IRQA (UC7)

**NMI** is generated by the front-panel **RESET switch S1** (debounced by
UE20, sequenced through UB6/UB4 on `M1`): NMI restarts the ROM program at
`0000` and forces bank 2. There is **no periodic/60 Hz NMI** — the "60 SEC"
signal is a video-tick line into the video PIA CA1 (used by the console
routine's real-time clock), not an NMI.

## 6. Connector / socket pinouts (mechanical tap points)

### Z80 CPU — DIP-40 (UC11)
Standard Z80A pinout (Zilog Z80 Microprocessor Family Databook; the O1 fits an
NEC µPD780C, pin-compatible). **Corrected 2026-10-10** — the previous table
here was wrong (it claimed pin 11 = GND, which is +5 V). Enforced from now on
by `tools/check_schematics.py`, which asserts this table against every
connector that mates with the O1's Z80 socket.

| Pin(s) | Signal |
|---|---|
| 1–5 | A11, A12, A13, A14, A15 |
| 6 | CLK (4 MHz) |
| 7–10 | D4, D3, D5, D6 |
| 11 | +5 V |
| 12–15 | D2, D7, D0, D1 |
| 16 | INT |
| 17 | NMI |
| 18 | HALT |
| 19 | MREQ |
| 20 | IORQ |
| 21 | RD |
| 22 | WR |
| 23 | BUSAK |
| 24 | WAIT |
| 25 | BUSRQ |
| 26 | RESET |
| 27 | M1 |
| 28 | RFSH |
| 29 | GND |
| 30–34 | A0, A1, A2, A3, A4 |
| 35–40 | A5, A6, A7, A8, A9, A10 |

### Character generator ROM — 24-pin (UA15)
2 KB (2716) character ROM at **UA15** — on **sheet 4 of 9** (PDF page 7, the
RAM sheet), *not* the video sheet; see `o1-mainboard-schematic.md` §4a for the
extraction. 128 chars × 8×10 in an 8×10 box (7×9 visible), addressed by
(char code + scan line), output to the video shift register (UA14, 74166).
This is the second tap point the ScreenPac personality (#24) uses.

| Pin | Signal |
|---|---|
| 1–8 | A7–A0 (`A0–A6` = char code from UA18; `A7` = `SCAN0`) |
| 9, 10, 11, 13–17 | O0–O7 |
| 12 | GND — **bussed with 18 and 20 to ground** |
| 18 | `/CE` — **grounded** |
| 19 | A10 (`SCAN3`) |
| 20 | `/OE` — **grounded** |
| 21 | strapped **+5 V** (A11 on a 2732) |
| 22 | A9 (`SCAN2`) |
| 23 | A8 (`SCAN1`) |
| 24 | VCC (+5) |

> The earlier version of this table grouped pins `13–21` as "O3–O7, A8–A10" and
> put `OE`/`CE` on 22/23. That was wrong — exactly the "never cross-checked"
> error gap #3 flagged. The socket is the plain Intel 2716 pinout, and because
> `/CE` and `/OE` are grounded the ROM **always drives** `O0–O7`; a tap cannot
> tristate it without intercepting those two pins.

### Other onboard connectors (for reference)

**Every connector on an Osborne 1 is on the FRONT of the machine** — there is
nothing to plug into at the back. That is not a detail: it is why fitting a
period peripheral meant unclipping the keyboard, which docks to seal that same
face (the O1A design note in `hardware/o1ng/`), and it is why every standalone
device in this project attaches at the front (#47, #56, #84).

- **P3** — IEEE-488, 26-pin edge (pins 25/26 unused)
- **P2** — RS-232, DB-25 (DTE)
- **P1** — Modem
- **P4** — Keyboard, 20-pin IDC (1=GND, 2–9 rows 4,0,3,6,2,5,1,7, 10–17 cols 0–7, 18 NC, 19=+12V, 20 GND).
  On the later **O1A ("blue/grey")** machines the coiled-cable plug has **24 holes but only the inner
  20 mate with pins**. Pin 19 carries **+12V only if jumper J6 is bridged** (a 2-pin link, open from
  the factory) through **R21 (22Ω)** — the intended way to power an accessory off the keyboard cable.
  Rows are driven low (open-collector inverters, one-hot); columns are pulled up to +5V via a 3.3K
  resistor pack and buffered onto the data bus. Reference: O1 Technical Manual; pinout per
  pinouts.ru (verified against a PCB), archived in-repo at
  `research/osborne1/keyboard/osborne_keyboard_pinout.html` (provenance alongside) —
  see #47 for the full matrix map.
- **P8** — Floppy drive, 34-pin
- **P5** — Video, 10-pin inline


## 7. Free I/O windows & recommended virtual-peripheral base

The bank-2 I/O window is sparsely decoded; many sub-ranges alias the real
devices. Conservatively **free** (no onboard device) within `2000–2FFF`:

| Range | Status |
|---|---|
| `2000–20FF` | Free |
| `2104–21FF` | Free (above floppy) |
| `2300–28FF` | Free (above keyboard, below IEEE) — **largest clean block** |
| `2904–29FF` | Free (above IEEE PIA) |
| `2A02–2BFF` | Free (above serial, below video PIA) |

> **Caution:** the O1 decode is "sloppy" (MAME) — chip selects do not check
> all address bits, so large regions alias real devices. Treat only
> page-aligned blocks *between* the listed devices as safe, and validate on
> hardware before committing.

### Recommendation
- **Primary virtual-peripheral block: `2300–23FF`** (256 bytes). Clean gap
  between keyboard (`2201–2280`) and IEEE-488 (`2900–2903`). Suggested
  sub-allocation: CoPower-88 emulation, network/modem FIFO, RTC, status regs.
- **Secondary: `2B00–2BFF`** (between serial `2A01` and video PIA `2C00`) if a
  second disjoint window is needed.
- Avoid `0x00–0x03` (bank switch) entirely.
- The interposer should decode **bank-2 I/O space** (memory-mapped) rather
  than Z80 `IN/OUT` port space, since onboard devices are memory-mapped and
  the plain I/O port space `0x00–0xFF` is almost entirely consumed by the
  bank-switch decoder aliases (only low 2 bits decoded → `0x00–0x03` repeats
  every 4 bytes across the whole low port page).

## 8. Decisions this unblocks

- **Gap #15 (memory-resident vs pure I/O):** → **pure I/O**, memory-mapped in
  bank 2 at `2300+`. No need to steal RAM or fight the bank flip-flops.
- **Gap #10 (modem ACIA ports):** → `2A00/2A01` confirmed; the WiFi modem can
  either emulate the 6850 there or live at a `2300+` FIFO with a small BIOS
  hook.
- **Gap #11 (floppy variant):** → MB8877 ≡ WD1793 confirmed; registers at
  `2100–2103`; drive/density selects are PIA-driven (emulate via PIA shadow).
- **#24 (ScreenPac):** → two tap points confirmed: Z80 DIP-40 (UC11) and
  char-gen 24-pin (UA15).

## Sources
- OCC schematic `1A2011-00` Rev E (`research/osborne1/OCC1_1A2011-00_Schem_RevE.pdf`),
  sheets 1–5 (CPU, RAM, video, IEEE-488, serial/disk).
- Osborne 1 Technical Manual `2F00153-01` (1982), ch. 3 (memory), ch. 4
  (interfaces), ch. 5 (video), ch. 7 (disk), ch. 8 (keyboard), ch. 11
  (theory of operations: ROM MODE/bank select, NMI).
- MAME `src/mame/osborne/osborne1.cpp` (bank/I/O map cross-check).
