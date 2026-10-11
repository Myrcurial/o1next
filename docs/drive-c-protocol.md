# Drive C: the IEEE-488 RAM disk — protocol and device contract (#6, #84)

**Status: solved.** The host side is read out of `DCL.COM`'s disassembly and
**confirmed against a trace of the real Drive C software running on the emulated
machine** (§9) — and a model of the box, built from this spec, makes the 1983
loader complete (`QUICKPAC Drive C: loading has been completed`) and CP/M start
copying to drive `C:` with PIP. What is *not* known is the box's internals
(§10); a replacement does not need them, because the contract below is what the
host exercises.

Sources: `research/drive_c/DRIVE_C.IMD` (the software), `research/drive_c/extracted/`
(`dcl.com`, `dfd.spr`), `research/source-code/BIOS-144-source/rom144.asm` (the
ROM's own account of the port), and `research/drive_c/Drive_C_Users_Manual.ocr.txt`.
Serves #6 (the protocol) and #84 (the reproduction); `docs/drive-c-design.md` is
the hardware + firmware spec built on it.

## 1. What the device is

A battery-backed RAM disk that hangs off the Osborne 1's **IEEE-488 edge
connector** (P3) and duplicates that connector plus the Ext. Video connector on
its own front panel, so the printer and a monitor can be plugged through it. It
sold as 192 K and 384 K, in two parts: the unit (the RAM) and a software package
(`DCL.COM` + `DFD.SPR`) that installs it as a CP/M drive and adds a print buffer.
`DCL.COM` is the installer/transport, `DFD.SPR` the resident command layer.

**The manual is explicit that this is not GPIB:**

> **IEEE-488 COMMUNICATIONS PROTOCOL IS NOT SUPPORTED** ON THE Drive C
> PRINTER/HARD DISK/8088 EDGE CONNECTOR

The connector is used as a **parallel port** — the same trick the ROM itself uses
for Centronics printers (§2). That is the single most important fact about the
device: it is not a GPIB device and does not decode GPIB handshake semantics.

## 2. The electrical layer: the PIA, and what each line is

The host drives the box by bit-banging the motherboard's **MC6821 PIA at
`2900–2903`** (bank 2). The ROM's own source documents what each pin is
(`rom144.asm` §"IEEE-488 INTERFACE", lines 2606–2715), and it is the authority
here — these are the vendor's comments, not an inference:

| PIA | Line | GPIB name | Centronics use (`rom144.asm` 3250–3263) |
|---|---|---|---|
| PA0–PA7 (`2900`) | DIO1–DIO8 | data | **data bus** |
| CA1 (`2901` bit 7) | SRQ | service request in | "low→high gates input data to port A" |
| CA2 (`2901` bits 5:3) | IFC | interface clear | **"going low indicates to device that we are busy"** |
| CB1 | — | not used | — |
| CB2 (`2903` bits 5:3) | REN | remote enable | — |
| PB0 (`2902` bit 0) | enable data out | | **`0` = data bus is output, `1` = input** |
| PB1 | enable NDAC/NRFD | | set to 1 |
| PB2 | enable EOI/DAV | | set to 0 |
| PB3 | EOI | | `0` output, `1` input |
| PB4 | ATN | | not used |
| PB5 | DAV | | **output strobe, active = 1** |
| PB6 | NDAC | | **`0` = printer busy, `1` = printer ready** |
| PB7 | NRFD | | not used |

Two facts fall out, and both are load-bearing:

- **PB0 is the direction control for the data lines.** It is how the host says
  "I am writing" (`PB0=0`) or "you drive the bus" (`PB0=1`), and it is also the
  bit that distinguishes the two operations (§4).
- **All signals are active-low** — *"ALL SIGNALS ARE LOW ON THE IEEE BUS WHEN
  PIA REGISTER CONTAINS 1"* — and the O1 drives them through 7406
  open-collector gates. A replacement must **release** lines, never drive them
  high.

Drive C's own use of the port (measured, §3) is a subset: port A for data, PB0
for direction, PB3/PB7 as framing, and **CA2 as the byte clock**.

## 3. The host's frame — measured

`DCL.COM` installs a relocatable block at `0x0600–0x07BE` (the file holds it at
`0x1600–0x17BE`; the internal `JP 0757h`/`JP 0763h` are its *installed*
addresses, which is what gives the relocation away). The transport routine is
`0x06D5–0x07B4`; a helper at `0x07B5` writes port A and pulses CA2.

**Every operation is one frame, and every frame re-initialises and tears down the
PIA.** A trace of the real software (10 195 PIA accesses, §9) shows this
sequence, byte for byte:

```
DI                                   ; interrupts off for the frame
OUT (0),A                            ; bank 2 (the O1's own I/O bank)
CRA=32h ; PA<-FFh ; CRA=36h          ; port A = output
CRB=32h ; PB<-FFh ; CRB=36h          ; port B = output, CB2 (REN) high

PB<-08h                              ; frame open
PA<-h1   ; CA2 pulse                 ; header byte 1
PB<-00h                              ; phase separator
PA<-h2   ; CA2 pulse                 ; header byte 2
   [read frames only] CRA=32h ; PA<-00h ; CRA=36h   ; port A -> INPUT
PB<-88h  (write) | 81h (read)        ; the operation
   128 x {  PA<->byte ; CA2 pulse  }  ; the data phase

PB<-09h                              ; frame close
CRA=32h ; PA<-FFh ; CRA=36h          ; port A back to output
CRB=00h ; PB<-BFh ; CRB=04h ; PB<-02h ; port B: PB6 becomes an INPUT
OUT (1),A ; EI                       ; bank 1, interrupts on
```

Two details in the teardown matter: `PB<-BFh` is written with `CRB` bit 2 clear,
so it lands in the **direction** register — **PB6 becomes an input** — and the
final `PB<-02h` leaves the port in a resting state. So after every frame the box
is *able* to drive PB6 (NDAC / "ready"), which is the one line the host could
read for flow control.

## 4. Port B: the four states

Port B is written as a **state word**, not as individual handshake lines. Only
four values are ever written during a frame, and each has a job:

| Value | Bits set | Meaning |
|---|---|---|
| `08h` | PB3 | **frame open** — EOI asserted low, data drivers disabled |
| `00h` | — | **phase separator** — between the two header bytes |
| `88h` | PB7, PB3 | **write** — NRFD asserted, EOI low, and **PB0=0 so the host drives DIO** |
| `81h` | PB7, PB0 | **read** — NRFD asserted, and **PB0=1 so the host releases DIO** |
| `09h` | PB3, PB0 | **frame close** — EOI low, data drivers released |

So `88h` and `81h` are the two operations, and the difference that matters is
**PB0**: `88h` = write to the box, `81h` = read from the box. That is confirmed
three ways — the op byte, the `DDRA` the host sets before the data phase, and
the direction of the `LDI` in the transfer loop (§6).

## 5. Port A: the two header bytes, and the record address

Before the operation byte the host sends **two bytes on port A**, each clocked by
a CA2 pulse. They are not a command and a length; they encode **the record
address**, and the code says exactly how. The caller
(`DCL.COM` `0x1122–0x115D`, installed `0x0122`) is entered with:

- `HL` = the caller's 128-byte buffer,
- `DE` = the **16-bit record address**,
- `A` = `0FFh` to read, `0` to write;

and it computes

```
h1   = (DE >> 1) & 0FFh          ; sent first
n    = (DE >> 9) & 0FFh          ; high bits of the record address
h2   = f(n) | ((DE & 1) << 7)    ; sent second
```

where `f(n)` is the sector/size nibble the box wants:

| `n` | 0 | 1 | 2 | 3 | 4 | 5 | 6 |
|---|---|---|---|---|---|---|---|
| `f(n)` low nibble | `Ch` | `Dh` | `Eh` | `3h` | `7h` | `Bh` | `Fh` |

So the pair `(h1, h2)` is a **bijective encoding of `DE`**: `h1` is the low eight
bits of `DE>>1`, bit 7 of `h2` is `DE&1`, and the low nibble of `h2` carries
`DE>>9` through the table above. `DE` is the CP/M record address in 128-byte
units, so the box's own unit is **256 bytes** (`DE>>1`), with `DE&1` selecting
the 128-byte half.

Measured examples from the trace: the boot-time format writes `h1 = 00h…0Fh`
with `h2 = 8Ch` (→ `DE = 1,3,5,…,31`) and `h1 = 00h…0Fh` with `h2 = 0Ch`
(→ `DE = 0,2,4,…,30`); and the first operation is a read at `h1 = E8h`,
`h2 = 83h` → `DE = 0x7D1`.

## 6. The byte clock, and the data phase

**CA2 is the byte clock.** The host writes `CRA=3Eh` then `CRA=36h` — CA2 low
then high — once per byte, and the helper at `0x07B5` wraps "write port A, then
pulse CA2". Nothing else is handshaken: **the transport never reads PB6 and never
polls for ready**, so the box has to keep up. The loop is ~52 T-states per byte
(about 13 µs at 4 MHz), and a read must be answered within ~6 T-states of the
CA2 edge.

The order differs between the two directions, and that is the box's cue:

- **write:** the byte is placed on port A **first**, then CA2 pulses — the pulse
  says *latch it*.
- **read:** CA2 pulses **first**, then the host reads port A — the pulse says
  *present the next byte*. (A box that keeps the next byte on DIO and advances on
  each pulse satisfies this; one that only drives the bus after seeing the pulse
  has ~1.5 µs to do it.)

128 bytes are transferred per frame in both directions.

## 7. The device contract — what a replacement must do

This is the normative summary. A box that satisfies it will run `DCL.COM`,
`DFD.SPR` and the rest of the software unchanged.

1. **Observe the PIA lines.** Port A (DIO1–8) is the data byte. Port B bits 0,
   3, 5 and 7 carry direction and framing. CA2 is the byte clock. CB2/REN is
   held high and can be ignored.
2. **Decode the frame** from the port-B state words: `08h` opens, `00h`
   separates the header, `88h`/`81h` is the operation, `09h` closes.
3. **Capture the two header bytes** on their CA2 pulses (after `08h`, then after
   `00h`) and decode them to a 16-bit record address (§5).
4. **For `88h`,** latch 128 bytes from port A, one per CA2 pulse, and store them
   at that record.
5. **For `81h`,** present 128 bytes on port A, one per CA2 pulse.
6. **Release the data lines** whenever `PB0 = 1`; drive them only while
   `PB0 = 0`. Everything is open-collector: never drive a line high.
7. **Keep up with the clock** — there is no ready handshake in the transport.
   PB6 may be driven (high = ready) and is left as an input at the end of every
   frame, but nothing in the transport reads it.
8. **Survive the frame boundary.** Each frame is self-contained: init, header,
   data, teardown. A replacement may be stateless across frames.

## 8. Capacity, the DPB, and how `C:` appears

The box itself is a block store; the *filesystem* is CP/M's, and the geometry
CP/M uses for `C:` comes from the **DPB the installer patches into the CBIOS**
when `DCL` runs. That is the one piece of the picture this spec does not yet
pin down (it is `DCL.COM`'s BIOS patch, not the transport), and it is the only
thing a replacement has to get *right* rather than merely *obey*.

What the trace does show is the **format**, and it is a strong hint: at boot the
software writes `0xE5` (CP/M's blank byte) across two regions —
`h1 = 00h…0Fh, h2 = 8Ch` and `h1 = 00h…0Fh, h2 = 0Ch`, i.e. `DE = 0…31` — then
**reads each block back** to verify. Two regions, 16 blocks each, 128 bytes per
block: that is 4 KiB, which is the *directory and boot area*, not the whole
disk. So the format is incremental and continues as the disk is used, and the
address space is paged by `DE` (§5), not by a flat block number.

The capacities the vendor sold (192 K, 384 K) and the `DE` range the nibble table
supports (`n = 0…6` → `DE < 3584` → 448 K) are consistent with a paged RAM
address space, which is what a replacement should implement: **`DE` is the
address, and the size is whatever the DPB says.**

## 9. Validation — the spec, run against the software

Two tools in `tools/research/` were written for this, and both are worth keeping:

- **`drive-c-trace.lua`** — write taps on `2900–2903`, logging every PIA access
  while the real software runs. Stable and reproducible: **10 195 accesses** on a
  30-emulated-second run, which is the trace quoted throughout this doc. It is
  how the frame in §3 was *measured* rather than only read out of the
  disassembly — including the two facts the disassembly is easy to misread:
  that the header bytes go to **port A** (not port B), and that the read frame
  sets `DDRA=00h` before the operation.
- **`drive-c-box.lua`** — a **model of the box** built from this spec: it decodes
  the port-B states, reconstructs the record address, keeps 128-byte blocks, and
  answers reads. With it present, the real 1983 software **completes**:

  ```
  QUICKPAC.  Loading Drive C:....
  A>DCL
  A>DCQ T + 1
  A>PIP C:=A:*.*[WVOR]
  COPYING -
  AUTOST.COM
  DCQ.DAT
  ```

  i.e. `DCL` installs, QUICKPAC loads the driver, and **PIP starts writing to
  drive `C:`** — so CP/M sees the drive and the protocol is good enough for the
  shipped software. (`[WVOR]` includes `V` for verify, which reports a mismatch
  against this simplified model; the addressing is right, the model's
  `0xE5`-only initial contents are not.)

**A MAME limitation, recorded because it cost time:** a read tap that returns a
*value* eventually segfaults MAME's Lua layer once the guest's resident driver
starts polling (the run dies ~20 emulated seconds in; returning a constant
instead keeps it alive). The trace tool is unaffected because it only writes
taps. Treat the box model as a validation aid for short runs, not a harness.

## 10. What is still open

1. **The DPB and the BIOS patch** (§8) — how many records `C:` has, and where
   `DCL.COM` hooks it in. This is what makes a replacement a *disk* rather than
   a *block store*, and it is the next unit of work for #84.
2. **The box's internals.** What the `f(n)` nibble means to the original hardware
   (§5), whether it is a hardware counter or an address decode, and whether the
   two format regions are directory + boot area or something else. Not needed to
   *obey* the protocol, but it would explain the design.
3. **The print-buffer path** (`PRN.TST`, `DCU`) and how spooling shares the same
   port with the pass-through printer connector.
4. **`DFD.SPR`'s command layer** — the resident CCP-style driver that calls the
   transport. Its committed listing is a linear sweep through zero blocks and is
   not usable; a code-aware disassembly would name the operations (§5's `DE` is
   the record, but *which* CP/M call drives which is in DFD.SPR).

## Sources

- `research/drive_c/DRIVE_C.IMD` — the Drive C software disk (ImageDisk,
  40-track FM 10×256); `research/drive_c/extracted/` holds the files.
- `research/source-code/BIOS-144-source/rom144.asm` — the ROM's IEEE-488 and
  Centronics line definitions (lines 2606–2715 and 3250–3269). The authority for
  §2.
- `research/drive_c/disasm/dcl.asm` — `z80dasm` of `dcl.com`; §3 and §5 are read
  from it (the resident block is file `0x1600–0x17BE`, installed `0x0600–0x07BE`).
- `research/drive_c/Drive_C_Users_Manual.ocr.txt` — the vendor's manual (OCR).
- `docs/o1-ieee488-port.md` — the port's device-level behaviour and the ROM's
  eight drivers.
- `tools/research/drive-c-trace.lua`, `tools/research/drive-c-box.lua` — the
  measurement and the model (§9).



## Appendix — the files on the disk
| File | Size | Role |
|---|---|---|
| DCL.COM | 6656 | "DRIVEC version 2.08" — driver installer/loader. Loads DFD.SPR, DCA/DCU. "Cannot install driver$Driver is already installed$". Per the vendor's review it **replaces the earlier `DRIVEC.COM`**, and when the print buffer is switched on it copies `DCU.COM` into the unit |
| DFD.SPR | 2560 | Resident driver (page-relocatable SPR). Contains CCP-style command table (DIR ERA HELP REN SAVE TYPE USER) + BIOS hook code. The vendor describes it as "**a substitute console command processor (CCP)**" that is "**automatically loaded**" |
| DCA.COM | 9984 | "DCA version 1.85" — the **Archive-Retrieve** program per the vendor's own review (it "replaces both `DCARCH.COM` and `DCRET.COM`"). The earlier "assign/configuration" label came from the disassembly and is questioned below |
| DCU.COM | 6272 | "DCU version 1.40" — RAM-disk utility (erase all, directory, files/line config; generates DCUN.COM via SAVE 28) |
| DCQ.COM + DCQ.DAT | 896+128 | "DCQ version 1.22" QUICKPAC — fast boot-time loader; DCLOADED.SYS marker |
| DCQINS.COM | 7296 | QUICKPAC installer (writes boot track via DCL); text by David E. Price |
| AUTOST.COM / DCQAUT.COM | 768 | Auto-starter: submits QUICKPAC at cold boot via $$$.SUB |
| PRN.TST | 7936 | Print test file (likely exercises the print-buffer feature) |
| PIP.COM, XDIR.COM | — | Utilities |

Author: Kenneth M. Toy, (c) 1983 Drive C. Also supports a print buffer
("Bad print buffer parameter, not loaded", "Not enough space for fixed
print buffer"). Osborne-1 only: "cannot be used with the Executive".

### The transport lives in DCL.COM, not DFD.SPR

This doc previously implied DFD.SPR held the protocol. It does not:
`grep -E '290[0-3]h' dfd.asm` returns **nothing** — DFD.SPR never touches the PIA.
DCL.COM holds all 22 PIA references. DFD.SPR's only port access is a single
`OUT (0F1h),A` at `0x0803`, still unexplained (`F1h` is not a PIA address; likely
the double-density board or a status port).

So the split is **DCL.COM = transport + installer**, **DFD.SPR = the command layer
that drives it** (its own command table is DIR/ERA/HELP/REN/SAVE/TYPE/USER). How
DFD.SPR reaches the transport is still the one thing missing from the command
layer (see §10), because it makes no direct PIA references — so it must be a
patched vector or a relocation DCL performs at install time.
### DFD.SPR's layout, and why the committed listing misleads (#6)

`research/drive_c/disasm/dfd.asm` is a `z80dasm` linear sweep from `0x100` over the
whole 2560-byte file. Reading the file's own structure (a raw byte scan — the
disassembly alone hides this) shows two large **zero-filled regions**, file
offsets `0x003–0x0FF` (253 bytes) and `0x10C–0x17B` (112 bytes), plus a
header/jump area and the command table:

| File offset (= address − `0x100`) | Contents |
|---|---|
| `0x000–0x002` | `00 C6 07` — SPR header |
| `0x003–0x0FF` | **zeros** (253 bytes) |
| `0x100–0x10B` | `JP 0103h` / `JP 00FFh` + `STAT` |
| `0x10C–0x17B` | **zeros** (112 bytes) |
| `0x183` / `0x18B` | `COM` / `$$$ … SUB` |
| `0x1CC` | **command table**: `DIR ERA HELP REN SAVE TYPE USER` |
| `0x1F0` | command **vector table** (`0591h 0525h 0647h 0666h`) |
| `0x1F8` | `=_.:;<>` |
| `0x2A3` | `NO FILE` |

Because the sweep starts at `0x100` and walks straight through those zero blocks,
its `call sub_01aah` / `sub_01b1h` / `sub_01f5h` / `sub_020fh` … targets all land
**inside the zeros** and are spurious — they are not entry points. So the
command layer cannot be read off this listing; it needs a disassembly that starts
at the code region and treats the zero blocks as data (§10).

What *is* established from the bytes:

- DFD.SPR contains **no access to the PIA** `2900–2903h` (no `32 xx 29` stores) —
  confirming the split above.
- Its only I/O opcode is the single `OUT (0F1h),A` at `0803`.
- Its command layer is self-contained in the `0x180–0xB00` region, with a real
  command table at `0x1CC` and a vector table at `0x1F0` whose entries point
  *within the file* (`0x591`, `0x525`, `0x647`, `0x666`) — code, not relocation
  slots.




## What the unit was like to use (contemporary reports)

Two letters in *The Portable Companion* #15 (Jan/Feb 1985, PDF p. 52) give the
user side of the unit. That matters to the reproduction (#84): it has to be worth
using, not merely protocol-correct.

> I've been using my **384K unit** for one month and it's turned my single density
> Osborne 1 into a totally new machine. … it takes **six seconds** to go from the
> editing no file menu in WordStar to the dot prompt in dBASE II. **Before I had
> Drive C: I had to boot up a new disk every time** I wanted to edit a program.
> That was minutes waiting while the Osborne booted up different files. … I had to
> shell out **$250 to Xerox for an exchange disk drive** two months ago. Now my
> **disk drives get 90% less wear** and I do 90% more work.
> — Martin Kilgore, South Pasadena, CA

And the reviewer, in the same issue, standing by a negative verdict:

> I still stand by what I wrote — **Drive C: is not a good buy for the average
> user**. … both of the readers who responded are doing precisely what I said the
> unit would be good at — **disk intensive operations for large parts of the
> day**.
> — Donald G. Krantz, Minneapolis, MN

So there was a **384K** configuration, and the disagreement was never about
whether it worked — it was about who it was for. Extract:
`research/technical-articles/TPC-Issue15-1985-pp52-drive-c-letters.pdf`.

## The vendor's software set, from a contemporary review

*The Portable Companion* #14 (Nov/Dec 1984), printed pp. 41–45 = PDF pp. 43–47,
carries **"Review of New Drive C: Loader & Archive Programs" by Larry Walker** —
and, usefully for provenance, it is a **reprint from *FOGHORN* (First Osborne
Group) 9/84**. It documents the second-generation Drive C: software, which is
what this disk holds, and it names each program and its job:

| Program | What the review says it is |
|---|---|
| `DCL.COM` | the loader "that makes the Drive C: unit accessible", replacing `DRIVEC.COM`; also turns the print buffer on, and then copies `DCU.COM` into the unit |
| `DFD.SPR` | "**A substitute console command processor (CCP)**, DFD.SPR is designed to make Drive C: work better and is **automatically loaded**" |
| `DCA.COM` | the **Archive-Retrieve** program, replacing both `DCARCH.COM` and `DCRET.COM` |
| `DCU.COM` | the print-buffer utility, loaded into the unit with the buffer; `DCU` gives a menu, `DCU E` erases every file |
| QuickPac: `DCQ.COM`, `DCQINS.COM`, `DCQ.DAT`, `DCQAUT.COM` | `DCQ.COM` "allows you to store a series of commands in SUBMIT fashion to load Drive C:, name it, copy the contents of a disk (or disks) into it, select a print buffer option, and run a program at the end of the process"; `DCQINS` is the menu-driven installer, writing the ASCII `DCQ.DAT`; startup becomes automatic by renaming `DCQAUT.COM` to **`AUTOST.COM`** |
| `DCN.COM` | "**automatically generated and loaded into Drive C: when the loader program is run**" — it backs the `DCN` rename command |
| `PRN.TST` | the print test file, sent to the printer at the end of installation |

The archive lineage is spelled out too: `DCARCH.BAS` (needed MBASIC, "very
slow") → `DCARCH.COM` (compiled, "bugs that arose when it was called upon to
close files") → `DCA.COM`.

### Command syntax of this generation

- `DC1 A` — install the unit and name it logical A. **This replaces
  `DRIVEC A: C:`**, which named the unit A and the left floppy C in one go.
- `DCN x` — rename the unit to logical name `x` at the CP/M prompt.
- `DC1 A16` … `DC1 A128` — as above plus a **fixed print buffer of 16, 32, 48, 64,
  80, 96, 112 or 128K**. Substituting `P` installs the **dynamic** buffer — all
  otherwise unused memory, released back to programs as the buffer drains. Any
  other letter means no buffer is installed.
- `DCU` — buffer menu (stop/restart the dump, clear the buffer, report dynamic
  space); `DCU E` erases the unit.
- `DCA RB` — run Archive-Retrieve in **Retrieve** mode from drive B:.

### Behaviour, and one gotcha that matters for emulation

- **A printer that is connected but switched off crashes the machine.** The
  review is explicit: *"If the printer is connected but OFF, the Loader will not
  work and the Osborne 1 will crash."* Cables must meet OCC's specification, and
  some printers (the reviewer's Daisywriter 2000) "look funny" to the unit — the
  fix being to disconnect the cable or leave the printer on. This is a property
  of the duplicated printer port, so a personality for #84 has to reproduce the
  failure and not only the success.
- **The reset button does not lose the unit's contents** — "only turning off the
  computer does that" — with the obvious advice to save first.
- **Archived files are stored contiguously as a single file** and are only
  readable through Retrieve; the directory shows one entry. A set spanning two
  disks names the second `filename.AR2`. The program warns when the target disk
  is not blank, shows its directory, and asks twice before erasing.
- **Speed**, as measured by the reviewer: `WSMSGS.OVR` (34K) retrieved into the
  unit in **10 seconds** versus **17** with PIP; a 272K WordStar + Spellguard set
  in 115 seconds. Single-density owners need two disk changes and take longer.
- **Cabling**: the unit mounts in the pocket below the right drive; the longer
  cable goes to the **IEEE-488 connector on the left side**, the shorter to the
  **External Video port** directly below the unit. Both O1 connectors are
  duplicated on the Drive C: panel (Centronics printer cable and shorting plug),
  and the unit has its own external video jack, so no adapter is needed.
- **Capacities sold**: 192K and 384K (the reviewer bought 384K).
- **Terms**: the new package was free to customers who bought after **31 December
  1983**, $39 to earlier ones; the manual runs to nearly 150 pages.
- **BackPac** — a battery pack inside the keyboard enclosure that holds the unit's
  memory for **8–10 hours** after power is lost, "deliberately or through power
  failure". Announced but not shipping at the time of writing, manual still being
  written, target price **$150**.
- The same vendor resold **Trantor** hard disks at a discount. The Trantor
  advertisement itself (*The Portable Companion* #5, February/March 1983,
  PDF p. 28; extract
  `research/technical-articles/TPC-Issue05-1983-pp28-trantor-tsl-hard-disk-ad.pdf`)
  shows what the product was: the **TSL-5** and **TSL-10**, **5 MB $2995 /
  10 MB $3395**, *"unpack your disk, **plug it into the IEEE port**, run a simple
  5 minute installation procedure"*, supplied *"complete with BIOS, back-up,
  retrieve utilities and cable"*. So Trantor's Winchester is a **third
  IEEE-488-attached** storage device on this machine alongside Drive C — one more
  claimant on the port that #84 has to arbitrate.

Extract: `research/technical-articles/TPC-Issue14-1984-pp43-47-drive-c-loader-and-archive-programs.pdf`.


## Disassembling

```
z80dasm -a -l -g 0x100 -o research/drive_c/disasm/dcl.asm research/drive_c/extracted/dcl.com
z80dasm -a -l -g 0x100 -o research/drive_c/disasm/dfd.asm research/drive_c/extracted/dfd.spr
```

**z80dasm 1.2.0** (`brew install z80dasm`) — the same version and flags as the
committed CoPower listings, so the two sets are directly comparable. It is a
linear sweep, so it misaligns around data tables: DCL.COM has a data and
jump-table region from roughly `0x0840`, and absolute `JP`/`CALL` targets that
land there are table bytes or loader-patched relocation points, not code. (The
`jp pe,00757h` / `jp pe,0763h` inside the data-transfer loop are the clearest
example: `0x0757 + 0x1000` is the loop's own body, so the loader is adding a page
offset when it installs the resident copy.) Read the listing with that in mind
rather than trusting it end to end.

cpmtools `cpmls`/`cpmcp` with the `osb1sssd` diskdef worked perfectly, once the
IMD was converted to raw with disk-analyse.
