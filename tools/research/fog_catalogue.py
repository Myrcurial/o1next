#!/usr/bin/env python3
"""fog_catalogue.py - build the curated FOG library catalogue from the disks.

PRIMARY SOURCE, not the index.  `fog-index.htm` is a 1985 catalogue snapshot
whose CRC column does not reproduce (it claims CAL2-EX.COM is 4A98; the file
on the disk is CRC-16/ARC 3AF9), so it is a cross-check, never the source.
Every disk carries its own catalogue page as a member, and *that* is what this
reads -- which also means the catalogue covers all 219 disks rather than the
149 the index happens to describe.

Two catalogue-page dialects, by vintage:

  1985  `::CPMnnn.DOC`  --  the sparse index format
        `  filename    CRC         description`
        `-FOG/CPM.003:      Printer graphics program in Aztec c ...`
        `BAR1    .GRF: 8B88 GRF files are saved graphics files for demo`
        `DEMO    .COM: D422   "`     <- `"` means "same as the one above"

  1988  `-CPMnnn.DOC`  --  the rich format
        `                       Fog Library Disk FOG-CPM.210`
        `Copyright (1989) by Fog International Computer Users Group ...`
        `<SHAREWARE> as part of the description ...`
        (disk description paragraph)
        `Filename     Description`
        `ZDE10   .COM 54DE  16K ver. 1.0     [Z-Sys Display Edit 1 of 10]`
        `             Based on the well-liked VDE program but ...`

Usage: fog_catalogue.py EXTRACTED_DIR OUTDIR
"""
import json
import os
import re
import sys

ZPAD = re.compile(r'\x1a+\s*$')
NAME_COLS = 12
DATE_RE = re.compile(r'^-\d\d-\d\d\s*\.\d\d$')
SELF_RE = re.compile(r'^-CPM\d{3}\s*\.DOC$')

def clean_line(l):
    """Strip CP/M EOF padding.  A `^Z` can sit at the *start* of a line as well
    as the end -- FOG200's page has one immediately before a wrapped
    description line, where it would otherwise be read as a filename."""
    return ZPAD.sub('', l).lstrip('\x1a')

def read_doc(path):
    """Read a catalogue page as text.

    CP/M text written by WordStar sets bit 7 on the last character of a word,
    and some of these pages carry that convention: 35 of the 220 pages have
    high-bit bytes.  Stripping bit 7 is not cosmetic here -- FOG047's label
    line ends `-FOG/CPM.047<0xBA>`, and 0xBA & 0x7F is `:`, so the *field
    separator* itself is high-bit and the line does not parse until it is
    cleared.  The same fix turns `Osborn<0xE5> Executiv<0xE5> an<0xE4> CPM<0xAB>`
    back into `Osborne Executive and CPM+`.
    """
    raw = open(path, 'rb').read()
    raw = bytes(c & 0x7F for c in raw)
    return raw.decode('latin1').replace('\r\n', '\n').replace('\r', '\n')

def find_doc(diskdir):
    """The disk's own catalogue page, whatever its prefix."""
    for f in sorted(os.listdir(diskdir)):
        if re.fullmatch(r'.*CPM\d{3}\s*\.DOC', f):
            return os.path.join(diskdir, f)
    return None

# ---------------------------------------------------------------- 1988 family
HEADER_NOISE = re.compile(
    r'^Copyright|^For information|^<SHAREWARE>|^of its members|^not copyrighted|'
    r'^gain is|^is distributed|^program\(s\)|^information on|^for the programs|'
    r'^development\.|^releases are|^Fog Library Disk', re.I)

def parse_rich(text, disknum):
    """`-CPMnnn.DOC`: label, year, shareware marker, disk blurb, file table."""
    lines = [clean_line(l) for l in text.split('\n')]
    label = year = None
    shareware = False
    blurb, table, in_table = [], [], False
    # The boilerplate block is: the copyright paragraph, the "contact FOG"
    # line, and -- on most disks -- the <SHAREWARE> paragraph.  Anchor on
    # whichever of those is *last*, or the <SHAREWARE> paragraph becomes the
    # disk description.
    has_sh = bool(re.search(r'<SHAREWARE>', text, re.I))
    anchor = re.compile(r'registered users\.' if has_sh
                        else r'contact FOG, P\. ?O\. Box', re.I)
    boilerplate_done = False

    for l in lines:
        s = l.strip()
        m = re.search(r'Fog Library Disk\s+(FOG-CPM\.\d+)', l, re.I)
        if m:
            label = m.group(1)
        m = re.search(r'Copyright \((\d{4})\)', l)
        if m:
            year = int(m.group(1))
        if s.upper().startswith('<SHAREWARE>'):
            shareware = True
        if anchor.search(s):
            boilerplate_done = True
            continue
        if re.match(r'^Filename\s+Description', l):
            in_table = True
            continue
        if not in_table:
            if s and boilerplate_done:
                blurb.append(s)
        else:
            table.append(l)

    files = []
    date = None
    for l in table:
        if not l.strip():
            continue
        name = l[:NAME_COLS].strip()
        rest = l[NAME_COLS:]
        if not name:
            if files:                       # a wrapped description line
                files[-1]['desc'] += ' ' + rest.strip()
            continue
        if DATE_RE.match(name):
            date = name.replace(' ', '')    # e.g. `07-07.88`
            continue
        if SELF_RE.match(name):
            continue                        # this page describing itself
        m = re.match(r'\s*([0-9A-F]{4})?\s*(\d+K)?\s*(ver\.\s*[\d.]+)?'
                     r'\s*(?:\[(.*?)\])?\s*(.*)$', rest)
        files.append(dict(name=name, crc=m.group(1) or '',
                          size=(m.group(2) or '').strip(),
                          version=(m.group(3) or '').replace('ver.', '').strip(),
                          category=(m.group(4) or '').strip(),
                          desc=m.group(5).strip()))
    return dict(disk=disknum, label=label, year=year, shareware=shareware,
                blurb=' '.join(blurb).strip(), files=files, dialect='1988',
                date=date)

# ------------------------------------- 1985/87 family (colon or tab separated)
DATE_META = re.compile(r'^[-/](?:\d\d[-/]\d\d|[A-Z]{3}[-/]\d\d)')
LABEL_META = re.compile(r'^-*FOG[/:]?CPM|^--FOG')
SELF_META = re.compile(r'^[-/]*CPM\d{3}\s*\.DOC$')
# A real file line has a CP/M filename in the name field.  Without this, a
# wrapped description line whose text begins inside the first 12 columns reads
# as a filename -- ` coupons, pr` from FOG175's page becomes "coupons, pr".
CPM_NAME = re.compile(r"^[A-Z0-9$#@!%&'()\-+^_{}~`]{1,8}\s*\.\s*[A-Z0-9$#@!%&'()\-+^_{}~`]{0,3}$")

def split_line(l):
    """One catalogue line -> (name, crc, description), whatever the dialect.

    The name lives in the first 12 columns; what follows may be a colon, a
    tab, spaces, or any combination.  The CRC is either four hex digits or two
    hex bytes separated by a space (`26 4E`), which is why it is normalised.
    """
    name = l[:NAME_COLS].strip()
    rest = re.sub(r'^[:\s]+', '', l[NAME_COLS:])
    m = re.match(r'^([0-9A-F]{2}\s?[0-9A-F]{2}|[0-9A-F]{4})?(?:\s+|$)(.*)$', rest)
    if m:
        return name, (m.group(1) or '').replace(' ', ''), m.group(2).strip()
    return name, '', rest.strip()

def parse_flat(text, disknum):
    """The `::CPMnnn.DOC` / `-CPMnnn.DOC` pages that predate the rich format."""
    lines = [clean_line(l) for l in text.split('\n')]
    label = date = None
    blurb_parts = []
    files, meta, prev = [], [], None
    for l in lines:
        if not l.strip():
            continue
        if re.match(r'^\s*filename\b', l, re.I):
            continue                        # the column header
        name = l[:NAME_COLS].strip()
        if LABEL_META.match(name):
            label = name
            desc = split_line(l)[2]
            if desc:
                blurb_parts.append(desc)
            meta.append(('label', name, desc))
            continue
        if SELF_META.match(name):
            desc = split_line(l)[2]
            if desc:
                blurb_parts.append(desc)
            meta.append(('self', name, desc))
            continue
        if DATE_META.match(name):
            date = name.replace(' ', '')
            meta.append(('date', name, split_line(l)[2]))
            continue
        if name.startswith('/'):
            meta.append(('extra', name, split_line(l)[2]))
            continue
        if not CPM_NAME.match(name):
            # not a filename, so it is a wrapped description line
            if files:
                files[-1]['desc'] += ' ' + l.strip()
            continue
        _, crc, desc = split_line(l)
        if desc in ('"', "'"):
            desc = prev or ''               # the ditto convention
        else:
            prev = desc
        files.append(dict(name=name, crc=crc, size='', version='',
                          category='', desc=desc))
    return dict(disk=disknum, label=label, year=None, shareware=False,
                blurb=' '.join(blurb_parts).strip(), files=files,
                dialect='flat', date=date, meta=meta)


# ----------------------------------------------------------------------- main
def main(argv):
    root, outdir = argv[0], argv[1]
    disks_root = os.path.join(root, 'disks')
    os.makedirs(outdir, exist_ok=True)

    records = []
    for d in sorted(os.listdir(disks_root)):
        diskdir = os.path.join(disks_root, d)
        if not os.path.isdir(diskdir):
            continue
        doc = find_doc(diskdir)
        if not doc:
            records.append(dict(disk=d, dialect='none', files=[]))
            continue
        text = read_doc(doc)
        # Dialect is a property of the *page*, not of its filename, and not of
        # its banner either: FOG175 announces itself as "FOG LIBRARY DISK" and
        # is still a flat, tab-separated page.  The discriminator is the table
        # header -- the rich format has `Filename` immediately followed by
        # `Description`, the flat ones put a `CRC` column in between.
        rich = re.search(r'^\s*Filename\s+Description', text, re.M | re.I)
        r = parse_rich(text, d) if rich else parse_flat(text, d)
        r['docname'] = os.path.basename(doc)
        r['filecount_on_disk'] = sum(1 for f in os.listdir(diskdir)
                                     if os.path.isfile(os.path.join(diskdir, f)))
        records.append(r)

    json.dump(records, open(os.path.join(outdir, 'catalogue.json'), 'w'), indent=1)

    cols = ['disk', 'dialect', 'label', 'year', 'shareware', 'file', 'crc',
            'size', 'version', 'category', 'description']
    with open(os.path.join(outdir, 'catalogue.tsv'), 'w') as fh:
        fh.write('\t'.join(cols) + '\n')
        for r in records:
            for f in r['files']:
                fh.write('\t'.join([r['disk'], r.get('dialect', ''),
                                    (r.get('label') or '').replace('\t', ' '),
                                    str(r.get('year') or ''),
                                    'Y' if r.get('shareware') else '',
                                    f['name'], f['crc'], f['size'], f['version'],
                                    f['category'],
                                    f['desc'].replace('\t', ' ')]) + '\n')

    print('disks: %d' % len(records))
    for k in ('1988', 'flat', 'none'):
        print('  dialect %-5s %d' % (k, sum(1 for r in records if r.get('dialect') == k)))
    print('files catalogued: %d' % sum(len(r['files']) for r in records))
    print('disks with a blurb: %d' % sum(1 for r in records if r.get('blurb')))
    print('shareware-marked: %d' % sum(1 for r in records if r.get('shareware')))
    print('files with a category: %d'
          % sum(1 for r in records for f in r['files'] if f['category']))

    # coverage: what the disk's own page lists vs what is actually on the disk
    import collections
    cov = collections.Counter()
    for r in records:
        listed = {f['name'].replace(' ', '').upper() for f in r['files']}
        actual = {f.replace(' ', '').upper()
                  for f in os.listdir(os.path.join(disks_root, r['disk']))
                  if os.path.isfile(os.path.join(disks_root, r['disk'], f))}
        actual = {a for a in actual if not re.match(r'.*CPM\d{3}\.DOC$', a)}
        cov['listed'] += len(listed)
        cov['actual'] += len(actual)
        cov['both'] += len(listed & actual)
        cov['listed_not_on_disk'] += len(listed - actual)
        cov['on_disk_not_listed'] += len(actual - listed)
    print('coverage vs disk contents: %s' % dict(cov))
    return 0

if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
