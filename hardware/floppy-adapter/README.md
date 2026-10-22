# floppy-adapter — the O1NEXT Floppy Adapter (switchable Gotek/physical-drive daughter card)

**Board:** `floppy-adapter` — the **O1NEXT Floppy Adapter** — the project's
**first deliverable**, and the only processor-less board in the set. See the
register in [`../README.md`](../README.md). Its revisions are the **Floppy
Adapter's** Rev A / Rev B, which is an unrelated board to the interposer's Rev A /
Rev B — so the letters are always qualified.

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
[`docs/floppy-adapter-design.md`](../../docs/floppy-adapter-design.md);
its seven open questions were **settled 2026-10-10** (§8 there) and the
**Floppy Adapter's Rev A schematic is captured** (below).

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
  select line to an on-card switch element (relay or 74CBT-class bus
  switch) — the switch itself is a plain panel-mount SPST, trivially
  mounted next to the Gotek in the storage pocket.
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
  properly on-card: high-side load switch for Gotek 5 V and a
  bus-switch/relay for drive select, so the remote switch handles no
  power at all.
- **Gotek physical fit:** with its top cover removed a Gotek fits a
  floppy storage pocket; top-facing headers make it too tall — plan a
  right-angle/side connection or direct-wire pads on the ribbon.
- **Cable egress:** a 34-pin ribbon won't pass the pocket ventilation
  slots; the daughter card should output the Gotek run on a slimmer
  cable (only the needed signals + power) that does.
- OLED display mods and FlashFloppy display-detect quirks are the
  user's Gotek-side choice, out of scope for the card.

## KiCad capture (Rev A)

- `floppy-adapter.kicad_sch` (+ `.kicad_pro`) — the Rev A schematic, **rewired and
  footprinted 2026-10-22** with the same treatment the WiFi COMM PAC got (#347).
- `gen_floppy_adapter_sch.py` — generator; edit the net tables and re-run
  (`python3 gen_floppy_adapter_sch.py`), then open/re-save in KiCad to normalise.
- **J1** female 2x17 socket (O1 logic-board P8), **J2** pass-through header to
  the OEM cable, **J3** Gotek signal header, **J4** switched Gotek power,
  **J5** panel switch, **K1** 4PDT relay, **D1/R1** flyback + coil pull-down,
  **R3/R4** DS-A pull-up, **R2+D2** optional indicator (R2, D2 and R4 are `dnp`).

**Every net is drawn.** The first capture attached a net *label* to every pin and
drew no wire between any two parts: a correct netlist and a drawing a reader could
not follow. Now the 24 nets are routed as orthogonal segments on a 1.27 mm grid,
the three rails are wired too (with **one power symbol each** and a `PWR_FLAG`,
because a symbol per pin would stack glyphs 2.54 mm apart on J1's eleven ground
pins), and **one label per signal net** keeps the names — one label, not fifteen,
so a missing wire *breaks* the netlist instead of being hidden by a label doing
the connecting.

**Footprints are assigned for everything except K1** (see below), from KiCad's own
libraries, through-hole throughout because this is the board a person builds by
hand. `Update PCB from Schematic` transfers nothing for a symbol with an empty
Footprint field, so this is what makes the board startable at all.

Verified rather than asserted:

```sh
python3 hardware/floppy-adapter/gen_floppy_adapter_sch.py
python3 tools/check_schematics.py --board floppy-adapter
python3 tools/check_boards.py
```

- **The netlist is unchanged** from the label-based version (24 nets, 0 added, 0
  lost, 0 altered) — the evidence that the wires connect what the labels did.
- `kicad-cli sch erc --severity-all`: **0 errors**, 18 violations, all of them the
  one kind (embedded `local:` symbols, one per placed symbol).
- `kicad-cli sch upgrade` — the re-save that detached 14 pins on the WiFi board —
  leaves the netlist identical, and the generator emits 0 overlapping and 0
  duplicate collinear segments.
- `tools/check_schematics.py` now asserts the **pinout of J1 and J2** against the
  interface table, the five connector footprints, and the switched nets.

Two defects came out of doing it, both found by comparing netlists rather than by
looking at the sheet: a wire ended on a **no-connect pin** (J3.14 and K1.11 got
pulled onto `FLP_DS_A_GOTEK` — the router blocked other nets' pins but not the
ones marked no-connect), and the checker was carrying a **pinout table that read
pins 4 and 6 as GND** while the design says TG43 and EARLY. Both are fixed, and
the sibling generator in `hardware/wifi-comm-pac/` has the first one fixed too.

## The switch part is open (2026-10-22)

**The 4PDT relay this design named is obsolete, and so is its whole class.** The
part was Omron **G6A-434P** / **G6A-474P**; both went out with a last-buy date of
2010-06-29, and the other 4-pole DIP signal relays followed — Panasonic
**TQ4-5V** and **DS4E-S-DC5V** are broker-only at $20–190 a piece. That is a
finding, not a preference, and it reopens one of the seven "settled" decisions
(`docs/floppy-adapter-design.md` §4.3, §8.3):

| Option | Parts | Cost | Verdict |
|---|---|---|---|
| **Two DPDT DIP-8** | Omron **G6S-2 DC5** (Newark $6.00 @1 / $4.65 @100; LCSC $0.99) or Hongfa **HFD2/005-S-L2** ($2.20 @1 / $1.66 @100) | **~$4–12 the pair** | **Recommended** — same three switches, fail-safe as before, and 56 mA of coil against the 4PDT's 73 mA |
| **Solid-state** | SN74CBT3257 (DS-A) + TPS22918 (+5 V) + N-MOSFET (GND), or 2 × AQY212GS | **~$3** | Real option now: silent, no coil, low profile; more parts and more 5 V-level care |
| **Industrial 4PDT on a socket** | Omron MY4N-DC5(S) on PY14-02, or Finder 55.34 | $8–15 + socket | Works, and **35 mm tall** — wrong shape for a mezzanine card |

K1 therefore carries **no footprint**: the symbol's pin numbers change with the
answer, and a footprint for the wrong package is a board that does not fit. The
generator prints the open item on every run, so it cannot be forgotten.

## Settled decisions (2026-10-10, relay reopened 2026-10-22)

The seven design questions are closed — see
[`docs/floppy-adapter-design.md`](../../docs/floppy-adapter-design.md) §8 for
the evidence behind each. Highlights:

- O1 floppy header is **male** (logic-board P8), so **J1 is a female socket**.
- **Relay, not silicon — but the *part* is open**: the 4PDT it named is obsolete
  (see above). Two DPDT DIP-8 is the recommendation.
- Switch **DS-A + both power rails** only — Loxley's proven minimum.
- **1 kΩ** DS-A pull-up default, **150 Ω** alternative footprint.
- Gotek drive-select jumper: **S1 first, S0 fallback** (bench-verify).
- Gotek sits in the **right-hand** pocket on a reduced ~12-line pigtail.


## Open items (not blocking capture)

- **The switch part** — see above. Everything else on this board is a drawing
  decision; this one is a purchase.
- The **relay's pin numbers** are DIP-14 logical placeholders and must be rebound
  to the chosen part's terminal arrangement when the footprint is assigned. That
  is not bookkeeping: on the WiFi COMM PAC, a symbol whose pin 1 was `+3V3`
  against a package whose pin 1 was `GND1` put 3.3 V on a ground pad.
- Mounting: piggyback footprint vs. standoffs over the DD board; confirm
  keep-outs against the mainboard schematic
  (`research/osborne1/OCC1_1A2011-00_Schem_RevE.pdf`) and host photos
  (`research/pictures/`).
- Interaction with the interposer's floppy personality (#20): document
  which device owns the bus in each configuration.
- G2 upgrade (#30): believed BIOS/DPB-only, nothing at the connector —
  confirm.


## References

- `research/osborne1/floppy-adapter/` — archived Osborne1FloppyAdapter
  KiCad project (connector/pinout prior art; **not** this design)
- `research/osborne1/OCC1_1A2011-00_Schem_RevE.pdf`
- Richard Loxley, Osborne Restoration parts 13–15 (concept origin)
