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
- **The measure is 104 characters** — the machine's own widest text mode — which
  is why the body size is 1.5× the ROM's 10px cell. Long lines wrap there rather
  than at a pixel width.
- **The wordmark** (`_includes/logo.svg`) derives from the Osborne Computer
  Corporation logotype: O, N and E are its letterforms; 1, X, T and G are drawn
  to the same measured metrics. It is an homage for a non-commercial project and
  claims no affiliation.

Layouts live in `_layouts/` and override the theme's, because minima put the
project name in the masthead, the nav, the page heading, the footer heading and
the footer contact line — five times on one page. The masthead carries it once,
in the logo.

### Previewing without Jekyll

Jekyll cannot be installed against this machine's system Ruby (2.6), so the
layouts cannot be built locally. Two ways to see a change before pushing:

1. Render a preview built from the real CSS, logo and font:
   `tools/site_preview.py home|post /tmp/preview.html`, then
   `qlmanage -t -s 1300 -o /tmp /tmp/preview.html` and look at the PNG.
2. Push and read the deployed page — `curl` the site and check the markup.

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
