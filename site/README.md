# site/ — project blog (GitHub Pages)

Source for the project's GitHub Pages site: the story of how this
project came to be, hardware-mod write-ups for the author's Osborne
machines, and the ongoing build log.

## Publishing

Jekyll, minimal config. Two supported ways to publish (pick one in
repo Settings → Pages):

1. **GitHub Actions** (recommended): the standard "Deploy Jekyll site"
   workflow with the source directory set to `site/` — publishes on
   every merge to `main`.
2. **Branch deploy**: an Action (or manual step) that pushes `site/` to
   a `gh-pages` branch.

(The usual `/docs` Pages source is unavailable — our `docs/` is the
engineering-notes tree and stays as-is.)

## Layout

- `_config.yml` — Jekyll config (title, theme, permalinks)
- `index.md` — landing page
- `_posts/YYYY-MM-DD-title.md` — blog entries
- `hardware/` — the Hardware section: one page per planned device, plus an index
- `compendium/` — the Osborne 1 Compendium. `index.md` is hand-written; the
  chapter pages are **generated** by `tools/build_book.py` from
  `book/manifest.txt` and should not be edited by hand
- `_includes/compendium-toc.html` — **generated** table of contents
- `assets/` — images; keep photos reasonably sized and prefer links to
  `research/pictures/` where the same photo already exists in-repo

## Theme and type

The look is taken from the machine, not invented:

- **Colours** are sampled from a photograph of the front panel, lid and keycaps
  (`oldcomputers.net/osborne-1-rev2.jpg`): blue-grey `#687898`, pale grey
  `#d0d8d8`, cream `#d8d0c0`. `assets/main.css` records where each came from.
- **The body face is the Osborne 1's own character generator**, decoded from the
  ROM in UA15 by `tools/romfont.py` and shipped as `assets/fonts/`. The page is
  set in the same letters the machine drew on its own screen.
- **The face comes in the machine's three text widths — `osborne1-52`, `-80` and
  `-104`.** The physical screen width never changes; the type narrows. So the
  three files share height and pixel components and differ only in horizontal dot
  width: **100%, 65% (52/80) and 50% (52/104)**. That makes `52ch` in the
  52-column face, `80ch` in the 80-column face and `104ch` in the 104-column face
  all the *same physical width*.
- **The site pairs a face with its own column count** — currently the
  **80-column** mode at `80ch`, the width this project's video work is about.
  Changing mode is two lines in `main.css` (`--mono` and `--measure`). The
  measure is set in characters rather than pixels because the cell is fixed.
- **The SCREEN PAC switch** sits in a box the height of the logo, standing to its
  right: the name in the top half, the three modes in the bottom half, split
  three ways. Each radio forces the matching face *and* its own column count
  together, so the rendered window is the **same physical width** in all three
  modes — the type narrows, the screen does not. It is pure CSS (`:has()`), so
  the site keeps its no-script character, and where `:has()` is unsupported the
  80-column default simply stands. `tools/site_preview.py` accepts `home-52` /
  `home-80` / `home-104` so any mode can be previewed offline.
- **The menu is left justified**, never pushed to the right, and the items are
  divided by a literal `|` so the grouping still reads when the row wraps — which
  it does at 52 columns, where the face is at its widest.
- **The wordmark** (`_includes/logo.svg`) derives from the Osborne Computer
  Corporation logotype: O, N and E are its letterforms; 1, X, T and G are drawn
  to the same measured metrics. It is an homage for a non-commercial project and
  claims no affiliation.

Layouts live in `_layouts/` and override the theme's, because minima put the
project name in the masthead, the nav, the page heading, the footer heading and
the footer contact line — five times on one page. The masthead carries it once,
in the logo.

### Diagrams are rendered, not linked

A Mermaid code fence in a post **does not render**.  Mermaid looks for elements
with class `mermaid`, and kramdown turns a fence into
`<pre><code class="language-mermaid">`, which it never matches — so the diagram
ships as a code block and looks like a rendering fault rather than a wiring one.

So a post's diagrams are **rendered to PNG at build time** and embedded:

```
site/assets/diagrams/*.mmd      the source
tools/render_mermaid.py         renders them
site/assets/*.png               what the post embeds
```

The type is the machine's own character generator at the 80-column width, on the
palette `main.css` records, so a diagram reads as part of the page.  It also keeps
the page no-script and survives RSS and printing.

**One thing to get right, because it fails quietly.**  The reading column is
`80ch` in the 80-column face — `80 × 0.52 × 15px`, about **624px**.  An image
wider than that is scaled down and its type shrinks with it, so a diagram should
be *narrow*: at a natural width of ~700px the type lands at ~16px, which is
legible, and at 1500px it lands at 8px, which is not.  Tall and narrow is fine; a
wide left-to-right flow with long labels is not.  Check the rendered PNG's
dimensions against 624 before committing it.

The **compendium chapter pages keep their Mermaid fences**, because they are
generated by `tools/build_book.py` and cannot be hand-edited.  They rely on a shim
in `_layouts/default.html` that rewrites the fences into the elements Mermaid
wants.  That shim is **unverified locally** — Jekyll will not install against this
machine's system Ruby — so the compendium diagrams want an eye on the deployed
page.



Jekyll cannot be installed against this machine's system Ruby (2.6), so the
layouts cannot be built locally. Two ways to see a change before pushing:

1. Render a preview built from the real CSS, logo and font:
   `tools/site_preview.py home|home-52|home-80|home-104|post /tmp/preview.html`,
   then `qlmanage -t -s 1300 -o /tmp /tmp/preview.html` and look at the PNG. The
   `-52`/`-80`/`-104` modes render the SCREEN PAC switch in that mode.
2. Push and read the deployed page — `curl` the site and check the markup.

## The Osborne 1 Compendium

`compendium/` is the book (#75), and it is **assembled rather than written**:

- **`book/manifest.txt`** is the table of contents — one line per chapter naming
  its source document and its status.
- **`tools/build_book.py`** reads the manifest and generates the chapter pages,
  the table of contents include, and (when a PDF engine is installed) the PDF.
  `--check` fails if the committed pages are stale, so the generated files can be
  verified in CI.
- **The chapter pages are generated.** Do not edit them; edit the source document
  in `docs/` and re-run the tool. The landing page, `compendium/index.md`, is
  hand-written and is not touched by the build.
- The tool never writes into `docs/`, and it marks every page as a draft with a
  banner, because the book is assembled from documents that are themselves
  explicitly partial.

Rendering the PDF needs an external engine for pandoc (`typst`, `tectonic` or a
LaTeX). Without one the tool says so and writes the HTML pages anyway.

**The PDF is committed**, because the Pages deploy builds Jekyll but does not run
our tools — so whatever is in the repository is what gets served. That also means
a document edited in `docs/` needs `tools/build_book.py` re-run before the
chapter pages are correct; `.github/workflows/generated-artifacts.yml` runs both
`--check` modes, so a stale *page* fails in CI rather than shipping quietly.

**The PDF is the exception to that check.** `--check` deliberately does not cover
it — rendering needs `typst`, which the CI runner does not have — so **a stale
PDF ships silently**. Re-run `tools/build_book.py` whenever `docs/` changes, and
do not chase the byte-level differences between runs: the PDF embeds a
timestamp, so two builds of identical sources differ by a few dozen bytes.

## Planned articles (tracking issue)

- My first computer
- How I met Lee Felsenstein
- Finding the CoPower-88
- My battery-powered Osborne 1
- Modification to support Gotek drives with 3D-printed floppy-disk
  faceplate
- Why this project at all
- Build log (1/n)

Also planned: write-ups of the hardware modifications made to two of
the author's three Osborne machines (one extensive).

### The masthead graphic is generated, not drawn

`assets/o1nextgen-logo.png` is the wordmark drawn in the machine's own graphics
characters, using the same technique as the original Osborne boot logo. It is
generated by `tools/o1logo.py`, which draws the letters to the geometry measured
from AUTOCPM's logo art (cap height 50 sub-pixels, stroke 15, corner radius 6,
full-width hatch rules 2 thick every 8) and then hands the drawing to the glyph
table in `tools/o1art.py`. The `.art.txt` beside it is the assembler-ready form,
the same shape as AUTOCPM's — so the o1ng could print it at boot.

```
tools/o1logo.py site/assets --name o1nextgen-logo
```

The letters are *drawn*, not downsampled: rasterising a traced outline at this
size stair-steps badly, because the graphics set only resolves two sub-pixels per
character cell. `assets/o1nextgen-wordmark.svg` is kept as the record of the
logotype's proportions, and `tools/o1art.py` is still the general tool for turning
any image into Osborne graphics art.

### White on black, and the green option

The middle of the page is white on black, because that is what an Osborne 1
actually looked like; the masthead and footer are the blue panel and the grey case.
Green-on-black was a very late production option and is *not* used here — it is a
monitor choice, and the video personality offers both (#24,
`firmware/screenpac-video/README.md`).

Only the middle scrolls: the header is pinned to the top of the window and the
footer to the bottom, with `flex` on `body` and `overflow-y: auto` on
`.page-content`.
