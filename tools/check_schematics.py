#!/usr/bin/env python3
"""Netlist regression checks for the o1next KiCad schematics.

Why this exists
---------------
A schematic can pass structural ERC and still be electrically wrong.  The
interposer generators placed every symbol pin at ``y + py`` where KiCad needs
``y - py`` (symbol geometry is Y-up, the sheet is Y-down), so each wire stub
and net label attached to the *mirror-image* pin; and in reva a '595 sat
directly on top of a '165, shorting GND to A3.  ERC reported only
``label_dangling`` and ``pin_not_connected`` -- nothing that named the real
fault.  The only thing that exposed either bug was exporting the netlist and
reading the node lists pin by pin.

So: this tool regenerates each board's netlist with ``kicad-cli`` and asserts
the electrical invariants the design depends on -- which pin is on which net,
what a connector must and must not carry, and that no two symbols or labels
collide on the sheet.

Usage
-----
    python3 tools/check_schematics.py              # all boards
    python3 tools/check_schematics.py --board reva # one board
    python3 tools/check_schematics.py -v           # list every net checked

Requires ``kicad-cli`` (KiCad 7 or newer).  Set ``KICAD_CLI`` or pass
``--kicad-cli`` if it is not on PATH.  Standard library only -- no deps.

Exit status: 0 = every check passed, 1 = at least one failed.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent

# KiCad stores symbol geometry with Y up and the sheet with Y down, so a pin
# declared at symbol-local (px, py) lands at sheet (x + px, y - py).  Every
# generator in this repo must use that convention; the checks below assume it.


# --------------------------------------------------------------------------
# s-expression reader (KiCad netlist and schematic are both s-expressions)
# --------------------------------------------------------------------------
_TOKEN = re.compile(r'\(|\)|"(?:[^"\\]|\\.)*"|[^\s()]+')


def sexpr(text: str):
    """Parse the first s-expression in *text* into nested lists of strings."""
    toks = _TOKEN.findall(text)
    pos = 0

    def read():
        nonlocal pos
        tok = toks[pos]
        pos += 1
        if tok == "(":
            out = []
            while toks[pos] != ")":
                out.append(read())
            pos += 1
            return out
        return tok[1:-1] if tok.startswith('"') else tok

    return read()


def _kids(node, key):
    return [c for c in node[1:] if isinstance(c, list) and c and c[0] == key]


def _kid(node, key):
    for c in node[1:]:
        if isinstance(c, list) and c and c[0] == key:
            return c
    return None


def _val(node, key):
    for c in node[1:]:
        if isinstance(c, list) and c and c[0] == key:
            return c[1]
    return None


def normalise_net(name: str) -> str:
    """Netlist names carry the sheet path: label ``/WR`` on the root sheet
    exports as ``//WR`` (escaped ``/{slash}WR``), label ``A0`` as ``/A0``.
    Strip exactly one leading slash to recover the label as drawn."""
    name = name.replace("{slash}", "/")
    return name[1:] if name.startswith("/") else name


def parse_netlist(path: Path) -> dict:
    """{(ref, pin)} keyed by normalised net name."""
    root = sexpr(path.read_text(errors="replace"))
    nets: dict = {}
    stack = [root]
    while stack:
        node = stack.pop()
        if not isinstance(node, list):
            continue
        if node and node[0] == "net":
            name = _val(node, "name")
            if name:
                nodes = set()
                for n in _kids(node, "node"):
                    ref, pin = _val(n, "ref"), _val(n, "pin")
                    if ref and pin:
                        nodes.add((ref, pin))
                nets.setdefault(normalise_net(name), set()).update(nodes)
        stack.extend(c for c in node if isinstance(c, list))
    return nets


# --------------------------------------------------------------------------
# schematic geometry (symbol bodies and net labels)
# --------------------------------------------------------------------------
def parse_sheet(path: Path):
    """Return (placed_symbols, labels).

    placed_symbols: list of (lib_id, x, y, half_w, half_h)
    labels:         list of (name, x, y)
    """
    root = sexpr(path.read_text(errors="replace"))

    # body extents per library symbol, from the embedded lib_symbols block
    extents: dict = {}
    for blk in _kids(root, "lib_symbols"):
        for sym in _kids(blk, "symbol"):
            lib_id = sym[1]
            for unit in _kids(sym, "symbol"):
                for rect in _kids(unit, "rectangle"):
                    start, end = _kid(rect, "start"), _kid(rect, "end")
                    if start and end:
                        x1, y1 = float(start[1]), float(start[2])
                        x2, y2 = float(end[1]), float(end[2])
                        extents[lib_id] = (abs(x2 - x1) / 2, abs(y2 - y1) / 2)

    placed, labels = [], []
    for node in root:
        if not isinstance(node, list) or not node:
            continue
        if node[0] == "symbol" and _kids(node, "lib_id"):
            lib_id = _val(node, "lib_id")
            at = _kid(node, "at")
            if lib_id in extents and at:
                hw, hh = extents[lib_id]
                placed.append((lib_id, float(at[1]), float(at[2]), hw, hh))
        elif node[0] == "label":
            at = _kid(node, "at")
            if at:
                labels.append((node[1], float(at[1]), float(at[2])))
    return placed, labels


def find_overlaps(placed):
    """Symbol bodies that overlap -- always a drawing bug, usually a short."""
    hits = []
    for i in range(len(placed)):
        for j in range(i + 1, len(placed)):
            a, b = placed[i], placed[j]
            ox = min(a[1] + a[3], b[1] + b[3]) - max(a[1] - a[3], b[1] - b[3])
            oy = min(a[2] + a[4], b[2] + b[4]) - max(a[2] - a[4], b[2] - b[4])
            if ox > 0 and oy > 0:
                hits.append(f"{a[0]}@({a[1]:g},{a[2]:g}) overlaps "
                            f"{b[0]}@({b[1]:g},{b[2]:g}) by {ox:.2f}x{oy:.2f} mm")
    return hits


def find_label_collisions(labels):
    """Two differently-named labels on the same point means two nets are
    shorted there (this is how the reva '595/'165 pile-up showed up)."""
    by_point: dict = {}
    for name, x, y in labels:
        by_point.setdefault((round(x, 3), round(y, 3)), set()).add(name)
    return [f"labels {sorted(names)} share ({x:g}, {y:g})"
            for (x, y), names in sorted(by_point.items()) if len(names) > 1]


# --------------------------------------------------------------------------
# kicad-cli
# --------------------------------------------------------------------------
def find_kicad_cli(explicit: str | None) -> str:
    for cand in (explicit, os.environ.get("KICAD_CLI")):
        if cand:
            return cand
    found = shutil.which("kicad-cli")
    if found:
        return found
    # macOS app bundle fallback
    mac = Path("/Applications/KiCad/KiCad.app/Contents/MacOS/kicad-cli")
    if mac.exists():
        return str(mac)
    sys.exit("error: kicad-cli not found. Install KiCad, or set KICAD_CLI / "
             "--kicad-cli to its path.")


def run(cmd: list[str], cwd=None) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, capture_output=True, text=True, cwd=cwd)


def regenerate_nets(cli: str, board: Board, tmp: Path):
    """Run the board's generator in a scratch dir and return its netlist.

    The committed .kicad_sch is what gets fabricated, but it is generated, so
    it can silently drift from its generator.  Regenerating and comparing the
    netlists catches that without needing byte-identical output (the generated
    files carry a date and fresh UUIDs).
    """
    gen = REPO / board.gen
    if not gen.exists():
        return None, f"generator {board.gen} not found"
    work = tmp / f"{board.name}-gen"
    work.mkdir(exist_ok=True)
    shutil.copy(gen, work / gen.name)
    proc = run([sys.executable, gen.name], cwd=str(work))
    out = work / board.sch.name
    if not out.exists():
        return None, (f"generator produced no {board.sch.name}: "
                      f"{(proc.stderr or proc.stdout).strip()[:200]}")
    netfile = work / "regenerated.net"
    err = export_netlist(cli, out, netfile)
    if err:
        return None, f"regenerated netlist export failed: {err}"
    return parse_netlist(netfile), ""


def export_netlist(cli: str, sch: Path, out: Path) -> str:
    proc = run([cli, "sch", "export", "netlist", "--output", str(out), str(sch)])
    if not out.exists() or out.stat().st_size == 0:
        return (proc.stdout + proc.stderr).strip() or "netlist export produced no output"
    return ""


ERC_TYPE_ALIASES = {
    # KiCad 9 raises this check as `label_dangling` at error severity; KiCad 10
    # renamed it `isolated_pin_label` and made it a warning.  Same check, same
    # count (11 on reva, 4 on rev0 under both) -- so the budget is keyed on the
    # normalised type only and stays portable across KiCad releases.
    "label_dangling": "isolated_pin_label",
}


def run_erc(cli: str, sch: Path, out: Path):
    """Return (counts_by_type, n_errors, n_total, error_string).

    Counts are keyed by *type only*: KiCad moves both the type names and the
    error/warning split between releases, so a (severity, type) budget would
    pin this gate to a single KiCad version.
    """
    pairs: list = []
    got_json = False
    proc = run([cli, "sch", "erc", "--severity-all", "--format", "json",
                "--output", str(out), str(sch)])
    if out.exists() and out.stat().st_size:
        try:
            data = json.loads(out.read_text())
        except json.JSONDecodeError:
            data = None
        if isinstance(data, dict):
            got_json = True
            for sheet in data.get("sheets", []):
                for v in sheet.get("violations", []):
                    pairs.append((v.get("severity", "?"), v.get("type", "?")))

    if not got_json:
        # KiCad 7 has no --format json; parse the text report instead
        proc = run([cli, "sch", "erc", "--severity-all",
                    "--output", str(out), str(sch)])
        if not out.exists() or not out.stat().st_size:
            return {}, 0, 0, ((proc.stdout + proc.stderr).strip()
                              or "ERC produced no report")
        current = None
        for line in out.read_text(errors="replace").splitlines():
            m = re.match(r"\[([a-z_]+)\]", line.strip())
            if m:
                current = m.group(1)
            m = re.match(r";\s*(error|warning|exclusion)", line.strip())
            if m and current:
                pairs.append((m.group(1), current))
        if not pairs:
            return {}, 0, 0, "could not parse the ERC report"

    counts: dict = {}
    for _, typ in pairs:
        typ = ERC_TYPE_ALIASES.get(typ, typ)
        counts[typ] = counts.get(typ, 0) + 1
    return counts, sum(1 for sev, _ in pairs if sev == "error"), len(pairs), ""


# --------------------------------------------------------------------------
# reference data -- the datasheet / spec facts the schematics must satisfy
# --------------------------------------------------------------------------
# Zilog Z80 (and NEC uPD780C) DIP-40 pinout.  Source: Zilog Z80 Microprocessor
# Family Databook, DIP-40 package; cross-checked against z80.info/zinout.htm
# (6=CLK, 11=+5V, 12=D2, 29=GND, 30=A0, 31=A1, 35=A5).  The Osborne 1 fits a
# standard Z80A-class part (NEC uPD780C) in this socket, so the socket's pin
# numbering *is* the chip's -- docs/o1-memory-io-map.md sec.6, gap #3.
Z80_DIP40 = {
    1: "A11", 2: "A12", 3: "A13", 4: "A14", 5: "A15", 6: "CLK",
    7: "D4", 8: "D3", 9: "D5", 10: "D6", 11: "+5V", 12: "D2", 13: "D7",
    14: "D0", 15: "D1", 16: "/INT", 17: "/NMI", 18: "/HALT", 19: "/MREQ",
    20: "/IORQ", 21: "/RD", 22: "/WR", 23: "/BUSAK", 24: "/WAIT",
    25: "/BUSRQ", 26: "/RESET", 27: "/M1", 28: "/RFSH", 29: "GND", 30: "A0",
    31: "A1", 32: "A2", 33: "A3", 34: "A4", 35: "A5", 36: "A6", 37: "A7",
    38: "A8", 39: "A9", 40: "A10",
}

# Osborne 1 character-generator ROM socket (UA15) -- the second half of gap #3.
# Read at 1200 dpi off sheet 4 of 9 of the OCC1 1A2011-00 Rev E schematic (PDF
# page 7, title block "RAM") on 2026-10-10; the extraction note is
# docs/o1-mainboard-schematic.md sec.4a.  It is a plain Intel 2716 -- the table
# that stood in docs/o1-memory-io-map.md sec.6 before that (A8-A10 on 13-21,
# /OE on 22, /CE on 23) was wrong, which is why the check below exists.
#
# Two entries are board wiring, not chip pins, and they matter to any tap:
#   * /CE (18) and /OE (20) are bussed with GND (12) and grounded, so the ROM
#     is permanently selected and always driving O0-O7.  Substituting font data
#     means intercepting 18 and 20 between socket and ROM -- the ScreenPac
#     personality (#24) only ever *reads* them.
#   * pin 21 is strapped to +5V (it is A11 on a 2732, so the socket is wired
#     for a 4 KiB part even though a 2 KiB 2716 is fitted).
CHARGEN_2716 = {
    1: "A7", 2: "A6", 3: "A5", 4: "A4", 5: "A3", 6: "A2", 7: "A1", 8: "A0",
    9: "O0", 10: "O1", 11: "O2", 12: "GND", 13: "O3", 14: "O4", 15: "O5",
    16: "O6", 17: "O7", 18: "/CE", 19: "A10", 20: "/OE", 21: "+5V", 22: "A9",
    23: "A8", 24: "VCC",
}

# Osborne 1 floppy interface, 34-pin Shugart-like.  Transcribed in
# docs/floppy-adapter-design.md sec.2 and verified 2026-10-10 against FSM
# 2F00040 and DWG 1A3004 (pins 2/4/6 are GND).  Pin 10 is the switched line,
# pin 14 is not connected.
FLOPPY_SIGNALS = {
    1: "GND", 2: "GND", 3: "GND", 4: "GND", 5: "GND", 6: "GND", 7: "GND",
    8: "INDEX", 9: "GND", 10: "DS_A", 11: "+12V", 12: "DS_B", 13: "+12V",
    14: None, 15: "+12V", 16: "4MHZ", 17: "+12V", 18: "DIR", 19: "GND",
    20: "STEP", 21: "+5V", 22: "WDATA", 23: "+5V", 24: "WGATE", 25: "+5V",
    26: "TRK0", 27: "GND", 28: "WPROT", 29: "GND", 30: "RDATA", 31: "GND",
    32: "SIDE", 33: "GND", 34: "LATE",
}


def pins(ref: str, numbers) -> set:
    return {(ref, str(n)) for n in numbers}


class Board:
    """One schematic plus the electrical invariants it must satisfy."""

    def __init__(self, name, sch, gen, erc_allowance, exact_nets=None,
                 contains_nets=None, excludes_nets=None, pin_nets=None,
                 passthrough=None, pinout=None, unused_pins=None,
                 allow_overlaps=0, allow_label_collisions=0):
        self.name = name
        self.sch = REPO / sch
        self.gen = gen
        self.erc_allowance = erc_allowance
        self.exact_nets = exact_nets or {}
        self.contains_nets = contains_nets or {}
        self.excludes_nets = excludes_nets or {}
        self.pin_nets = pin_nets or {}
        self.passthrough = passthrough or []
        self.pinout = pinout or []
        self.unused_pins = unused_pins or {}
        self.allow_overlaps = allow_overlaps
        self.allow_label_collisions = allow_label_collisions


def net_of(nets, ref, pin):
    pin = str(pin)
    for name, nodes in nets.items():
        if (ref, pin) in nodes:
            return name
    return None


# --------------------------------------------------------------------------
# checks
# --------------------------------------------------------------------------
def check_board(cli: str, board: Board, tmp: Path, verbose: bool):
    """Return (failures, notes)."""
    failures, notes = [], []

    if not board.sch.exists():
        return [f"schematic not found at {board.sch}"], []

    netfile = tmp / f"{board.name}.net"
    err = export_netlist(cli, board.sch, netfile)
    if err:
        return [f"netlist export failed: {err}"], []
    nets = parse_netlist(netfile)
    notes.append(f"{len(nets)} nets")

    placed, labels = parse_sheet(board.sch)
    notes.append(f"{len(placed)} symbols, {len(labels)} labels")

    # -- sheet geometry -----------------------------------------------------
    hits = find_overlaps(placed)
    if len(hits) > board.allow_overlaps:
        failures.append(f"overlapping symbol bodies ({len(hits)}):")
        failures += [f"      {h}" for h in hits[:10]]

    hits = find_label_collisions(labels)
    if len(hits) > board.allow_label_collisions:
        failures.append(f"two nets shorted by coincident labels ({len(hits)}):")
        failures += [f"      {h}" for h in hits[:10]]

    # -- netlist ------------------------------------------------------------
    for name, want in sorted(board.exact_nets.items()):
        got = nets.get(name)
        if got is None:
            failures.append(f"net {name!r} is missing from the netlist")
        elif got != want:
            msg = f"net {name!r} is wrong:"
            if want - got:
                msg += f" missing {sorted(want - got)}"
            if got - want:
                msg += f" unexpected {sorted(got - want)}"
            failures.append(msg)

    for name, want in sorted(board.contains_nets.items()):
        missing = sorted(want - nets.get(name, set()))
        if missing:
            failures.append(f"net {name!r} is missing {missing}")

    for name, unwanted in sorted(board.excludes_nets.items()):
        found = sorted(nets.get(name, set()) & unwanted)
        if found:
            failures.append(f"net {name!r} must not carry {found}")

    for (ref, pin), want in sorted(board.pin_nets.items()):
        got = net_of(nets, ref, pin)
        if got != want:
            failures.append(f"{ref}.{pin} is on net {got!r}, expected {want!r}")

    for ref, unused in sorted(board.unused_pins.items()):
        for pin in sorted(unused, key=int):
            got = net_of(nets, ref, pin)
            if got is not None:
                failures.append(f"{ref}.{pin} must be unconnected, but is on {got!r}")

    for a, b, numbers, exceptions in board.passthrough:
        for n in numbers:
            if n in exceptions:
                continue
            na, nb = net_of(nets, a, n), net_of(nets, b, n)
            if na != nb:
                failures.append(f"pass-through broken at pin {n}: "
                                f"{a}.{n} on {na!r} but {b}.{n} on {nb!r}")

    for ref, table in board.pinout:
        for pin, sig in sorted(table.items()):
            if sig is None:
                continue
            # `sig` is the label as drawn; normalise_net() already reduced the
            # netlist's sheet-path-prefixed name back to exactly that label.
            got = net_of(nets, ref, pin)
            if got != sig:
                failures.append(f"{ref}.{pin} is on net {got!r}, "
                                f"expected {sig!r}")

    # -- ERC budget ---------------------------------------------------------
    ercfile = tmp / f"{board.name}.erc.json"
    counts, n_err, n_total, err = run_erc(cli, board.sch, ercfile)
    if err:
        failures.append(f"ERC: {err}")
    else:
        for key in sorted(set(counts) | set(board.erc_allowance)):
            n, limit = counts.get(key, 0), board.erc_allowance.get(key, 0)
            if n > limit:
                failures.append(f"ERC {key}: {n} (allowed {limit})")
        notes.append(f"ERC {n_err} errors / {n_total} violations")

    # -- 'NC' is a sentinel, not a net --------------------------------------
    # Labelling unused pins "NC" ties them all to one net: on reva that joined
    # four unused 74AHCT595 totem-pole outputs, which is output contention.
    # Unused pins get no-connect flags instead (see the floppy generator).
    if "NC" in nets:
        tied = sorted(nets["NC"])
        failures.append(f"a net named 'NC' ties {len(tied)} pins together "
                        f"{tied}; use no-connect flags instead")

    # -- the committed schematic still matches its generator ----------------
    regen, err = regenerate_nets(cli, board, tmp)
    if err:
        failures.append(f"regenerate: {err}")
    elif regen != nets:
        msg = ("the committed .kicad_sch is stale -- regenerating from "
               f"{board.gen} gives a different netlist")
        only_here = sorted(set(nets) - set(regen))
        only_regen = sorted(set(regen) - set(nets))
        differ = sorted(n for n in set(nets) & set(regen) if nets[n] != regen[n])
        if only_here:
            msg += f"; only in the committed file: {only_here[:5]}"
        if only_regen:
            msg += f"; only when regenerated: {only_regen[:5]}"
        if differ:
            msg += f"; nets that differ: {differ[:5]}"
        failures.append(msg)

    return failures, notes


# --------------------------------------------------------------------------
# board specifications
# --------------------------------------------------------------------------
# Osborne 1 floppy adapter (issue #62).  Settled design: DS-A plus the power
# rails are the only switched lines; drive B is never touched; the Gotek gets
# Loxley's 11-line signal subset and switched 5 V only.
FLOPPY = Board(
    name="floppy-adapter",
    sch="hardware/floppy-adapter/floppy-adapter.kicad_sch",
    gen="hardware/floppy-adapter/gen_floppy_adapter_sch.py",
    erc_allowance={"lib_symbol_issues": 12},   # embedded symbols, no sym-lib-table
    exact_nets={
        "FLP_DS_A": {("J1", "10"), ("K1", "8")},
        "FLP_DS_A_PHY": {("J2", "10"), ("K1", "9")},
        "FLP_DS_A_GOTEK": {("J3", "10"), ("K1", "10"), ("R3", "1"), ("R4", "1")},
        "FLP_DS_B": {("J1", "12"), ("J2", "12")},
        "FLP_4MHZ": {("J1", "16"), ("J2", "16")},
        "+12V": pins("J1", (11, 13, 15, 17)) | pins("J2", (11, 13, 15, 17)),
        "+5V_SW": {("J4", "1"), ("K1", "4")},
        "GND_SW": {("J4", "2"), ("J4", "3"), ("K1", "7")},
    },
    excludes_nets={
        # the Gotek header carries signals only -- never a power rail or 4 MHz
        "+12V": pins("J3", range(1, 35)) | pins("J4", range(1, 5)),
        "+5V": pins("J3", range(1, 35)) | pins("J4", range(1, 5)),
        "FLP_4MHZ": pins("J3", range(1, 35)) | pins("J4", range(1, 5)),
    },
    passthrough=[
        # the cable passes straight through except the switched line and NC
        ("J1", "J2", range(1, 35), {10, 14}),
        # and the Gotek header sees the same signal on the same pin number
        ("J1", "J3", {8, 18, 20, 22, 24, 26, 28, 30, 32, 34}, set()),
    ],
    unused_pins={
        # Loxley's 11-line audit: exactly these J3 pins, nothing else
        "J3": set(range(1, 35)) - {8, 10, 18, 20, 22, 24, 26, 28, 30, 32, 34},
        "J4": {4},
    },
)

# Interposer Rev A engineering sample.  J1 plugs into the O1's Z80 socket and
# U1 is the on-board Z84C00, so both must follow the Z80 DIP-40 pinout exactly.
REVA = Board(
    name="reva",
    sch="hardware/interposer/reva/reva.kicad_sch",
    gen="hardware/interposer/reva/gen_reva_sch.py",
    erc_allowance={
        "pin_not_connected": 12,    # genuinely unused pins (U7/U8 /QH, U11 2A2/2Y2,
                                    # Pico RUN/ADC_VREF/3V3_EN/VBUS, ESP IO2/IO8/IO10)
        "isolated_pin_label": 11,   # nets appearing once -- real design gaps
                                    # (/MREQ_DRV, /IORQ_RAW, /Z80_CLK, /ESP_EN, ...)
        "lib_symbol_issues": 28,    # no 'local' entry in sym-lib-table; the symbols
                                    # are embedded, so this is cosmetic
    },
    pinout=[("J1", Z80_DIP40), ("U1", Z80_DIP40)],
    passthrough=[("J1", "U1", range(1, 41), set())],
    exact_nets={
        # the two nets the '595-on-'165 pile-up used to short together
        "A0": {("J1", "30"), ("U1", "30"), ("U3", "15"), ("U6", "11")},
        "A3": {("J1", "33"), ("U1", "33"), ("U3", "3"), ("U6", "14")},
        "SR_MISO": {("U2", "4"), ("U8", "9")},
    },
)

# Interposer Rev 0 (snoop-only test probe).  J1 is the plug, J2 the socket the
# CPU moves into: every pin must pass through unchanged.
REV0 = Board(
    name="rev0",
    sch="hardware/interposer/rev0/rev0.kicad_sch",
    gen="hardware/interposer/rev0/gen_rev0_sch.py",
    erc_allowance={
        "pin_not_connected": 28,    # unused 165 /QH outputs + unassigned Pico GPIOs
                                    # (PICO_NET is preliminary: firmware owns the
                                    # final mapping -- see gen_rev0_sch.py)
        "isolated_pin_label": 4,
        "lib_symbol_issues": 14,    # embedded symbols, no sym-lib-table entry
    },
    pinout=[("J1", Z80_DIP40), ("J2", Z80_DIP40)],
    passthrough=[("J1", "J2", range(1, 41), set())],
)

BOARDS = [FLOPPY, REVA, REV0]


def check_reference_tables() -> list:
    """Check the hand-transcribed pinouts above against their sources.

    A typo in one of these silently weakens every board that uses it, and a
    board check cannot catch it -- the board would be *consistently* wrong, the
    same way the generators were consistently off by one on the Z80.  So the
    tables get their own assertions, and the two sockets gap #3 is about get
    the pin values spelled out.
    """
    failures = []
    for name, table, size in (("Z80_DIP40", Z80_DIP40, 40),
                              ("CHARGEN_2716", CHARGEN_2716, 24)):
        if sorted(table) != list(range(1, size + 1)):
            failures.append(f"{name}: pins are not 1..{size}: {sorted(table)}")
    # Z80 DIP-40, the pins the generators got wrong (docs/o1-mainboard-schematic
    # sec.4): +5V is 11, GND is 29, A0 is 30.
    for pin, sig in ((11, "+5V"), (29, "GND"), (30, "A0"), (40, "A10")):
        if Z80_DIP40.get(pin) != sig:
            failures.append(f"Z80_DIP40.{pin} is {Z80_DIP40.get(pin)!r}, "
                            f"expected {sig!r}")
    # UA15: grounded enables and the 2732-style pin-21 strap, per sec.4a.
    for pin, sig in ((12, "GND"), (18, "/CE"), (20, "/OE"), (21, "+5V"),
                     (24, "VCC")):
        if CHARGEN_2716.get(pin) != sig:
            failures.append(f"CHARGEN_2716.{pin} is {CHARGEN_2716.get(pin)!r}, "
                            f"expected {sig!r}")
    return failures


def main() -> int:
    ap = argparse.ArgumentParser(
        description="Netlist regression checks for the o1next schematics.")
    ap.add_argument("--board", action="append", metavar="NAME",
                    help="only check this board (repeatable)")
    ap.add_argument("--kicad-cli", metavar="PATH", help="path to kicad-cli")
    ap.add_argument("-v", "--verbose", action="store_true")
    args = ap.parse_args()

    # The reference tables are checked before KiCad is even looked for: a typo
    # in one of them is the failure mode this tool exists to catch, and it
    # should not need a working kicad-cli to surface.
    ref_failures = check_reference_tables()
    print(f"{'FAIL' if ref_failures else 'PASS'}  reference pinout tables"
          f"  (Z80 DIP-40, UA15 2716)")
    for f in ref_failures:
        print(f"    {f}")

    cli = find_kicad_cli(args.kicad_cli)
    print(f"kicad-cli: {run([cli, '--version']).stdout.strip() or cli}")

    wanted = [b for b in BOARDS if not args.board or b.name in args.board]
    if not wanted:
        return int(bool(sys.stderr.write(
            f"error: no such board; known: {[b.name for b in BOARDS]}\n")) or 2)

    failed = 0
    with tempfile.TemporaryDirectory() as td:
        tmp = Path(td)
        for board in wanted:
            failures, notes = check_board(cli, board, tmp, args.verbose)
            print(f"\n{'FAIL' if failures else 'PASS'}  {board.name}"
                  f"  ({'; '.join(notes)})")
            for f in failures:
                print(f"    {f}")
            failed += bool(failures)

    print()
    if failed:
        print(f"{failed} of {len(wanted)} board(s) FAILED")
    if failed or ref_failures:
        return 1
    print(f"all {len(wanted)} board(s) passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())



