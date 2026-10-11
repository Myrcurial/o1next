# Drive C reproduction — hardware and firmware spec (#84)

**Status: design.** The protocol it must speak is solved and validated
(`docs/drive-c-protocol.md`), so this is a specification to build against rather
than a research question. Two things it deliberately does *not* invent: the
**pin-level map of P3** (we hold the connector's existence and its role, not its
pinout — §7), and the **DPB** the installer patches for drive `C:` (§6).

Tracks: #84 (the device), #6 (the protocol). Sibling of
`hardware/usb-keyboard-adapter/` and `hardware/wifi-modem-module/` — a period
device reproduced on modern parts, hanging off a port, reversible.

## 1. What we are building

A standalone replacement for the **Drive C** IEEE-488 RAM disk:

| Element | Choice | Why |
|---|---|---|
| Bus | **P3**, the O1's 26-pin IEEE-488 card edge | the device's own interface |
| Power | **P5**, the 10-pin video connector, via a passive shunt | EXMON precedent; keeps the machine unmodified |
| Compute | **RP2040** (a stock Pico) | bit-banging at the required rate is well inside PIO/GPIO |
| Storage | **external flash**, 512 KiB+ | the largest Drive C was 384 KiB |
| Bonus | composite video out from the same shunt | the EXMON shunt already does this, passively |

It is a **reproduction**, not an adapter: the machine sees a device on the port
speaking the same protocol, so period software drives it unchanged. Look closely
and you find an RP2040 where the original had a handful of TTL — which is the
point.

## 2. Electrical design

### 2.1 The bus

P3 is a 26-pin card edge (**pins 25/26 unused**) carrying the 6821's lines
(`docs/o1-memory-io-map.md` §6, `docs/o1-mainboard-schematic.md` sheet 9). The
host drives it through **7406 open-collector drivers** with **3.3 K pull-ups**
(UD6/UD8–UD11, RN7/RN11–RN16), and **all signals are active-low**. Three
consequences, and they are the whole electrical design:

1. **Never drive a line high.** Every line is a wired-OR: the box pulls a line
   low or it releases it. A push-pull driver on this bus fights the O1.
2. **Level-shift.** The bus is 5 V; the RP2040 is 3.3 V and not 5 V tolerant.
   The same **74AHCT/HCT** conclusion that governs the interposer applies
   (`docs/research-gaps.md` gap 2): AHCT gates on the way in (5 V tolerant, TTL
   thresholds), and open-drain outputs (or AHCT with a series resistor) on the
   way out.
3. **Present a sane load.** The O1's pull-ups are 3.3 K; the box should not add
   appreciably more capacitance or loading than one more TTL device on the bus.

Which P3 pin is which signal is **not** in our material — the ROM's comments give
the PIA↔signal map (`drive-c-protocol.md` §2), not signal↔pin. §7 makes that the
first thing to measure.

### 2.2 Power

The EXMON precedent (`hardware/drive-c/README.md`) takes power from **P5**, the
10-pin video connector, through a **passive shunt** — a Sullins
MP-0100-10-DS-4 edge connector and a Hyko K688-DI sync combiner — and uses
**+12 V**. What else is on P5, whether **+5 V** is available there, and what the
connector's current budget is are all **unmeasured**; §7 lists them. The RP2040
needs 3.3 V at ~50 mA (more in bursts), so a small buck from whichever rail P5
provides is the likely answer.

The shunt is a **mod**, even though it is passive and reversible, and must be
documented as one — the same way the USB keyboard adapter's J6 bridge is.

### 2.3 Signals the box must actually watch

Per the protocol, the box needs only:

| Signal | PIA | Role |
|---|---|---|
| DIO1–DIO8 | PA0–PA7 | the data byte |
| PB0 | port B bit 0 | direction: `0` = host drives, `1` = box drives |
| PB3, PB7 | port B bits 3, 7 | frame open/close framing |
| CA2 | CRA bits 5:3 | **the byte clock** |
| PB6 | port B bit 6 | *optional* — the box may drive it high as "ready"; the transport never reads it |

PB1, PB2, PB4, PB5, CA1, CB1 and CB2 are not needed to satisfy the transport.
(They matter for the **pass-through printer**, §5.)

## 3. Firmware — the Drive C personality

### 3.1 The frame state machine

The whole personality is a decoder for the frame in `drive-c-protocol.md` §3.
It has five states and no timing assumptions beyond "keep up":

```
IDLE    PB=08h                     -> HEADER1      (clear the byte counter)
HEADER1 CA2 edge, DIO present      -> store h1
        PB=00h                     -> HEADER2
HEADER2 CA2 edge, DIO present      -> store h2; decode the record address
        PB=88h                     -> WRITE
        PB=81h                     -> READ
WRITE   CA2 edge                   -> latch DIO into record[n++]
READ    CA2 edge                   -> drive DIO with record[n++]
        n == 128, or PB=09h        -> IDLE
```

Notes that matter:

- **The header bytes arrive on port A, clocked by CA2** — not on port B. This is
  the single easiest thing to get wrong, and it is measured
  (`drive-c-protocol.md` §9).
- **The direction is PB0**, sampled from the operation byte (`88h` → host drives,
  `81h` → box drives). Release DIO whenever PB0 = 1.
- **The frame is self-contained.** No state has to survive a frame boundary, so
  a reset mid-frame costs nothing.
- **PB6** may be driven high continuously as "ready". Nothing in the transport
  reads it, so it is optional — but it is the only line the host leaves as an
  input after every frame, so driving it is the safe choice.

### 3.2 Timing

The host clocks a byte every **~52 T-states (~13 µs at 4 MHz)** and, on a read,
samples DIO **~6 T-states (~1.5 µs)** after the CA2 edge. The safe design is to
keep the next read byte **already on DIO** and advance on each CA2 edge, rather
than to drive the bus on demand. An RP2040 does this comfortably in PIO or even
in a tight GPIO loop; the numbers are two orders of magnitude inside budget.

CA2 is sampled, not generated, so the box needs one edge-triggered input per
byte. A PIO state machine with a wait-on-pin is the natural implementation, with
the DMA feeding read data and draining write data.

### 3.3 Where the code lives

The personality is the same device as the interposer's IEEE-488 storage
personality (#22) — one implementation, two hosts. `firmware/drive-c-gpib/`
already exists as the home; this spec is what it implements.

## 4. Storage and geometry

**Addressing.** `DE` (the CP/M record address, in 128-byte units) is what the
host sends; the header pair encodes it bijectively (`drive-c-protocol.md` §5).
The box should decode it back to `DE` and index a flat store at
`DE * 128` bytes — the simplest correct model, and the one the validation model
in `drive-c-box.lua` uses (which is why the loader completes).

**Size.** The vendor sold 192 K and 384 K. `DE`'s encoding tops out around
448 K. A **512 KiB flash** covers every variant; the personality can report a
size or simply accept whatever `DE` the DPB produces.

**What the box does *not* do.** It does not implement CP/M. The directory,
allocation map and file structure live on the host side, in the CBIOS that
`DCL.COM` patches in. The box is a paged 128-byte record store, and the
boot-time format it sees (`0xE5` written across two regions and read back,
`drive-c-protocol.md` §8) is CP/M formatting *its own* disk through the box.

**What is missing** is that DPB (§7 item 4): how many records `C:` has. Until it
is known, the box can be built and will answer every frame correctly, but the
drive will be the wrong size.

## 5. Coexistence: the pass-through printer, and address 0

Drive C duplicates the IEEE-488 connector on its front panel so a printer can
plug through it, and the manual is explicit that **GPIB protocol is not
supported** on that connector — it duplicates the *parallel port function*. So a
reproduction has to decide what the pass-through connector is:

- **Minimum viable:** a mechanical/passive pass-through of the connector (a short
  ribbon), so a Centronics printer attached there still works with the machine's
  own parallel driver. That is what the original did electrically for the printer
  path, and it needs no firmware.
- **Full:** snoop the parallel traffic and spool it (the print buffer, `DCU`,
  `PRN.TST`). That is a separate feature and a separate issue.

**Bus arbitration.** Three devices now claim this port in the archive — Drive C,
the RT-60A clock (`docs/rt60a-analysis.md`) and Trantor's hard disks
(`docs/drive-c-protocol.md`) — and the O1's **own address is 0**, so nothing else
on the bus may use it (`docs/o1-ieee488-port.md` §1). A reproduction that only
answers when it sees the Drive C frame pattern is compatible with all of them by
construction: it stays released until it sees its own framing.

## 6. Test plan

1. **Protocol (done).** The frame, measured on the real software
   (`drive-c-protocol.md` §9).
2. **Box model (done, short runs).** `tools/research/drive-c-box.lua` makes the
   1983 loader complete and PIP write to `C:`. Extend it into a proper harness
   once the DPB is known — that is the fastest place to iterate on firmware logic
   before any hardware exists.
3. **DPB** (§7 item 4). Until `C:` has the right size, nothing downstream is
   meaningful.
4. **Hardware-in-the-loop.** With a real O1: `DCL`, then `DCQ`, then
   `PIP C:=A:*.*[WV]` and a byte-comparison of a file moved both ways — the same
   acceptance test #95 used for the floppy formats, and the one the software
   itself provides.

## 7. What must be measured before a board is laid out

1. **The P3 pinout.** Which signal is on which of the 26 pins. The ROM gives
   PIA↔signal; the connector's signal↔pin is unrecorded. One pass with a
   continuity tester on a real machine settles it, and it blocks layout.
2. **P5 power.** What rails are on the 10-pin video connector, whether +5 V is
   among them, and the connector's current budget. The EXMON shunt uses +12 V; do
   not assume the rest.
3. **Bus loading.** How much additional load (capacitance, pull-up) the bus
   tolerates before the O1's timings move — worth a scope check with a TTL gate
   as the load, before committing to a buffer choice.
4. **The DPB** (`drive-c-protocol.md` §8): the record count `C:` gets, from
   `DCL.COM`'s BIOS patch. A disassembly job on `DCL.COM`, not a measurement, and
   the last thing standing between this spec and a working drive.

## Sources

- `docs/drive-c-protocol.md` — the protocol this implements (the contract).
- `docs/o1-ieee488-port.md` — the port's device-level behaviour, the ROM's eight
  drivers, and the joystick worked example.
- `docs/o1-memory-io-map.md` §6 — P3/P5 and the other connectors.
- `docs/o1-mainboard-schematic.md` sheet 9 — the IEEE-488 interface, the PIA and
  the open-collector drivers.
- `docs/interposer-survey.md` §5 — NODISKEMU and cbmSD, the IEEE-488 state
  machines to port.
- `hardware/drive-c/README.md` — the device's place in the project, and the EXMON
  shunt precedent.


