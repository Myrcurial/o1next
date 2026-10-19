# screenpac-video — SCREEN-PAC 80/104-column video + HDMI (RP2354B)

Emulates the SCREEN-PAC 80/104-column video personality and provides
modern video out — **HDMI**, via the RP2354B's HSTX block, with the
connector on `hardware/interposer-upgrade/ui-pod/`.

Tracks: #24; char-gen ROM context in #44.

## Output: HDMI, not VGA (settled 2026-10-11)

The personality's output is **HDMI**. **VGA is not pursued**: HSTX is fixed to
GP12–19 on the RP2354B, so a resistor DAC would need the same range and the two are
mutually exclusive.

The same decision now applies across the project — the SFF board carries **HDMI
only** and no composite circuitry at all (`hardware/next-integrated/README.md`). The display
*character* (white, green or amber — see "Monitor character") is a rendering choice in the
personality's configuration rather than a hardware one; see "Monitor character"
below.

## Definition

- Tap the 24-pin char-gen socket (UA15) like the real ScreenPac; **read
  whatever font ROM is actually installed at init** — the personality
  works with early/late stock and Nuevo fonts without bundled ROMs.
- Emulate the SCREEN-PAC register interface so period software (and the
  ScreenPac service-manual behaviors, `research/screenpac/`) work.
- Render framebuffer → HDMI; keep timing on PIO/core1 per the
  radio-jitter rule.
- Also the video source for the KVM console (`../kvm-console/`).

## The ScreenPac's physical interface (from the field service manual)

Per `research/osborne1/2F00040_service_2ndEd_1983.pdf` §6.12 (OCR:
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
render the frame in the RP2354B → HDMI. No fly leads, no soldered
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

## Deliverables

- ScreenPac register emulation + renderer
- Font-ROM init reader
- Validation vs. `research/osborne1/2F00040_service_2ndEd_1983.pdf`

## Monitor character: white, green or amber (#24)

The interposer drives a modern display, so it can present the machine's screen in
the colours the Osborne portables actually had:

- **white on black** — the standard through Osborne 1 production, and the default;
- **green on black** — the very late Osborne 1 run, after Chapter 11;
- **amber on black** — the **Osborne Executive**'s screen, 7-inch, 80 × 24.

This is a display option rather than a hardware one: the same video snoop feeds
any palette, so the switch belongs in the personality's configuration (and in the
web UI), not in the font or in the char-gen ROM. The bitmap is identical either
way, which is why the font tooling needs no knowledge of it at all.

Two things to keep straight about the amber one, because they are easy to
conflate:

- **It is a CRT, so amber is a fourth phosphor, not a fourth technology.** The
  Executive's display is a 7-inch amber-phosphor CRT: RICM records it as a
  "7-inch 80 character × 24 line amber monochrome CRT", the Centre for Computing
  History as a "7-inch amber phosphor screen", and the 1983 *Creative Computing*
  review as "a 7" amber display" — which also lists the front panel's **external
  video** and **composite video** connectors. Same geometry, same glyphs,
  different colour: it belongs in the white/green family.
- **A gas-plasma panel is not a palette in that family.** It is a different
  display technology — emissive cells, hard-edged pixels, no phosphor bloom or
  decay, a different gamma — so rendering one needs its own path rather than a
  tint of the CRT model. This note is deliberately not naming the machine or
  panel that implies: that is still to be recorded. (The HDMI section above used
  to read "the amber plasma mode", which conflated the Executive's amber CRT with
  plasma; fixed 2026-10-11.)

The project blog makes the same choice for the same reason: it is white on black,
with the green noted as the late-production option.
