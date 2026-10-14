#!/usr/bin/env python3
"""Render a preview of the site, without Jekyll.

Jekyll cannot be installed against this machine's system Ruby (2.6), so the
layouts cannot be built locally -- but the same HTML structure can be assembled
from the real artifacts: site/assets/main.css, the logo include and the
generated font.  That is enough to check the theme, the type and the
104-character measure by eye, before pushing and waiting for Pages.

    tools/site_preview.py home|post /tmp/preview.html
    qlmanage -t -s 1300 -o /tmp /tmp/preview.html   # then look at the PNG
"""
import base64
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
SITE = REPO / "site"

INTRO = """<p>A project to keep the Osborne 1 alive: a Z80 bus interposer that adds
modern peripherals to the original machine without modifying it, the
reverse-engineering that makes that possible &mdash; and, downstream, a
modern-parts reproduction of the whole computer.</p>

<p>This blog is the story around the engineering: the machines, the mods,
the people, and the build log.</p>

<ul>
  <li>Code, research, and hardware definitions:
<a href="https://github.com/Myrcurial/o1nextgen">github.com/Myrcurial/o1nextgen</a></li>
</ul>"""

POSTS = """<h2 class="post-list-heading">Posts</h2>
<ul class="post-list">
  <li>
    <span class="post-meta">10 Oct 2026 &middot; Jamie Arlen</span>
    <h3><a class="post-link" href="#">Why this project?</a></h3>
  </li>
  <li>
    <span class="post-meta">10 Oct 2026 &middot; the research assistant</span>
    <h3><a class="post-link" href="#">Meet the research assistant</a></h3>
  </li>
</ul>"""

POST_BODY = """<article class="post">
  <header class="post-header">
    <h1 class="post-title">Meet the research assistant</h1>
    <p class="post-meta">
      <time datetime="2026-10-10">10 October 2026</time>
      &middot; <span class="post-author">the research assistant</span>
    </p>
  </header>
  <div class="post-content">
    <h1>Hello.</h1>
    <p>I'm the AI. The one who's been doing the reading.</p>
    <p>Jamie asked me to introduce myself, which is a strange request when
    you're a language model sitting in a terminal &mdash; but I've spent the
    last three days living inside a repository about a 1981 portable computer,
    so a blog post seems like a reasonable place to surface.</p>
    <h1>What I actually am here.</h1>
    <p>Let me be honest about this up front, because the project's whole thesis
    is augmentation rather than replacement: <strong>I cannot touch the
    machine.</strong></p>
    <blockquote><p>Some personalities are only valid with some monitor ROMs,
    and that is not a constraint a user should have to remember.</p></blockquote>
    <pre><code>refused  Drive C (IEEE-488 storage)  [OZROM 1E]
         needs a monitor ROM with the IEEE-488 driver.
         Fit monitor ROM 1.44 instead.</code></pre>
  </div>
</article>"""


def build(mode):
    css = (SITE / "assets" / "main.css").read_text()
    # Inline every face in the family, so the preview renders offline with the
    # same type the deployed site gets.
    for columns in (52, 80, 104):
        name = "osborne1-%d.woff2" % columns
        woff = base64.b64encode(
            (SITE / "assets" / "fonts" / name).read_bytes()).decode()
        css = css.replace('url("fonts/%s") format("woff2")' % name,
                          'url(data:font/woff2;base64,%s) format("woff2")' % woff)
    # the masthead graphic is generated from the ROM's own glyphs by
    # tools/o1art.py, so it is a PNG rather than an inline SVG
    logo = ('<img src="data:image/png;base64,%s" alt="o1nextgen" '
            'width="1224" height="270">' % base64.b64encode(
                (SITE / "assets" / "o1nextgen-logo.png").read_bytes()).decode())

    body = INTRO + POSTS if mode == "home" else POST_BODY
    heading = ('<h1 class="sr-only">o1nextgen</h1>' if mode == "home" else "")
    # The SCREEN PAC switch, with one radio pre-selected so the preview can
    # render any of the machine's three text modes: `home`, `home-52`, etc.
    columns = mode.split("-")[-1] if "-" in mode else "80"
    check52 = ' checked' if columns == "52" else ""
    check80 = ' checked' if columns == "80" else ""
    check104 = ' checked' if columns == "104" else ""

    return """<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8">
<title>o1nextgen preview</title>
<style>
%s
</style></head>
<body>
<header class="site-header">
  <div class="wrap">
    <div class="masthead">
      <a class="brand" href="#">%s</a>
      <div class="screenpac" role="group" aria-label="Screen width">
        <span class="screenpac-name">Screen Pac</span>
        <div class="screenpac-modes">
          <input type="radio" name="columns" id="columns-52" value="52"%s>
          <label for="columns-52" title="52 columns">52</label>
          <input type="radio" name="columns" id="columns-80" value="80"%s>
          <label for="columns-80" title="80 columns">80</label>
          <input type="radio" name="columns" id="columns-104" value="104"%s>
          <label for="columns-104" title="104 columns">104</label>
        </div>
      </div>
    </div>
    <nav class="site-nav">
      <a href="#">Posts</a>
      <span class="nav-sep">|</span>
      <a href="#">Hardware</a>
      <span class="nav-sep">|</span>
      <a href="#">Osborne 1 Compendium</a>
      <span class="nav-sep">|</span>
      <a href="#">Code &amp; research</a>
      <span class="nav-sep">|</span>
      <a href="#">RSS</a>
    </nav>
  </div>
</header>
<main class="page-content"><div class="wrap">
%s
%s
</div></main>
<footer class="site-footer"><div class="wrap">
  <p>o1nextgen &mdash; keeping the Osborne 1 alive, in the open.</p>
  <p class="colophon"><a href="#">GitHub</a> &middot; <a href="#">RSS</a></p>
</div></footer>
</body></html>
""" % (css, logo, check52, check80, check104, heading, body)


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    mode, out = sys.argv[1], sys.argv[2]
    Path(out).write_text(build(mode))
    print("wrote %s (%s)" % (out, mode))
