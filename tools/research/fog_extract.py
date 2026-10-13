#!/usr/bin/env python3
"""fog_extract.py - extract the FOG library: ARC -> LBR -> CP/M files.

Two layers, one tool.  `unar` (The Unarchiver) reads both ARC and the CP/M
LBR container, so nothing is hand-rolled; this script drives it and then
*verifies* the result rather than trusting it.

WHY THE HEADER PATCH
    unar's ARC recogniser rejects an archive whose compressed size exceeds
    its uncompressed size (`XADARCParser.m`: "Assume files are always
    compressed or stored").  That assumption is wrong: ARC stores data with
    a compression method even when the method expands it, and 10 of the 219
    FOG disks do exactly that -- by as little as 32 bytes (fog129,
    161312 vs 161280).  unar then reports "Couldn't recognize the archive
    format" for a perfectly good archive.

    The workaround is to raise the *uncompressed-size* field in a throwaway
    copy so the heuristic passes.  Nothing else in the header is touched, and
    unar decompresses to the true length regardless -- verified, not assumed.
    The safety net is that unar checks the ARC's own CRC-16, and this script
    checks it independently as well, so a bad patch cannot pass silently.

VERIFICATION
    Every extracted `.LBR` is checked against the CRC-16/ARC in its ARC
    header.  That CRC is the archive's own integrity claim, so a match means
    the bytes are the bytes, whichever route they took out.

Usage: fog_extract.py FOGDIR [--out OUTDIR]
"""
import os
import shutil
import struct
import subprocess
import sys

def crc16_arc(data):
    """CRC-16/ARC: poly 0xA001 reflected, init 0 -- the polynomial ARC uses
    (x^16 + x^15 + x^2 + 1, `ARC-FILE.INF`)."""
    c = 0
    for b in data:
        c ^= b
        for _ in range(8):
            c = (c >> 1) ^ 0xA001 if c & 1 else c >> 1
    return c

def arc_members(path):
    """Walk the ARC header chain: (name, method, comp, crc, orig, offset)."""
    b = open(path, 'rb').read()
    out, off = [], 0
    while off + 29 <= len(b) and b[off] == 0x1A:
        meth = b[off + 1]
        name = b[off + 2:off + 15].split(b'\x00')[0].decode('latin1')
        comp, _date, _time, crc, orig = struct.unpack('<IHHHI', b[off + 15:off + 29])
        out.append((name, meth, comp, crc, orig, off))
        off += 29 + comp
    return out

def unar(archive, outdir):
    os.makedirs(outdir, exist_ok=True)
    r = subprocess.run(['unar', '-q', '-f', '-o', outdir, archive],
                       capture_output=True, text=True)
    return r.returncode, (r.stdout + r.stderr).strip()

def main(argv):
    src = argv[0]
    out = os.path.join(src, 'extracted')
    for i, a in enumerate(argv):
        if a == '--out':
            out = argv[i + 1]
    tmp = os.path.join(out, '.patch')
    lbrdir = os.path.join(out, 'lbr')
    # Start clean, both of them.  unar does not overwrite on a name collision
    # even with -f -- it writes `NAME 2` beside the original -- so a second run
    # against a dirty directory silently doubles the tree instead of replacing
    # it.  That is how this script first produced 423 LBRs from 219 archives.
    for d in (tmp, lbrdir):
        shutil.rmtree(d, ignore_errors=True)
    for d in (tmp, lbrdir, os.path.join(out, 'log')):
        os.makedirs(d, exist_ok=True)

    arcs = sorted(f for f in os.listdir(src)
                  if f.startswith('fog') and f.endswith('.arc'))
    patched, ok, failed, mismatched = [], [], [], []

    for f in arcs:
        members = arc_members(os.path.join(src, f))
        if len(members) != 1:
            failed.append((f, 'expected 1 member, got %d' % len(members)))
            continue
        name, meth, comp, crc, orig, _ = members[0]
        target = os.path.join(src, f)
        # The 10 archives unar's recogniser rejects: raise the declared
        # uncompressed size in a copy so the heuristic passes.
        if comp > orig:
            b = bytearray(open(target, 'rb').read())
            struct.pack_into('<I', b, 25, comp + 1)
            target = os.path.join(tmp, f)
            open(target, 'wb').write(bytes(b))
            patched.append(f)
        rc, msg = unar(target, tmp)
        got = os.path.join(tmp, name)
        if rc != 0 or not os.path.exists(got):
            failed.append((f, msg or 'rc=%d' % rc))
            continue
        data = open(got, 'rb').read()
        if len(data) != orig:
            failed.append((f, 'size %d, header says %d' % (len(data), orig)))
            continue
        if crc16_arc(data) != crc:
            mismatched.append(f)
            continue
        os.replace(got, os.path.join(lbrdir, name))
        ok.append((f, name, len(data)))

    print('ARC layer: %d archives' % len(arcs))
    print('  extracted and CRC-16/ARC verified: %d' % len(ok))
    print('  of those, needed the recogniser patch: %d  (%s)'
          % (len(patched), ', '.join(p[:-4] for p in patched) or 'none'))
    print('  CRC mismatch: %d' % len(mismatched))
    print('  failed: %d' % len(failed))
    for f, why in failed:
        print('    %-14s %s' % (f, why))
    return 0 if not failed and not mismatched else 1

if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
