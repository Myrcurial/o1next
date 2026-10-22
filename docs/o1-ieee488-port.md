# The Osborne 1 IEEE-488 (GPIB) port — P3 (#22, #84)

**Status: Solved.** The P3 pinout is transcribed from the Technical Manual's
§4.1.2 and corroborated line for line by the ROM's own comment block; what the
port implements is read from the ROM's eight drivers and the manual's own
figure. The one thing still open on P3 is electrical rather than logical — the
loading a device may present (§7).

**P3 is a 26-pin card edge connector carrying 24 IEEE-488 lines** (pins 25 and
26 are unused), driven by a **Motorola MC6821 PIA at `2900–2903`** (§6). The
machine can act as Talker, Listener or Controller, and its own bus address is
**0** (§1). It implements **a subset of IEEE-488, with no three-wire handshake**
— the ROM's **eight low-level drivers** are the whole of its behaviour, and
`DAV`/`NRFD`/`NDAC` cannot be read back, which is why every device on this port
invents its own clock (§2, §6.1). The same pins are re-labelled as a
**Centronics printer port** when SETUP selects the printer personality (§6.2).
§5 is the project's one fully-worked external device on the port: a **game
joystick on `D0`–`D4`**, read either through driver 8 (`CALL 0E154H`) or by
bit-banging the PIA directly.

Source: *The Portable Companion* #8, July 1983 — "**Understanding the IEEE-488
port** — Scientific interfacing with the Osborne 1" by **Wayne Kogachi** and
**Shahriar Kianersi**, PDF pp. 38–41 (printed 36–39), and "**Interfacing
External Devices** — add a game joystick to the Osborne 1" by **Kelly Smith**,
PDF pp. 44–49 (printed 42–47). Archived in-repo at
`research/technical-articles/TPC-Issue08-1983-pp38-41-understanding-the-ieee-488-port.pdf`
and `research/technical-articles/TPC-Issue08-1983-pp44-49-interfacing-external-devices-joystick.pdf`.

Both authors of the first article are **OCC staff** — Kogachi a software
engineer, Kianersi a system support specialist — so the article is effectively
the vendor's own account of the port, and it points at the *User's Guide*
chapter "IEEE-488 implementation" for the same material.

The port's address map and the ROM's view of it live in
`docs/o1-memory-io-map.md` §2 (`2900–2903`, **MC6821 at UC7**) and
`docs/o1-rom-source.md`; the Drive C: RAM disk that hangs off it is in
`docs/drive-c-protocol.md`. **This doc records what the two articles add**: the
port's device-level behaviour, the eight ROM drivers as the articles name them,
and the one fully-worked application — a game joystick wired straight onto the
data lines.

Bearing issues: #22 (Drive C / IEEE-488 storage), #84 (standalone Drive C on
P3), #19 (virtual MX-80 / Centronics capture), #12 (interposer spec).

## 1. What the port is

- **TTL logic level**, driven by a **Motorola 6821 PIA**; "after configuring the
  pin connection for the IEEE standard, one can simply connect the Osborne to
  any IEEE compatible device."
- The machine can act as any of the three IEEE-488 device definitions:
  **Talker, Listener and Controller**. Bus management is: announce the
  **Talker first, then the Listener**, after which the Controller releases the
  bus and lets those two devices talk. The Controller may announce itself as
  either Talker or Listener, and its periodic takeovers "should be done
  *synchronously* rather than *asynchronously*."
- **Up to 15 devices** on the bus: *"The IEEE-488 port can call up to 15
  different devices at one time on the data bus. (From a software point of
  view, the figure is 29 different devices; however, due to practical hardware
  limitations only 15 devices are allowed.)"*
- **The Osborne's own address is zero**, *"so no other device with that address
  port can sit on the data bus"* — a hard constraint on any bus we build.
- The second article's framing is the useful one for this project: *"The
  IEEE-488 Bus implementation is really just a **parallel data port
  controller** that can be used for a variety of interfacing possibilities that
  require byte-wide (8 bits at a time) data. This controller is known as a 6821
  PIA … and may be programmed in a variety of different input/output control
  modes."*


## 2. The eight ROM drivers

> "Osborne's IEEE-488 port has **eight low-level 'drivers,' which reside in the
> ROM** and take care of all the IEEE-488 interfacing requirements. These
> routines are documented in the *User's Guide* in the IEEE-488 implementation
> chapter. One may invoke any of the routines simply by calling them and passing
> the proper parameters through preassigned registers. One may also receive
> messages through assigned registers."

| # | Driver | Parameter registers | Returns |
|---|---|---|---|
| 1 | **Control Out** | `C` = code to clear the interface (IFC) and/or set/reset REN | — |
| 2 | **Status In** | — | `A` = value acknowledging that a device is requesting service |
| 3 | **Go To Stand By** | — | lets other devices on the bus take control |
| 4 | **Take Control** | `C` = code; synchronous or asynchronous takeover | `A` = error messages, if any |
| 5 | **Output Interface Messages** | `C` = message byte (talker or listener address) | `A` = error messages |
| 6 | **Output Device Messages** | `C` = data byte; `B` = end-of-message acknowledgement code | `A` = error messages |
| 7 | **Input Device Messages** | — | `A` = data byte; `L` = error message |
| 8 | **Input Parallel Poll** | — | `A` = the parallel-poll bit pattern |

Driver 8 carries a hardware consequence worth recording: *"The devices that are
capable of 'parallel poll' will respond by pulling low a preassigned data line
so that some kind of code is returned which will correspond to a particular
device. **If this routine is used, only eight devices can sit on the data bus**
(one data bit line for each device)"* — parallel poll trades device count for
polling speed, 15 → 8.

### The same eight, as a jump table in the ROM

`docs/o1-rom-variants.md` records that OZROM 1E removed the IEEE-488 support and
that the machine-readable evidence is a jump table: *"013F-0156 WERE IEEE-488
ROUTINES"*. **`013F–0156` is 24 bytes — eight 3-byte `JP` instructions, one per
driver above**, which independently confirms both the count and the order: the
*n*-th entry sits at `013F + 3n`, so the **eighth** (Input Parallel Poll) is at
**`0154`** — and the joystick article calls exactly that address, as `0E154H`,
the same routine seen in the ROM's high mapping (see §6). The articles name the
drivers; the ROM fixes their addresses and their order.

Checked in the bytes, in every stock image the project holds — all of them carry
eight `C3` (`JP`) triples from `013F`, the eighth at `0154`:

| ROM | the first seven entries | 8th entry at `0154` |
|---|---|---|
| factory 1.40 (`tools/emulator-setup/roms/rev1.40.ud11`) | `C3 36 09`, `C3 79 09`, `C3 8C 09`, `C3 98 09`, `C3 D8 09`, `C3 FB 09`, `C3 3D 0A` | `C3 99 0A` |
| factory 1.44 (`research/roms/os1-144.rom`) | `C3 49 09`, `C3 8C 09`, `C3 9F 09`, `C3 AB 09`, `C3 EB 09`, `C3 0E 0A`, `C3 50 0A` | `C3 AC 0A` |
| Nuevo 1.51 (`tools/emulator-setup/roms/monrom-rev1.51-12.ud11`) | `C3 3D 09`, `C3 80 09`, `C3 93 09`, `C3 9F 09`, `C3 DF 09`, `C3 02 0A`, `C3 44 0A` | `C3 A0 0A` |

**The parallel-poll routine moves between ROM revisions** — `0AAC` in 1.44,
`0999` in 1.40, `0AA0` in Nuevo's 1.51 — which is exactly why the joystick
article's source must be assembled at a different origin per monitor version and
then hand-patched. Same table, different targets: a usable ROM-variant
signature, and the thing OZROM 1E destroys.


## 3. Errors the drivers report

- **Time Out** — non-fatal: *"a 100 microsecond grace period of time for the
  device to respond. Alternately, you can call the device repetitively to allow
  for slow devices to respond."*
- **No Device Present** — *"either the port is not hooked up to any device, or
  all the devices sitting on the data bus are turned off."*
- **Not taking the data after agreeing to take the data.**

## 4. A printer or plotter needs none of this

> "if only a printer/plotter is being used on the port there is no need to go
> through these routines. Using the SETUP program, make sure that the right
> protocol is chosen (Printers protocols, IEEE-488 compatible) and that the IEEE
> address port matches the device number. The latter can be simply accomplished
> with **BIOS 1.4**. With **BIOS 1.3 and earlier** versions there is a patch that
> is provided in the Technical Tips section of this issue. Double density
> computers (1.4 BIOS) have a **menu-driven device address patcher**."

That is the emulation surface for #19 (virtual MX-80): the printer path is a
SETUP-selected protocol plus a device address, not a driver call sequence.

Two operational details from the same article, both worth keeping:

- **The control codes must be in capital letters.** *"Some manufacturers
  enforce that; otherwise an error message will be returned."*
- The MBASIC example works by poking a small assembly-language interface plus a
  register-save area high in RAM and calling it from BASIC (`CALL IEEE0(…)` /
  `IEEE1(…)`), passing the driver number and its parameters through the shared
  locations. That is why the BIOS-1.3-or-earlier caveat exists — the poked
  routine and the ROM drivers have to coexist with CP/M in high memory.

## 5. The worked application: a game joystick on the data lines

The joystick article is the project's only fully-worked external device on this
port, and it is small enough to reimplement: **a switch-closure box read as five
data bits.**

### The cable

- One **DB-9 male** (it mates an Atari joystick), one **26-pin (13-pin dual row)
  card-edge / flat-ribbon connector** that mates with the IEEE-488 connector on
  the machine, and about 7 inches of **12-conductor ribbon** (14-conductor is
  standard — strip two conductors off).
- **Only `D0`–`D4` and GND are used.** The cable should leave the IEEE-488
  connector going *up* and then loop down under the case for strain relief.
- The physical fact to keep: the machine's "IEEE-488" port is a **26-pin card
  edge connector**, and the article's Figure 1 is its pin assignment as seen
  from the front of the computer.

### The bit mapping (Figures 5 and 6)

| Data bits `D7…D0` | Decimal | Direction | Screen offset |
|---|---|---|---|
| `00000000` | 0 | center | 0 |
| `00000001` | 1 | north | −128 |
| `00000010` | 2 | south | +128 |
| `00000100` | 4 | east | +1 |
| `00001000` | 8 | west | −1 |
| `00000101` | 5 | north-east | −127 |
| `00000110` | 6 | south-east | +129 |
| `00001001` | 9 | north-west | −129 |
| `00001010` | 10 | south-west | +127 |
| `00010000` | 16 | **fire button** | (the program clears the screen) |

The offsets are screen-memory deltas for the O1's **128-character row** — a line
is ±128, a character position ±1, so the diagonals are ±127/±129. Diagonals are
*"the sum of the binary values (actually two simultaneous switch closures) —
combinations such as 3 and 7 are not mechanically possible within the joystick."*
Bits 5–7 are spare: *"If you have a joystick with three more switches, they
could just as well be assigned to bit positions 5, 6, and 7 and
'sampled-in-software' accordingly."* The fire button has a quirk — *"As
programmed, you MUST return to center position on the joystick to detect the
closure of the 'Fire Button' ONLY"* — and the article warns that any switch
wired in *"must have full ISOLATION from any source of external electrical
power"* (its worked example of what not to do is a doorbell button:
*"Zorch-City"*).

### Reading it two ways

**(a) High level.** `CALL 0E154H` — the ROM's **Input Parallel Poll** driver
(#8 above) — returns the switch-closure bit pattern in `A`. That is the whole
interface for the article's "Etch-a-Sketch" checkout program, which walks a
pointer around the 128×32 screen by adding the offsets above.

**(b) Low level.** `JOYSTIK.ASM` programs the 6821 directly:

```asm
porta0  equ 2900h  ; 6821 pia port-a data/direction register
porta1  equ 2901h  ; 6821 pia port-a control register
portb2  equ 2902h  ; 6821 pia port-b data/direction register
portb3  equ 2903h  ; 6821 pia port-b control register
flagpos equ 0ef08h ; ram/rom flag position address: 0=rom, 1=ram
```

`istick` floats both ports and then sets port A for input; `rstick` reads the
joystick as `di` / `out 0` (ROM on, RAM off) / `xra a` / `sta flagpos` (tell the
system the ROM is in) / `lda porta0` / `mov b,a` / `out 1` (RAM on, ROM off) /
`mvi a,1` / `sta flagpos` / `ei` / `mov a,b` / `ani 01fh` (mask to `D0`–`D4`) /
`sta sdata` / `ret`.

Two machine-level facts fall out of that listing:

- **`EF08H` is the ROM/RAM bank flag** the system reads: `0` = ROM, `1` = RAM.
  The routine has to keep it consistent with its own `OUT 0`/`OUT 1` bank
  switch, because it reads the port *while the ROM is banked in*.
- The mask is **`01FH`** — the port is read as a full byte and only `D0`–`D4`
  carry the switches.

### Version dependence

The source is assembled at a **different origin per monitor ROM version** —
`ver2` → `0EE80H`, `ver3` → `0ED80H`, `ver4` → `0EA80H` — because it calls into
ROM addresses that move between revisions. The `.HEX` then has to be patched by
hand for the machine's version (*"Change to 61"*, *"Change to CBE6"*, …), and
the article says to press RESET and read the sign-on message if in doubt. For
BIOS 1.4 the labels are `sdata` `EA80`, `rstick` `EA81`, `istick` `EA8B`,
`end` `EAC8`, and the `.HEX` records load at `EA80`. This is the same
version-dependence the first article flags from the other side (move CP/M down
1K on BIOS 1.3 or earlier).

The article is **part one of two**; the SPACEWAR game that uses the interface is
promised for the next issue. Kelly Smith is with *Wizard of OsZ* and wrote
"Monster" in the Companion's inaugural issue; he offered the SPACEWAR program
(200 lines) and joystick hardware for a nominal fee (P.O. Box 964, Chatsworth,
CA 91311).

## 6. The P3 edge connector — the pinout, and what the port actually implements

The pin-level map of P3 — `docs/drive-c-design.md` §7's first listed unmeasured
item — is in the Technical Manual extract the project already archives, §4.1.2
"IEEE-488 Pinouts". The manual explains why the connector is not the standard
one:

> Because this port is used for more than just IEEE 488 signals, we've declined
> to use a standard IEEE connector.

Source: `research/osborne1/modem/o1techman-interface-extract.pdf`, PDF p. 2 =
printed p. 14 (Figure 4.1.2), and Figure 4.1.1 on PDF p. 1 = printed p. 13 for the
directions. **The scan has no text layer** — it is EPSON Scan output, so
`pdftotext` returns nothing and the tables below were read off a 250 dpi render.

The connector is a **26-pin card edge**, read looking at the front of the
machine, odd pins on one side and even on the other; **pins 25 and 26 are not
used** ("provided for compatability"). The IEEE column is the standard 24-pin
IEEE-488 assignment, kept here because it is what a GPIB cable or a GPIB device
document will name.

| IEEE-488 | **P3** | Signal | PIA line (ROM) | O1 direction |
|---|---|---|---|---|
| 1 | **1** | DIO1 | PA0 | bidir |
| 13 | **2** | DIO5 | PA4 | bidir |
| 2 | **3** | DIO2 | PA1 | bidir |
| 14 | **4** | DIO6 | PA5 | bidir |
| 3 | **5** | DIO3 | PA2 | bidir |
| 15 | **6** | DIO7 | PA6 | bidir |
| 4 | **7** | DIO4 | PA3 | bidir |
| 16 | **8** | DIO8 | PA7 | bidir |
| 5 | **9** | EOI | PB3 | O1 drives |
| 17 | **10** | REN | CB2 | O1 drives |
| 6 | **11** | DAV | PB5 | O1 drives |
| 12 | **12** | signal ground (DAV) | — | ground |
| 7 | **13** | NRFD | PB7 | O1 drives |
| 18 | **14** | signal ground (NRFD) | — | ground |
| 8 | **15** | NDAC | PB6 | **box may drive** |
| 19 | **16** | signal ground (NDAC) | — | ground |
| 9 | **17** | IFC | **CA2** | O1 drives |
| 20 | **18** | signal ground (IFC) | — | ground |
| 10 | **19** | SRQ | CA1 | **input** |
| 21 | **20** | signal ground (SRQ) | — | ground |
| 11 | **21** | ATN | PB4 | O1 drives |
| 22 | **22** | signal ground (ATN) | — | ground |
| 12 | **23** | cable shield + ground | — | ground |
| 24 | **24** | signal ground (logic) | — | ground |
| — | **25** | *unused* | — | — |
| — | **26** | *unused* | — | — |

The PIA column is the ROM's own comment block (`rom144.asm` 2606–2715, quoted in
`docs/drive-c-protocol.md` §2); the two sources agree line for line, which is
worth saying because they were derived independently — one is a 1983 manual, the
other a 1983 ROM listing.

Note what the PIA column does **not** contain: there is no `DAV`, `NRFD`, `NDAC`,
`EOI` or `IFC` *input*. **The O1 cannot read any of the five handshake/control
lines it drives.** Only `SRQ` (CA1) and `NDAC` (PB6, and only after `CRB` bit 2
is cleared) can be read back at all.

### 6.1 The port is not GPIB, and Figure 4.1.1 shows it

Figure 4.1.1 draws each line solid or dashed, and the split is the whole story:

| Drawn | Lines | Meaning |
|---|---|---|
| **solid** | `REN` (out), `ATN` (in), `SRQ` (in), `DATA0–7` (bidir) | implemented by the O1 |
| **dashed** | `IFC`, `NRFD`, `DAV`, `EOI`, `NDAC` | *not implemented* by the ROM's driver set |

The manual says as much in words — *"a subset of the complete IEEE
specification"*, *"no provision has been made for controlling multiple devices"*
— but the figure is the useful version, because it names the subset. **The three
IEEE-488 handshake lines (`DAV`, `NRFD`, `NDAC`) are the ones missing**, which is
exactly why nothing on this port can do an IEEE-488 three-wire handshake, and why
every device on it invents its own clock. Drive C: uses `CA2`/`IFC`; the printer
uses `DAV` as a strobe (`§6.2`).

`ATN` and `SRQ` are drawn as *inputs*, which is odd for a controller and correct
for this machine: the O1 can only ever be told, not ask.

### 6.2 The same pins, as a Centronics printer port

Figure 4.1.5 (PDF p. 4 = printed p. 16) re-labels the same edge connector for the
printer personality that `SETUP` selects (`IOBYTE` = `BAT:`, `UR1:`, `UP1:`,
`LPT:`). It is the same wires, with four of them re-purposed:

| P3 | O1 name | Centronics pin | Centronics name |
|---|---|---|---|
| 1 | DIO1 | 2 | data 0 |
| 2 | DIO5 | 6 | data 4 |
| 3 | DIO2 | 3 | data 1 |
| 4 | DIO6 | 7 | data 5 |
| 5 | DIO3 | 4 | data 2 |
| 6 | DIO7 | 8 | data 6 |
| 7 | DIO4 | 5 | data 3 |
| 8 | DIO8 | 9 | data 7 |
| 11 | DAV | 1 | **out strobe** |
| 12 | ground | 19 | ground |
| 15 | NDAC | 11 | **busy** |
| 16 | ground | 29 | ground |
| 19 | SRQ | 13 | **select** |

So `DAV` is the printer strobe, `NDAC` is *busy* and `SRQ` is *select* — and
`NDAC` is the same line the Drive C transport leaves as an input as its optional
"ready" (`docs/drive-c-protocol.md` §2, §7). **One pin, two meanings, chosen by
which personality is installed.** Anything we put on P3 has to be harmless in
both modes, which is a constraint `docs/drive-c-design.md` §2.3 now carries.

## 7. What this means for o1next

- The port is a **byte-wide parallel port on a 6821**, so a personality can
  implement it as such (`docs/virtual-peripherals-block-diagram.md`), and the
  **eight ROM drivers are the behaviour that has to be right**.
- **Address 0 is the machine's own** — anything else we place on the bus needs a
  different address.
- The port already has three quite different users in the archive: the ROM's
  driver set (this doc), a printer selected in SETUP (§4), and a dumb
  switch-closure box read through driver 8 (§5). Drive C: is a fourth, and the
  manual is explicit that it does **not** speak real GPIB on this connector
  (`docs/drive-c-protocol.md`).
- The driver table at **`013F–0156`** (eight `JP`s) is a *checkable* signature:
  present in stock ROMs, destroyed in OZROM 1E (`docs/o1-rom-variants.md`).
- **The pinout is solved** (§6): the Technical Manual's §4.1.2, with the ROM's
  comment block corroborating it line for line. So `hardware/drive-c-repro/` can
  be laid out against a documented connector rather than a measured one, and the
  one remaining electrical unknown on P3 is loading, not mapping.

