#!/usr/bin/env python3
"""o1imd8.py -- read an Osborne Computer Corp 8-inch engineering disk.

WHY THIS EXISTS
    `research/source-code/*.IMD` -- the OCC engineering source disks -- are
    **8-inch** disks, not Osborne 1 5.25" ones, and nothing in the tree could
    read them.  `imdinfo.py` reports their geometry correctly but its `--raw`
    dump is not something `cpmtools` can address, because the disk is a
    *hybrid*: track 0 is FM 26 x 128 (the IBM-3740 boot track) and tracks 1-76
    are MFM 8 x 1024.  A `cpmtools` diskdef reads an image linearly as
    `tracks x sectrk x seclen`, so the 3328-byte first track desynchronises
    every track after it.  This tool writes the image in the shape the diskdef
    expects, and writes the diskdef itself.

WHAT THE FORMAT IS
    77 cylinders, one head, 630 784 bytes.  Track 0: 250 kbit/s FM, 26 sectors
    of 128 bytes.  Tracks 1-76: 250 kbit/s MFM, 8 sectors of 1024 bytes.  The
    CP/M filesystem on top is 2 KiB blocks, 128 directory entries (4096 bytes,
    two blocks), two reserved tracks -- and **skew 3**: the sectors of a track
    are interleaved, so `cpmtools`' `skew 3` table

        0 3 6 1 4 7 2 5

    is what maps CP/M's logical sector onto the physical one.  That table is
    exactly `tools/cpmfs.py`'s `skew_table(3, 8)`, i.e. `cpmtools`' own
    (cpmfs.c) -- see the cross-check in docs/rom-13-reconstruction.md.

    The skew is the whole difficulty, and it fails *quietly*.  Read without it
    and the directory still parses and every file still comes back -- from the
    wrong sectors, as interleaved garbage.  The read that identified it here
    was content chaining: at skew 3 every sector boundary in `occrom33.asm`
    joins mid-token to the next, e.g. `BDOS (f` + `unction`, `\\tJMP\\t` +
    `LIST`, `;HOUSE` + `KEEPING`.

OUTPUT
    o1imd8.py IN.imd OUT.raw [--diskdefs PATH]

    OUT.raw is `tracks x 8 x 1024` with track 0's 3328 real bytes padded out to
    8192, so a diskdef with `boottrk 2` lands on cylinder 2, where the CP/M
    directory actually starts.  A `diskdefs` file is written beside it
    (default `OUT.raw`'s directory + `/diskdefs`) -- `cpmtools` looks for a
    file of that name in the current directory before its own share directory,
    so `cd` to it and the name `occ8` resolves:

        diskdef occ8
          seclen 1024
          tracks 77
          sectrk 8
          blocksize 2048
          maxdir 128
          skew 3
          boottrk 2
          os 2.2
        end

Issue: #205 (see docs/rom-13-reconstruction.md).  Related: #2, #72.
"""
import os
import sys

SIZES = {0: 128, 1: 256, 2: 512, 3: 1024, 4: 2048, 5: 4096, 6: 8192}
TRACK = 8 * 1024                    # every track normalised to this

DISKDEF = """\
# Osborne Computer Corp 8-inch engineering disk (research/source-code/*.IMD).
# Track 0 is FM 26 x 128 and tracks 1-76 are MFM 8 x 1024; o1imd8.py pads
# track 0 out to 8192 bytes so this linear description works.  Written by
# o1imd8.py (#205).
diskdef occ8
  seclen 1024
  tracks 77
  sectrk 8
  blocksize 2048
  maxdir 128
  skew 3
  boottrk 2
  os 2.2
end
"""


def plausible(d, p):
    """Does a track record plausibly start at p?"""
    if p + 5 > len(d):
        return False
    mode, cyl, head, nsect, ssize = d[p:p + 5]
    return (0 <= mode <= 5 and cyl <= 84 and (head & 0x3F) <= 1
            and 1 <= nsect <= 32 and ssize <= 6)


def unpack(path):
    """IMD -> one bytes object per track, sectors in physical order."""
    d = open(path, 'rb').read()
    p = next(i + 1 for i in range(len(d)) if d[i] == 0x1A and plausible(d, i + 1))
    out = []
    while p is not None and p + 5 <= len(d) and plausible(d, p):
        mode, cyl, head, nsect, ssize = d[p:p + 5]
        q = p + 5 + nsect
        if head & 0x80:
            q += nsect
        if head & 0x40:
            q += nsect
        track = bytearray()
        for _ in range(nsect):
            t = d[q]
            q += 1
            if t == 0:
                data = b''                       # unavailable
            elif t in (2, 4, 6, 8):              # compressed: one byte, repeated
                data = bytes([d[q]]) * SIZES[ssize]
                q += 1
            else:                                # 1, 3, 5, 7: normal data
                data = d[q:q + SIZES[ssize]]
                q += SIZES[ssize]
            track += data
        # Track 0 is 3328 bytes on the real disk; pad it so the linear
        # description below keeps every later track where the diskdef expects.
        if len(track) < TRACK:
            track += bytes(TRACK - len(track))
        out.append(bytes(track))
        p = q
    return out


def main(argv):
    args = list(argv)
    diskdefs = None
    if '--diskdefs' in args:
        i = args.index('--diskdefs')
        diskdefs = args[i + 1]
        del args[i:i + 2]
    if len(args) < 2:
        sys.exit(__doc__)
    src, dst = args[0], args[1]

    tracks = unpack(src)
    raw = b''.join(tracks)
    open(dst, 'wb').write(raw)
    if diskdefs is None:
        diskdefs = os.path.join(os.path.dirname(os.path.abspath(dst)), 'diskdefs')
    open(diskdefs, 'w').write(DISKDEF)
    print(f'o1imd8.py: {src}: {len(tracks)} tracks, {len(raw)} bytes -> {dst}')
    print(f'o1imd8.py: diskdef "occ8" -> {diskdefs}')


if __name__ == '__main__':
    main(sys.argv[1:])
