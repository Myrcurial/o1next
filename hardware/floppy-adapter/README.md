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

- `floppy-adapter.kicad_sch` (+ `.kicad_pro`) — structural Rev A schematic.
- `gen_floppy_adapter_sch.py` — generator; edit the net tables and re-run
  (`python3 gen_floppy_adapter_sch.py`), then open/re-save in KiCad to
  normalise.
- **J1** female 2x17 socket (O1 logic-board P8), **J2** pass-through header to
  the OEM cable, **J3** Gotek signal header, **J4** switched Gotek power,
  **J5** panel switch, **K1** 4PDT relay, **D1/R1** flyback + coil pull-down,
  **R3/R4** DS-A pull-up, **R2+D2** optional indicator.
- Validated with `kicad-cli sch export netlist` (netlist matches the design
  doc's net table) and `kicad-cli sch erc` (0 errors).
- Layout follow-ups: the relay pin numbers are **DIP-14 logical placeholders**;
  assign footprints at layout (KiCad ships no G6A-434P footprint).

## Settled decisions (2026-10-10)

The seven design questions are closed — see
[`docs/floppy-adapter-design.md`](../../docs/floppy-adapter-design.md) §8 for
the evidence behind each. Highlights:

- O1 floppy header is **male** (logic-board P8), so **J1 is a female socket**.
- **Relay** (not solid-state) for Rev A.
- Switch **DS-A + both power rails** only — Loxley's proven minimum.
- **1 kΩ** DS-A pull-up default, **150 Ω** alternative footprint.
- Gotek drive-select jumper: **S1 first, S0 fallback** (bench-verify).
- Gotek sits in the **right-hand** pocket on a reduced ~12-line pigtail.

## Open items (not blocking capture)

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
