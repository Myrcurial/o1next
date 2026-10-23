# floppy-adapter — the O1NEXT Floppy Adapter (switchable Gotek/physical-drive daughter card)

**Board:** `floppy-adapter` — the **O1NEXT Floppy Adapter** — the project's
**first deliverable**, and the only processor-less board in the set. See the
register in [`../README.md`](../README.md). Its revisions are the **Floppy
Adapter's** Rev A / Rev B, which is an unrelated board to the interposer's Rev A /
Rev B — so the letters are always qualified.

**State: the Rev A schematic is complete and every design decision is made** — the
switch is solid state (below) — and **the next unit of work is the PCB floorplan and
routing**.

A daughter card that mounts over the mainboard / double-density board
floppy connector and makes **three drives available, two active**: both
original drives, *or* drive A + Gotek, selected by a user-accessible
switch. All interception happens at the mainboard-end connector — the
OEM floppy IDC cable is never cut or modified.

Inspiration (not a copy): Richard Loxley's Osborne restoration series —
[part 14](https://www.richardloxley.com/2018/04/24/osborne-restoration-part-14-usb-floppy-emulator-a-semi-permanent-solution/)
and [part 15](https://www.richardloxley.com/2018/04/25/osborne-restoration-part-15-usb-floppy-emulator-finishing-off/)
(also a YouTube series) — which proved the concept with a spaghetti of
hand-cut Dupont cables, an extension cable with a severed drive-select
line, and a DPDT switch + 5 V relay soldered onto the Gotek itself.
This design moves all of that work onto a PCB at the connector end of
the cable, where it belongs.

Tracking: **#62** (design spec + schematic). Feeds #20 (floppy
interposer personality) and #30 (G2 multi-format support). Prior art
archived by PR #50. Full design in
[`docs/floppy-adapter-design.md`](../../docs/floppy-adapter-design.md),
whose **eight open questions are all closed** (§8 there); the schematic
that implements them is described below.

## Design

- **Mezzanine mount:** plugs onto the mainboard (or DD-board) 34-pin
  floppy header; the OEM floppy cable re-plugs into a pass-through
  34-pin connector on the daughter card. Fully reversible, no
  modifications to the machine or its cables.
- **Second 34-pin connector:** routes the floppy bus out to a Gotek
  (FlashFloppy) mounted in one of the floppy storage pockets.
- **Switching:** drive-select A (pin 10) is routed on-card either to
  the OEM-cable pass-through (physical drive A) or to the Gotek
  connector. The remote switch lead carries only a low-current logic
  select line to the on-card switch element, and the switch itself is a
  plain panel-mount SPST, trivially mounted next to the Gotek in the
  storage pocket.
- **Gotek power:** dedicated 5 VDC connection on the Gotek connector,
  fed via an on-card switch so the Gotek can be fully depowered in
  "both physical drives" mode. Both +5 V **and** GND are switched —
  switching one rail alone fails (`docs/floppy-adapter-design.md` §4.2).
- **Drive B is never switched** — it stays on the pass-through, so the
  machine always boots from a physical disk if desired. The Gotek takes
  drive A's place.
- **DS-A pull-up:** the O1's 150 Ω term pack lives on drive A, so the
  card adds a pull-up on the Gotek-side DS-A net (1 kΩ default) —
  `docs/floppy-adapter-design.md` §4.5.

## Signals carried to the Gotek

(Per the blog's audit — 11 lines plus power; the card routes the full
bus to be safe.)

| 34-pin | Signal |
|---|---|
| 8 | Index |
| 10 | Drive select A (**switched**) |
| 18 | Direction |
| 20 | Step |
| 22 | Write data |
| 24 | Write gate |
| 26 | Track 0 |
| 28 | Write protect |
| 30 | Read data |
| odds | Ground |
| — | +5 V (switched, on-card) |

## Lessons from the reference build (designed in, here)

- **Power-switching a Gotek is subtle.** Switching only +5 V fails —
  the O1's pulled-up signal lines parasitically power the board;
  switching only GND makes the *other* drive unreliable (shared +5 V
  reference with floating ground). The blog's fix was switching both
  rails with a DPDT plus a 5 V relay for drive select. We solve this
  properly on-card: a high-side load switch for Gotek 5 V, a MOSFET on
  its ground return, and a 2:1 bus switch for drive select — so the
  remote switch handles no power at all.
- **Gotek physical fit:** with its top cover removed a Gotek fits a
  floppy storage pocket; top-facing headers make it too tall — plan a
  right-angle/side connection or direct-wire pads on the ribbon.
- **Cable egress:** a 34-pin ribbon won't pass the pocket ventilation
  slots; the daughter card should output the Gotek run on a slimmer
  cable (only the needed signals + power) that does.
- OLED display mods and FlashFloppy display-detect quirks are the
  user's Gotek-side choice, out of scope for the card.

## KiCad capture (Rev A)

- `floppy-adapter.kicad_sch` (+ `.kicad_pro`) — the Rev A schematic: wired and
  footprinted with the same treatment the WiFi COMM PAC got (#347).
- `gen_floppy_adapter_sch.py` — generator; edit the net tables and re-run
  (`python3 gen_floppy_adapter_sch.py`), then open/re-save in KiCad to normalise.
- **J1** female 2x17 socket (O1 logic-board P8), **J2** pass-through header to
  the OEM cable, **J3** Gotek signal header, **J4** switched Gotek power,
  **J5** panel switch, **U1** NC7SB3157P6X (DS-A), **U2** TPS22918 (+5 V),
  **Q1** AO3400A (GND), **R1** control pull-down, **R5** series in the switch lead,
  **R3/R4** DS-A pull-up, **R2+D2** optional indicator (R2, D2 and R4 are `dnp`).

**Every net is drawn.** A net *label* on every pin with no wire between any two
parts is a correct netlist and a drawing a reader cannot follow, so the nets are
routed as orthogonal segments on a 1.27 mm grid, and the three rails are wired too
(with **one power symbol each** and a `PWR_FLAG`, because a symbol per pin would
stack glyphs 2.54 mm apart on J1's eleven ground pins). **One label per signal net**
keeps the names — one label, not fifteen, so a missing wire *breaks* the netlist
instead of being hidden by a label doing the connecting.

**Footprints are assigned for every part** (13 of 13), from KiCad's own libraries.
The connectors and passives are through-hole; the three switches are SMD because
nothing through-hole works on a 5 V bus. `Update PCB from Schematic` transfers
nothing for a symbol with an empty Footprint field, so this is what makes the board
startable at all.

Verified rather than asserted:

```sh
python3 hardware/floppy-adapter/gen_floppy_adapter_sch.py
python3 tools/check_schematics.py --board floppy-adapter
python3 tools/check_boards.py
```

- `kicad-cli sch erc --severity-all`: **0 errors**, 19 violations, all of them the
  one kind (embedded `local:` symbols, one per placed symbol).
- `kicad-cli sch upgrade` — the re-save that detached 14 pins on the WiFi board —
  leaves the netlist identical, and the generator emits 0 overlapping and 0
  duplicate collinear segments.
- `tools/check_schematics.py` asserts the **pinout of J1 and J2** against the
  interface table, **which throw of U1 is which device**, the control node's three
  consumers, and the connector and switch footprints.

Three defects came out of doing it, all found by comparing netlists rather than by
looking at the sheet: a wire ended on a **no-connect pin** (J3.14 and K1.11 got
pulled onto `FLP_DS_A_GOTEK` — the router blocked other nets' pins but not the ones
marked no-connect; the sibling generator in `hardware/wifi-comm-pac/` had the same
hazard and was fixed with it), the checker was carrying a **pinout table that read
pins 4 and 6 as GND** while the design says TG43 and EARLY, and the relay's pin
numbers were placeholders — which the switch decision finally closed, with the
parts' own pin numbers.

## The switch is solid state (decided 2026-10-22)

**There is not enough height in the case for relay blocks** — and that is the whole
argument. This card is a **mezzanine** between the logic board and the floppy
harness: a DIP-14 signal relay is ~10 mm, a socketed industrial 4PDT is 35 mm, and
neither fits. So Rev A switches with **three silicon parts**, ~1.5 mm tall:

| Ref | Part | What it does |
|---|---|---|
| **U1** | **NC7SB3157P6X** (SC70-6) | DS-A 2:1 switch — ≤10 Ω, 5 V rail-to-rail, **break-before-make** |
| **U2** | **TPS22918** (SOT-23-6) | the Gotek's **+5 V** — 52 mΩ, 2 A, logic-level `ON` |
| **Q1** | **AO3400A** (SOT-23) | the Gotek's **GND return** — 28 mΩ at Vgs = 4.5 V |

**The fail-safe survives, and it is the switch's own truth table:** *S low → B0
connected to A*, so **B0 is the physical drive** and a control that is low,
floating or unplugged parks the machine on the real drive. `R1` (10 kΩ) pulls the
control node down for the same reason the relay design pulled the coil node down.
**Break-before-make** means the two devices are never both connected to DS-A, even
momentarily — the property the relay gave for free.

Two side-effects worth having: the **panel-switch lead now carries microamps**
instead of 73 mA of coil current, and there is no click and no contact to wear out.

**The relay is not a fallback either.** Omron **G6A-434P** / **G6A-474P** were
discontinued with a last-buy date of 2010-06-29, and the whole 4-pole DIP
signal-relay class with them — Panasonic **TQ4-5V** and **DS4E-S-DC5V** are
broker-only at $20–190 a piece. The other relay routes priced for this board — two
DPDT DIP-8 at ~$4–12 the pair, or an MY4N on a PY14-02 socket at $8–15 and 35 mm —
are recorded in `docs/floppy-adapter-design.md` §4.3.

**One consequence for assembly:** the three switches are SMD and there is no
through-hole alternative that works — the 5 V-capable analog switches in DIP
(CD4053, 74HC4053) are 70–120 Ω, which against a 1 kΩ pull-up puts the DS-A low
level at 0.7–0.9 V against a 0.8 V TTL threshold. Everything else on the card is
through-hole, and SC70 is the smallest thing on it.

## The panel switch, and the lead that leaves the board

**UP = the physical drives. DOWN = the Gotek.** A plain panel-mount **SPST flip
switch** in series between the cable's +5 V and the control node: closed (down) is
the Gotek, open (up) leaves `R1` to pull the node low, which is the physical drives.
**Up is the fail-safe position**, and the two wires are interchangeable — an SPST in
series with a gate input is symmetric.

- **`R5` (1 kΩ) is in series in that lead.** It leaves the board and runs to the
  front panel, so it is the one net that can arrive carrying something the board
  never sent; 1 kΩ limits what a transient or a short can push into three CMOS gates
  and a FET gate. `R1` sits on the *control* side, so an unplugged lead is still a
  low.
- **The lead carries microamps**, where the relay's coil wanted 73 mA.
- **J5 is a bare 2-pin 2.54 mm header, and that is the decision** (2026-10-22), not a
  placeholder: a series SPST has no polarity to key, and *"an appropriate switch with
  a twisted pair dupont connector wire is trivial to implement"*. The shrouded JST PH
  alternative was considered and is recorded as rejected in
  `docs/floppy-adapter-design.md` §4.5.

## Getting the cables out of the pocket

The card sits at the logic-board connector, inside the machine. What has to leave is
the **Gotek run** and the **2-wire switch lead**, and the pocket's ventilation slots
are the constraint. Both accepted routes are in
[`docs/floppy-adapter-design.md`](../../docs/floppy-adapter-design.md) §7, and the
card is the same either way:

1. **Break the 34-pin run into parts that fit the slots** (Loxley's approach) — a
   reduced 12-line signal set plus power, split into runs that pass, rejoined inside
   the pocket. **Nothing on the machine is cut.**
2. **Cut the case** for a full-size 34-pin cable alongside the two switch wires —
   irreversible, and no joints to go intermittent.

J3 is a full 2×17 header for exactly that reason: the cable that arrives may be
either, and the unused positions simply carry no wire.

## Settled decisions (2026-10-10, switch decided 2026-10-22)

The eight design questions are closed — see
[`docs/floppy-adapter-design.md`](../../docs/floppy-adapter-design.md) §8 for
the evidence behind each. Highlights:

- O1 floppy header is **male** (logic-board P8), so **J1 is a female socket**.
- **Solid state, not a relay** — the case has no height for one (above).
- Switch **DS-A + both power rails** only — Loxley's proven minimum.
- **1 kΩ** DS-A pull-up default, **150 Ω** alternative footprint.
- Gotek drive-select jumper: **S1 first, S0 fallback** (bench-verify).
- Gotek sits in the **right-hand** pocket on a reduced ~12-line pigtail.


## Open items (not blocking capture)

- **The PCB floorplan and routing — this is the next unit of work.** Every decision
  is made (§8 in the design doc), every net is drawn and every part has a footprint.
  Place the connectors on their faces, set the keep-outs against the mainboard and
  the pocket, route it.
- **Height is the binding constraint** and the floorplan must respect it: it is why
  the switch is silicon, and the three packages are ~1.5 mm against a relay's 10 mm.
- Mounting: piggyback footprint vs. standoffs over the DD board; confirm
  keep-outs against the mainboard schematic
  (`research/osborne1/OCC1_1A2011-00_Schem_RevE.pdf`) and host photos
  (`research/pictures/`).
- **Rev B, recorded not done:** U2's `QOD` pin if the Gotek ever proves slow to power
  down (it is left open, which disables the output discharge).
- Interaction with the interposer's floppy personality (#20): document
  which device owns the bus in each configuration.
- G2 upgrade (#30): believed BIOS/DPB-only, nothing at the connector —
  confirm.


## References

- `research/osborne1/floppy-adapter/` — archived Osborne1FloppyAdapter
  KiCad project (connector/pinout prior art; **not** this design)
- `research/osborne1/OCC1_1A2011-00_Schem_RevE.pdf`
- Richard Loxley, Osborne Restoration parts 13–15 (concept origin)
