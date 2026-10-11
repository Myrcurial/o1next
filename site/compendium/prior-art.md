---
layout: page
title: "Prior art: Z80 bus interposers"
subtitle: "The project"
draft: "Draft &mdash; assembled from the working notes by `tools/build_book.py`. The source document is the authority; this page is a copy for reading, and it is regenerated from that source."
---

Input to the RP2350 Osborne 1 interposer (Rev A). Prior art for a
Raspberry Pi Pico 2 W interposer between a 4 MHz, 5 V Z80 and its
socket, with passive capture + active drive + USB/WiFi streaming.
All claims cited; sources verified 2026-10-08.

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

## 3. Electrical design lessons

- Level shifting observed in the wild: 74LVC4245 x6 (AtomBusMon),
  dedicated fast-shifter boards (logicanalyzer), 74LVC245-class parts
  recommended for inputs; 74HCT245 or dual-supply parts for outputs.
- RP2040/RP2350 GPIOs are NOT 5 V tolerant; do not rely on
  series-resistor hacks for a product-quality board.
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
6. Power: USB-powered Pico, common ground, heavy decoupling.
7. Mechanical: turned-pin headers, minimal profile, early test-fit
   in the O1 case.
8. Process: publish BOM with fit/no-fit notes; expect >=1 footprint
   erratum; build trace-compare tooling early; keep the bus-driver
   firmware layer standalone.

  upstream sample into a standalone library after finding mixed
  concerns (buttons/LCD/SPI-RAM tangled with bus driving).
- Key lesson: keep the bus-driver firmware layer a clean standalone
  module; also proves ~MHz Z80s can be driven by MCUs.
