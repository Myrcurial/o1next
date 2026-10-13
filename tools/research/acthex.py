#!/usr/bin/env python3
"""acthex.py -- turn a SORCIM ACT `H=` hex file into a flat ROM image.

WHY THIS EXISTS
    #203 reassembles the 1.44 monitor ROM with the vendor's *own* assembler --
    `ACT80.COM`, SORCIM's "Assembly Code Translator" -- run under MAME, and the
    last step is turning ACT's hex output back into the 4096-byte image the CRC
    comparison needs. Nothing in the tree did that, and the obvious candidate
    cannot: `LOAD.COM` refuses an ORG-0 hex file with *"INVERTED LOAD ADDRESS,
    LOAD ADDRESS 0000"*, because it expects a .COM at 0100h. So the conversion
    happens on the host.

    Three things about ACT's output are worth knowing, and all three are
    checked or reported here:

    * ACT's records are ordinary Intel HEX (count/address/type/data/checksum).
      253 of the 255 records in the 1.44 build validate under the standard
      checksum (two's complement of the sum of *all* bytes including the count).
      This tool validates every record and names the ones that fail.
    * The records do **not** cover the whole address space. ACT emits a record
      only where the source put a byte, so a program with an ORG hole or an
      unwritten tail leaves *gaps*, and the ROM's content there is whatever the
      part was programmed with. `--fill` picks it, and it matters: `00`
      reproduces `research/roms/os1-144.rom`; `ff` leaves 42 bytes different.
    * A record can arrive damaged without the file looking damaged. On the
      #203 run one record reached the floppy image with 6 non-hex bytes in it
      (still 44 characters long, so every line length looked right). Its
      checksum was intact and correct for the data it *should* have held, which
      is what identifies it as transport damage rather than an assembler error
      -- and why a record whose checksum disagrees with its own bytes is
      reported loudly rather than skipped.

    `--recover-ff` exists for that third case and is deliberately narrow. A
    record whose first eight characters survive still tells us its count,
    address and type, and its last two characters still give the checksum; if
    `count` bytes of FF satisfy *that* checksum, the record's content is
    determined by its own bytes rather than assumed, and the range is filled
    with FF. If the checksum does not fit, nothing is recovered and the record
    stays an error. It is not a general hex-repair mode and does not pretend to
    be one -- it recovers exactly the damage #203 saw.

USAGE
    acthex.py IN.hex OUT.bin [--fill 00] [--size 4096] [--reference ROM]
                             [--recover-ff] [--merge OTHER.hex ...]

    --reference compares the built image against a known-good ROM: CRC32s, the
    differing offsets and their bytes. Exits 1 if they differ, so the shell
    pipeline can gate on it.

    --merge takes further runs of the *same* build and fills in records the
    first one lacks.  It exists for a second, unrelated failure: the MAME
    emulation writes the guest's hex file back to the floppy image
    incompletely, damaging a handful of records per build
    (docs/rom-13-reconstruction.md 7).  As measured, that damage is identical
    between runs, so a merge does not currently rescue anything -- the option
    is here because it costs only time and is the fix if the damage ever moves.
    A record two runs disagree about is reported, not silently resolved, so a
    merge cannot hide a real difference.
"""
import argparse
import binascii
import sys


def read_records(path):
    """Yield (lineno, rawline, bytes) for each ':' record; bytes is None if the
    line could not be decoded as hex."""
    raw = open(path, "rb").read()
    for n, line in enumerate(raw.split(b"\n"), 1):
        # CP/M pads the tail of a 128-byte record with 0x1A, which lands on the
        # same line as the file's last record when the file is extracted whole.
        line = line.split(b"\x1a")[0].strip()
        if not line.startswith(b":"):
            continue                      # 0x1A padding, blank lines, stray CR
        try:
            yield n, line, bytes.fromhex(line[1:].decode("ascii"))
        except (ValueError, UnicodeDecodeError):
            yield n, line, None


def recover_ff(line, size):
    """Recover a record damaged in transit, if its own checksum says it is FF.

    Returns (addr, count) or None. The prefix ':' + count + address + type and
    the trailing checksum are what survive; if `count` bytes of FF satisfy the
    checksum, the record's content is pinned by the record itself.
    """
    s = line[1:].decode("latin-1", "replace")
    head, tail = s[0:8], s[-2:]
    hexd = "0123456789abcdefABCDEF"
    if len(s) < 10 or any(c not in hexd for c in head + tail):
        return None
    count = int(head[0:2], 16)
    addr = int(head[2:6], 16)
    typ = int(head[6:8], 16)
    if len(s) != 2 * (count + 5):
        return None                       # colon + 2*(count,addr,type,data,sum)
    csum = int(tail, 16)
    if (count + (addr >> 8) + (addr & 0xFF) + typ + count * 0xFF + csum) & 0xFF:
        return None                       # all-FF does not fit its checksum
    if addr + count > size:
        return None
    return addr, count


def record_map(path, size):
    """{addr: data} for every record in `path` that validates."""
    out = {}
    for _, _, b in read_records(path):
        if b is None or len(b) < 5 or b[3] != 0:
            continue
        count, addr = b[0], (b[1] << 8) | b[2]
        if len(b) != 5 + count or (sum(b) & 0xFF) != 0:
            continue
        out[addr] = b[4:4 + count]
    return out


def build(path, size, fill, recover=False, merge=()):
    img = bytearray([fill]) * size
    covered = set()
    records = malformed = badsum = recovered = 0
    for n, line, b in read_records(path):
        records += 1
        if b is not None and len(b) == 4 and b[0] == 0:
            # ACT's own terminator: ':' + count 00 + 0100 + 10, four bytes and no
            # data. It is not Intel's ':00000001FF', and both 3.0 and 3.2 emit it
            # byte-identically, so it is recorded as ACT's and not as damage.
            print(f"acthex.py: line {n}: ACT terminator record, no data -- "
                  f"{line!r}", file=sys.stderr)
            continue
        if b is None or len(b) < 5:
            malformed += 1
            got = recover_ff(line, size) if recover else None
            if got:
                addr, count = got
                for i in range(count):
                    img[addr + i] = 0xFF
                    covered.add(addr + i)
                recovered += 1
                print(f"acthex.py: line {n}: damaged record recovered as "
                      f"{count} x FF at {addr:04x} (its checksum agrees) -- "
                      f"{line!r}", file=sys.stderr)
            else:
                print(f"acthex.py: line {n}: not a usable record -- {line!r}",
                      file=sys.stderr)
            continue
        count, addr, typ = b[0], (b[1] << 8) | b[2], b[3]
        data = b[4:4 + count]
        if len(data) != count or len(b) != 5 + count:
            malformed += 1
            print(f"acthex.py: line {n}: bad record length -- {line!r}",
                  file=sys.stderr)
            continue
        if (sum(b) & 0xFF) != 0:
            badsum += 1
            print(f"acthex.py: line {n}: checksum fails (record says "
                  f"{b[-1]:02x}) -- {line!r}", file=sys.stderr)
        if typ == 0:
            for i, v in enumerate(data):
                if addr + i < size:
                    img[addr + i] = v
                    covered.add(addr + i)
        elif typ != 1:
            print(f"acthex.py: line {n}: record type {typ} ignored",
                  file=sys.stderr)
    print(f"acthex.py: {records} records, {len(covered)}/{size} bytes covered, "
          f"{malformed} malformed ({recovered} recovered), "
          f"{badsum} bad checksum", file=sys.stderr)
    # Merge further runs of the same build.  MAME's floppy write-back loses or
    # corrupts a handful of records per run, and it does so *differently* each
    # time -- see docs/rom-13-reconstruction.md 7 -- so the union of a few runs
    # covers what one run cannot.  A record that two runs disagree about is
    # reported rather than silently resolved.
    for extra in merge:
        added = 0
        for addr, data in record_map(extra, size).items():
            if all(addr + i in covered for i in range(len(data))):
                got = bytes(img[addr:addr + len(data)])
                if got != data:
                    print(f"acthex.py: {extra}: record at {addr:04x} disagrees "
                          f"with the first run ({got.hex()} vs {data.hex()})",
                          file=sys.stderr)
                continue
            img[addr:addr + len(data)] = data
            covered.update(range(addr, addr + len(data)))
            added += 1
        print(f"acthex.py: {extra}: {added} additional records merged "
              f"({len(covered)}/{size} bytes covered)", file=sys.stderr)
    return bytes(img)


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("hexfile")
    ap.add_argument("out")
    ap.add_argument("--fill", default="00",
                    help="byte for addresses no record covers (default 00)")
    ap.add_argument("--size", type=lambda s: int(s, 0), default=4096)
    ap.add_argument("--reference", help="known-good ROM to compare against")
    ap.add_argument("--recover-ff", action="store_true",
                    help="recover a damaged record as FF when its own checksum "
                         "agrees (see the docstring)")
    ap.add_argument("--merge", action="append", default=[], metavar="HEX",
                    help="another run's hex file; records it holds that the "
                         "first does not are merged in (repeatable).  For the "
                         "flaky MAME write-back -- see the docstring.")
    a = ap.parse_args()

    img = build(a.hexfile, a.size, int(a.fill, 16), a.recover_ff, a.merge)
    open(a.out, "wb").write(img)
    print(f"acthex.py: wrote {a.out} ({len(img)} bytes, fill {a.fill})")
    print(f"acthex.py: CRC32 {binascii.crc32(img):08x}")

    if a.reference:
        ref = open(a.reference, "rb").read()
        rc = binascii.crc32(ref)
        print(f"acthex.py: reference {a.reference} CRC32 {rc:08x} "
              f"({len(ref)} bytes)")
        diff = [i for i in range(min(len(img), len(ref))) if img[i] != ref[i]]
        if len(img) != len(ref):
            diff += list(range(min(len(img), len(ref)), max(len(img), len(ref))))
        if diff:
            print(f"acthex.py: {len(diff)} bytes differ: "
                  + " ".join(f"{i:04x}" for i in diff[:24])
                  + (" ..." if len(diff) > 24 else ""))
            for i in diff[:8]:
                print(f"    {i:04x} built={img[i]:02x} reference={ref[i]:02x}")
            return 1
        print("acthex.py: IDENTICAL to the reference")
    return 0


if __name__ == "__main__":
    sys.exit(main())
