#!/usr/bin/env python3
"""Generate the firmware ROM-identity table from docs/o1-rom-variants.md (#86).

Why this exists
---------------
The interposer sits in the Z80 socket, so it can read the fitted monitor ROM and
identify it by CRC32 -- and some personalities are only valid with some ROMs
(Drive C and the virtual printer both need the ROM's IEEE-488 driver, which
OZROM 1E does not have).  That means the firmware needs a ROM table, and the
table has to agree with what the documentation says we hold.

Two copies of that knowledge would drift, so there is one: the document.  This
tool parses the CRC rows out of ``docs/o1-rom-variants.md``, then *recomputes*
the CRC of every file the row names and refuses to proceed if the bytes and the
document disagree.  That is the document's own identification rule -- two
independent sources agreeing on a CRC -- applied mechanically.

The capability flags (IEEE-488 driver, video window size) are not derivable from
the CRC, so they are curated below, keyed by CRC, and cross-checked against the
parsed rows: a ROM in one and not the other is an error.

Usage
-----
    python3 tools/gen_rom_table.py            # write the generated files
    python3 tools/gen_rom_table.py --check    # fail if they are stale (CI)
    python3 tools/gen_rom_table.py -v         # list every ROM as it is verified

Standard library only.  Exit status: 0 = ok, 1 = verification or drift failure.
"""
from __future__ import annotations

import argparse
import re
import sys
import zlib
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
DOC = REPO / "docs" / "o1-rom-variants.md"
OUT_DIR = REPO / "firmware" / "rom-ident"
OUT_H = OUT_DIR / "rom_table.h"
OUT_C = OUT_DIR / "rom_table.c"

# Curated properties, keyed by CRC32, because none of this is in the CRC.
#
# Every flag is justified in docs/o1-rom-variants.md section "Personality-
# relevant properties", with the evidence (manual text or the bytes at the
# vector table).  The values here are the machine-readable form of that section;
# the CRC set is cross-checked against the parsed rows below, so a ROM added to
# one and not the other fails the build.
#
#   slug        -> C enum suffix and the name used in gate messages
#   kind        -> which socket/role the image is for
#   socket      -> where it is fitted
#   ieee488     -> PRESENT / ABSENT / UNKNOWN: does the ROM carry the IEEE-488
#                  driver?  UNKNOWN means "we have not verified it", and the
#                  gate treats that as unusable rather than assuming good.
#   video_kb    -> video window size in KiB, 0 = unknown
PROPERTIES = {
    # stock OCC monitor ROMs, UD11
    "3d966335": ("OCC_14", "MONITOR", "UD11", "PRESENT", 4),
    "91a48e3c": ("OCC_143", "MONITOR", "UD11", "PRESENT", 4),
    "c0596b14": ("OCC_144", "MONITOR", "UD11", "PRESENT", 4),
    # third-party monitor ROMs, UD11
    "ba1f6131": ("OZROM_1E", "MONITOR", "UD11", "ABSENT", 3),
    "298da402": ("NUEVO_151", "MONITOR", "UD11", "UNKNOWN", 0),
    # the 2732->2764 daughterboard image: which half is live depends on A12
    "edc31846": ("OCC_144_PLUS_OZROM", "COMBINED", "UD11", "UNKNOWN", 0),
    # character generators, UA15
    "5297c109": ("CHARGEN_EARLY", "CHARGEN", "UA15", "UNKNOWN", 0),
    "6c1eab0d": ("CHARGEN_LATE", "CHARGEN", "UA15", "UNKNOWN", 0),
    # not a Z80 monitor ROM at all: the SWP co-processor board's 8088 firmware
    "948556db": ("SWP_P88", "COPROCESSOR", "NONE", "UNKNOWN", 0),
}

CRC_RE = re.compile(r"`([0-9a-f]{8})`")
TOKEN_RE = re.compile(r"`([^`]+)`")
PATH_RE = re.compile(r"^(?:research|tools)/")
SIZE_RE = re.compile(r"^(\d+)\s*KiB$")
UNDUMPED_RE = re.compile(r"NO_DUMP")

# --------------------------------------------------------------------------
# parse the document
# --------------------------------------------------------------------------

def strip_markdown(text):
    """Turn a table cell into a plain name (drop emphasis and code markers)."""
    text = re.sub(r"\*\*(.+?)\*\*", r"\1", text)
    text = re.sub(r"\*(.+?)\*", r"\1", text)
    return text.replace("`", "").strip()


def parse_doc(text):
    """Return the identity rows in *text*, plus the revisions that are undumped.

    An identity row is a table row carrying exactly one backticked 8-hex CRC.
    That is the discriminator: the socket list, the "one image, five names"
    table and the MAME cross-reference carry no CRC, while the rows for BIOS
    revisions that have never been dumped carry an em dash in the CRC column.
    """
    rows = []
    undumped = []
    section = ""
    for line in text.splitlines():
        if line.startswith("## "):
            section = line[3:].strip()
        if not line.startswith("|") or set(line) <= set("|- "):
            continue
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        tokens = TOKEN_RE.findall(line)
        crcs = [t for t in tokens if re.fullmatch(r"[0-9a-f]{8}", t)]
        if not crcs:
            # The stock table's NO_DUMP rows are revisions that exist but have
            # never been dumped -- worth naming in the header, because a machine
            # fitted with one cannot be identified at all.  Other tables mention
            # NO_DUMP in passing (the MAME cross-reference), so scope this to the
            # stock monitor table rather than matching the string anywhere.
            if UNDUMPED_RE.search(line) and "monitor ROM" in section:
                undumped.append(strip_markdown(cells[0]))
            continue
        if len(crcs) != 1:
            raise SystemExit(f"{DOC.name}: {len(crcs)} CRCs in one row: {line.strip()}")
        rows.append({
            "section": section,
            "name": strip_markdown(cells[0]),
            "crc": crcs[0],
            "sizes": [int(SIZE_RE.match(c).group(1)) * 1024
                      for c in cells if SIZE_RE.match(c)],
            "sources": [t for t in tokens if PATH_RE.match(t)],
        })
    if not rows:
        raise SystemExit(f"{DOC.name}: no ROM identity rows found -- has the "
                         f"table format changed?")
    return rows, undumped


def verify(rows, verbose):
    """Recompute every CRC from the bytes; refuse to continue on any mismatch.

    This is the document's own rule -- two independent sources agreeing on a CRC
    is positive identification -- applied mechanically.  A row citing several
    copies of one image (the late character generator has five names) must have
    all of them agree.
    """
    for row in rows:
        sizes = set(row["sizes"])
        for src in row["sources"]:
            path = REPO / src
            if not path.exists():
                raise SystemExit(f"{DOC.name}: {row['name']}: cited file is "
                                 f"missing: {src}")
            data = path.read_bytes()
            crc = "%08x" % zlib.crc32(data)
            if crc != row["crc"]:
                raise SystemExit(
                    f"{DOC.name}: {row['name']}: CRC mismatch\n"
                    f"  document says {row['crc']}\n"
                    f"  {src} is    {crc}  ({len(data)} bytes)")
            sizes.add(len(data))
            if verbose:
                print(f"  {crc}  {len(data):6d}  {src}")
        if not sizes:
            raise SystemExit(f"{DOC.name}: {row['name']}: no size -- the row has "
                             f"no copy and no Size column")
        if len(sizes) != 1:
            raise SystemExit(f"{DOC.name}: {row['name']}: size disagreement "
                             f"{sorted(sizes)}")
        row["size"] = sizes.pop()
    return rows


def cross_check(rows):
    """The curated properties and the parsed rows must describe the same ROMs."""
    doc_crcs = {r["crc"] for r in rows}
    prop_crcs = set(PROPERTIES)
    missing = sorted(doc_crcs - prop_crcs)
    extra = sorted(prop_crcs - doc_crcs)
    if missing:
        raise SystemExit("no capability properties for ROM(s) in the document: "
                         + ", ".join(missing))
    if extra:
        raise SystemExit("capability properties for ROM(s) not in the document: "
                         + ", ".join(extra))

# --------------------------------------------------------------------------
# emit the firmware table
# --------------------------------------------------------------------------

KIND_ORDER = ["MONITOR", "CHARGEN", "COPROCESSOR", "COMBINED"]


def render(rows, undumped):
    """Render rom_table.h and rom_table.c as text."""
    rows = sorted(rows, key=lambda r: (KIND_ORDER.index(PROPERTIES[r["crc"]][1]),
                                       r["crc"]))

    h = []
    h.append("/* GENERATED by tools/gen_rom_table.py -- do not edit by hand.\n"
             " *\n"
             " * Source of truth: docs/o1-rom-variants.md (#86).  Every CRC below was\n"
             " * recomputed from the file bytes at generation time and agreed with the\n"
             " * value the document publishes; the capability flags come from that\n"
             " * document's \"Personality-relevant properties\" section.\n"
             " *\n"
             " * `python3 tools/gen_rom_table.py --check` fails if this file drifts from\n"
             " * the document or from the archive.\n"
             " *\n"
             " * The table is complete only for images we hold.  These BIOS revisions\n"
             " * have never been dumped, so a machine fitted with one is reported as\n"
             " * O1_ROM_UNKNOWN and cannot be gated on: "
             + (", ".join(undumped) if undumped else "(none recorded)") + ".\n"
             " */\n")
    h.append("#ifndef O1_ROM_TABLE_H\n#define O1_ROM_TABLE_H\n\n"
             "#include <stddef.h>\n#include <stdint.h>\n\n")
    h.append("/* Identity of a ROM image, keyed by (CRC32, size). */\n"
             "typedef enum {\n    O1_ROM_UNKNOWN = 0,\n")
    for r in rows:
        h.append("    O1_ROM_%s,\n" % PROPERTIES[r["crc"]][0])
    h.append("} o1_rom_id_t;\n\n")
    h.append("/* What the image is, and therefore which socket it belongs in. */\n"
             "typedef enum {\n"
             "    O1_ROM_KIND_MONITOR = 0, /* 4 KiB Z80 monitor/BIOS, UD11 */\n"
             "    O1_ROM_KIND_CHARGEN,     /* 2 KiB character generator, UA15 */\n"
             "    O1_ROM_KIND_COPROCESSOR, /* the SWP board's 8088 firmware */\n"
             "    O1_ROM_KIND_COMBINED,    /* daughterboard holding two monitors */\n"
             "} o1_rom_kind_t;\n\n"
             "typedef enum {\n"
             "    O1_ROM_SOCKET_UD11 = 0,\n"
             "    O1_ROM_SOCKET_UA15,\n"
             "    O1_ROM_SOCKET_NONE,\n"
             "} o1_rom_socket_t;\n\n"
             "/* A capability is only PRESENT when it has been verified.  UNKNOWN is\n"
             " * not a soft yes: the gate refuses rather than assume. */\n"
             "typedef enum {\n"
             "    O1_CAP_UNKNOWN = 0,\n"
             "    O1_CAP_PRESENT,\n"
             "    O1_CAP_ABSENT,\n"
             "} o1_capability_t;\n\n")
    h.append("typedef struct {\n"
             "    uint32_t        crc32;\n"
             "    uint16_t        size;      /* bytes, part of the identity key */\n"
             "    o1_rom_id_t     id;\n"
             "    o1_rom_kind_t   kind;\n"
             "    o1_rom_socket_t socket;\n"
             "    o1_capability_t ieee488;   /* IEEE-488 driver present in the ROM */\n"
             "    uint8_t         video_kb;  /* video window, 0 = unknown */\n"
             "    const char     *name;\n"
             "    const char     *source;    /* repo copy, NULL if we hold none */\n"
             "} o1_rom_info_t;\n\n")
    h.append("#define O1_ROM_TABLE_LEN %d\n\n" % len(rows))
    h.append("extern const o1_rom_info_t o1_rom_table[O1_ROM_TABLE_LEN];\n\n"
             "/* Look up an image read from a socket.  Returns NULL if the pair is not\n"
             " * in the table.  Size is part of the key: a CRC32 alone can collide. */\n"
             "const o1_rom_info_t *o1_rom_lookup(uint32_t crc32, size_t size);\n\n"
             "#endif /* O1_ROM_TABLE_H */\n")

    c = ["/* GENERATED by tools/gen_rom_table.py -- do not edit by hand. */\n",
         '#include "rom_table.h"\n\n',
         "const o1_rom_info_t o1_rom_table[O1_ROM_TABLE_LEN] = {\n"]
    for r in rows:
        slug, kind, socket, ieee, video = PROPERTIES[r["crc"]]
        src = '"%s"' % r["sources"][0] if r["sources"] else "NULL"
        c.append('    { 0x%su, %5du, O1_ROM_%-19s O1_ROM_KIND_%-12s '
                 'O1_ROM_SOCKET_%-5s O1_CAP_%-8s %2du, %-28s %s },\n'
                 % (r["crc"], r["size"], slug + ",", kind + ",", socket + ",",
                    ieee + ",", video, '"%s",' % r["name"], src))
    c.append("};\n")
    return "".join(h), "".join(c)


def main(argv=None):
    ap = argparse.ArgumentParser(
        description="Generate the firmware ROM-identity table from the docs.")
    ap.add_argument("--check", action="store_true",
                    help="verify the committed files are up to date (CI mode)")
    ap.add_argument("-v", "--verbose", action="store_true",
                    help="print every image as it is verified")
    args = ap.parse_args(argv)

    rows, undumped = parse_doc(DOC.read_text(encoding="utf-8"))
    verify(rows, args.verbose)
    cross_check(rows)
    h, c = render(rows, undumped)

    if args.check:
        stale = [p for p, want in ((OUT_H, h), (OUT_C, c))
                 if not p.exists() or p.read_text(encoding="utf-8") != want]
        if stale:
            print("stale generated file(s):")
            for p in stale:
                print("  " + str(p.relative_to(REPO)))
            print("run: python3 tools/gen_rom_table.py")
            return 1
        print("rom table OK: %d images verified, %d revisions undumped"
              % (len(rows), len(undumped)))
        return 0

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for path, want in ((OUT_H, h), (OUT_C, c)):
        path.write_text(want, encoding="utf-8")
        print("wrote " + str(path.relative_to(REPO)))
    print("  %d images verified against the archive, %d revisions undumped"
          % (len(rows), len(undumped)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
