---
layout: page
title: "The interposer and its virtual peripherals"
subtitle: "The project · design"
draft: "Draft &mdash; assembled from the working notes by `tools/build_book.py`. The source document is the authority; this page is a copy for reading, and it is regenerated from that source."
---

How the RP2350 interposer sits on the Z80 bus and where each virtual
peripheral lives in the Osborne 1 memory and I/O maps.

## 1. Where the interposer physically sits

The Osborne 1 exposes the Z80 on a 40-pin DIP socket. Like the
CoPower-88 and the OCC ScreenPac, the interposer **plugs into the Z80
socket** and the Z80 plugs into the interposer — so it sees (and can
drive) every bus cycle.

```mermaid
flowchart TB
    subgraph MB["Osborne 1 mainboard"]
        ZSKT["40-pin Z80 socket<br/>(A0-A15, D0-D7,<br/>MREQ/IORQ/RD/WR/M1,<br/>RFSH, HALT, INT, NMI, RESET, CLK)"]
        ROM["4KB BIOS ROM<br/>0000-0FFF"]
        RAM["64KB DRAM<br/>(banked)"]
        VRAM["Video RAM<br/>F000-FFFF window"]
        IO["Onboard I/O<br/>(FDC, PIO, SIO, KBD)"]
        CG["Char-gen ROM socket<br/>UA15, 24-pin<br/>(font data + scan lines)"]
        ZSKT --- ROM & RAM & VRAM & IO
    end

    subgraph INTP["RP2350 Interposer (in Z80 socket)"]
        direction TB
        Z80["Original Z80A<br/>(NMOS, 4 MHz)<br/>reinstalled here"]
        BUF["74LVC245 buffers /<br/>level shifters<br/>(5V Z80 <-> 3.3V RP2350)"]
        PIO["RP2350 PIO + DMA<br/>bus sniffer / driver"]
        MCU["RP2350 cores<br/>cycle decoder +<br/>peripheral firmware"]
        WIFI["WiFi / USB<br/>stream out"]
        VID["Video renderer<br/>(shadow VRAM + font)<br/>DVI/HDMI via RP2350 HSTX"]
        HDMI["HDMI monitor out"]
        Z80 <--> BUF <--> PIO <--> MCU --> WIFI
        PIO --> VID --> HDMI
    end

    ZSKT <-."A/D/MREQ/IORQ/RD/WR<br/>tapped + can be driven".-> BUF
    CG <-."char-gen socket tap<br/>(ScreenPac-style, #24)".-> VID
```

**Second tap point (#24):** like the ScreenPac, the interposer taps the
Z80 socket **and** the character-generator ROM socket (UA15, 24-pin). The
Z80 tap gives it every bus cycle (including all video-RAM writes); the
char-gen tap captures the font. Together they feed the HDMI video-output
personality described in §5.

**Level shifting note (#11):** the host Z80A is NMOS (confirmed, date
8408). NMOS outputs are TTL-ish; NMOS inputs have ~2.0–2.4 V high
thresholds. Use **74AHCT/74HCT toward the Z80** (TTL-compatible inputs)
and **74LVC245 host-side**. ScreenPac used raw 74HC; we prefer AHCT/LVC
for margin across all three target machines.

## 2. Z80 memory map and where virtual devices attach

The O1 banks ROM, RAM, and video in a 64KB space. The interposer claims
a small decode window by **snooping MREQ and either passing through or
overriding** the onboard response.

```mermaid
flowchart LR
    subgraph MAP["Z80 64KB memory map"]
        direction TB
        R0["0000-0FFF<br/>BIOS ROM<br/>(bank 0)"]
        R1["1000-EFFF<br/>System RAM<br/>(shared both banks)"]
        R2["F000-FFFF<br/>Video RAM<br/>(bank-switched window)"]
    end

    subgraph VW["Interposer-claimed window (config)"]
        VP["Virtual-peripheral<br/>mailbox RAM<br/>(e.g. EF00-EFFF)"]
    end

    MCU2["RP2350 firmware"]
    MAP -->|"MREQ+A15-A0 snooped"| DEC{"Decode<br/>match?"}
    DEC -->|"no: pass through"| MB2["Onboard ROM/RAM<br/>respond normally"]
    DEC -->|"yes: assert override,<br/>tri-state host, drive bus"| VP
    VP <--> MCU2
```

### Banking caveat
The O1 video RAM and BIOS share the top of the map via a bank-select
I/O bit. Any memory-resident virtual device must **(a)** live in an
address range the current bank exposes and **(b)** defer to the real
video RAM when it is mapped in. Safest is a small mailbox page in the
always-present RAM region, or an I/O-port device instead (below).

## 3. Z80 I/O map and the virtual-peripheral ports

I/O-mapped devices are cleaner: they never collide with the memory
banks and are how every real O1 peripheral (and the CoPower-88) already
works.

```mermaid
flowchart TB
    subgraph IOP["Z80 I/O space (A7-A0 decoded)"]
        direction TB
        ONB["Onboard ports<br/>FDC / PIO / SIO / KBD<br/>(existing decode)"]
        CP88["CoPower-88 mailbox<br/>0x7E data / 0x7F status<br/>(or 0xFE/0xFF)<br/>*real hw being reverse-eng*"]
        V1["VIRT: net disk<br/>port base B+0..B+3"]
        V2["VIRT: WiFi modem<br/>port base B+4..B+7"]
        V3["VIRT: RTC<br/>port base B+8..B+B"]
        V4["VIRT: virtual MX-80<br/>printer port base B+C..B+F"]
    end

    Z802["Z80<br/>IN/OUT (IORQ+RD/WR)"] --> DEC2{"Port decode<br/>A7-A0"}
    DEC2 --> ONB
    DEC2 --> CP88
    DEC2 -->|"claim free base B"| V1 & V2 & V3 & V4
    V1 & V2 & V3 & V4 <--> FW["RP2350<br/>peripheral firmware"]
    FW --> NET["WiFi / SD /<br/>host stream"]
```

**Port-base strategy:** pick a base `B` in a region the onboard decode
leaves free **and** that does not collide with the CoPower-88's
0x7E/0x7F (Kaypro) or 0xFE/0xFF (Zorba) — so the interposer can
*emulate or coexist with* the real CoPower. The comparator-based decode
on the real CoPower board (the "16-2103" IC, see photo-survey) is the
model for a clean single-port-pair decode.

The interposer's **own** host↔firmware channel — the mailbox, the one port the
machine's CP/M tooling talks to directly — is specified separately in
[`docs/mailbox-protocol.md`](https://github.com/Myrcurial/o1nextgen/blob/main/docs/mailbox-protocol.md) (#155): it takes a port pair of its own, chosen so that
a leaked write cannot move the bank latches.

## 4. The virtual peripherals (from the roadmap)

| Virtual peripheral | Bus type | Address/Port | Host interface | Back end |
|---|---|---|---|---|
| **Network disk** | I/O ports | base+0..3 (cfg) | command/data/status FIFO | SD image / WiFi block server |
| **WiFi modem** | I/O ports | base+4..7 (cfg) | 8250-ish UART regs | TCP/Telnet over WiFi |
| **RTC** | I/O ports | base+8..B (cfg) | RT-60A-compatible regs (see #7) | RP2350 RTC / NTP |
| **Virtual MX-80 printer** | I/O ports | base+C..F (cfg) | Centronics-style data+strobe | WiFi / USB to host spooler |
| **Video / HDMI output** (ScreenPac personality, #24) | memory snoop + char-gen tap | VRAM `F000-FFFF` (passive) + UA15 socket | none — transparent to host | DVI/HDMI via RP2350 HSTX (§5) |

The four I/O peripherals are each an independent decode window; firmware
registers a `{base, mask, read_fn, write_fn}` entry and the cycle decoder
dispatches. The video personality is different: it never answers a bus
cycle at all — it only *listens* (and taps the char-gen socket), so it
cannot collide with any onboard or virtual device.

## 5. Video output — ScreenPac personality and HDMI out (#24)

The interposer's second personality is video. The OCC ScreenPac is the
template: it taps **both** the Z80 40-pin socket **and** the character
generator ROM socket (UA15, 24-pin), and shadows the display through
dual-port video RAM (6116s + 74HC157 muxes). The interposer reproduces
that function in firmware and extends it to a modern output:

1. **VRAM snoop.** Video RAM lives at `F000-FFFF` (128×32 cells, 52×24
   visible). Sitting in the Z80 socket, the interposer already sees every
   bus cycle; writes into the VRAM window update a shadow copy in RP2350
   RAM.
2. **Font capture.** The 2716 character ROM (128 chars × 8×10 pixels) is
   dumped once at init through the UA15 tap — or a known-good font image
   is preloaded in firmware — and frames are re-rendered from shadow
   VRAM + font. Tapping UA15 like the ScreenPac did also tracks machines
   running replacement/upgrade char ROMs. The tap is **read-only by
   necessity**: on the mainboard `/CE` (18) and `/OE` (20) are bussed with
   GND and grounded, so the ROM is permanently selected and always driving
   `O0–O7` (`o1-mainboard-schematic.md` §4a). Reading costs nothing;
   *replacing* the font would mean intercepting those two pins between
   socket and ROM, so the design keeps the fitted ROM as the source of
   truth and preloads a font image for the 80/104-column modes instead.
3. **Render + output.** The second RP2350 core renders the shadow frame
   and drives DVI/HDMI via the RP2350 **HSTX** peripheral (or
   PicoDVI-style bitbang). O1 timing is gentle: 15.9744 MHz master,
   8 MHz dot clock, 60 Hz frame — comfortably inside DVI 640×480 margins
   with integer upscale.

### Prior art — Pico-based bus video cards (candidate boards to study)

- **A2DVI** — `github.com/rallepalaveev/A2DVI`: Apple II digital video
  card, RP2040-based, HDMI/DVI out. Closest analogue: a Pico-class MCU
  on a vintage bus rendering HDMI in real time.
- **V2RetroComputing "analog"** — `github.com/V2RetroComputing/analog`:
  Pico-based Apple II card outputting DVI video over an HDMI connector.
- **AppleII-VGA** — `github.com/markadev/AppleII-VGA`: Pico-based VGA
  card; same snoop-and-render architecture, VGA instead of DVI.
- **PicoDVI** — `github.com/Wren6991/PicoDVI`: the RP2040 DVI bitbang
  library; on the RP2350 the HSTX hardware does the heavy lifting
  instead.

All four prove the pattern this personality needs: a Pico-class MCU
snooping a vintage bus and emitting stable modern video. Unlike the
Apple II cards, the interposer sits *in the CPU socket* (ScreenPac-style),
so it also sees bank-switch writes and can track which bank currently owns
`F000-FFFF` (video RAM vs the dim-bit attribute bank — see
[`docs/o1-memory-io-map.md`](https://github.com/Myrcurial/o1nextgen/blob/main/docs/o1-memory-io-map.md)).

> Relationship to the real ScreenPac: the reverse-engineering phase sniffs
> the real board like the other targets (#9 photos; service manual safety
> copy in [`research/screenpac/`](https://github.com/Myrcurial/o1nextgen/blob/main/research/screenpac/)). The HDMI personality is then the
> "virtual ScreenPac" — plus a display output the original never had.

## 6. Coexistence with the real peripherals being reverse-engineered

```mermaid
flowchart LR
    subgraph REAL["Real hardware (reverse-eng targets)"]
        CP["CoPower-88<br/>0x7E/0x7F"]
        DC["Drive C<br/>IEEE-488 ramdisk"]
        RTC["RT-60A<br/>RTC"]
        ACT["ACT hard disk<br/>OCC1"]
    end
    subgraph VIRT["Interposer emulation"]
        VCP["virtual CoPower"]
        VDC["virtual Drive C"]
        VRTC["virtual RTC"]
        VACT["virtual HD"]
    end
    REAL -->|"sniff real cycles<br/>to learn protocol"| LEARN["RP2350<br/>capture"]
    LEARN --> VIRT
    VIRT -->|"later: replace real hw<br/>on same ports"| HOST["O1 runs unchanged<br/>software"]
```

The interposer first **passively sniffs** each real device to pin its
protocol (the reverse-engineering phase), then can **emulate** it on the
same decode so the original software runs against the virtual version.

## 7. Personality selection — the gate, and where each personality stands

**No decisions have been taken here.** This section is the *input* to that
decision: the rule we apply, what it misses, and the resulting map — recorded so
the choice is argued once rather than re-derived per personality.

### The current rule, and its gap

[`firmware/README.md`](https://github.com/Myrcurial/o1nextgen/blob/main/firmware/README.md) states the project rule: *"If we hold the drivers for a piece
of period hardware, we plan a personality for it."* That is necessary but not
sufficient — on its own it says nothing about whether a personality can be
*tested*, whether it collides with another, or whether the fitted ROM still
supports it.

### The five tests

1. **Driver held?** — the existing rule. A driver means no Osborne-side software
   work and a known-good test suite.
2. **Interface reachable?** — Z80 socket, char-gen socket, or a port (P1/P2/P3/P5),
   without cutting traces.
3. **Testable?** — is there software we can *run* against it (MAME or hardware)?
4. **Address-space arbitration** — does it collide with another personality?
5. **ROM-gated?** — does the fitted ROM still support it? (#86 is closed; the gate
   is built)

### Stacking is not the constraint — addresses are

Worth stating plainly, because it is easy to get wrong: **virtual interposers
stack.** The maintainer's own machine carries a real SCREEN-PAC *and* a real
CoPower-88 at the same time, which is the existence proof — and in the virtual
case it is easier still, because every personality is firmware rather than a board.
A personality that would have been a Z80-socket interposer in period (the ACT hard
disk, the CoPower-88, the TRA video board) is therefore **not** excluded by
occupancy: the interposer is already in that socket, so it can simply *be* the
device.

The real constraint is **decode**. Two personalities cannot claim the same
addresses at once, and the O1's decode is famously loose — the "4 port boundary"
the hard-disk controllers demand is the same coarse two-line decode the rest of
the machine uses. So the arbitration question for each candidate is: *which
addresses does the driver touch, and who else wants them?*

### The map

| Personality | Driver | Interface | Addresses it claims | ROM gate | Tier |
|---|---|---|---|---|---|
| `bus-analyzer` | — | Z80 socket | none (passive) | — | **0 — prerequisite for all** |
| `rt60a-rtc` | ABI documented (#7) | mailbox; **no IEEE handshake** | the `0x0040` block is *software's*, not ours | fine | **1** |
| `drive-c-gpib` | `DCL`/`DFD.SPR` ✓ | IEEE-488 (P3), PIA `2900–2903` | GPIB **device address** | **not under OZROM** | **1** |
| `virtual-printer` | ROM IEEE driver ✓ | IEEE-488 (P3) | **device 3** | Centronics survives OZROM | **1** |
| `floppy-emulator` | — | floppy bus | none (interrupts the Shugart bus) | — | **2** |
| `screenpac-video` | — | Z80 + UA15 tap | video window + `2400H` bit | — | **2** |
| `zimodem-fork` | — | P1 (TTL) | ACIA `2A00`/`2A01` | — | **2** |
| `occ1-harddisk` | `HARD`/`PORTCHNG` ✓ | *virtual* Z80 interposer | a relocatable port window (#8) | ? | **3** |
| `copower88-shim` | drivers + ROM ✓ | *virtual* Z80 interposer | `0x7E`/`0x7F` | ? | **3 — last** |
| `kvm-console` | composition | video + keyboard | none | — | **3** |

### The open question that decides the IEEE row

Three personalities want the IEEE-488 port: Drive C, the virtual printer and the
RT-60A. **GPIB is an addressed bus** — the printer is *device 3* (OZROM's appendix:
*"IEEE-488 as IOBYTE device 3 now null device"*) — so if Drive C and the RT-60A
answer different addresses, all three can coexist, and the interposer can
multiplex because it already sees the PIA at `2900–2903`. **That is a deliverable
of #6, and it is the difference between "one personality at a time" and
"coexist".**

### What this section is not

It is not a decision record, and nothing above has been chosen. The tier ordering
is a proposal for sequencing. The storage question in particular (#8) is still
open: Drive C is the easiest to build **standalone** (#84), but that is a different
claim from "the only one worth emulating".
