#!/usr/bin/env python3
"""The board register, and the two places that have to agree with it (#308).

Why this exists
---------------
`Rev A` / `Rev B` / `Rev 0` named four unrelated things in this tree, and the
boards themselves were named three different ways in three different places:
`hardware/README.md` listed seven folders, `site/hardware/index.md` listed a
different set under different names, and `tools/check_schematics.py` covered
three boards.  None of the three was derivable from another -- and the site is
what the world reads.

So `hardware/README.md`'s board register is the single table, and this is the
check that keeps it single.  It fails when:

  * a board's ``Home`` is neither a directory that exists nor the words
    "no directory" plus the issue that will make one;
  * a board with no schematic does not say so, or does not name the issue;
  * the register gives a board a schematic that `tools/check_schematics.py`
    does not check, or that tool checks a board the register does not list;
  * a ``.kicad_sch`` in the tree belongs to no checked board;
  * `site/hardware/index.md` presents a different set of boards, or the same
    set in a different order.

Standard library only, and no `kicad-cli`: it imports the board *list* from
`tools/check_schematics.py`, it does not run the netlist checks.  The names on
both sides are the maintainer's, from the 2026-10-19 board list on #308.

Usage
-----
    python3 tools/check_boards.py            # check
    python3 tools/check_boards.py -v         # also print what it parsed

Exit status: 0 = everything agrees, 1 = at least one thing does not.
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
REGISTER = REPO / "hardware" / "README.md"
SITE_INDEX = REPO / "site" / "hardware" / "index.md"

MARKUP = re.compile(r"[*`]")


def strip_markup(text: str) -> str:
    """``[**O1NEXT Upgrade**](url)`` -> ``O1NEXT Upgrade``."""
    text = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", text)
    return MARKUP.sub("", text).strip()


def board_name(cell: str) -> str:
    """The board's name, from a register cell or a site link.

    A cell may gloss the name after an em dash (``**O1NEXT Upgrade** — the
    interposer``); the name is what comes before it.
    """
    return strip_markup(cell.split("\u2014")[0]).strip()


def parse_register() -> list:
    """The register's rows, from the markdown table headed ``| Home |``."""
    lines = REGISTER.read_text(errors="replace").splitlines()
    boards = []
    for i, line in enumerate(lines):
        if not (line.startswith("|") and "| Home |" in line):
            continue
        for row in lines[i + 2:]:              # past the header and the ---
            if not row.startswith("|"):
                break
            cells = [c.strip() for c in row.strip().strip("|").split("|")]
            if len(cells) < 5:
                continue
            boards.append({
                "name": board_name(cells[0]),
                "home": cells[1],
                "state": cells[3],
                "schematic": re.findall(r"`([^`]+)`", cells[4]),
            })
        break
    return boards


def parse_site() -> list:
    """The board names in ``site/hardware/index.md``'s board table.

    The row is read with a regex rather than split on ``|``, because the cell's
    link carries ``{{ ... | relative_url }}`` and that pipe is not a column
    boundary.
    """
    lines = SITE_INDEX.read_text(errors="replace").splitlines()
    names, in_table = [], False
    for line in lines:
        if line.startswith("| Board |"):
            in_table = True
            continue
        if not in_table:
            continue
        if not line.startswith("|"):
            break
        m = re.match(r"\|\s*\[([^\]]*)\]", line)
        if m:
            names.append(board_name(m.group(1)))
    return names


def check() -> list:
    failures = []

    boards = parse_register()
    if not boards:
        return [f"no board table found in {REGISTER.relative_to(REPO)}"]

    for b in boards:
        # -- a home, or a stated absence with the issue that fixes it -------
        path = re.search(r"`([^`]+)`", b["home"])
        if path:
            if not (REPO / path.group(1)).is_dir():
                failures.append(f"{b['name']}: home {path.group(1)} is not a "
                                f"directory")
        elif "no directory" not in b["home"].lower():
            failures.append(f"{b['name']}: home is neither a path nor "
                            f"'no directory yet' + the issue that makes one")
        elif not re.search(r"#\d+", b["home"]):
            failures.append(f"{b['name']}: has no directory, but no issue is "
                            f"named to make one")

        # -- a board with no schematic says so, and names the issue ---------
        if not b["schematic"]:
            if "no schematic" not in b["state"].lower():
                failures.append(f"{b['name']}: no schematic listed, and the state "
                                f"does not say so")
            elif not re.search(r"#\d+", b["state"]):
                failures.append(f"{b['name']}: no schematic listed, and no issue "
                                f"is named to make one")

    # -- the netlist checker covers exactly the boards with a schematic ----
    sys.path.insert(0, str(REPO / "tools"))
    import check_schematics

    covered = {b.name for b in check_schematics.BOARDS}
    listed = {n for b in boards for n in b["schematic"]}
    for name in sorted(listed - covered):
        failures.append(f"the register gives {name!r} a schematic, but "
                        f"tools/check_schematics.py has no such board")
    for name in sorted(covered - listed):
        failures.append(f"tools/check_schematics.py checks {name!r}, which the "
                        f"register does not give a schematic")

    # -- and no schematic in the tree is left unchecked --------------------
    checked_dirs = {b.sch.parent for b in check_schematics.BOARDS}
    for sch in sorted((REPO / "hardware").rglob("*.kicad_sch")):
        if sch.parent not in checked_dirs:
            failures.append(f"{sch.relative_to(REPO)} belongs to no board in "
                            f"tools/check_schematics.py")

    # -- the site presents the same set, in the same order -----------------
    site = parse_site()
    if not site:
        failures.append(f"no board table found in {SITE_INDEX.relative_to(REPO)}")
    else:
        here = [b["name"] for b in boards]
        for name in here:
            if name not in site:
                failures.append(f"{name!r} is in the register but not on the site")
        for name in site:
            if name not in here:
                failures.append(f"{name!r} is on the site but not in the register")
        shared = [n for n in site if n in here]
        if shared != [n for n in here if n in site]:
            failures.append("the register and the site list the same boards in a "
                            "different order")
    return failures


def main() -> int:
    ap = argparse.ArgumentParser(
        description="Check that the board register, the netlist checker and "
                    "site/hardware/ name the same boards.")
    ap.add_argument("-v", "--verbose", action="store_true",
                    help="print what was parsed")
    args = ap.parse_args()

    boards = parse_register()
    if args.verbose:
        for b in boards:
            print(f"  {b['name']}\n      home: {b['home']}\n"
                  f"      schematic: {b['schematic'] or ['(none yet)']}")

    failures = check()
    print(f"{'FAIL' if failures else 'PASS'}  board register "
          f"({len(boards)} boards, {REGISTER.relative_to(REPO)})")
    for f in failures:
        print(f"    {f}")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
