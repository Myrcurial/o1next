#!/usr/bin/env python3
"""Assemble the Osborne 1 Compendium from the working docs (#75).

``docs/`` stays the single source of truth.  This tool does not copy the
analysis -- it *orders* it.  From ``book/manifest.txt`` it generates:

    site/compendium/<slug>.md            one Jekyll page per chapter
    site/_includes/compendium-toc.html   the clickable table of contents
    site/assets/compendium/<name>.pdf    the rendered book, via pandoc

Every generated page carries a draft banner, because the book is assembled from
docs that are themselves explicitly partial -- a chapter that says "Partially
solved" upstream must still say so in the book.

Two things it deliberately does *not* do:

- It never writes into ``docs/``.  Edit the source doc, re-run this.
- It does not fail when no PDF engine is installed.  The pages and the TOC are
  the deliverable; the PDF is a convenience, and pandoc needs an external engine
  for it (typst, tectonic, wkhtmltopdf, weasyprint or a LaTeX).  Without one the
  tool says so and carries on.

Usage:
    tools/build_book.py             # write the pages, the TOC and the PDF
    tools/build_book.py --no-pdf    # pages and TOC only
    tools/build_book.py --check     # fail if the committed pages are stale (CI)
"""
import argparse
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
MANIFEST = REPO / "book" / "manifest.txt"
SITE = REPO / "site"
OUT_PAGES = SITE / "compendium"
OUT_TOC = SITE / "_includes" / "compendium-toc.html"
OUT_PDF = SITE / "assets" / "compendium" / "osborne1-compendium-draft.pdf"

BLOB = "https://github.com/Myrcurial/o1nextgen/blob/main"

ROMAN = ["I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X"]

DRAFT = ("Draft &mdash; assembled from the working notes by "
         "`tools/build_book.py`. The source document is the authority; this "
         "page is a copy for reading, and it is regenerated from that source.")

# The status words docs/README.md defines, plus the ones the manifest adds for
# material that is not a solved/partial question.
STATUS_NOTE = {
    "solved": "",
    "partial": "partially solved",
    "design": "design",
    "reference": "reference",
    "living": "living document",
    "pending": "not yet written",
}

# Backticked repo paths become links to the file on GitHub, so the book is
# navigable without the reader knowing the repository layout.
REPO_PATH = re.compile(
    r"`((?:docs|research|tools|software|firmware|hardware|book|site)"
    r"/[A-Za-z0-9._/-]+)`")


def read_manifest(path):
    """Parse the manifest into [(part_title, [chapter, ...]), ...].

    A chapter is a dict: slug, title, source (or None), status.
    """
    parts = []
    for lineno, raw in enumerate(path.read_text().splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("[part]"):
            parts.append([line[len("[part]"):].strip(), []])
            continue
        fields = [f.strip() for f in line.split("|")]
        if len(fields) != 4:
            raise SystemExit("%s:%d: expected 'slug | title | source | status'"
                             % (path, lineno))
        slug, title, source, status = fields
        if not parts:
            raise SystemExit("%s:%d: chapter before any [part]" % (path, lineno))
        if status not in STATUS_NOTE:
            raise SystemExit("%s:%d: unknown status %r" % (path, lineno, status))
        parts[-1][1].append({"slug": slug, "title": title,
                             "source": None if source == "-" else source,
                             "status": status})
    return [(t, c) for t, c in parts]


def link_repo_paths(text):
    """Turn backticked repo paths into links to the file on GitHub.

    The working docs refer to each other by path -- ``docs/foo.md`` -- which is
    right inside the repository and useless in a rendered book.  Only paths that
    *exist* are linked; anything else stays a code span, so a stale reference is
    visible rather than quietly turned into a broken link.
    """
    def repl(match):
        rel = match.group(1)
        if not (REPO / rel).exists():
            return match.group(0)
        return "[`%s`](%s/%s)" % (rel, BLOB, rel)
    return REPO_PATH.sub(repl, text)


def demote(text):
    """Push every heading down one level, so it sits under the chapter title.

    Fenced code blocks are skipped -- the docs quote ROM listings that start
    with `#`, and those are comments, not headings.
    """
    out, fence = [], None
    for line in text.splitlines():
        stripped = line.lstrip()
        if stripped.startswith("```") or stripped.startswith("~~~"):
            marker = stripped[:3]
            fence = None if fence == marker else (fence or marker)
            out.append(line)
            continue
        if fence is None and line.startswith("#"):
            out.append("#" + line)
            continue
        out.append(line)
    return "\n".join(out)


def chapter_body(chapter):
    """The chapter's markdown, or None when it has not been written yet."""
    if chapter["source"] is None:
        return None
    src = REPO / chapter["source"]
    if not src.exists():
        raise SystemExit("chapter %s: source %s does not exist"
                         % (chapter["slug"], chapter["source"]))
    lines = src.read_text().splitlines()
    # Drop the leading H1: the page layout renders the title from front matter,
    # so the doc's own heading would be a duplicate.
    for i, line in enumerate(lines):
        if line.startswith("# "):
            del lines[i]
            break
    return link_repo_paths("\n".join(lines).strip("\n"))


def yaml(value):
    """A YAML-safe double-quoted scalar.  Titles contain colons."""
    return json.dumps(value, ensure_ascii=False)


def chapter_page(part_title, chapter):
    """The Jekyll page for one chapter, or None if it has not been written."""
    body = chapter_body(chapter)
    if body is None:
        return None
    note = STATUS_NOTE[chapter["status"]]
    subtitle = part_title if not note else "%s &middot; %s" % (part_title, note)
    return """---
layout: page
title: %s
subtitle: %s
draft: %s
---

%s
""" % (yaml(chapter["title"]), yaml(subtitle), yaml(DRAFT), body)


def toc_html(parts):
    """The clickable table of contents, as a Jekyll include."""
    out = ['<ul class="toc">']
    for i, (part_title, chapters) in enumerate(parts):
        out.append('  <li class="toc-part">%s &middot; %s</li>'
                   % (ROMAN[i], part_title))
        for ch in chapters:
            note = STATUS_NOTE[ch["status"]]
            tail = (' <span class="toc-status">&mdash; %s</span>' % note
                    if note else "")
            if ch["source"] is None:
                out.append("  <li>%s%s</li>" % (ch["title"], tail))
            else:
                out.append("  <li><a href=\"{{ '/compendium/%s/' | "
                           "relative_url }}\">%s</a>%s</li>"
                           % (ch["slug"], ch["title"], tail))
    out.append("</ul>")
    return "\n".join(out) + "\n"


# --------------------------------------------------------------------------
# the PDF: pandoc plus whatever engine the host happens to have
# --------------------------------------------------------------------------

# pandoc cannot make a PDF on its own -- it shells out to one of these.
PDF_ENGINES = ("typst", "tectonic", "xelatex", "lualatex", "pdflatex",
               "wkhtmltopdf", "weasyprint", "prince", "context")


def find_engine():
    for name in PDF_ENGINES:
        if shutil.which(name):
            return name
    return None


def book_markdown(parts):
    """The whole book as one markdown document, for pandoc."""
    doc = ["---",
           "title: The Osborne 1 Compendium",
           "subtitle: A complete reference, assembled from the project's own research",
           "author: o1nextgen",
           "---",
           "",
           "> **DRAFT.** This book is assembled from the project's working notes,",
           "> which are explicitly partial: chapters carry a status and some are",
           "> not written yet. Where a chapter is incomplete, the source document",
           "> says so and says why. The repository is the authority.",
           ""]
    for part_title, chapters in parts:
        doc += ["# %s" % part_title, ""]
        for ch in chapters:
            doc += ["## %s" % ch["title"], ""]
            body = chapter_body(ch)
            if body is None:
                doc += ["*(not yet written)*", ""]
            else:
                doc += [demote(body), ""]
    return "\n".join(doc)


def build_pdf(parts):
    engine = find_engine()
    if engine is None:
        return ("no PDF engine found -- pandoc needs one. Install typst "
                "(`brew install typst`) or tectonic, then re-run. The pages "
                "and the TOC are written regardless.")
    OUT_PDF.parent.mkdir(parents=True, exist_ok=True)
    proc = subprocess.run(
        ["pandoc", "--from", "markdown", "--to", "pdf", "--toc",
         "--toc-depth=2", "--pdf-engine", engine,
         "-o", str(OUT_PDF)],
        input=book_markdown(parts), text=True,
        capture_output=True)
    if proc.returncode != 0:
        return "pandoc failed with %s:\n%s" % (engine, proc.stderr.strip())
    return "wrote %s (%d bytes) with %s" % (
        OUT_PDF.relative_to(REPO), OUT_PDF.stat().st_size, engine)


def main(argv=None):
    ap = argparse.ArgumentParser(
        description="Assemble the Osborne 1 Compendium from the working docs.")
    ap.add_argument("--check", action="store_true",
                    help="fail if the committed pages are stale (CI)")
    ap.add_argument("--no-pdf", action="store_true",
                    help="skip the PDF (it is the slow part)")
    args = ap.parse_args(argv)

    parts = read_manifest(MANIFEST)

    pages = {}
    for part_title, chapters in parts:
        for ch in chapters:
            page = chapter_page(part_title, ch)
            if page is not None:
                pages[OUT_PAGES / ("%s.md" % ch["slug"])] = page
    pages[OUT_TOC] = toc_html(parts)

    if args.check:
        stale = [str(p.relative_to(REPO)) for p, want in sorted(pages.items())
                 if not p.exists() or p.read_text() != want]
        if stale:
            print("stale book page(s): " + ", ".join(stale))
            print("run: tools/build_book.py")
            return 1
        print("book pages OK: %d chapters, %d written"
              % (sum(len(c) for _, c in parts), len(pages) - 1))
        return 0

    for path, text in sorted(pages.items()):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
        print("wrote %s" % path.relative_to(REPO))

    if not args.no_pdf:
        print(build_pdf(parts))
    return 0


if __name__ == "__main__":
    sys.exit(main())

