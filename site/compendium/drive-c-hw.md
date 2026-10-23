---
layout: page
title: "The Drive C reproduction: hw + firmware"
subtitle: "Peripherals and storage · design"
draft: "Draft &mdash; assembled from the working notes by `tools/build_book.py`. The source document is the authority; this page is a copy for reading, and it is regenerated from that source."
---

**Status: Solved as a design.** The shape is settled and unblocked — the protocol
it must speak is validated ([`docs/drive-c-protocol.md`](https://github.com/Myrcurial/o1next/blob/main/docs/drive-c-protocol.md)), the **DPB** that sets the
drive's size is found (§8.1 there), and the **pin-level map of P3** is transcribed
from the Technical Manual ([`docs/o1-ieee488-port.md`](https://github.com/Myrcurial/o1next/blob/main/docs/o1-ieee488-port.md) §6). Nothing in the
electrical or logical design is waiting on a measurement any more. Nothing is
built either: what is left is a layout and firmware (§7).

Tracks: #84 (the device), #6 (the protocol), #22 (the port it hangs off) and #145
(the DPB its size comes from). Sibling of
[`hardware/keyboard-adapter/`](https://github.com/Myrcurial/o1next/blob/main/hardware/keyboard-adapter/) and [`hardware/wifi-comm-pac/`](https://github.com/Myrcurial/o1next/blob/main/hardware/wifi-comm-pac/) — a period
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

### 1.1 The envelope, from the vendor's own spec sheet

§7-2 of the Drive C manual is a full specification sheet — and the Executive
manual's §6-2 is the same page with one word changed. These are the numbers a
reproduction should be measured against:

| | Original (384K unit) |
|---|---|
| Dimensions, no cables | 5.6 × 5.9 × 1.0 in (14 × 15 × 2.5 cm) |
| Weight / shipping weight | 1 lb (0.45 kg) / 3 lb (1.4 kg) |
| Operating temperature | +5 to +60 °C (+40 to +140 °F) |
| Storage temperature | −20 to +100 °C |
| Power | 11–14.5 VDC at 0.3 A max, **2.5 W nominal** |
| Latency | none — solid state, no moving parts |
| **Max data throughput** | **55,000 B/s** (445,000 b/s) |
| Random-sector access | ≈40 µs (software access time) |
| Load a 32K `.COM` and run it | 1.1 s max (1.0 s on the Executive) |
| TPA RAM used on the host | 1152 B; +1024 B with the print buffer |

The throughput figure is the one the firmware has to live inside: 55,000 B/s is
**18 µs per byte sustained** (445,000 b/s over 8 bits), against a transport that
clocks one byte per CA2 pulse in ~52 T-states (~13 µs, `drive-c-protocol.md` §6).
§3.2's timing has to stay within it.

**And one design served two machines.** The Osborne 1 and Executive variants
differ only in software — the Executive's book describes an `ECL`/`ECN`/`ECU`
loader for CP/M+ where the Osborne 1 uses `DCL`/`DCN`/`DCU` under CP/M 2.2 —
while the mechanical, electrical and performance appendices are otherwise word
for word. So this is **one design, not two**, and a board built to this spec
serves either host. [`docs/drive-c-executive.md`](https://github.com/Myrcurial/o1next/blob/main/docs/drive-c-executive.md) §1.

## 2. Electrical design

### 2.1 The bus

P3 is a 26-pin card edge (**pins 25/26 unused**) carrying the 6821's lines
([`docs/o1-memory-io-map.md`](https://github.com/Myrcurial/o1next/blob/main/docs/o1-memory-io-map.md) §6, [`docs/o1-mainboard-schematic.md`](https://github.com/Myrcurial/o1next/blob/main/docs/o1-mainboard-schematic.md) sheet 9). The
host drives it through **7406 open-collector drivers** with **3.3 K pull-ups**
(UD6/UD8–UD11, RN7/RN11–RN16), and **all signals are active-low**. Three
consequences, and they are the whole electrical design:

1. **Never drive a line high.** Every line is a wired-OR: the box pulls a line
   low or it releases it. A push-pull driver on this bus fights the O1.
2. **Level-shift.** The bus is 5 V; the RP2040 is 3.3 V and not 5 V tolerant.
   The same **74AHCT/HCT** conclusion that governs the interposer applies
   ([`docs/research-gaps.md`](https://github.com/Myrcurial/o1next/blob/main/docs/research-gaps.md) gap 2): AHCT gates on the way in (5 V tolerant, TTL
   thresholds), and open-drain outputs (or AHCT with a series resistor) on the
   way out.
3. **Present a sane load.** The O1's pull-ups are 3.3 K; the box should not add
   appreciably more capacitance or loading than one more TTL device on the bus.

Which P3 pin is which signal **is** in our material, and it never needed
measuring: [`docs/o1-ieee488-port.md`](https://github.com/Myrcurial/o1next/blob/main/docs/o1-ieee488-port.md) §6 transcribes §4.1.2 of the Technical
Manual, and the ROM's own comment block agrees with it line for line. §2.3 gives
the mapping for the lines this design actually touches.

### 2.2 Power

The EXMON precedent ([`hardware/drive-c-repro/README.md`](https://github.com/Myrcurial/o1next/blob/main/hardware/drive-c-repro/README.md)) takes power from **P5**, the
10-pin video connector, through a **passive shunt** — a Sullins
MP-0100-10-DS-4 edge connector and a Hyko K688-DI sync combiner — and uses
**+12 V**.

**The budget is documented, not guessed.** §7-2 of the Drive C manual gives the
original unit's own supply requirement:

> Power Requirements: **11 to 14.5 VDC at 0.3 A max.** (2.5 Watts nominal, 384K
> unit). Source: Draws power from the **O1 EXT. VIDEO connector** or from the
> optional Drive C BackPac backup power supply.

So the vendor ran the whole 384K unit — 384 KiB of static RAM, the printer
pass-through, all of it — off P5 at **0.3 A worst case**, from the same rail that
feeds the CRT. An RP2040 plus flash is a small fraction of that (a Pico is ~50 mA
at 3.3 V, well under 0.1 A at the rail after a buck). **No new measurement is
needed:** the shunt has to pass less than the original did, and the EXMON shunt is
only a connector plus a sync combiner, so it does not change the arithmetic.

The shunt is a **mod**, even though it is passive and reversible, and must be
documented as one — the same way the USB keyboard adapter's J6 bridge is.

### 2.3 Signals the box must actually watch, and where they are on P3

Per the protocol the box needs only five things, and [`docs/o1-ieee488-port.md`](https://github.com/Myrcurial/o1next/blob/main/docs/o1-ieee488-port.md) §6
gives each of them a pin. The **P3** column is what the board is laid out
against; the Technical Manual and the ROM agree on it.

| Signal | PIA | **P3 pin** | Role in this design |
|---|---|---|---|
| DIO1–DIO8 | PA0–PA7 | **1,3,5,7,2,4,6,8** | the data byte |
| PB0 | port B bit 0 | *not on the connector* | direction: `0` = host drives, `1` = box drives — it gates the 7406s |
| EOI | PB3 | **9** | low for the whole frame (`08h`, `88h`, `09h`) — frame framing |
| NRFD | PB7 | **13** | high only in the operation byte (`88h`/`81h`) — what distinguishes it |
| IFC | **CA2** | **17** | **the byte clock** — one pulse per byte |
| NDAC | PB6 | **15** | *optional* — the box may drive it high as "ready"; the transport never reads it |

Three consequences a layout has to respect:

- **The data lines are interleaved across the edge** — `DIO1–4` on the odd pins
  `1,3,5,7` and `DIO5–8` on the even pins `2,4,6,8`. That is the card edge's own
  geometry, not a bit-order choice, and it is why a straight ribbon will not do.
- **Pin 15 is `NDAC` in this personality and *busy* in the printer one**
  (`o1-ieee488-port.md` §6.2), while pin 11 (`DAV`) is the printer's strobe. A box
  that drives pin 15 has to stay harmless when the machine switches to the
  printer personality.
- **Pin 13 (`NRFD`) has to stay harmless as well.** The vendor's own printer-cable
  appendix ([`docs/drive-c-executive.md`](https://github.com/Myrcurial/o1next/blob/main/docs/drive-c-executive.md) §6) warns that a cable carrying
  Centronics pin 12 (Paper Error) to pin 13 "will interfere with normal Drive C
  operation if connected and MUST be removed" — so the original Drive C was
  watching pin 13, and a box on the same line must not fight it.

PB1, PB2, PB4, PB5, CA1, CB1 and CB2 are not needed to satisfy the transport —
though `PB1` and `PB2` are *enables* for the NDAC/NRFD and EOI/DAV drivers, so
they gate lines this design reads (`NDAC`) and watches (`EOI`, `NRFD`).

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
in a tight GPIO loop: a 13 µs byte interval is 77 kHz, far inside either path's
limit.

CA2 is sampled, not generated, so the box needs one edge-triggered input per
byte. A PIO state machine with a wait-on-pin is the natural implementation, with
the DMA feeding read data and draining write data.

### 3.3 Where the code lives

The personality is the same device as the interposer's IEEE-488 storage
personality (#22) — one implementation, two hosts. [`firmware/drive-c-gpib/`](https://github.com/Myrcurial/o1next/blob/main/firmware/drive-c-gpib/)
already exists as the home; this spec is what it implements.

## 4. Storage and geometry

**Addressing.** The host sends `DE`, the CP/M record address in 128-byte units,
as the header pair, and `drive-c-protocol.md` §5 decodes it. `DE>>1` is the box's
**track** (256 bytes), `DE&1` is the sector inside it, and `DE>>9` selects a
64 KiB bank. The box should decode the pair back to a flat byte offset —
`DE * 128` — which is the simplest correct model and the one `drive-c-box.lua`
uses.

**Size: 384 KiB, and the ceiling is 448 KiB.** The DPB is found
(`drive-c-protocol.md` §8.1): `SPT = 2`, 2 KiB blocks, `DSM = 191` → **192 blocks
= 384 KiB**; `DRM = 127` → 128 directory entries; `AL0 = C0h` → 4096 bytes of
directory. That is the 384K unit the archived disk belongs to, and it is what the
box must present. The host's own code caps the addressable range at `n ≤ 6` →
**448 KiB** (`drive-c-protocol.md` §8.3), so a **512 KiB flash** holds any Drive C
that can ever be driven, with room for a copy of the original image beside it.

**What the box does *not* do.** It does not implement CP/M. The directory,
allocation map and file structure live on the host side, in the CBIOS that
`DCL.COM` patches in. The box is a paged 128-byte record store, and the format it
sees (`0xE5` written across two regions and read back, `drive-c-protocol.md` §8.5)
is CP/M formatting *its own* disk through the box — **once, at install, not at
every boot** (§4.1).

**One thing to leave open in the firmware.** `f(n)` is identical for `n = 0, 1, 2`
(`drive-c-protocol.md` §5), so the header alone cannot tell tracks 0, 256 and 512
apart. A reproduction that treats `f` exactly as the driver does is unaffected —
it aliases exactly as much as the original does, if it aliases at all — but the
firmware should key storage on the **raw `(h1, h2)` pair** rather than
pre-decoding to an address, so that whichever answer turns out to be right can be
implemented without touching the frame decoder.

### 4.1 Persistence: the format happens once, and the loader knows it

It is easy to read `drive-c-protocol.md` §8.5 as *"the unit is re-formatted on
every boot"* and it is not true. The vendor's loader is **idempotent**, and the
manual says so in as many words:

> `DCQ T + n` means: *"If there is a file on the Drive C unit named
> **`DCLOADED.SYS`**, then skip n lines in this file to the next command line. If
> no such file exists execute the next line, and create the `DCLOADED.SYS` file on
> the Drive C unit."* … *"This operation prevents QuickPac from copying all your
> files over from floppy to Drive C if you have already done so but are **forced to
> reload and reboot CP/M**."*

`DCL.COM` guards itself independently — it carries the strings `Cannot install
driver` / `Driver is already installed` — and the contemporary review confirms it
from the user's side: *"The reset button does not lose the unit's contents — only
turning off the computer does that."* To force a re-load you must `ERA
DCLOADED.SYS`, or `DCU E`, which erases the unit.

**What that means for the reproduction.** Nothing in the contract changes: the
marker is an ordinary file in the CP/M directory, so it lives in records the box
already stores, and **load/unload needs no special support** — QuickPac's copy-in
and `DCA`'s Archive-Retrieve are bulk record traffic and nothing more.

The one divergence to decide, and the recommendation is to keep it: the original
loses everything on power-off unless a **BackPac** battery is fitted (8–10 hours),
and without one the marker goes too, so the next boot re-loads. Our storage is
**flash**, so contents persist inherently — the behaviour of a BackPac-equipped
unit. That is strictly better, costs nothing to implement, and means a working set
loaded once stays loaded. A bare unit's power-off amnesia is deliberately **not**
reproduced.

### 4.2 The blob: a raw CP/M image, so the tooling already exists

If the reproduction carries FAT32 storage (microSD or USB) and the image library
(#20, #27) keeps a unit's contents as a file on it, **the blob format is the one
thing that has to be chosen — and it does not need a new format.** The Drive C's
memory *is* a CP/M 2.2 filesystem, so a plain raw image of it is already readable
and writable by tooling this project uses.

The geometry is the DPB `DCL.COM` installs (`drive-c-protocol.md` §8.1), and it
maps onto a `cpmtools` diskdef exactly:

```
diskdef drivec
  seclen 128
  tracks 1536
  sectrk 2
  blocksize 2048
  maxdir 128
  skew 0
  boottrk 0
  os 2.2
end
```

**Checked, not asserted.** Every DPB field falls out of that geometry and matches
the bytes read out of `DCL.COM` — this is how [`tools/cpmfs.py`](https://github.com/Myrcurial/o1next/blob/main/tools/cpmfs.py)'s new `drivec`
format was verified:

| DPB field | From the geometry | In `DCL.COM` |
|---|---|---|
| `SPT` | `sectrk` = 2 | 2 |
| `BSH` / `BLM` | `blocksize` 2048 → 4 / 15 | 4 / 15 |
| `EXM` | 2048 B blocks, `DSM ≤ 255` → 1 | 1 |
| `DSM` | 393 216 / 2048 − 1 = 191 | 191 |
| `DRM` | `maxdir` 128 → 127 | 127 |
| `AL0` | 4096 B directory = 2 blocks → `C0h` | `C0h` |
| `OFF` / `CKS` | 0 / 0 | 0 / 0 |

**Why not `.IMD` or `.HFE`.** Both encode *floppy* geometry — FM/MFM encoding,
per-track sector IDs, the WD179x's world. The Drive C has no floppy controller:
its "tracks" are 256-byte units of two 128-byte records addressed by `DE`. An IMD
of it would mean inventing sector headers the hardware does not have. They are the
right formats for drives `A:`/`B:` — which is exactly what #20 says — and the
wrong one here.

**Three consequences worth fixing now:**

- **The file size *is* the geometry.** 393 216 bytes is the 384K unit; 196 608 is
  the 192K unit. A blob is self-describing by length, which is what a FAT32
  library wants — no sidecar metadata, and a wrong-sized file is obviously wrong.
- **It has to be byte-exact, not file-level.** `DFD.SPR` lives in user area 15 and
  `DCLOADED.SYS` / `DRIVEC.SYS` are hidden system files, so an archive of the
  *files* (`.LBR`, `.ARK`, `.ZIP`) will not do — the image must round-trip whole.
- **The mount is #20/#27's business, not the box's.** The transfer is Pico-side,
  FAT32 → record store, triggered over the **mailbox port**
  ([`docs/mailbox-protocol.md`](https://github.com/Myrcurial/o1next/blob/main/docs/mailbox-protocol.md), #155); `MOUNT.COM` only selects which blob. The
  box never parses FAT32, and nothing in §7's contract changes. This is also what
  makes "persistent Drive C" (#20) fall out for free: flash holds the records, and
  §4.1 says the loader will not re-format them.

**What the DPB is, and how it was read.** The DPB is the 15-byte CP/M 2.2
parameter block `DCL.COM` installs into the CBIOS; it sets the drive's size, and
`drive-c-protocol.md` §8.1 reads it as bytes out of `DCL.COM` at file `0x142F`
(installed `0x052F`). The whole round trip then passes through `cpmtools` as well,
on an image built from the same diskdef — write, list, read back, byte-compare:

```sh
dd if=/dev/zero of=d.img bs=128 count=3072   # 393216 bytes; mkfs does not size it
mkfs.cpm -f drivec d.img
cpmcp -T raw -f drivec d.img hello.txt 0:HELLO.TXT
cpmls  -T raw -f drivec d.img                # 0: hello.txt
cpmcp -T raw -f drivec d.img 0:HELLO.TXT hello.out
cmp hello.txt hello.out                      # byte-identical
```

**Why `-T raw` is needed.** `cpmls`/`cpmcp` hand libdsk a bare filename and let
it autodetect the container — and libdsk 1.4.2's **IMD** driver answers for a
file that is not an IMD. Its `imd_readto()` counts the read that hits EOF, so
`imd_open()` then asks for one byte more than the file holds and returns
`DSK_ERR_SYSERR`, which `dsk_strerror()` renders as `strerror(errno)` — *"No such
file or directory"* on a file that is plainly there. IMD is probed **before** the
raw drivers, so autodetection aborts there and never reaches the one that would
have accepted the image. `-T raw` names that driver (`dc_posix`, the "Raw file
driver") instead of asking for a guess; `-T logical` works equally well.
`mkfs.cpm` needs no flag because it opens the file directly and never consults
libdsk.

**This is a 1.4.2-only bug, and it is already fixed upstream.** libdsk **1.5.22**
carries the same over-read in `imd_readto()` but reports it as `DSK_ERR_NOTME`,
so the probe falls through to the raw driver instead of stopping. Measured
against this image with both builds: 1.4.2's `dsk_open(…, NULL, …)` fails with
`ENOENT`, a 1.5.22 build returns *no error*, and `-T imd` answers "Disc rejected
by driver" rather than the bogus `ENOENT`. Homebrew ships **1.4.2** — upstream's
*stable* release; 1.5.x is the development line — which is why the flag is what
makes `cpmtools` usable here. The upstream ask is therefore a **backport** into
the 1.4.x line, not a new fix: [`tools/README.md`](https://github.com/Myrcurial/o1next/blob/main/tools/README.md) has the recipe, and **#157** is
the report.

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

**Bus arbitration.** Two devices claim this port on a real machine — Drive C itself
and Trantor's hard disks ([`docs/drive-c-protocol.md`](https://github.com/Myrcurial/o1next/blob/main/docs/drive-c-protocol.md)) — and the O1's **own address
is 0**, so nothing else on the bus may use it ([`docs/o1-ieee488-port.md`](https://github.com/Myrcurial/o1next/blob/main/docs/o1-ieee488-port.md) §1). A
reproduction that only answers when it sees the Drive C frame pattern is
compatible with both by construction: it stays released until it sees its own
framing.

The **RT-60A is deliberately not in that list.** It is physically an IEEE-488
device, but this project implements its **ABI in software** rather than the
hardware ([`docs/rt60a-analysis.md`](https://github.com/Myrcurial/o1next/blob/main/docs/rt60a-analysis.md); #7 closed on exactly that basis), so no RT-60A
sits on the bus in any configuration we build. It is a software contract, not a
contender for the port, and the firmware does not need to arbitrate with it.

## 6. Test plan

1. **Protocol (done).** The frame, measured on the real software
   (`drive-c-protocol.md` §9).
2. **Box model (done, short runs).** [`tools/research/drive-c-box.lua`](https://github.com/Myrcurial/o1next/blob/main/tools/research/drive-c-box.lua) makes the
   1983 loader complete and PIP write to `C:`. Extend it into a proper harness —
   §7 item 3 — which is the fastest place to iterate on firmware logic before any
   hardware exists.
3. **DPB (done).** `drive-c-protocol.md` §8.1 — 192 blocks of 2 KiB, 128
   directory entries, 4096 bytes of directory. Give the box model that geometry
   and a full `PIP` copy can be checked end to end.
4. **Hardware-in-the-loop.** With a real O1: `DCL`, then `DCQ`, then
   `PIP C:=A:*.*[WV]` and a byte-comparison of a file moved both ways — the same
   acceptance test #95 used for the floppy formats, and the one the software
   itself provides.

## 7. What is left

Everything this spec was waiting on has now been answered from material already
in the archive, so this is a work list rather than a measurement list. The
Executive manual comparison ([`docs/drive-c-executive.md`](https://github.com/Myrcurial/o1next/blob/main/docs/drive-c-executive.md)) closed two more items
and confirmed the hardware is a single design for both machines.

1. **Board layout — unblocked.** The P3 pinout is documented (§2.3,
   [`docs/o1-ieee488-port.md`](https://github.com/Myrcurial/o1next/blob/main/docs/o1-ieee488-port.md) §6) and independently corroborated by the vendor's
   own printer-cable appendix ([`docs/drive-c-executive.md`](https://github.com/Myrcurial/o1next/blob/main/docs/drive-c-executive.md) §6); the power budget
   is documented (§2.2); and the mechanical, electrical and performance envelope
   is in §1.1. Nothing on the board is waiting on a measurement.
2. **Bus loading — the one real electrical unknown.** How much additional load
   (capacitance, pull-up) the O1's bus tolerates before its timings move. It is
   **not a design driver** and should be confirmed cheaply rather than designed
   around: the O1's pull-ups are 3.3 K, the transport clocks a byte every ~13 µs,
   and one more TTL-class load — or the AHCT input the RP2040 side will present,
   which is lighter still — is a leakage-and-a-few-pF question at those edge
   rates. What it decides is whether the board needs a **bus buffer at all**, so
   it is a confirmation step, not a blocker. A scope check with a spare TTL gate
   as the load settles it in an afternoon.
3. **Firmware against the model.** Turn [`tools/research/drive-c-box.lua`](https://github.com/Myrcurial/o1next/blob/main/tools/research/drive-c-box.lua) into a
   proper harness (§6 item 2) and drive the §8.1 DPB geometry through it.
4. **The `f(n)` ambiguity** (`drive-c-protocol.md` §10 item 2). Not a blocker —
   keep the raw `(h1, h2)` key so the answer stays swappable (§4).
5. **TurboPac is out of scope for #84.** The unit is also the Trantor hard-disk
   host adapter (`drive-c-protocol.md` §8.4); that half needs the hard-disk side,
   which overlaps #8.
6. **A print buffer, if we offer one.** The manuals give its capacity and its
   fixed/dynamic split (`drive-c-executive.md` §5) — including that a fixed
   buffer is carved out of the RAM disk — but not the spooling *protocol*: how
   the box interleaves buffer traffic with the pass-through printer connector.
   Optional feature, not part of the RAM-disk contract.

## Sources

- [`docs/drive-c-protocol.md`](https://github.com/Myrcurial/o1next/blob/main/docs/drive-c-protocol.md) — the protocol this implements (the contract), the
  DPB (§8.1) and the capacity ceiling (§8.3).
- [`docs/drive-c-executive.md`](https://github.com/Myrcurial/o1next/blob/main/docs/drive-c-executive.md) — the Executive variant and the manuals' appendices:
  the envelope (§1.1), the print-buffer budget (§7 item 6) and the printer-cable
  corroboration of P3 (§2.3).
- [`research/drive_c/Drive_C_Users_Manual.pdf`](https://github.com/Myrcurial/o1next/blob/main/research/drive_c/Drive_C_Users_Manual.pdf) (OCR at `…ocr.txt`) — §7-2 hardware
  specifications (power, throughput, access time) and §7-3 CP/M parameters. Both
  spec pages are image-only with an OCR that loses the table alignment, so read
  them from the PDF: printed p. 133 = PDF p. 141, printed p. 134 = PDF p. 142.
- [`research/osborne1/modem/o1techman-interface-extract.pdf`](https://github.com/Myrcurial/o1next/blob/main/research/osborne1/modem/o1techman-interface-extract.pdf) — §4.1.2 the **P3
  pinout**, §4.1.1 the signal directions, §4.1.5 the same pins as a Centronics
  port; transcribed in [`docs/o1-ieee488-port.md`](https://github.com/Myrcurial/o1next/blob/main/docs/o1-ieee488-port.md) §6.
- [`docs/o1-ieee488-port.md`](https://github.com/Myrcurial/o1next/blob/main/docs/o1-ieee488-port.md) — the port's device-level behaviour, the ROM's eight
  drivers, and the joystick worked example.
- [`docs/o1-memory-io-map.md`](https://github.com/Myrcurial/o1next/blob/main/docs/o1-memory-io-map.md) §6 — P3/P5 and the other connectors.
- [`docs/o1-mainboard-schematic.md`](https://github.com/Myrcurial/o1next/blob/main/docs/o1-mainboard-schematic.md) sheet 9 — the IEEE-488 interface, the PIA and
  the open-collector drivers.
- [`docs/interposer-survey.md`](https://github.com/Myrcurial/o1next/blob/main/docs/interposer-survey.md) §5 — NODISKEMU and cbmSD, the IEEE-488 state
  machines to port.
- [`hardware/drive-c-repro/README.md`](https://github.com/Myrcurial/o1next/blob/main/hardware/drive-c-repro/README.md) — the device's place in the project, and the EXMON
  shunt precedent.
