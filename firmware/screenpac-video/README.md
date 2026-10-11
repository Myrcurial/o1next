# screenpac-video — SCREEN-PAC 80/104-column video + HDMI (RP2350)

Emulates the SCREEN-PAC 80/104-column video personality and provides
modern video out (HDMI via RP2350 HSTX/DVI, or VGA resistor DAC via
`hardware/front-panel-ui/`).

Tracks: #24; char-gen ROM context in #44.

## Definition

- Tap the 24-pin char-gen socket (UA15) like the real ScreenPac; **read
  whatever font ROM is actually installed at init** — the personality
  works with early/late stock and Nuevo fonts without bundled ROMs.
- Emulate the SCREEN-PAC register interface so period software (and the
  ScreenPac service-manual behaviors, `research/screenpac/`) work.
- Render framebuffer → DVI/VGA; keep timing on PIO/core1 per the
  radio-jitter rule.
- Also the video source for the KVM console (`../kvm-console/`).

## The ScreenPac's physical interface (from the field service manual)

Per `research/screenpac/2F00040_service_2ndEd_1983.pdf` §6.12 (OCR:
`2F00040_service_2ndEd_1983.ocr.txt`), the ScreenPac install is:

1. Pull the Z80 and the char-gen ROM; the ScreenPac board plugs into
   **both** sockets (40-pin + 24-pin pin spacers), plus a power harness.
2. **A 14-wire IC harness soldered to logic-board IC pins** (Table 1,
   "solder connections") plus a **coax from logic-board B13 pin 6 to
   ScreenPac U1 pin 15**:

| Logic board IC.pin | Harness wire | | Logic board IC.pin | Harness wire |
|---|---|---|---|---|
| B11.12 | Blue 9 | | D17.14 | Green 10 |
| B16.1 | Grey 1 | | D18.14 | Orange 2 |
| D13.5 | Orange 12 | | E13?.1 | Yellow 1 |
| D16.4 | Red 13 | | E22.12 | Black 5 |
| D16.5 | Brown 14 | | B13.6 | coax → U1.15 |
| D17.10 | Brown 4 | | (wires 3 red, 11 yellow cut) | |
| D17.12 | White 6 | | | |

(OCR-cleaned; verify against the scan before relying on D13/E13/B11
identities.) These are taps into the **video timing chain** (counters,
sync, dot clock) — B13 is implicated in dot-clock generation (the B13
bulletin warns Fairchild/SG-made parts break 80-column mode).

## Do we need those fly leads? Mostly no — with one caveat

The O1's screen is **memory-mapped video RAM**; the char-gen socket tap
(UA15) gives the font. So the video personality can be built as pure
**memory-side reconstruction**: watch video-RAM writes on the Z80 bus
(already have them), read the installed font ROM via the UA15 tap,
render the frame in the RP2350 → HDMI/VGA. No fly leads, no soldered
taps. ScreenPac mode-register writes are also bus-visible, so 80/104
column switching is tracked automatically.

**Caveat / research task:** the fly leads exist because the real
ScreenPac *re-times the video circuitry itself* (it drives the original
CRT at 80/104-column dot clocks). We only need to care if (a) we ever
want to drive the original CRT through the ScreenPac path, or (b) a
ScreenPac is *physically installed* alongside us — as on the fully
loaded host machine — in which case our personality must **snoop, not
drive** (defer to the installed board). Action: identify each tapped
IC's function against `research/osborne1/OCC1_1A2011-00_Schem_RevE.pdf`
(B11/B13/B16/D13/D16–D18/E22) so the "what the ScreenPac changes
electrically" story is documented even though we don't replicate it.

## Open questions

- Char-gen socket pinout confirmation (ScreenPac install pages +
  Rev E schematic; research-gaps #3).
- HDMI vs VGA as the primary output (decided with front-panel hardware).

## Deliverables

- ScreenPac register emulation + renderer
- Font-ROM init reader
- Validation vs. `research/screenpac/2F00040_service_2ndEd_1983.pdf`

## Monitor character: white or green (#24)

The interposer drives a modern display, so it can present the machine's screen in
either of the two colours an Osborne 1 actually had:

- **white on black** — the standard through production, and the default;
- **green on black** — the very late run, after Chapter 11.

This is a display option rather than a hardware one: the same video snoop feeds
either palette, so the switch belongs in the personality's configuration (and in
the web UI), not in the font or in the char-gen ROM. The bitmap is identical
either way, which is why the font tooling needs no knowledge of it at all.

The project blog makes the same choice for the same reason: it is white on black,
with the green noted as the late-production option.
