#!/usr/bin/env python3
"""rom2blob.py -- the ROM 2.0 boot screen's code as an artifact: 4096 bytes, padded.

WHY THIS EXISTS
    #247's step 8 put the screen's code in the *interposer's* flash rather than in
    the monitor's 72 free bytes (`docs/o1-rom-2.0.md` 4.7).  The monitor keeps a
    ~30-byte stub that asks for it with `PRESENT(3)`, copies window page 1 to RAM
    at `4000h` and jumps; the code itself is a 4096-byte page the Pico serves.
    This tool makes that page out of the build.

    It is **not** a generator in `rom2strokes.py`'s sense.  The frame is derived
    from the art by this repo's own code, so its `--check` can rebuild it and
    compare bytes.  The blob is the vendor's ACT80 assembling the vendor's
    dialect: nothing here can recompute it, and CI has no MAME and never will.  So
    `--check` asks the question it *can* ask -- **is this blob in step with its
    source?** -- by carrying, inside the blob, the digest of the source it was
    extracted from.  Edit the source without regenerating the blob and the check
    fails, which is the whole of the guarantee; it is not a proof that the bytes
    are right, and does not pretend to be one.

WHAT IS IN THE PAGE

    0x0000-0x00B7   the code, exactly as the assembler emitted it at 4000h-40B7h
    0x00B8-0x0FEF   0FFh, the vendor's own fill (`ECHO 0FFFH-RLWA ! DB 0FFH`).
                    The stub copies the whole page and nothing reads the tail
    0x0FF0-0x0FF5   `O1NEXT`
    0x0FF6-0x0FFD   the first 8 bytes of the SHA-256 of the source
    0x0FFE-0x0FFF   the 16-bit sum of the 0FFEh bytes before it, little-endian

    The trailer is at the *top* of the page rather than at the frame's `0FF8h`
    because nothing reads it: the monitor's trailer check is the *frame's*, and
    this page is code.  The trailer is provenance, and it is deliberately out of
    the code's way -- `--extract` refuses a blob that reaches it.

Usage:
    tools/research/rom2blob.py --extract ROM2.HEX -o firmware/rom-service/screen.bin
    tools/research/rom2blob.py --check          # is the committed blob in step?
"""
import argparse
import hashlib
import importlib.util
import os
import sys

PAGE = 4096                        # one window page, and exactly one screen
BLOB_AT = 0x4000                   # where the stub copies it to, and enters it
TRAILER_AT = 0x0FF0                # 16 bytes at the top of the page
MAGIC = b'O1NEXT'
DIGEST_LEN = 8
SUM_AT = TRAILER_AT + len(MAGIC) + DIGEST_LEN       # 0FFEh
PAD = 0xFF                         # the vendor's fill, not 00: see the docstring

SRC = os.path.join('research', 'source-code', 'BIOS-200-source',
                   'rom2-screen.asm')
BIN = os.path.join('firmware', 'rom-service', 'screen.bin')


def repo_root():
    return os.path.dirname(os.path.dirname(os.path.dirname(
        os.path.abspath(__file__))))


def _sibling(name):
    """Import a tool beside this one, so the hex is parsed one way in this repo.

    `acthex.py` already knows what ACT's hex looks like and what the emulator's
    write-back does to it, and the monitor's image is built with the same reader.
    A second parser here would be a second opinion about the same damage.
    """
    here = os.path.dirname(os.path.abspath(__file__))
    for d in (here, os.path.dirname(here)):
        path = os.path.join(d, name)
        if os.path.exists(path):
            break
    else:
        raise SystemExit('rom2blob.py: cannot find %s beside this tool' % name)
    spec = importlib.util.spec_from_file_location(name[:-3], path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def source_digest(path):
    """The first `DIGEST_LEN` bytes of the SHA-256 of the source."""
    with open(path, 'rb') as fh:
        return hashlib.sha256(fh.read()).digest()[:DIGEST_LEN]


def seal(body, digest):
    """The page: the body, then the trailer, then the sum of everything before it."""
    if len(body) != TRAILER_AT:
        raise ValueError('a page body is %d bytes, not %d'
                         % (TRAILER_AT, len(body)))
    checksum = sum(body) & 0xFFFF
    return bytes(body) + MAGIC + digest + bytes([checksum & 0xFF,
                                                 checksum >> 8])


def trailer_sum(page):
    """The 16-bit sum a page carries at `0FFEh`, little-endian, read back."""
    return page[SUM_AT] | (page[SUM_AT + 1] << 8)

def extract(hexpath, lwa=None):
    """(page, extent) -- the blob's code in a 4096-byte page, and where it ends.

    Contiguity from `4000h` is required, not checked afterwards: a hole means the
    emulator's floppy write-back lost a record *inside the code*, and the padded
    byte would look exactly like a clean build (`docs/rom-13-reconstruction.md` 7).
    """
    acthex = _sibling('acthex.py')
    img = bytearray([PAD]) * PAGE
    covered = set()
    records = 0
    for n, line, b in acthex.read_records(hexpath):
        if b is None or len(b) < 5:
            continue
        count, addr, typ = b[0], (b[1] << 8) | b[2], b[3]
        if typ != 0 or len(b) != 5 + count:
            continue
        if (sum(b) & 0xFF) != 0:
            print('rom2blob.py: line %d: checksum fails -- %r' % (n, line),
                  file=sys.stderr)
            continue
        if addr + count <= BLOB_AT:
            continue
        if addr < BLOB_AT:
            raise SystemExit('rom2blob.py: a record at %04x straddles %04xh'
                             % (addr, BLOB_AT))
        off = addr - BLOB_AT
        if off + count > TRAILER_AT:
            raise SystemExit('rom2blob.py: a record reaches %04x, into the '
                             'trailer at %04xh' % (addr + count - 1, TRAILER_AT))
        img[off:off + count] = b[4:4 + count]
        covered.update(range(off, off + count))
        records += 1
    if not covered:
        raise SystemExit('rom2blob.py: %s holds no records at or above %04xh.  '
                         'The screen code is not in the build -- see step 7 of '
                         'rom2asm.sh.' % (hexpath, BLOB_AT))
    extent = max(covered)
    holes = [i for i in range(extent + 1) if i not in covered]
    if holes:
        raise SystemExit(
            'rom2blob.py: %s covers 0-0x%03x but not 0x%03x-0x%03x -- the\n'
            '  emulator\'s floppy write-back lost records inside the blob, and a\n'
            '  padded byte would look like a clean build\n'
            '  (docs/rom-13-reconstruction.md 7).  Re-run the assembly.'
            % (hexpath, extent, holes[0], holes[-1]))
    if lwa is not None and BLOB_AT + extent + 1 != lwa:
        raise SystemExit('rom2blob.py: the records end at %04xh but the assembler '
                         'says the program ends at %04xh -- the build is not the '
                         'one the source describes' % (BLOB_AT + extent, lwa))
    print('rom2blob.py: %d records, 0x000-0x%03x (%d bytes of code), %d bytes of '
          'fill' % (records, extent, extent + 1, PAGE - (extent + 1)))
    return img, extent


def verify(page):
    """`(ok, message)` -- does this page carry a good trailer at its own `0FF0h`?"""
    if len(page) != PAGE:
        return False, '%d bytes, not %d' % (len(page), PAGE)
    magic = bytes(page[TRAILER_AT:TRAILER_AT + len(MAGIC)])
    if magic != MAGIC:
        return False, 'trailer %r, not %r' % (magic, MAGIC)
    want = sum(page[:TRAILER_AT]) & 0xFFFF
    got = trailer_sum(page)
    if got != want:
        return False, 'trailer says %04x and the body sums to %04x' % (got, want)
    return True, '%s + sum %04x' % (MAGIC.decode(), got)


def check(path, srcpath):
    """Is the committed blob in step with the source it was extracted from?"""
    page = open(path, 'rb').read()
    ok, message = verify(page)
    print('  %-4s %s: %s' % ('ok' if ok else 'BAD', path, message))
    if not ok:
        return False
    want = source_digest(srcpath)
    got = bytes(page[TRAILER_AT + len(MAGIC):SUM_AT])
    if got != want:
        print('  BAD  %s: extracted from a different %s'
              % (path, os.path.basename(srcpath)))
        print('       the blob records %s' % got.hex())
        print('       the source is    %s' % want.hex())
        print('       run: tools/research/rom2blob.py --extract ROM2.HEX -o %s'
              % path)
        return False
    print('  ok   %s: extracted from %s as it stands'
          % (path, os.path.basename(srcpath)))
    return True


def main(argv=None):
    root = repo_root()
    ap = argparse.ArgumentParser(
        description='Make the boot screen\'s code an artifact: 4096 bytes, padded.')
    ap.add_argument('--extract', metavar='ROM2.HEX',
                    help='read a build\'s hex and write the blob; the records at '
                         'and above 4000h are the code, and they have to be '
                         'contiguous')
    ap.add_argument('-o', '--out', metavar='screen.bin',
                    help='with --extract, where to write it')
    ap.add_argument('--lwa', type=lambda s: int(s, 16), metavar='ADDR',
                    help='with --extract, assert the blob ends where the assembler '
                         'says the program does: `Program LWA`, which is the '
                         'location counter and therefore one past the blob\'s own '
                         'last byte')
    ap.add_argument('--source', default=os.path.join(root, SRC),
                    help='the source the blob is extracted from (default %s)'
                         % SRC)
    ap.add_argument('--check', nargs='?', const=os.path.join(root, BIN),
                    metavar='screen.bin',
                    help='verify the committed blob carries a good trailer and '
                         'the digest of the source as it stands, and exit '
                         'non-zero if it does not; writes nothing')
    args = ap.parse_args(argv)

    if args.extract:
        if not args.out:
            ap.error('--extract needs -o/--out')
        page, extent = extract(args.extract, args.lwa)
        digest = source_digest(args.source)
        with open(args.out, 'wb') as fh:
            fh.write(seal(page[:TRAILER_AT], digest))
        print('rom2blob.py: wrote %s (4096 bytes, code to 0x%03x, source %s)'
              % (args.out, extent, digest.hex()))
        return 0

    if args.check is not None:
        return 0 if check(args.check, args.source) else 1

    ap.print_help()
    return 0


if __name__ == '__main__':
    sys.exit(main())

