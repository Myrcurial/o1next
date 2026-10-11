---
layout: page
title: The Osborne 1 Compendium
subtitle: A complete reference, assembled from the project's own research
draft: "This is a draft, and it will stay one until the research issues close. Chapters marked <em>partially solved</em> say so because the underlying question is still open; chapters marked <em>not yet written</em> have no source document yet."
---

Nobody should have to reverse-engineer an Osborne 1 twice. This book is the
project's attempt to write down everything we have worked out about the machine —
the ROM, the schematics, the memory and I/O map, every peripheral protocol, the
third-party upgrade boards and the disk library — in one place, with the evidence
attached and the unknowns named.

It is **assembled, not written**: each chapter is one of the project's working
documents in `docs/`, and the repository stays the single source of truth. If you
want to check a claim, follow it back to the source file — every chapter names
its source, and the cross-references link straight to it on GitHub.

## Contents

{% include compendium-toc.html %}

## Download

{%- assign pdf = site.static_files | where_exp: "f", "f.path contains 'osborne1-compendium'" | first %}
{%- if pdf %}
[**Download the PDF**]({{ pdf.path | relative_url }}) — the whole book in one
file, rendered with pandoc from the same sources.
{%- else %}
The PDF is **not built yet**: rendering one needs a PDF engine for pandoc
(`typst`, `tectonic` or a LaTeX), and this machine does not have one. The pages
above are the book in HTML in the meantime.
{%- endif %}

## How it is put together

- **`book/manifest.txt`** is the table of contents — one line per chapter, naming
  its source document and its status. Editing the manifest changes the book.
- **`tools/build_book.py`** reads the manifest and generates this page's table of
  contents, the chapter pages, and the PDF. It never writes into `docs/`.
- **Nothing is duplicated.** A chapter is a *view* of a working document, so a
  correction made in `docs/` shows up here on the next build rather than drifting.

That structure is deliberate: a book that copies its sources is a book that goes
quietly out of date.

## What is missing

Three kinds of gap, all visible in the contents above rather than hidden:

- **Chapters with no source yet** — the overview, the keyboard and printer
  chapter, the software library, boot disks, and the *Portable Companion* extract
  index. These are book-only writing, and they are marked.
- **Chapters that are partial** — Drive C's command set, the hard-disk controller
  comparison, the RT-60A contract. The chapter says what is unknown and which
  issue closes it.
- **Diagrams** — the working documents use Mermaid, which pandoc does not render
  without extra tooling. In the PDF they appear as code blocks; in the HTML they
  render properly.
