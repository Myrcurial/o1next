#!/usr/bin/env python3
"""One part number for the interposer: RP2354B.

The interposer carries the **bare RP2354B** — the 48-GPIO, 2 MB-flash B part, on
a custom PCB.  Not a Pico module, not the A part, not the B-less RP2354.  This is
the guard that keeps it that way (#247, T3/W0).

Why a guard rather than a promise: the vocabulary drifted once already.  The board
was designed around a **radio-bearing module** — whose 26 exposed GPIO are the
reason the Rev 0 probe needed a '165 shift-register front end — and the tree kept
saying so for weeks after the module was dropped: "Pico 2 W", "RP2350",
"RP2350B", "CYW43439", "RP2354".  Every one of those spellings is plausible,
which is exactly why a wrong part number survives review.

Forbidden, in every scanned file:

    RP2350        the A part, and the bare family name — the B part has the GPIO
    RP2350B       a real part, but not ours: RP2354**B** is the one with flash
    RP2354        imprecise — the B part's 2 MB flash is the point of the B
    Pico 2        the module, in any spelling ("Pico 2", "Pico 2 W")
    Pico W        the older module

The bare word "Pico" is deliberately **not** forbidden.  It survives as shorthand
for the interposer's MCU — "the Pico serves the ROM window" — in 39 places across
17 files, and a guard that forbade it would fire on the prior art, on PicoEm and
on PicoDVI, which are other people's projects.

Exempt, and why.  This list is the whole argument; do not grow it silently:

    docs/interposer-survey.md     research on OTHER PEOPLE'S projects.  Their
                                  MCUs are RP2040 and Pico W, and a blanket
                                  replace corrupts the survey.
    site/compendium/prior-art.md  its generated mirror, so it inherits the above.
    hardware/interposer/rev0/**   the superseded, never-built probe.  It records
                                  the module it was designed around, and that
                                  module's 26 GPIO are the reason the production
                                  board uses the bare part — rewriting the record
                                  would destroy the argument.
    research/**                   an archive of other people's material (manuals,
                                  magazine OCR, disk images), not our vocabulary.
    .git/ .venv/ node_modules/    not source.

Two more files are exempt because their *purpose* is to name the wrong spellings:

    tools/check_part_numbers.py     this file — it lists what is forbidden
    .github/workflows/part-numbers.yml  its workflow, for the same reason
    tools/README.md                 its documentation — a rule has to be able to
                                    state itself

Binaries are skipped by content (a NUL byte), so an archived PDF or a
`boot-animation.bin` cannot trip the guard.

Usage:
    tools/check_part_numbers.py            # scan, exit 1 on a violation
    tools/check_part_numbers.py --check    # the same check (CI spells it this way)
    tools/check_part_numbers.py --quiet    # only the exit status

Standard library only, and no host tooling.
"""
import argparse
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent

# name -> what to look for.  Case-sensitive on purpose: the schematic symbols are
# `PICO2W` / `PICO_2` and they describe the 40-pin symbol's pin map, which is a
# hardware change to fix, not a rename.
RULES = [
    ("RP2350", re.compile(r"RP2350(?!B)")),
    ("RP2350B", re.compile(r"RP2350B")),
    ("RP2354", re.compile(r"RP2354(?!B)")),
    ("Pico 2", re.compile(r"Pico 2")),
    ("Pico W", re.compile(r"Pico W")),
]

EXEMPT_FILES = {
    "docs/interposer-survey.md",
    "site/compendium/prior-art.md",
    # These name the forbidden spellings on purpose -- that is their job.
    "tools/check_part_numbers.py",
    ".github/workflows/part-numbers.yml",
    "tools/README.md",
}

EXEMPT_DIRS = (
    "research",
    "hardware/interposer/rev0",
)

SKIP_DIRS = {".git", ".venv", "node_modules", "__pycache__",
             # Generated build output, the same category as .venv: a Pico SDK
             # build tree and a Rust target/ are full of the third party's own
             # vocabulary, and neither is tracked.  (firmware/*/build/ and
             # tools/picoem-bridge/target/ -- #286.)
             "build", "target"}

MAX_BYTES = 2 * 1024 * 1024


def is_exempt(rel: str) -> bool:
    if rel in EXEMPT_FILES:
        return True
    return any(rel.startswith(d + "/") for d in EXEMPT_DIRS)


def candidates():
    """Every tracked-looking text file, as (path, repo-relative posix path)."""
    for p in sorted(REPO.rglob("*")):
        if not p.is_file():
            continue
        try:
            rel = p.relative_to(REPO).as_posix()
        except ValueError:
            continue
        if any(part in SKIP_DIRS for part in Path(rel).parts):
            continue
        if is_exempt(rel):
            continue
        try:
            if p.stat().st_size > MAX_BYTES:
                continue
            data = p.read_bytes()
        except OSError:
            continue
        if b"\x00" in data:
            continue
        yield rel, data.decode("utf-8", errors="replace")


def scan():
    violations = []
    for rel, body in candidates():
        for lineno, line in enumerate(body.splitlines(), 1):
            for name, rx in RULES:
                m = rx.search(line)
                if m:
                    violations.append((rel, lineno, name, m.group(0), line.strip()))
    return violations


def main(argv=None):
    ap = argparse.ArgumentParser(
        description="Guard the interposer's part number — RP2354B (#247).")
    ap.add_argument("--check", action="store_true",
                    help="the CI spelling; the default is the same check")
    ap.add_argument("--quiet", action="store_true", help="only the exit status")
    args = ap.parse_args(argv)

    violations = scan()
    if not violations:
        if not args.quiet:
            print("part numbers OK: the interposer is RP2354B, and no Pico "
                  "module is claimed")
        return 0

    for rel, lineno, name, got, line in violations:
        print(f"{rel}:{lineno}: {name!r} found as {got!r}", file=sys.stderr)
        print(f"    {line[:120]}", file=sys.stderr)
    print(f"\n{len(violations)} forbidden part-number mention(s).", file=sys.stderr)
    print("The interposer is RP2354B — the 48-GPIO, 2 MB-flash B part on a custom "
          "PCB. Write it that\nway, or add a documented exemption in this file if "
          "the text is about someone else's\nproject or a superseded record.",
          file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
