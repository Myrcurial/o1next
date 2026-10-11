#!/usr/bin/env python3
"""imdinfo.py -- report the geometry of an ImageDisk (.imd) floppy image.

WHY THIS EXISTS
    We kept needing to answer "what *is* this disk image?" -- which format, how
    many tracks, what sector size, is it single or double density -- for the
    2026-10 research drop (Osborne 1 system disks, the Nuevo/Osmosis images, the
    Adaptec hard-disk utilities) while working #70/#71/#79. `disk-analyse` is
    the real tool for this, but it is an external dependency and it only
    converts; this is a stdlib-only reader that prints the structure directly
    and can dump a reconstructed raw image, which was enough to settle the
    questions without installing anything.

WHAT IT FOUND
    The `-blank.imd` boot disks are double-density (250 kbps MFM) 40-track
    images with 5 x 1024-byte sectors -- not blank, and all three differ by
    exactly two bytes. The Nuevo system disk has the same geometry. Written for
    #70 and #79; see docs/mame-emulation.md section 4.

    `--raw` places each sector at its *logical* position, not its position in
    the file. Those coincide for most images, but single-density Osborne disks
    carry a rotated numbering map -- (2,3,...,10,1) -- and appending in file
    order rotates every track by one sector. That failure is quiet: the
    rotated image still parses as a CP/M filesystem, just the wrong one.
    Found on OZROM.IMD, which yielded 12 files instead of 20 (#81).

IMD FORMAT (Dave Dunfield's spec, IMD.TXT section 6 -- public domain)
    Text header line(s), terminated by 0x1A, then track records:
        1 byte  mode            0-5 (0=500k FM ... 5=250k MFM)
        1 byte  cylinder
        1 byte  head            bits 6/7 are flags: 0x80 = cylinder map
                                present, 0x40 = head map present
        1 byte  number of sectors
        1 byte  sector size     0-6 (128..8192 bytes)
        N bytes sector numbering map
        N bytes sector cylinder map   (optional)
        N bytes sector head map       (optional)
        then one data record per sector, each a type byte plus data:
            00 = unavailable (0 bytes)   01 = normal (size bytes)
            02 = compressed, 1 byte      03 = deleted-AM, normal
            04 = compressed, 1 byte      05 = read error, normal
            06 = compressed, 1 byte      07 = deleted+error, normal
            08 = compressed, 1 byte

    NOTE: there is no separate "sector type map" -- the type byte belongs to
    each sector's data record. Getting that wrong is the classic way to write
    a parser that desynchronises on the second track.

Usage:
    imdinfo.py IMAGE.IMD [...]            # report structure
    imdinfo.py --raw OUT.img IMAGE.IMD    # also write a reconstructed raw image
"""
import sys

MODES = {0: "500k FM", 1: "300k FM", 2: "250k FM",
         3: "500k MFM", 4: "300k MFM", 5: "250k MFM"}
SIZES = {0: 128, 1: 256, 2: 512, 3: 1024, 4: 2048, 5: 4096, 6: 8192}
# sector data record type -> (bytes stored, is a normal (size-byte) payload)
REC = {0: (0, False), 1: (None, True), 2: (1, False), 3: (None, True),
       4: (1, False), 5: (None, True), 6: (1, False), 7: (None, True),
       8: (1, False)}


def plausible(d, p):
    """Does a track record plausibly start at p?"""
    if p + 5 > len(d):
        return False
    mode, cyl, head, nsect, ssize = d[p:p + 5]
    return (0 <= mode <= 5 and cyl <= 84 and (head & 0x3F) <= 1
            and 1 <= nsect <= 32 and ssize <= 6)


def find_tracks(d):
    """Offset of the first track record: the 0x1A before it ends the text."""
    for p in range(len(d)):
        if d[p] == 0x1A and plausible(d, p + 1):
            return p
    return -1


def parse(d, start):
    """Yield (mode, cyl, head, nsect, ssize, numbering, nbytes, data) per track."""
    p = start
    while p < len(d) and plausible(d, p):
        mode, cyl, headflags, nsect, ssize = d[p:p + 5]
        head = headflags & 0x3F
        p += 5
        numbering = list(d[p:p + nsect]); p += nsect
        if headflags & 0x80:
            p += nsect                      # cylinder map
        if headflags & 0x40:
            p += nsect                      # head map
        size = SIZES[ssize]
        data, nbytes = [], 0
        for _ in range(nsect):
            t = d[p]; p += 1
            n, normal = REC.get(t, (None, True))
            n = size if n is None else n
            chunk = d[p:p + n]
            p += n
            data.append((t, chunk))
            nbytes += size if normal else 0
        yield mode, cyl, head, nsect, ssize, numbering, nbytes, data


def report(path, raw_out=None):
    d = open(path, "rb").read()
    print("=" * 72)
    print(f"{path}  ({len(d)} bytes)")
    start = find_tracks(d)
    if start < 0:
        print("  !! no track records found -- not an ImageDisk file?")
        return
    for line in [l for l in d[:start].decode("latin-1").split("\n") if l.strip()]:
        print(f"  | {line.rstrip()}")

    tracks, modes, sizes, cyls, heads = 0, set(), set(), set(), set()
    spt, reconstructed, raw = set(), 0, bytearray()
    for mode, cyl, head, nsect, ssize, numbering, nbytes, data in parse(d, start + 1):
        tracks += 1
        modes.add(MODES.get(mode, mode)); sizes.add(SIZES.get(ssize, ssize))
        cyls.add(cyl); heads.add(head); spt.add(nsect)
        reconstructed += nbytes
        size = SIZES[ssize]
        # Sectors arrive in *file* order; the numbering map says which logical
        # sector each one is. Place them by logical number rather than by
        # arrival order: single-density Osborne disks number (2,3,...,10,1),
        # so a straight append rotates every track by one sector -- and a
        # rotated CP/M disk still parses into a plausible but wrong file list,
        # which is how this was found (OZROM.IMD: 12 files instead of 20).
        track = bytearray(nsect * size)
        for k, (t, chunk) in enumerate(data):
            if t in (1, 3, 5, 7):                       # normal data
                sec = chunk
            elif t in (2, 4, 6, 8) and chunk:           # compressed: one value
                sec = bytes([chunk[0]]) * size
            else:                                       # unavailable
                sec = b"\xe5" * size
            logical = (numbering[k] - 1) if k < len(numbering) else k
            if 0 <= logical < nsect:
                track[logical * size:(logical + 1) * size] = sec[:size]
        raw += track
    print(f"  tracks={tracks}  modes={sorted(map(str, modes))}  "
          f"sector sizes={sorted(sizes)}  sectors/track={sorted(spt)}")
    print(f"  cylinders={min(cyls)}-{max(cyls)}  heads={sorted(heads)}  "
          f"reconstructed sector data={reconstructed} bytes")
    if raw_out:
        open(raw_out, "wb").write(bytes(raw))
        print(f"  wrote {raw_out} ({len(raw)} bytes; sectors in logical order)")


if __name__ == "__main__":
    args = sys.argv[1:]
    raw = None
    if args and args[0] == "--raw":
        raw, args = args[1], args[2:]
    if not args:
        sys.exit(__doc__)
    for a in args:
        report(a, raw)
