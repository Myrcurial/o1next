#!/usr/bin/env python3
"""populate-hd.py - put software on the O1NEXT's hard disk, from a staging tree.

    # 1. build the staging tree (visible, editable, and the input to step 2)
    tools/research/populate-hd.py --stage \
        --fog ~/Documents/O1NEXT/fog/disks \
        --selection hd-selected.txt \
        --out ~/Documents/O1NEXT/hd

    # 2. write it into the drive's partitions, with an INDEX.TXT in each
    tools/research/populate-hd.py --write /path/to/bootable.raw

WHY A STAGING TREE AND NOT A SCRIPT THAT DOES IT ALL

    Because the maintainer asked for one (#262): a folder tree you can look at,
    fill, and re-arrange, where each logical drive is a directory and each
    directory carries a manifest of what is in it and where it came from.  So
    `--stage` is the mechanical half (match the selection list against an
    extracted FOG library, sort into topical buckets) and `--write` is the
    filesystem half.  **The tree is the input to `--write`**, so moving a file
    between drives, or editing a description, is done by moving the file or
    editing the manifest -- no code change, and no re-derivation of anything.

THE BUCKETS ARE A FIRST PASS, AND THE MANIFEST IS THE RECORD

    Sorting 740 files into topical buckets is done by keyword on the
    description the selection list carries (GAME -> games, MODEM -> comms, and
    so on, table below).  It will be wrong for some files: that is what the
    manifest is for.  Move the file, edit its line, re-run `--write`.

PROVENANCE

    Every manifest line is `file <TAB> source <TAB> description`, and `source`
    is the FOG disk the file came out of (`FOG001`, ...), which is the archive's
    own name for it.  The selection list is the maintainer's, from #262.

THE FILESYSTEM

    cpmtools (`cpmcp`) does the writing, against a diskdef this tool generates
    for the MD-10's partition geometry -- 512-byte sectors, 8 KiB blocks, 1024
    directory entries, no boot tracks, and the partition's byte offset in the
    drive.  That is the answer to #262's question: yes, cpmtools can address one
    of these partitions, given a def that describes *one partition* rather than
    the whole drive.  cpmtools reads `./diskdefs` from the working directory,
    which is why this tool makes one rather than editing anything of the user's.
"""
import argparse
import os
import re
import shutil
import subprocess
import sys
import tempfile

# ----------------------------------------------------------------- the buckets
# (keyword in the description) -> drive letter.  First match wins, so the order
# here is the priority order.
BUCKETS = [
    ('util',    ('utilit', 'unerase', 'compares', 'find & replace', 'character set',
                 'character generator', 'file', 'text', 'label', 'menu')),
    ('comms',   ('modem', 'communi', 'terminal', 'xmodem', 'zmodem', 'kermit',
                 'telnet', 'bbs', 'compuserve', 'hayes', 'mex', 'dial', 'mdm',
                 'comm-pac', 'commpac', 'acoustic', 'phonebook', 'bulletin')),
    ('word',    ('word process', 'wordstar', 'mailmerge', 'mail merge', 'text '
                 'editor', 'spell', 'thesaurus', 'document')),
    ('data',    ('spreadsheet', 'database', 'data base', 'calc', 'dbase',
                 'supercalc', 'report', 'sort', 'file manager')),
    ('lang',    ('basic', 'compiler', 'assembler', 'pascal', 'fortran',
                 'interpreter', 'language', 'debugger', 'z80', 'c program')),
    ('disk',    ('disk', 'format', 'copy', 'unerase', 'directory', 'archive',
                 'backup', 'diagnost', 'repair')),
    ('print',   ('print', 'spool', 'font', 'character set')),
    ('games',   ('game', 'adventure', 'mastermind', 'chess', 'card', 'puzzle',
                 'arcade', 'simulat', 'star trek', 'zork')),
    ('edu',     ('education', 'tutorial', 'learn', 'teaching', 'teach')),
]
DRIVES = list('ABCDEFGHIJK')          # 11 partitions, the maximized layout

# which drive each bucket lands on.  A is the working drive -- the one you land
# on after boot -- so it gets the utilities; J is the catch-all.
BUCKET_DRIVE = {'util': 'A', 'comms': 'B', 'word': 'C', 'data': 'D', 'lang': 'E',
                'disk': 'F', 'print': 'G', 'games': 'H', 'edu': 'I'}
CATCH_ALL = 'J'

# --------------------------------------------------------------- the toolkit
# The drive is a CP/M machine, and a CP/M machine with no assembler and no
# debugger cannot install the overlays that are on it.  The FOG library has
# neither -- it is applications -- so the toolkit comes from the *shipped system
# disk* this repo holds: research/shipped-software/OS1SYSD.IMD, the factory DD
# disk, whose file list is `asm ddt load pip stat ed submit xsub`.  It is the
# difference between a drive that carries M7OD-5.ASM and a drive that can
# assemble it into a working MDM740.
#
# cpmtools' own `osborne1` diskdef is the DD format (1024-byte sectors, 5 per
# track, 3 boot tracks), which is what these images are.
TOOLKIT = ('ASM.COM', 'DDT.COM', 'LOAD.COM', 'PIP.COM', 'STAT.COM',
           'ED.COM', 'SUBMIT.COM', 'XSUB.COM')
SYSTEM_DISK = os.path.join('research', 'shipped-software', 'OS1SYSD.IMD')
SYSTEM_DEF = 'osborne1'


def bucket_for(desc, ext):
    d = (desc or '').lower()
    for name, words in BUCKETS:
        for w in words:
            if w in d:
                return BUCKET_DRIVE[name]
    return CATCH_ALL


def strip_high_bit(s):
    """The same line with bit 7 cleared from every character.

    Some rows of the selection were pasted out of a disk's own catalogue page
    through a path that left the high bit set on some bytes: `MLOAD2´ .COMº   D¸
    AÁ` is `MLOAD24.COM:` with the CRC bytes after it.  They do not match the
    pattern, so the entry was dropped in silence -- and one of those rows is
    MLOAD24.COM, the replacement for CP/M's LOAD that installs the MDM7, IMP and
    MEX overlays.  That is precisely the tool this drive needs to turn the
    uninstalled MDM740 into a working one, and it was never staged.
    """
    return ''.join(chr(ord(c) & 0x7F) if ord(c) > 0x7F else c for c in s)


def parse_selection(path):
    """The maintainer's list: `NAME.EXT: <two hex bytes> description`."""
    out = []
    for line in open(path, errors='replace'):
        raw = line.rstrip('\n')
        for cand in (raw, strip_high_bit(raw)):
            m = re.match(r'^([A-Z0-9#$&@!_\-]{1,8})\s*\.([A-Z0-9]{1,3})\s*:\s*(.*)$',
                         cand)
            if m:
                break
        if not m:
            continue
        name, ext, rest = m.group(1).upper(), m.group(2).upper(), m.group(3)
        desc = re.sub(r'^[0-9A-Fa-f]{2}\s+[0-9A-Fa-f]{2}\s*', '', rest).strip()
        out.append((name, ext, desc))
    return out


def index_fog(fogdir):
    """name.ext (upper) -> (path, disk).  The first disk that has it wins.

    A second index is built for FOG's *compression markers*.  The catalogue pages
    list the stored names: a Squeezed or Crunched member has the second character
    of its extension replaced by `Q` or `Z`, so the page says `.AQM` where the
    extracted disk carries `.ASM`, `.IQC` for `.INC`, `.MZC` for `.MAC`, `.0Q1`
    for `.001`.  **477 of the page/disk mismatches are this** -- and 27 of the
    maintainer's own selection is, including `M7OD-5.AQM`, the overlay that makes
    MDM740 usable with this machine's Comm-Pac.  Matching the page's name
    literally dropped all 27 silently, and the drive shipped without them.
    """
    have, marked = {}, {}
    for disk in sorted(os.listdir(fogdir)):
        d = os.path.join(fogdir, disk)
        if not os.path.isdir(d):
            continue
        for f in sorted(os.listdir(d)):
            key = f.upper()
            have.setdefault(key, (os.path.join(d, f), disk))
            stem, dot, ext = key.rpartition('.')
            if dot and len(ext) == 3:
                # `M7OD-5.ASM` is also reachable as `M7OD-5.AQM`: same first and
                # third characters, whatever FOG's marker put in the middle.
                marked.setdefault('%s.%s?%s' % (stem, ext[0], ext[2]),
                                  (os.path.join(d, f), disk))
    return have, marked


def marked_key(key):
    """The compression-marker spelling of `NAME.EXT`, or None if there is none.

    Only an extension whose second character is already `Q` or `Z` can be a
    marker (`AQM`, `DQC`, `MZC`, `0Q1`, ...), which is what keeps an ordinary
    `.DOC` from being confused with a crunched `.D?C`.
    """
    stem, dot, ext = key.rpartition('.')
    if not dot or len(ext) != 3 or ext[1] not in 'QZ':
        return None
    return '%s.%s?%s' % (stem, ext[0], ext[2])



# ------------------------------------------------------------------- staging

def stage_toolkit(out, manifests):
    """The CP/M toolkit, from the shipped system disk, into A:.

    Not part of the FOG selection, because it is not FOG's -- it is the factory
    system disk this repo holds -- so it is read out of that image with cpmtools,
    the same way `--write` does its work.  `--no-toolkit` skips it.
    """
    repo = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    imd = os.path.join(repo, SYSTEM_DISK)
    if not os.path.exists(imd):
        print('toolkit:     skipped -- %s is not in this checkout' % SYSTEM_DISK)
        return 0
    with tempfile.TemporaryDirectory() as work:
        raw = os.path.join(work, 'system.raw')
        subprocess.run([sys.executable,
                        os.path.join(repo, 'tools', 'research', 'imdinfo.py'),
                        '--raw', raw, imd], check=True,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        got = 0
        for name in TOOLKIT:
            dest = os.path.join(out, 'A', name)
            r = subprocess.run(['cpmcp', '-f', SYSTEM_DEF, raw,
                                '0:' + name.lower(), dest],
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            if r.returncode == 0 and os.path.exists(dest) and os.path.getsize(dest):
                manifests['A'].append((name, 'OS1SYSD',
                                       'CP/M 2.2 toolkit: assemble, and install overlays'))
                got += 1
    print('toolkit:     %d of %d file(s) from %s'
          % (got, len(TOOLKIT), SYSTEM_DISK))
    return got

def stage(args):
    want = parse_selection(os.path.expanduser(args.selection))
    have, marked = index_fog(os.path.expanduser(args.fog))
    out = os.path.expanduser(args.out)

    for d in DRIVES:
        os.makedirs(os.path.join(out, d), exist_ok=True)
    manifests = {d: [] for d in DRIVES}

    matched, aliased, missing = 0, 0, []
    for name, ext, desc in want:
        key = '%s.%s' % (name, ext)
        src_disk, alias = have.get(key), None
        if src_disk is None:
            # The catalogue page lists the *stored* name; the extracted disk
            # carries the restored one.  `.AQM` in the selection is `.ASM` on
            # disk, and matching the page literally is what lost the overlay.
            mk = marked_key(key)
            if mk is not None:
                src_disk, alias = marked.get(mk), mk
        if src_disk is None:
            missing.append(key)
            continue
        src, disk = src_disk
        # Stage it under the name the disk actually has -- `.ASM`, not `.AQM` --
        # because that is the name that works on the machine.
        real = os.path.basename(src)
        letter = bucket_for(desc, ext)
        shutil.copyfile(src, os.path.join(out, letter, real))
        manifests[letter].append((real, disk, desc))
        matched += 1
        aliased += alias is not None

    if not args.no_toolkit:
        stage_toolkit(out, manifests)

    for d in DRIVES:
        rows = sorted(manifests[d])
        with open(os.path.join(out, d, 'MANIFEST.txt'), 'w') as f:
            f.write('# %s: %d file(s), from the FOG library (#262)\n' % (d, len(rows)))
            f.write('# file\tsource\tdescription\n')
            for key, disk, desc in rows:
                f.write('%s\t%s\t%s\n' % (key, disk, desc))

    print('selection:   %d entries' % len(want))
    print('matched:     %d  (%d of them by FOG compression marker)' % (matched, aliased))
    print('missing:     %d  (%s)' % (len(missing), ', '.join(missing[:8]) or 'none'))
    print()
    for d in DRIVES:
        total = sum(os.path.getsize(os.path.join(out, d, f))
                    for f in os.listdir(os.path.join(out, d)) if f != 'MANIFEST.txt')
        print('  %s: %3d files, %7.1f KiB' % (d, len(manifests[d]), total / 1024.0))
    print()
    print('staged in %s -- move files between drives or edit a MANIFEST.txt and' % out)
    print('re-run --write; the tree is the input, not a by-product.')
    return 0


# ------------------------------------------------------------------- writing

def partitions(raw):
    """The label's 28-byte partition records, in drive order (md10table.py's walk)."""
    with open(raw, 'rb') as f:
        label = f.read(512)
    if label[:2] != b'MD':
        sys.exit('%s: no MD-10 label at LBA 0' % raw)
    out, i = [], 48
    while i + 28 <= len(label):
        r = label[i:i + 28]
        if r[0] == 0xFF:
            break
        out.append({'start': r[1] | (r[2] << 8) | (r[3] << 16),
                    'blocks': r[4] | (r[5] << 8),
                    'name': r[16:26].decode('latin1').strip('\x00 ')})
        i += 28
    return out


def diskdefs(work):
    """One def, offset 0, for *one partition written as its own image*.

    Two things had to be measured to get cpmtools to write here at all, and both
    are worth keeping:

      * **`-T raw` is mandatory.**  cpmtools 2.23 reads the image through libdsk,
        and without `-T raw` libdsk tries to *identify* the image and gives
        `cannot open <file> (No such file or directory)` for a file that is right
        there, or `cannot read superblock (Bad parameter)` when the def's offset is
        a long way into the drive.  With `-T raw` both go away.
      * **a def can address a partition directly** -- `offset 10240` for the first
        one, in *bytes*, works -- but this tool extracts the partition, writes it,
        and puts it back instead.  It costs two copies of 8 MB and it removes the
        offset from the question entirely, which is one less thing to be wrong
        when a file lands somewhere unexpected.

    The geometry is the MD-10's own: 512-byte sectors, 8 KiB blocks, 1024
    directory entries (32 KiB, four blocks, `AL0 = F0`), no boot tracks, and no
    skew -- the card's LBA *is* the block number, so the mapping is linear.
    """
    path = os.path.join(work, 'diskdefs')
    with open(path, 'w') as f:
        f.write('diskdef md10\n')
        f.write('  seclen 512\n')
        f.write('  tracks 1\n')
        f.write('  sectrk 15706\n')
        f.write('  blocksize 8192\n')
        f.write('  maxdir 1024\n')
        f.write('  boottrk 0\n')
        f.write('  offset 0\n')
        f.write('  os 2.2\n')
        f.write('end\n')
    return path


def index_text(drive_dir):
    """The drive's INDEX.TXT: `NAME.EXT <TAB> description`, alphabetized (#262).

    Built from the manifest, so it says what the *staging tree* says -- including
    descriptions the maintainer has edited -- rather than what a directory
    listing happens to contain.
    """
    rows = []
    man = os.path.join(drive_dir, 'MANIFEST.txt')
    if os.path.exists(man):
        for line in open(man, errors='replace'):
            if line.startswith('#') or not line.strip():
                continue
            parts = line.rstrip('\n').split('\t')
            if len(parts) >= 3:
                rows.append((parts[0], parts[2]))
            elif len(parts) == 1:
                rows.append((parts[0], ''))
    have = {f.upper() for f in os.listdir(drive_dir)
            if f != 'MANIFEST.txt' and not f.startswith('.')}
    listed = {k.upper() for k, _ in rows}
    for extra in sorted(have - listed):            # files the manifest does not know
        rows.append((extra, ''))
    rows.sort()
    return ''.join('%s\t%s\n' % (k, d) for k, d in rows)


def write(args):
    raw = args.write
    stage_dir = os.path.expanduser(args.stage)
    parts = partitions(raw)
    if len(parts) < 2:
        sys.exit('%s: %d partition record(s) -- the first is the O/S partition, so '
                 'there is no CP/M drive to present' % (raw, len(parts)))
    cpm_drives = parts[1:1 + len(DRIVES)]
    print('%s: %d partitions, %d CP/M drives' % (raw, len(parts), len(cpm_drives)))

    cpmcp = shutil.which('cpmcp')
    if not cpmcp:
        sys.exit('cpmcp not found: install cpmtools (REQUIREMENTS.md)')
    cpmrm = shutil.which('cpmrm')
    if not cpmrm:
        sys.exit('cpmrm not found: it comes with cpmtools (REQUIREMENTS.md)')
    work = tempfile.mkdtemp(prefix='populate-hd-')
    diskdefs(work)

    failures, written = [], 0
    with open(raw, 'r+b') as drive:
        for letter, rec in zip(DRIVES, cpm_drives):
            d = os.path.join(stage_dir, letter)
            if not os.path.isdir(d):
                continue
            files = sorted(f for f in os.listdir(d)
                           if f != 'MANIFEST.txt' and not f.startswith('.'))
            off, size = rec['start'] * 512, rec['blocks'] * 512
            drive.seek(off)
            part = os.path.join(work, 'part.img')
            open(part, 'wb').write(drive.read(size))
            print()
            print('%s: %s, %d file(s)' % (letter, rec['name'] or '?', len(files)))
            # Wipe the partition before writing it.  `cpmcp` will not overwrite an
            # existing file -- it says "can not create X: file already exists" and
            # returns non-zero -- so without this a *second* --write against the
            # same drive keeps the old contents and reports a failure for every
            # file it already had.  That is not a cosmetic problem: it means the
            # tree could not actually become the drive again, which is the whole
            # contract of this tool ("the tree is the input, not a by-product").
            # Measured 2026-10-23, when a re-populate left the *uninstalled*
            # MDM740.COM on B: while the tree held the installed one.
            if not args.dry_run:
                subprocess.run([cpmrm, '-T', 'raw', '-f', 'md10', part, '0:*.*'],
                               cwd=work, capture_output=True, text=True)
            for f in files:
                if args.dry_run:
                    continue
                r = subprocess.run([cpmcp, '-T', 'raw', '-f', 'md10', part,
                                    os.path.join(d, f), '0:' + f],
                                   cwd=work, capture_output=True, text=True)
                if r.returncode != 0:
                    failures.append((letter, f, (r.stderr or r.stdout).strip()))
                else:
                    written += 1
            text = index_text(d)
            idx = os.path.join(work, 'INDEX.TXT')
            open(idx, 'w').write(text)
            if not args.dry_run:
                r = subprocess.run([cpmcp, '-T', 'raw', '-f', 'md10', part, idx, '0:INDEX.TXT'],
                                   cwd=work, capture_output=True, text=True)
                if r.returncode != 0:
                    failures.append((letter, 'INDEX.TXT', (r.stderr or r.stdout).strip()))
                else:
                    written += 1
                    print('    INDEX.TXT written (%d line(s))' % text.count(chr(10)))
                drive.seek(off)
                drive.write(open(part, 'rb').read())

    shutil.rmtree(work, ignore_errors=True)
    print()
    print('written: %d file(s)%s' % (written,
                                     ' (dry run: nothing written)' if args.dry_run else ''))
    if failures:
        print('failed: %d' % len(failures))
        for letter, f, why in failures[:20]:
            print('  %s: %-14s %s' % (letter, f, why[:70]))
        return 1
    return 0


def main():
    ap = argparse.ArgumentParser(description='put software on the O1NEXT hard disk')
    ap.add_argument('--stage', action='store_true',
                    help='build the staging tree from the FOG extraction')
    ap.add_argument('--fog', default='~/Documents/O1NEXT/fog/disks',
                    help='the extracted FOG library (fog_extract.py + fog_lbr.py)')
    ap.add_argument('--selection', default='hd-selected.txt',
                    help="the maintainer's selected-file list (#262)")
    ap.add_argument('--out', default='~/Documents/O1NEXT/hd',
                    help='the staging tree (default ~/Documents/O1NEXT/hd)')
    ap.add_argument('--write', metavar='DRIVE.RAW',
                    help='write the staging tree into this drive image')
    ap.add_argument('--stage-dir', default='~/Documents/O1NEXT/hd',
                    help='the staging tree to write from')
    ap.add_argument('--dry-run', action='store_true',
                    help='with --write: say what would happen, write nothing')
    ap.add_argument('--no-toolkit', action='store_true',
                    help='with --stage: do not put the CP/M toolkit on drive A')
    args = ap.parse_args()
    if args.stage:
        return stage(args)
    if args.write:
        args.stage = args.stage_dir
        return write(args)
    ap.error('nothing to do: pass --stage or --write')


if __name__ == '__main__':
    sys.exit(main())
