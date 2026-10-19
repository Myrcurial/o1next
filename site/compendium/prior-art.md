---
layout: page
title: "Prior art: Z80 bus interposers"
subtitle: "The project"
draft: "Draft &mdash; assembled from the working notes by `tools/build_book.py`. The source document is the authority; this page is a copy for reading, and it is regenerated from that source."
---

Input to the interposer (`O1NEXT Upgrade`, Rev A). Prior art for a
Raspberry Pi Pico 2 W interposer between a 4 MHz, 5 V Z80 and its
socket, with passive capture + active drive + USB/WiFi streaming.
All claims cited; sources verified 2026-10-08.

**Revised 2026-10-18: the survey was incomplete, and this document said it was
not.** Two entries were missing. §1.6 is **picoZ80 / pico6502** — an RP2350B
*drop-in Z80/6502 CPU replacement* with a cycle-accurate PIO bus interface, 30
releases and four machine families, and the closest prior art to the interposer's
central timing claim. §1.7 is **z80_pico** — small, unfinished, and the only
project here that answers the question the interposer actually has: what to do
when you must *follow* somebody else's clock. Three consequences run through the
document: §3's advice on level shifting now has two counter-examples and three
competing answers, §2.1's "directly copyable" claim needed a licence check it
never had, and §7 gains both a clocking idea and a wait-state strategy. **§8 is
new and is the one to read before reusing anything here.**

---

## 1. RP2040/RP2350-based bus capture / CPU-emulation projects

### 1.1 gusmanb/logicanalyzer (24-ch, 100 Msps Pico logic analyzer)
- URL: https://github.com/gusmanb/logicanalyzer
- MCU: RP2040 (Pico / Pico W; Pico W supports WiFi streaming).
- Approach: PIO + DMA capture, up to 24 channels into RP2040 RAM;
  pre/post trigger; edge or pattern trigger; 100 Msps, 32K samples.
  Separate fast level-shifter board required for 5 V targets.
- Level shifting: dedicated shifter PCB (KiCad in repo). Documented
  **gusmanb/logicanalyzer Rev-A** erratum: J1/J2 footprints exchanged
  (inputs<->outputs); recovered by flipping the symmetric board.
  *(Someone else's board: not the interposer's Rev A.)*
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

### 1.7 z80_pico (tendai22) — small, unfinished, and the only worked answer to our specific problem
- URL: https://github.com/tendai22/z80_pico
- MCU: **RP2040** (Pico). 5 commits, 13 stars, one target machine (SBC8080), no
  releases, and **no licence file at all** — see §8.
- Approach: the **third** architecture in this document. Not a replacement and not
  an interposer — a *host that subjugates the CPU* (the RetroShield shape, §2.3):
  the Pico generates the Z80 clock (GPOUT0 on GP21), holds the whole machine's
  64 KB of ROM/RAM in RP2040 SRAM as a C array, emulates an **i8251** on UART0,
  and **stretches every memory cycle with /WAIT**. The author's own verdict:
  *"far from elegant design, but I dare to do it for my personal intention."*
- **What it is worth reading for, and it is the only project here that answers it:**
  - **Software cannot assert /WAIT in time.** *"Even if RP2040 CPU is fast, it is
    still hard to issue /WAIT in time to make Z80 surely to start wait state. A
    half of 74HC74, D-FF takes falling edge of /MREQ to flip its output /Q,
    directly connecting to /WAIT input of Z80 CPU."* The assertion is
    **combinational, not programmed** — and `/RFSH` has to gate the D-FF's clock
    input, or the refresh cycle's /MREQ falling edge is mistaken for a memory
    cycle. **Every other project in this document dodges this by *generating* the
    Z80 clock** (§1.6 included). The interposer is the only architecture that must
    *follow* one, so this is the only worked answer to our version of the problem.
  - **Releasing /WAIT and the data bus is a hardware problem too.** *"I am glad to
    adopt a hardware logic (DO buffer and its /OE signal connected to /RD) to
    handle this issue. No software provision is needed. If we implement it as
    software, this issue will become much more confusing."* That is the same
    hazard [`docs/picoem-bridge.md`](https://github.com/Myrcurial/o1next/blob/main/docs/picoem-bridge.md) §4 met from the other side: *"the idle state has
    to be driven, not left alone."*
  - **The cost of stretching every cycle, measured.** Z80 clock 3.8 MHz,
    *"effectively about 2 MHz, with 3 WAIT cycles"*; `ASCIIART.BAS` in MSBASIC took
    **8 min 23 s**. Three wait states per memory cycle **halves the machine**. This
    is the number that says the interposer must be **transparent when it is
    passive** — a design that stretches every cycle is not an interposer, it is a
    new machine wearing one.
- **Level shifting**, and it refines §3 rather than repeating it: eight level
  shifters on the 5 V→3.3 V **input** path and **none** on the 3.3 V→5 V output
  path — *"3.3 V output can drive 5 V CMOS gate inputs, and we do not have any
  critical issues, so it is okay."* Shift what you receive; be deliberate about
  what you drive.
- **Pin budget**, for comparison with our 595/165 shift fabric and picoZ80's direct
  mapping (§1.6): 8 bits in + 8 bits out (GPIO0-7 DI, GPIO8-15 DO), with **six
  buffers/latches** — address high, address low, data in, status, controls, data
  out — selected onto the input port by a **74HC138 3-to-8 decoder** on GP18-20.
  The author notes a decoder "can decrease the necessary number of GPIOs"; the real
  cost is that every bus read becomes a multiplexed *sequence* rather than a
  parallel sample.
- Also present: **INTA support** (`M1 && IORQ` → stretch, then put `0xFF`/RST 7 on
  the data bus), and a `rom2c` ROM-to-C-array tool — the CPU-in-a-jar pattern,
  which is not ours.
- Key lesson: **the interesting part of this project is its limitations.** It is
  the smallest and least finished thing in this document, and it is the only one
  that says out loud what it costs to get bus timing wrong by a factor of two.

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
- **A third answer, and it splits the problem in two** (§1.7): z80_pico shifts the
  5 V→3.3 V **inputs** (8 level shifters) and shifts **nothing** on the 3.3 V→5 V
  outputs, on the grounds that *"3.3 V output can drive 5 V CMOS gate inputs, and
  we do not have any critical issues."* So the field's answers are: series
  resistors everywhere (picoZ80), transceivers everywhere (AtomBusMon), or
  **shift what you receive and be deliberate about what you drive**. Note the
  caveat that makes the third one work and is easy to miss: a 74HC input at
  VCC 5 V has VIH ≈ 3.15 V, so a 3.3 V drive is *just* inside spec — which is not
  the same as having margin, and is worth measuring on the O1 rather than assuming.
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
5b. **The target clock is already in the design, so the prior art settles a
    question Rev B had already answered (§1.6).** [`hardware/interposer/revb/README.md`](https://github.com/Myrcurial/o1next/blob/main/hardware/interposer/revb/README.md)
    allocates **GP21 = CLK, "direct — PIO timing reference"** — and the machine's
    clock is a *mainboard* signal, 15.9744 MHz ÷ 4 through the UD3 LS161 counter
    (`o1-memory-io-map.md` §1), not the Z80's own oscillator. So the interposer is
    loading a distributed logic output rather than a crystal, which is the easy
    case. picoZ80 proves the technique; the open item is therefore not *whether*
    to use the clock but **what the state machine does with it**: a PIO *clocked*
    by CLK executes one instruction per T-state (picoZ80's constraint, and why its
    programs are one `set pins` per T-state), while a PIO on the system clock
    *observing* CLK has ~37 instructions per T-state but must track cycle phase in
    firmware. The Rev B README does not say which, and the two are different
    programs.
5c. **And /WAIT should be scheduled rather than raced — a structural argument, not
    a cautious one.** Rev B asserts /WAIT *after* observing `ADDR_HIT` (GP23), so
    it is a **reaction**: it must fit inside the window on every cycle, worst case,
    across temperature, voltage and part tolerance. An assertion derived from the
    clock phase can be made in **T1**, before the address has even settled, because
    the interposer knows from the clock that this cycle is one it owns. A race has
    a statistical margin; a schedule has a guaranteed one.

    The window looks comfortable and the claim is not obviously wrong, but the
    margin is **inferred, not measured**: `o1-memory-io-map.md` §1 attaches the
    machine's wait states to **RAM accesses** (≈375 ns for non-M1, 188 ns for the
    first M1) and says ROM executes with no added delay — and it says nothing at
    all about **I/O cycles**, which is what the interposer's `30h`–`33h` window
    actually is. *If* the I/O cycle is also unstretched, `ADDR_HIT` early in T1
    leaves ~1.5 T-states (≈375 ns at 4 MHz) to the falling edge of T2 against the
    README's "~50 ns", a 7× margin. **That premise needs checking against the wait
    generator's own decode on sheet 2/9, not assumed** — it is the number the
    margin rests on, and this document has form for writing an inference down as a
    fact.

    And **50 ns is one term in an unmeasured sum** — it is the PIO's response, and
    the path also contains the 688's
    propagation, whatever converts its 5 V output down to GP23's 3.3 V, the PIO's
    two-cycle input synchroniser, and the OC buffer's turn-on. That sum is the one
    number the live-response path rests on, and it has not been measured.
5d. **The machine already stretches its own cycles, so /WAIT is a wire-OR — with
    three consequences.** `o1-memory-io-map.md` §1: RAM accesses insert ≈375 ns of
    wait for non-M1 cycles and 188 ns for the first M1, while ROM executes with no
    added delay. So (a) the interposer's /WAIT drive **must** be open-collector or
    otherwise OR-able, and Rev B's "fast OC buffer" on GP22 is the right call;
    (b) the interposer's T-state machine must tolerate TW states **it did not
    insert**, because it cannot assume a cycle is three T-states long; and (c)
    **MAME omits the machine's wait states** (`o1-mainboard-schematic.md` §8), so
    this interaction cannot be exercised in emulation at all — which makes it a
    hardware-gated gap in its own right, and the one behaviour a race is least
    able to survive.
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
checked for every entry that could plausibly be reused, and all three need
qualifying:

| Project | Licence | What it permits |
|---|---|---|
| **picoZ80 / pico6502** (§1.6) | firmware **GPL v3**; hardware and docs **CC BY-NC-SA 4.0**; a NOTICE adding attribution, trademark and anti-passing-off terms | **Study it; do not copy it.** GPL v3 is one-way: code taken into o1next would relicense our firmware as GPL v3. CC BY-NC-SA forbids commercial use *and* forces ShareAlike on derivatives, which is incompatible with this repository's **MIT** licence, with a Phase 5 reproduction (#49) and with the deliverable tree (#133–#140) |
| **AtomBusMon** (§2.1) | **GPL-3.0** | The same direction of problem, one step milder: a *schematic* is a copyrightable work, so "the BOM and shifter choice are directly copyable" is true of the **part numbers** (facts) and false of the **design files** (expression). The turned-pin piggyback idea and the wiki are fair to learn from |
| **z80_pico** (§1.7) | **none — the repository has no licence file** | **The strictest case, and the one people get wrong.** *"It is on GitHub" is not a licence.* With no licence all rights are reserved; GitHub's terms grant viewing and forking through GitHub's own features, not reuse in our project. The practical answer is the same as picoZ80 — learn from it, copy nothing — arrived at for an entirely different reason |

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
