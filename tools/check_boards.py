#!/usr/bin/env python3
"""The board register, and the places that have to agree with it (#308).

Why this exists
---------------
The boards were named three ways in three places, and none was derivable from
another: `hardware/README.md` listed seven folders, `site/hardware/index.md`
listed a different set under different names, and `tools/check_schematics.py`
covered three boards -- while the folders themselves were named after neither
(`wifi-modem-module/` held the `O1NEXT WiFi COMM PAC`).  The site is what the
world reads, so the drift was visible to everyone.

The rule now: **the shortform is the board's name**, and it is the folder, the
site URL and the checker's board id.  `hardware/README.md`'s register is the one
table.  This is the check that keeps it that way.  It fails when:

  * a board's ``Home`` is neither a directory named after its shortform nor the
    words "no directory" plus the issue that will make one;
  * a board with no schematic does not say so, or does not name the issue;
  * the register gives a board a schematic that `tools/check_schematics.py` does
    not check, that tool checks a board the register does not list, or a board id
    does not belong to a shortform;
  * a ``.kicad_sch`` in the tree belongs to no checked board;
  * a part of `interposer-upgrade` (it is one unit in four parts) has no home;
  * a folder under `hardware/` is not a board's home;
  * `site/hardware/index.md` presents a different set of boards, in a different
    order, or under a URL that is not ``/hardware/<shortform>/``.

Standard library only, and no `kicad-cli`: it imports the board *list* from
`tools/check_schematics.py`, it does not run the netlist checks.  The names are
the maintainer's, from the 2026-10-19 board list on #308.

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


def cells(row: str) -> list:
    return [c.strip() for c in row.strip().strip("|").split("|")]


def table(header: str, ncols: int) -> list:
    """The rows of the markdown table whose header line starts with *header*."""
    lines = REGISTER.read_text(errors="replace").splitlines()
    rows = []
    for i, line in enumerate(lines):
        if not line.startswith(header):
            continue
        for row in lines[i + 2:]:                  # past the header and the ---
            if not row.startswith("|"):
                break
            row = cells(row)
            if len(row) >= ncols:
                rows.append(row)
        break
    return rows


def parse_register() -> list:
    """Shortform | Board | Home | Tracking issues | State | Schematic."""
    return [{"shortform": strip_markup(r[0]), "board": strip_markup(r[1]),
             "home": r[2], "state": r[4],
             "schematic": re.findall(r"`([^`]+)`", r[5])}
            for r in table("| Shortform |", 6)]


def parse_parts() -> list:
    """The `interposer-upgrade` parts table: Part | Home."""
    return [{"part": strip_markup(r[0]), "home": r[1]}
            for r in table("| Part |", 2)]


def parse_site() -> list:
    """(board name, link target) for each row of the site's board table.

    Read with regexes rather than split on ``|``, because the link carries
    ``{{ ... | relative_url }}`` and that pipe is not a column boundary.
    """
    lines = SITE_INDEX.read_text(errors="replace").splitlines()
    rows, in_table = [], False
    for line in lines:
        if line.startswith("| Board |"):
            in_table = True
            continue
        if not in_table:
            continue
        if not line.startswith("|"):
            break
        m = re.match(r"\|\s*\[([^\]]*)\]\(\{\{\s*'([^']*)'", line)
        if m:
            rows.append((strip_markup(m.group(1)), m.group(2)))
    return rows


def home_failure(what: str, home: str, need_issue: bool) -> str:
    """A board/part home must be a directory, or say why it is not."""
    path = re.search(r"`([^`]+)`", home)
    if path:
        if not (REPO / path.group(1)).is_dir():
            return f"{what}: home {path.group(1)} is not a directory"
        return ""
    if "no directory" not in home.lower():
        return (f"{what}: home is neither a path nor 'no directory yet' + the "
                f"issue that makes one")
    if need_issue and not re.search(r"#\d+", home):
        return f"{what}: has no directory, but no issue is named to make one"
    return ""


def check() -> list:
    failures = []

    boards = parse_register()
    if not boards:
        return [f"no board register found in {REGISTER.relative_to(REPO)}"]

    for b in boards:
        # -- a home named after the shortform ------------------------------
        fail = home_failure(b["shortform"], b["home"], need_issue=True)
        if fail:
            failures.append(fail)
        elif (REPO / f"hardware/{b['shortform']}").is_dir():
            want = f"`hardware/{b['shortform']}/`"
            if b["home"] != want:
                failures.append(f"{b['shortform']}: home {b['home']} is not the "
                                f"board's own folder {want}")

        # -- a board with no schematic says so, and names the issue --------
        if not b["schematic"]:
            if "no schematic" not in b["state"].lower():
                failures.append(f"{b['shortform']}: no schematic listed, and the "
                                f"state does not say so")
            elif not re.search(r"#\d+", b["state"]):
                failures.append(f"{b['shortform']}: no schematic listed, and no "
                                f"issue is named to make one")

    # -- the parts of the one unit -----------------------------------------
    parts = parse_parts()
    if not parts:
        failures.append("the register no longer lists the parts of "
                        "interposer-upgrade")
    for p in parts:
        fail = home_failure(p["part"], p["home"], need_issue=False)
        if fail:
            failures.append(fail)

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
    shortforms = {b["shortform"] for b in boards}
    for name in sorted(covered):
        if not any(name == s or name.startswith(s + "-") for s in shortforms):
            failures.append(f"the netlist checker's board {name!r} does not "
                            f"belong to any shortform")

    # -- and no schematic in the tree is left unchecked --------------------
    checked_dirs = {b.sch.parent for b in check_schematics.BOARDS}
    for sch in sorted((REPO / "hardware").rglob("*.kicad_sch")):
        if sch.parent not in checked_dirs:
            failures.append(f"{sch.relative_to(REPO)} belongs to no board in "
                            f"tools/check_schematics.py")

    # -- no stray folders: every folder under hardware/ is a board ---------
    homes = {b["home"].strip("`") for b in boards}
    for d in sorted(p for p in (REPO / "hardware").iterdir() if p.is_dir()):
        if f"{d.relative_to(REPO)}/" not in homes:
            failures.append(f"hardware/{d.name}/ is not a board's home — a "
                            f"board is named once, in the register")

    # -- the site presents the same set, in the same order, at the same URLs
    site = parse_site()
    if not site:
        failures.append(f"no board table found in {SITE_INDEX.relative_to(REPO)}")
    else:
        here = [b["shortform"] for b in boards]
        names = [n for n, _ in site]
        for name in here:
            if name not in names:
                failures.append(f"{name!r} is in the register but not on the site")
        for name in names:
            if name not in here:
                failures.append(f"{name!r} is on the site but not in the register")
        if [n for n in names if n in here] != [n for n in here if n in names]:
            failures.append("the register and the site list the same boards in a "
                            "different order")
        for name, url in site:
            if name in here and url != f"/hardware/{name}/":
                failures.append(f"the site links {name!r} at {url!r}, but the "
                                f"board's folder and URL are /hardware/{name}/")
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
            print(f"  {b['shortform']:20} {b['board']}\n"
                  f"      home: {b['home']}\n"
                  f"      schematic: {b['schematic'] or ['(none yet)']}")
        for p in parse_parts():
            print(f"  part: {p['part']}  ->  {p['home']}")

    failures = check()
    print(f"{'FAIL' if failures else 'PASS'}  board register "
          f"({len(boards)} boards, {REGISTER.relative_to(REPO)})")
    for f in failures:
        print(f"    {f}")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
