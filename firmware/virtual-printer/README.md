# virtual-printer — Virtual Epson MX-80, capture → PDF on-device (RP2354B)

The **Virtual Epson MX-80**: captures Centronics-mode output on the
IEEE-488 port and renders it to PDF emulating a period 9-pin Epson
MX-80. PDFs are served from the interposer's HTTP interface — no
external computer required.

Tracks: #19. References archived in `research/mx80/`.

## Definition

- **Capture:** snoop the IEEE-488/Centronics write path, buffer the
  byte stream per print job.
- **Renderer (runs on the RP2354B):** emulate the 9-pin printhead into
  a 1-bit raster page buffer — at ~60×72 DPI a full page is ~50 KB,
  well within the RP2354B's 520 KB SRAM. Then wrap the bitmap in a
  minimal PDF (plain objects + xref, no compression required).
  - Supported: two fonts, double-wide, italics, bold, underline.
  - **Not supported:** graphics printout (ESC K/L) — period-documented
    limitation of this emulation.
- Written as **portable C** so the same renderer also builds as a host
  tool for development and golden-file testing.
- **Serving:** finished jobs appear in the web UI (`../web-ui/`) as
  downloadable PDFs.

## Page presentation: tractor-feed paper

Not photographic realism — just the hint that you might need to tear
the sides off each page on your screen. Ship a small embedded image
asset (or procedurally-drawn strip) of **fanfold tractor-feed edges**:
perforated margins with sprocket holes along left/right edges, optional
per-page perforation line. Rendered as the PDF page background with the
rasterized print overlaid, so WordStar output looks like it came off
the platen. Keep the asset tiny (1-bit, a few KB) and the effect
subtle; a config toggle in the web UI turns it off for clean PDFs.

## Glyph sources (research/mx80/)

- **Source of truth:** MX-80 operation manual, Appendix 4 character
  font tables (PDF p. 97+) — how glyphs fit the 6×9 matrix.
- **Cross-check:** Michael Walden's MX-80 font pack (CC BY-NC-SA 4.0).

## Open questions

- **Double-strike / density modes:** the Walden font renders ~2× wider
  than expected — hypothesis is a draft vs. high-quality mode where the
  head prints each character twice with a half-pin-width offset for
  density. Resolve against the manual's ESC density codes and Appendix 4
  column counts (and ideally a scan of real output in both modes)
  before locking glyph metrics. (More in `research/mx80/README.md`.)
- Exact ESC subset boundary: which control codes beyond the supported
  feature list get acknowledged-and-ignored vs. treated as errors.

## Deliverables

- Capture module (snoop/poke engine)
- `mx80/` portable renderer library (device + host builds)
- Glyph data transcribed from the manual's Appendix 4
- Tractor-feed page asset + web-UI toggle
- Test corpus: period CP/M print output (WordStar etc.)
