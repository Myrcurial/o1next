#!/usr/bin/env python3
"""The docs contract: status lines, the index, and the cross-references (#200).

Why this exists
---------------
``docs/`` is forty documents written over two weeks by many sessions.  The
material was right; the *shape* was not -- the answer sat under a dated
``Correction`` block hundreds of lines below the claim it refuted, and the index
did not agree with the documents it indexed.  #200 was the pass that fixed it:
the answer in the lead, the corrections folded in, one statement of each fact.

A pass like that is worth exactly as much as the next document that ignores it,
so this is the check that keeps it true.  It fails when:

  * a document has no status line, or the status line does not open with one of
    the four words ``docs/README.md`` defines -- Solved, Partially solved, Open,
    Superseded;
  * a document has no row in ``docs/README.md``, or has more than one, or the
    row's ``State`` cell disagrees with the document's own status *word*;
  * a ``docs/x.md`` reference does not resolve, or a ``research/...`` path a
    document cites does not exist;
  * a dated correction block survives anywhere in ``docs/`` -- the shape #200
    was filed to remove.

What it cannot check is prose quality, and it does not pretend to: the judgement
in that pass was a person's.  What it checks is the mechanical part, which is
also the part that decays without anyone noticing.

Deliberate exemptions, and why.  This list is the whole argument; do not grow it
silently:

  * `docs/emulating-the-osborne-1.md` — that path belongs to a **different
    repository** (`Myrcurial/o1prsnt`, the adaption base), cited here as
    `o1prsnt/docs/emulating-the-osborne-1.md`.  It is not ours to hold.
  * `firmware/rom-service/frame.bin`, `screen.bin` — named in `docs/o1-rom-2.0.md`
    and `docs/rom-pico-protocol.md` as **deliberately not in the tree**: the art
    stayed when the ROM-side frame path retired (#278), and saying so is the
    point of the sentence.
  * `hardware/gpio.h`, `hardware/gpio_coproc.h` — the **Pico SDK's** own headers.
    They collide with our `hardware/` directory, and a prose path in backticks
    cannot be told apart from an include path.
  * A reference containing a glob (`*`), a brace expansion or an ellipsis is a
    shorthand, not a path, and is skipped rather than reported.
  * Quoted material is not our prose.  The dated-correction patterns below are
    deliberately narrow — the exact shapes #200 removed — so that a manual
    quotation or a FOG disk description cannot trip them.

Standard library only, and no host tooling.

Usage
-----
    python3 tools/check_docs.py            # check
    python3 tools/check_docs.py -v         # also print what it parsed
    python3 tools/check_docs.py --check    # the same check (CI spells it this way)

Exit status: 0 = the docs agree, 1 = at least one thing does not.
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
DOCS = REPO / "docs"
INDEX = DOCS / "README.md"

# Longest first: "Partially solved" contains "Solved".
STATUS_WORDS = ("Partially solved", "Superseded", "Solved", "Open")

# A row of the index table: | `file.md` | answers | issues | state |
INDEX_ROW = re.compile(r"^\| `([^`]+\.md)` \|(.*)\|([^|]*)\|([^|]*)\|\s*$")

# `docs/x.md` in a link, and in a code span.
LINK = re.compile(r"\[[^\]]*\]\(([^)\s]+)\)")
CODE_PATH = re.compile(
    r"`((?:docs|research|tools|hardware|firmware|software|site|book)/"
    r"[A-Za-z0-9._/-]+)`")

# A glob, a brace expansion or an ellipsis marks a shorthand, not a path.
SHORTHAND = re.compile(r"[*{}]|\.\.\.|…|<\w+>")

# The shapes #200 removed.  Narrow on purpose -- see the docstring.
DATED = (
    re.compile(r"\*\*(?:Correction|Corrected|Withdrawn|Revised)\s*\(?20\d\d"),
    re.compile(r">\s*\*\*(?:Correction|Corrected|Withdrawn|Revised)[,:]"),
    re.compile(r"^#{2,4} .*(?:\bCorrection\b|\bcorrected\b)", re.M),
)

# Cited paths that are deliberately not in this tree.  The argument for each one
# is in the docstring above; this list is the whole of it.
KNOWN_ABSENT = {
    "docs/emulating-the-osborne-1.md",      # another repository (o1prsnt)
    "firmware/rom-service/frame.bin",       # retired with #278, and says so
    "firmware/rom-service/screen.bin",      # retired with #278, and says so
    "hardware/gpio.h",                      # the Pico SDK's, not ours
    "hardware/gpio_coproc.h",               # the Pico SDK's, not ours
}


def status_word(text: str) -> tuple[str | None, str]:
    """The document's status word, and the text it was read from.

    The status line is the first block after the H1.  If no word is in it the
    document is reported, with what the first block actually said.
    """
    lines = text.splitlines()
    start = next((i for i, l in enumerate(lines) if l.startswith("# ")), 0)
    para: list[str] = []
    buf: list[str] = []
    for line in lines[start + 1:]:
        if not line.strip():
            if buf:
                para = buf
                break
            continue
        buf.append(line)
    if not para:
        para = buf or lines[start + 1:start + 26]
    block = "\n".join(para)
    for word in STATUS_WORDS:
        if word in block:
            return word, block
    return None, block


def strip_markup(text: str) -> str:
    text = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", text)
    return text.replace("*", "").replace("`", "").strip()


def targets(text: str) -> list[str]:
    """Every repo path the document cites, in either form."""
    out = []
    for m in LINK.finditer(text):
        t = m.group(1).strip()
        if t.startswith(("http://", "https://", "mailto:", "#")):
            continue
        out.append(t.split("#")[0])
    out += CODE_PATH.findall(text)
    return [t for t in out if t and not SHORTHAND.search(t)]


def resolves(rel: str, doc: Path) -> bool:
    """A reference resolves if it exists from the doc, the docs dir or the root."""
    return any((base / rel).exists() for base in (doc.parent, DOCS, REPO))


def check(verbose: bool) -> int:
    problems: list[str] = []
    docs = sorted(p for p in DOCS.rglob("*.md") if p.name != "README.md")
    index = INDEX.read_text()

    rows: dict[str, str] = {}
    for line in index.splitlines():
        m = INDEX_ROW.match(line)
        if not m:
            continue
        name = m.group(1)
        if name in rows:
            problems.append("docs/README.md: `%s` has more than one row" % name)
        rows[name] = strip_markup(m.group(4))

    for path in docs:
        rel = path.relative_to(REPO).as_posix()
        text = path.read_text()
        word, block = status_word(text)

        if word is None:
            problems.append("%s: no status line opening with one of %s -- the "
                            "first block reads %r"
                            % (rel, " / ".join(STATUS_WORDS),
                               block.strip().replace("\n", " ")[:70]))
        elif verbose:
            print("  %-42s %s" % (rel, word))

        row = rows.get(path.name)
        if row is None:
            problems.append("%s: no row in docs/README.md" % rel)
        elif word is not None and word not in row:
            problems.append("%s: status line says %r, its index row says %r"
                            % (rel, word, row[:60]))

        for target in targets(text):
            if target in KNOWN_ABSENT:
                continue
            if not resolves(target, path):
                problems.append("%s: %r does not resolve" % (rel, target))

        for pattern in DATED:
            for m in pattern.finditer(text):
                line = text[:m.start()].count("\n") + 1
                problems.append("%s:%d: dated correction block: %r"
                                % (rel, line, m.group(0).strip()[:60]))

    for name in rows:
        if not (DOCS / name).exists():
            problems.append("docs/README.md: a row for `%s`, which does not exist"
                            % name)

    print("docs: %d documents, %d index rows" % (len(docs), len(rows)))
    if problems:
        print("\n%d problem(s):" % len(problems))
        for p in problems:
            print("  " + p)
        return 1
    print("docs OK: every document has a status line and a row, the words agree, "
          "and every reference resolves")
    return 0


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(
        description="Check the docs/ contract: status lines, the index, links.")
    ap.add_argument("--check", action="store_true",
                    help="the same check (CI spells it this way)")
    ap.add_argument("-v", "--verbose", action="store_true",
                    help="print each document and its status word")
    args = ap.parse_args(argv)
    return check(args.verbose)


if __name__ == "__main__":
    sys.exit(main())
