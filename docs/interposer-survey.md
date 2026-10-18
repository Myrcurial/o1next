# Research: Open-Source Z80 Bus Interposers / Sniffers / ICEs

Input to the RP2350 Osborne 1 interposer (Rev A). Prior art for a
Raspberry Pi Pico 2 W interposer between a 4 MHz, 5 V Z80 and its
socket, with passive capture + active drive + USB/WiFi streaming.
All claims cited; sources verified 2026-10-08.

**Revised 2026-10-18: the survey was incomplete, and this document said it was
not.** §1.6 is **picoZ80 / pico6502** — an RP2350B *drop-in Z80/6502 CPU
replacement* with a cycle-accurate PIO bus interface, 30 releases, and four
machine families — which was missing entirely, and which is the closest prior art
to the interposer's central timing claim. Two consequences run through the
document: §3's blanket advice about level shifting has a counter-example, and
§2.1's "directly copyable" claim needed a licence check it never had. **§8 is new
and is the one to read before reusing anything here.**

---

## 1. RP2040/RP2350-based bus capture / CPU-emulation projects

### 1.1 gusmanb/logicanalyzer (24-ch, 100 Msps Pico logic analyzer)
- URL: https://github.com/gusmanb/logicanalyzer
- MCU: RP2040 (Pico / Pico W; Pico W supports WiFi streaming).
- Approach: PIO + DMA capture, up to 24 channels into RP2040 RAM;
  pre/post trigger; edge or pattern trigger; 100 Msps, 32K samples.
  Separate fast level-shifter board required for 5 V targets.
- Level shifting: dedicated shifter PCB (KiCad in repo). Documented
  Rev-A erratum: J1/J2 footprints exchanged (inputs<->outputs);
  recovered by flipping the symmetric board.
- Capture vs drive: capture only.
- Key lessons:
  - Trigger logic must live in PIO; naive GPIO-compare loops cost
    ~16 cycles/sample.
  - 100 Msps is burst-to-RAM via DMA, NOT continuous USB streaming;
    capture depth is the limit.
- Relevance: proves PIO samples >20 lines far above 4 MHz Z80 speeds;
  its Pico W WiFi mode is our streaming precedent.

### 1.2 AESilky/sd-dkr
- URL: https://github.com/AESilky/sd-dkr
- MCU: RP2040. Disk, keyboard, RTC as a device on a Z80-class
  parallel bus (device side, not interposer).
- Relevance: RP2040 meeting Z80 bus-peripheral timing.

### 1.3 lambdamikel/picoram-ultimate & picoram6116
- URLs: https://github.com/lambdamikel/picoram-ultimate,
  https://github.com/lambdamikel/picoram6116
- MCU: RP2040. SRAM emulator + SD interface for vintage SBCs
  (incl. 6116 SRAM emulation for the Z80-based Microprofessor MPF-1).
  Pico sits in the memory socket and drives the data bus
  synchronously with Z80 cycles.
- Key lesson: bare RP2040 meets ~4 MHz Z80 memory-cycle timing
  without glue logic; evidence RP2350 meets a Z80 T-state budget.

### 1.4 74HC138/RP-Floppy
- URL: https://github.com/74HC138/RP-Floppy
- MCU: RP2040. Bitbanged PIO floppy controller (early stage, GPL-3).
- Relevance: PIO MFM/flux handling reference for the floppy personality.

### 1.5 Flee-Time/FloppyController
- URL: https://github.com/Flee-Time/FloppyController
- MCU: RP2040 floppy controller speaking the Greaseweazle protocol,
  plus USB MSC. Second datapoint for PIO flux capture.

### 1.6 picoZ80 / pico6502 (Philip Smart, engineers@work) — the field's most mature example
- URL: https://git.eaw.app/eaw/pico (Gitea) · https://eaw.app/picoz80/
- MCU: **RP2350B** (bare part, not a module) + **8 MB PSRAM** + 16 MB flash, with
  an **ESP32-S3-PICO-1** co-processor for WiFi/BT/SD-card/web UI.
- Approach: **a drop-in CPU replacement, not an interposer.** The board plugs
  into the Z80 (or 6502) DIP-40 socket and *is* the CPU: three PIO blocks take
  cycle-accurate control of the address, data and control buses, and the RP2350
  emulates the instruction stream behind them. 54x19 mm board, parts on both
  sides, DIP-40 extender footprint; v2.5 fab files are in-tree.
- Maturity: **30 releases** (latest v3.434, 2026-08-09), and the machine list is
  not a demo — Sharp MZ-700/800/80A/80B/1500/2000/2200/2500, Tatung Einstein
  TC-01, Amstrad PCW-9512, plus a generic `BaseZ80` and an **RC2014** persona.
- **The PIO technique** (`projects/tzpuPico/src/z80.pio`, ~30 KB):
  - **One PIO program per Z80 bus-cycle type** — normal fetch, interrupt
    acknowledge, NMI acknowledge, and the memory/I/O read and write cycles — with
    the **T-states written out as comments** (`T1`…`T7`): the published Z80 bus
    timing diagram transcribed state by state.
  - **Every T-state is one Z80 clock.** The program advances with `wait 1 gpio
    <CLK_S>` / `wait 0 gpio <CLK_S>` against a **derived Z80 clock on a GPIO**
    (GP35), rather than dividing the 150 MHz system clock. This is the
    architectural idea worth understanding: *the PIO is clocked by the target*,
    so T-state accuracy does not depend on the PIO's own clock budget.
  - **Wait states are real**: `jmp pin` on the `WAIT` line inserts TW and loops,
    so the host sees the Z80 stretch a cycle exactly as it should.
  - **Inter-SM handshakes through PIO IRQs** (`irq set 1` / `wait 0 irq 1`) to
    sequence address, data and control state machines.
  - Pin map: address GP0-15, data GP16-23, control GP24-33
    (RD/WR/BUSACK/HALT/M1/RFSH/MREQ/IORQ/BUSRQ/INT), derived clock GP35.
- **The C side** (`src/Z80CPU.c`): the instruction core runs in C and **polls the
  PIO** — `z80_run` reads `pio2_hw->irq` for a /RESET from PIO SM3 — so the PIO
  owns the bus and the CPU code blocks on it. Its `PICOMOD.md` records
  Cortex-M33 micro-optimisations with measured costs (indirect callback ~5 cycles
  vs direct ~2; call overhead ~10-15 cycles; a local cycle counter in the run loop
  ~3 cycles/instruction), useful to anyone writing a hot loop on this core.
- **Virtual device framework**: 57 C files of period-peripheral models —
  `PPI8255`, `PIT8253`, `Z80SIO`, `uPD765`, `WD1770`/`WD1773`, cassette, quick
  disk, **SASI** (the SCSI predecessor) — plus per-machine drivers. Configuration
  is a **`config.json` on the SD card** (245 of them in-tree): memory map, ROM
  images and driver selection are runtime data, not compile-time choices. That is
  a direct alternative to our compile-time personalities and to the mailbox
  protocol for configuration.
- Electrical: ~45 series resistors in two symmetric banks (R1-R19, R28-R45) and
  **seven ICs total** on the placement file — i.e. **no bus-transceiver array**.
  See §3, where this contradicts our own advice.
- **Licence: firmware GPL v3, hardware and docs CC BY-NC-SA 4.0, plus NOTICE
  terms on attribution, trademarks and passing-off. Not reusable — §8.**
- Key lessons:
  - **A cycle-accurate PIO Z80 bus on RP2350 is not a hope; it ships.** That
    retires the largest open risk in this project's design (§7).
  - **Clock the PIO from the target's clock** wherever you can see it. A CPU
    replacement owns the clock; an interposer cannot — but if the interposer can
    see Z80 CLK, a PIO clocked from it makes T-states exact rather than asserted.
  - **One PIO program per cycle type, with the T-states in comments**, is a
    reviewable decomposition and the natural way to check work against a timing
    diagram.
  - A per-machine driver framework plus a JSON memory map is the shape our
    `firmware/` personalities are groping toward.

## 2. Prior art: interposers / bus monitors on other vintage machines

### 2.1 AtomBusMon (David Banks / hoglet67)
- URL: https://github.com/hoglet67/AtomBusMon (stardot.org.uk)
- Approach: "ICE" adapters piggybacking the 40-pin CPU socket (6502,
  Z80, 6809, 8080...); Z80 adapter uses 6x 74LVC4245 level shifters
  and turned-pin (Preci-Dip) headers; single-step, breakpoints, full
  bus trace.
- Errata accumulated across spins ("R10,R12,R13 should not be fitted",
  "C15 not fitted"); extra socket needed for stacking height.
- Key lesson: THE canonical socket-piggyback ICE design; its Z80
  adapter BOM and shifter choice are directly copyable.

### 2.2 BusRaider (Peter Tandler / Rob Dobson r12a)
- URL: https://github.com/robdobsn/BusRaider
- Approach: Raspberry Pi Zero on the RC2014 (Z80) bus; can snoop and
  DRIVE the bus; `rawBusClockDisable` / `rawBusTake` model — stop the
  Z80 clock, then walk the bus at leisure.
- Key lessons:
  - Clock control converts impossible real-time problems into trivial
    ones. Add WAIT-stretch / clock-gate hooks to Rev A.
  - A debugging session found swapped PAGE_WR/PGEN_WR lines; a
    comparative trace against a known-good board would have caught it
    earlier — build golden-trace diff tooling, not just tracing.

### 2.3 RetroShield (8bitforce) and skx/z80retroshield
- URLs: https://github.com/8bit-1/retroshield (Arduino),
  https://github.com/skx/z80retroshield
- Approach: Arduino/Teensy drives a real Z80's clock and buses,
  emulating memory/IO in software (CPU-in-a-jar). skx rewrote the
  upstream sample into a standalone library after finding mixed
  concerns (buttons/LCD/SPI-RAM tangled with bus driving).
- Key lesson: keep the bus-driver firmware layer a clean standalone
  module; also proves ~MHz Z80s can be driven by MCUs.

## 3. Electrical design lessons

- Level shifting observed in the wild: 74LVC4245 x6 (AtomBusMon),
  dedicated fast-shifter boards (logicanalyzer), 74LVC245-class parts
  recommended for inputs; 74HCT245 or dual-supply parts for outputs.
- RP2040/RP2350 GPIOs are NOT 5 V tolerant; do not rely on
  series-resistor hacks for a product-quality board.
  **Counter-example, and it is the most mature board in the field** (§1.6):
  picoZ80 appears to carry ~45 series resistors and **no** level-shifting or
  transceiver ICs, on a board that sits in a 5 V Z80 socket and has shipped 30
  releases — its placement file lists seven ICs (U2-U7) and no 74-series array.
  This bullet and that board cannot both be right. **Resolve it from their
  schematic and from the RP2350 datasheet's GPIO absolute-maximum ratings, not
  from either document's advice — and note that the placement file has no values,
  so "series resistors" is an inference from 45 symmetric designators, not a
  reading.**
- Verify whether the Osborne 1's Z80 is NMOS (VIH 2.0 V -> 3.3 V
  drive OK) or CMOS Z84C00 (VIH ~3.5 V -> needs HCT/dual-supply)
  before committing the output stage. [Check against machine photos
  in research/pictures.]
- Power: don't feed WiFi transmit peaks from the CPU socket 5 V pin
  without checking regulator headroom; prefer USB-powered Pico with
  common ground + generous local decoupling (AtomBusMon: 12x 100 nF
  + bulk).
- Mechanical: turned-pin headers; expect stacking-height problems
  inside the O1 case; keep profile minimal and test-fit early.

## 4. PIO sampling & streaming

- Clock-synchronous sampling (sample on the clock edge qualified by
  MREQ/IORQ) yields compact per-cycle records; oversampling is
  affordable (4 MHz bus, >=25x PIO headroom per logicanalyzer's
  100 Msps / 24 ch).
- USB FS budget ~1 MB/s is insufficient for raw every-cycle capture
  at 4 MHz. Mitigations, in order:
  a) PIO-side filtering (M1-only, address windows, triggers) —
     trigger logic must live in PIO;
  b) RAM burst capture with pre/post trigger;
  c) WiFi streaming as a peer path on the Pico 2 W.
- Double-buffered DMA from day one.

## 5. Floppy & GPIB references

- FlashFloppy/Gotek (Keir Fraser) is STM32, NOT Pico — do not plan
  around porting it; instead track 74HC138/RP-Floppy and
  Flee-Time/FloppyController for PIO MFM, and Keir's Disk-Utilities
  (disk-analyse) on the host side.
- NODISKEMU (https://github.com/nils-eilers/NODISKEMU) and cbmSD
  (http://cbmsteve.ca/cbmsd/) are AVR-based; their IEEE-488 state
  machines are the reference to port to PIO for the Drive C
  personality.

## 6. Documented errata / "what I'd do differently"

- logicanalyzer: J1/J2 footprints swapped in first fab run.
- AtomBusMon Z80 adapter: BOM fit/no-fit errata across spins;
  stacking-height fix.
- skx/z80retroshield: rewrote upstream into a standalone library —
  separation of concerns matters.
- BusRaider: golden-trace diffing would have caught swapped lines.

## 7. Synthesis: recommendations for Rev A

1. Architecture: RP2350 BETWEEN Z80 and socket (AtomBusMon-style
   40-pin DIP piggyback), real Z80 in a top socket so passive mode is
   electrically transparent. Two PIO banks: capture (clock-edge-sync
   push of addr/data/status) and drive (data bus + WAIT/NMI/INT/BUSRQ).
2. Level shifting: 74LVC245 inputs + 74LVC8T245/74HCT245 outputs,
   following AtomBusMon precedent.
3. Capture rate is a non-problem; spend the effort on PIO triggers.
4. Streaming: PIO filtering -> RAM burst -> USB/WiFi drain.
5. Active drive: WAIT-stretch and clock-gating hooks (BusRaider
   model) — being able to stop the clock is a superpower.
5b. **Prior art for the timing claim, and it changes the question (§1.6).**
    picoZ80 drives a cycle-accurate Z80 bus from three RP2350 PIO blocks,
    *clocked by a derived Z80 clock*, with real wait states and inter-SM IRQ
    handshakes — and has shipped 30 releases across four machine families. So
    "can a PIO do a 4 MHz Z80 bus cycle-accurately" is answered, and the Rev B
    question becomes **which architecture we want**: a *replacement* that owns
    the clock, or an *interposer* that must follow it. Given that BusRaider's
    lesson (2.2) and picoZ80's clocked PIO are the same insight from opposite
    directions, **consider bringing Z80 CLK into the interposer** so a PIO can be
    clocked from it — that is the difference between asserting the T2 timing
    claim and being able to measure it.
6. Power: USB-powered Pico, common ground, heavy decoupling.
7. Mechanical: turned-pin headers, minimal profile, early test-fit
   in the O1 case.
8. Process: publish BOM with fit/no-fit notes; expect >=1 footprint
   erratum; build trace-compare tooling early; keep the bus-driver
   firmware layer standalone.

## 8. Licences, and what "prior art" actually lets us reuse

This document says things like *"its Z80 adapter BOM and shifter choice are
directly copyable"* (§2.1). That is a claim about **engineering**, and it silently
assumed something about **licensing** that had never been checked. It has now been
checked for two entries, and both need qualifying:

| Project | Licence | What it permits |
|---|---|---|
| **picoZ80 / pico6502** (§1.6) | firmware **GPL v3**; hardware and docs **CC BY-NC-SA 4.0**; a NOTICE adding attribution, trademark and anti-passing-off terms | **Study it; do not copy it.** GPL v3 is one-way: code taken into o1next would relicense our firmware as GPL v3. CC BY-NC-SA forbids commercial use *and* forces ShareAlike on derivatives, which is incompatible with this repository's **MIT** licence, with a Phase 5 reproduction (#49) and with the deliverable tree (#133–#140) |
| **AtomBusMon** (§2.1) | **GPL-3.0** | The same direction of problem, one step milder: a *schematic* is a copyrightable work, so "the BOM and shifter choice are directly copyable" is true of the **part numbers** (facts) and false of the **design files** (expression). The turned-pin piggyback idea and the wiki are fair to learn from |

What that leaves, and it is not nothing:

- **Ideas, methods and facts are not copyrightable.** The technique in §1.6 —
  clock a PIO from the target's clock, one program per cycle type, `jmp pin` on
  /WAIT, IRQ handshakes between state machines — is fair to learn and to
  reimplement in our own code. What we may not do is copy their `.pio` file,
  their C, their KiCad or their documentation.
- **Existence proofs are facts.** "A cycle-accurate PIO Z80 bus on RP2350 ships,
  with 30 releases" is usable in an argument and needs no licence at all.
- **Asking is a real option, and it is invited.** picoZ80's NOTICE ends with
  contact details for exactly this, including commercial licensing. If any part
  of it turns out to be worth more than the idea, the route is a message — and
  this repository should record the answer either way.
- **Put the licence in the entry, and check it before writing "copyable".** This
  section exists because two of the document's reuse claims were made without
  that check, and one of them was wrong.

### Open question for the maintainer

picoZ80's licence posture (non-commercial hardware, GPL firmware, trademark and
anti-passing-off terms) is the opposite of this project's MIT default, and it is
worth a deliberate decision rather than a default: **do we want o1next to remain
MIT, or is a copyleft/non-commercial posture acceptable for parts of it?** The
answer changes what can be borrowed, and §1.6 is the first entry where the
question actually bites.
