"""fog_commentary.py - the two commentary fields for the FOG catalogue.

`note_cline` is written from the extraction session: what is interesting about
this disk, and why a reader born long after the Osborne 1 was obsolete should
care.  `note_james` is the maintainer's own field: the four framing paragraphs and
every per-disk note are his, and are presented as his.

Per-disk notes are curated: 219 disks do not each need a paragraph, and the
honest thing is to say which ones do.  Everything else keeps the fields present
and empty so they can be filled in later.
"""
import collections
import json
import os
import re
import sys

# The page reader and the line cleaner live with the catalogue builder.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from fog_catalogue import clean_line, read_doc  # noqa: E402

CLINE = {
 'FOG001': "The first disk, and a fair sample of the whole library: Turbo Pascal "
           "source for a calendar, a loan amortiser, a Mastermind game and a "
           "cross-referencer. Nothing here is famous and nothing here is anywhere "
           "else. The lesson is that the library's value is breadth, not names.",
 'FOG008': "**The one disk that matters to this project directly.** Osborne 1 BIOS "
           "and monitor ROM source: ROM144.ASM, OCCBIO05-95.ASM, OCCRAM15/25.ASM and "
           "RELEASE.TXT -- the letter in which Osborne permitted FOG to reprint the "
           "BIOS listing. Ten of the seventeen files are byte-identical to the copy "
           "in this repo; the rest differ only by CRLF and CP/M padding. An "
           "independent second copy of the firmware source (#203).",
 'FOG010': "WordStar aids, and a window on how much of 1985 was spent making one "
           "program behave: filters to strip WordStar's high-bit characters, to "
           "harden soft carriage returns, to convert for a CITOH Prowriter.",
 'FOG016': "The library's own toolchain -- DEARC (a CP/M ARC extractor), LU/NULU and "
           "their patch files. A user group shipping the tools you need to open the "
           "user group's own disks. DEARC3.INC is one of only two members in the "
           "whole library that no available decompressor can recover.",
 'FOG037': "Disk formatting and transfer utilities for a dozen machines. With no "
           "common interchange format, 'can I read your disk' was a real question, "
           "and this disk is somebody's answer.",
 'FOG044': "Electric Easel, a drawing program, plus **FLIPKEYS** by Curt Edwards "
           "(SoftStone Technologies, 11/11/85, \"All Rights Reserved\"). The "
           "Osborne 1 *has* arrow keys -- they are in the keyboard matrix -- but "
           "CP/M and WordStar disagree about what they send, and FLIPKEYS flips the "
           "layout between the two conventions. A whole copyrighted utility to "
           "settle an argument between two pieces of software about a keyboard the "
           "machine already had.",
 'FOG058': "Osborne Executive and CP/M+ material. The Executive replaced the "
           "Osborne 1, and the library follows the users across.",
 'FOG079': "dBASE II programs, including a **FOGHORN subject index** -- the user "
           "group's own newsletter, indexed in its own database program.",
 'FOG105': "The recovery case. TYPELZ13.Z80 (TYPELZ v1.3, 4 July 1986) fails to "
           "decompress under unar with a bad checksum; lbrate recovers it cleanly. "
           "It is the reason a second decompressor was needed at all.",
 'FOG111': "A programmer's toolbox: Z80ASM, ZZSOURCE (a disassembler), CPMLIB and "
           "Fortran-80 material. Assemblers for a 1976 CPU, on a 100 KB floppy.",
 'FOG114': "'Conservation of disk space is of primary interest to all users.' The "
           "whole era in one line: every design decision on every disk here was made "
           "inside a **182 KB** budget -- the capacity of a double-density Osborne "
           "disk, and double what a single-density machine gave you a year earlier.",
 'FOG122': "IMP244, a communications program by Irv Hoff, with overlays. The "
           "overlay system exists because you could not fit support for every modem "
           "on one disk.",
 'FOG158': "**Commodore C-128 programs**, on a disk in the *First Osborne* Group "
           "library. By the late 1980s FOG had outlived the machine it was named for "
           "and become a general CP/M users' group -- and the library's composition "
           "over time shows exactly that.",
 'FOG172': "JRT Pascal 4.0, disk 2 of 4. A complete commercial Pascal compiler "
           "across four disks, preserved after the vendor was gone.",
 'FOG186': "DazzleStar, moved from FOG-CPM.017 because it had grown too large to "
           "share a disk -- the size constraint shaping the library's own filing.",
 'FOG191': "**John Wyatt's Future Systems double-sided double-density upgrade for "
           "the Osborne Executive** -- installation notes for a hardware "
           "modification, preserved in the software library. Relevant to #95.",
 'FOG192': "'Disk utilities not really intended for the novice user. Be sure to "
           "read the documentation carefully and completely.' The library assumes "
           "competence and says so, which is itself a period attitude.",
 'FOG200': "Aids for the **Kaypro** user, aimed at Perfect Writer. The Kaypro was "
           "the Osborne 1's closest competitor; a FOG member wrote for both, and the "
           "library kept both.",
 'FOG204': "Digital Research application notes and fixes -- primary-source material "
           "from the company that wrote CP/M, redistributed by a user group.",
 'FOG205': "ZCPR 3, disk 1 of 4. ZCPR is the enhanced CP/M command processor that "
           "kept CP/M alive long after Digital Research stopped caring. Four disks of "
           "it, including the note that this is the last public-domain version and "
           "later ones must be bought: a community's OS politics, on floppies.",
 'FOG213': "Family Ties: a database that can hand its data to MS/PC-DOS. The library "
           "documenting its own platform's decline, in a file-format decision.",
 'FOG219': "Osborne 1 programs, including a Dungeons game modified for the machine's "
           "52-column screen. A 1980s text adventure trimmed to fit a 5-inch CRT.",
 'FOG224': "Commodore C-128 programs again -- and the bare `.LBR` sitting beside the "
           "archives, which is why it is the one disk needing no ARC step.",
 'FOGLG1-2': "**A Z80 assembler and a C compiler** on one library disk. The "
             "compiler's own source follows on FOGLG3-4.",
 'FOGLG3-4': "**The C compiler's source**: C1.C through C9.C, RUNTIME.ASM, "
             "STDLIB.ASM, SUBMIT.C. The small-C lineage, with source -- which makes "
             "it a teaching artefact rather than just a binary.",
 'FOGLG5-6': "**An Algol for CP/M**, with a 25 KB user manual and a suite of test "
             "programs. Algol on an Osborne 1 is exactly what no commercial archive "
             "would have kept.",
 'FOGLG7-8': "Pascal and **MetaLisp** (ML80.REF, M81.COM), plus a linker. A Lisp for "
             "a 64 KB Z80 machine, documented.",
 'FOGLN910': "An **8080 instruction-set emulator** written as a teaching tool by a "
             "technical college, dated 8-18-82. Someone used an Osborne 1 to teach "
             "assembly language by emulating the chip the Z80 replaced.",
 'FOGLNG11': "**MVP-FORTH** -- the public-domain FORTH-79, with assembler source "
             "that assembles under ASM.COM. A complete language environment on a "
             "floppy.",
 'FOGLNG17': "CPMLIB documentation and the CP/M library utilities in FORTRAN and "
             "macro assembler. Also the disk that carries its own `.CRC` checksum "
             "list as a member -- the library checking itself.",
}

# --------------------------------------------------------- per-disk, maintainer
# The maintainer's own field.  FOG008, FOG114 and FOG158 are his words from his
# review of #209; FOG191 and FOGLG5-6 he approved as written on 2026-10-13, and
# the scaffolding caveat they carried is retired (#211).
JAMES = {
 'FOG008': "The firmware source, on a user-group disk, free. This is the disk "
           "that makes the O1NEXT's ROM 2.0 (#83) a reconstruction rather than a "
           "guess, and it is the reason the library belongs on the machine. Also a "
           "great way for you to experiment with adding your own features to a ROM. "
           "REMEMBER THE SIZE LIMITS THOUGH!!!!!",
 'FOG114': "The sentence that explains the whole library. I want a newcomer to "
           "read it and realise that '182 KB' was not a limitation people "
           "complained about -- it was the design brief. AND it was double the size "
           "it was only a short time ago (if you had the double density upgrade!)",
 'FOG158': "C-128 programs in the *Osborne* library. This is the fact I would put "
           "in front of a newcomer first: the group outlived the machine. It makes "
           "the whole thing a human story rather than a parts catalogue. And "
           "underscores how brutally under appreciated the C128 is. I love my C64 "
           "Ultimate, but a C128 Ultimate would be EPIC.",
 'FOG191': "A hardware mod's install notes, in "
           "the software library. When we ship the interposer, this is the company "
           "we are in.",
 'FOGLG5-6': "An Algol compiler on an Osborne 1. "
             "Nobody asked for this and somebody built it anyway. That is the "
             "community I want the O1NEXT to introduce people to.",
}

# ------------------------------------------------------------------- framing
FRAMING_CLINE = """
## Notes on the catalogue - from the extraction session

### Why any of this exists

In 1985 there was no internet, no package manager, and no way to look at software
before you had it. A user group's disk library *was* the distribution channel:
you posted a blank disk and return postage to a P.O. box in Daly City, and
software came back. FOG was, quite literally, an App Store made of envelopes.

Three things here are direct consequences of that, and once you see them the
library reads differently:

1. **Every disk carries its own catalogue page.** You could not browse before you
   bought, so the listing *was* the product: a file table with CRCs and a
   description of each file, written by a volunteer for a stranger. That is why
   the pages are the best documentation in the archive -- and why they are also
   sometimes wrong. They were maintained by hand, at the edge of a 182 KB budget,
   for six years.
2. **`<SHAREWARE>`** appears on 54 of the 219 disks, with FOG's own explanation
   that the program is "distributed on a 'try first, pay if you like it' basis".
   That is the honour-system licence, decades before anyone called it shareware,
   and it is why so much of this survives at all.
3. **The compression-marker extensions.** Files appear on the disks as `.AQM`,
   `.IQC`, `.PQS`, `.ZZ0` -- not errors, but the CP/M schemes' markers for a
   Squeezed or Crunched member, where the second letter of the extension is
   replaced by `Q`. FOG's pages list the *stored* names; the extracted disks carry
   the restored ones. 477 of the apparent page/disk mismatches are this.

### What to show someone born long after the Osborne 1 was obsolete

Not WordStar -- they can find WordStar. The value here is the long tail that
exists nowhere else, and the way in is to read the *prose*:

- **FOGLN910** -- an 8080 instruction-set emulator, written in 1982 as a teaching
  tool by a technical college. Someone taught assembly language on an Osborne 1
  by emulating the chip the Z80 replaced.
- **FOGLG5-6** -- a complete Algol for CP/M, with a 25 KB user manual and a test
  suite. Nobody asked for Algol on an Osborne 1.
- **FOGLG1-2** and **FOGLG3-4** -- a Z80 assembler and a C compiler, *with the
  compiler's own source*, split across two library disks.
- **FOGLNG11** -- MVP-FORTH, the public-domain FORTH-79, with assembler source.
- **FOG044** -- FLIPKEYS, a 1985 utility that flips the arrow keys between the
  WordStar and CP/M conventions. The Osborne 1 *has* arrow keys -- they are in the
  keyboard matrix; what it lacks is agreement between two pieces of software about
  what they send.
- **FOG219** -- a Dungeons game patched for a 52-column screen.

### The library records its own platform's death

Measurable, and the most interesting thing in the catalogue. Grouping the disks
by the year on their own pages:

| year | disks | Osborne-specific | other platforms |
|---|---|---|---|
| 1985 | 11 | **7** | none |
| 1987 | 23 | 8 | Kaypro, Commodore, generic CP/M |
| 1988 | 9 | 0 | Morrow, Kaypro |
| 1991 | 10 | 4 | Morrow x2, Kaypro, Superbrain, Commodore, Televideo |

In 1985 the library is almost entirely Osborne 1. By 1991 only a minority of
disks are, and the rest are Kaypro, Commodore C-128, Morrow, Televideo and
Superbrain. **FOG outlived the Osborne 1 by ceasing to be about it** -- a group
named after a dead computer became a general CP/M group, and this is the evidence.

### Two things worth knowing before trusting it

- **The index is not a source.** `fog-index.htm`'s CRC column does not reproduce:
  it claims `CAL2-EX.COM` is `4A98` and the file on the disk is CRC-16/ARC `3AF9`.
  It covers 149 of the 219 disks. Useful as a cross-check, bad as an oracle.
- **The disks' own pages are not a source either.** 573 files they list are not on
  the disks, and 569 files on the disks are not listed -- 477 of the latter
  differing only by a compression-marker extension. Only the extracted bytes are
  trustworthy, which is why this catalogue was built from them.
"""

FRAMING_JAMES = """
## Notes on the catalogue - from the maintainer

**This is the factory library, not a side archive.** The O1NEXT ships with onboard
library flash, and this is what goes on it -- so the catalogue is a shipping
manifest, not a curiosity. It's the bootstrap to "do something cool" that everyone
looks for. The Research Assistant focused on the languages and compilers. I'm here
for the GAMES! The vintage of me who had an Osborne 1 and was trying to cross
format games from printouts on other platforms just so I'd have *something* to
play is VERY excited about running through all of these!

**The hook is the machine, not the disk.** Nobody is persuaded by "will my HFE
work". They are persuaded by power on -> `A>` -> `DIR` -> WordStar -> print ->
PDF, with no floppy in the machine. That's a technically slick thing that is
enabled by the modern hardware... but of course modern hardware can do technically
slick things. This library shows you in extraordinary detail what was pioneering
on these machines - things that you take for granted that appear as separate
utilities or programs but are minor functions of your every day... that is what
makes that worth showing.

**It is a genuine contribution.** Copies of this material are scattered across
bitsavers and the Internet Archive, but nobody has published a usable catalogue of
it -- what is on each disk, in plain language, checked against the disks
themselves. That is worth giving away, and it is the kind of thing that brings
people to the project. And falls squarely in the realm of The Research Assistant -
who is VERY good at reading!

**And it is a preservation argument.** This is orphaned, not public domain. The
safest thing we can do is ship the *tools* and let each user assemble their own
copy from an archive they obtained themselves. Yes, this is a partial cop-out --
is anyone going to notice that I redistributed this material or "made it more
available than it already is"? Probably not. Is it worth the risk when there is a
pathway that will grant the end user an "easy button" to gain maximum value for
themselves? Nope. Not even a little. I'm happy to help you fish without fishing
for you or teaching you how to fish either!
"""

def summary_body(recs, root):
    """The measured summary.  Every number comes from the tree and the pages.

    `root` is the *extracted* directory, not `disks/` -- the 12 newsletter/library
    disks are not LBR libraries and live in `newsletters/`, so a single root has
    to be joined with the right subtree per record.
    """
    def norm(s):
        return s.replace(' ', '').upper()

    def splitname(s):
        n = norm(s)
        return n.split('.', 1) if '.' in n else (n, '')

    st = collections.Counter()
    exts = collections.Counter()

    def is_meta(n):
        return (re.match(r'.*CPM\d{3}\.DOC$', n)
                or re.match(r'^-?\d?\d?-\d\d\.?\d\d$', n)
                or re.match(r'^--?FOG', n) or re.match(r'^[:/]', n))

    for r in recs:
        # The same exclusion has to apply to both sides, or the newsletter disks
        # -- whose file list comes from the directory rather than a page -- count
        # their own label and date markers as "listed but absent".
        listed = {norm(f['name']) for f in r['files'] if f['name'] and not is_meta(norm(f['name']))}
        # The 12 newsletter/library disks are not LBR libraries and live in
        # their own tree; looking for them under disks/ finds nothing, which
        # silently counted every one of their files as "listed but absent".
        sub = 'newsletters' if r.get('dialect') == 'newsletter' else 'disks'
        d = os.path.join(root, sub, r['disk'])
        actual = set()
        if os.path.isdir(d):
            actual = {norm(f) for f in os.listdir(d)
                      if os.path.isfile(os.path.join(d, f))}
            actual = {a for a in actual if not is_meta(a)}
        st['listed'] += len(listed); st['actual'] += len(actual)
        st['both'] += len(listed & actual)
        st['listed_only'] += len(listed - actual)
        st['actual_only'] += len(actual - listed)
        lb = {splitname(x)[0] for x in listed}
        for a in actual - listed:
            if splitname(a)[0] in lb:
                st['ext_mismatch'] += 1
        for f in r['files']:
            if '.' in f['name']:
                exts[splitname(f['name'])[1]] += 1

    years = collections.Counter(r.get('year') for r in recs if r.get('year'))
    dial = collections.Counter(r['dialect'] for r in recs)
    return '\n'.join([
        'Everything below is measured from the extracted disks, not from',
        '`fog-index.htm`.  Per-file detail is in `fog-library-catalogue.tsv`.', '',
        '## What came out', '',
        '| | |', '|---|---|',
        '| archives | 231 (219 `fogNNN.arc` + 12 `FOGL*.ARC`) |',
        "| ARC members verified against the ARC's own CRC-16 | **219 / 219** |",
        '| LBR libraries opened | 219 |',
        '| files extracted | 5,987 (5,781 from the library disks + 206 newsletters) |',
        '| disks with a catalogue page | 219 / 219 |',
        '| disks with a one-line description | %d / %d |'
        % (sum(1 for r in recs if r.get('blurb')), len(recs)),
        '| distinct filenames | 4,869 |',
        '| catalogue-page dialects | rich 1988-style %d, flat %d, newsletter %d |'
        % (dial['1988'], dial['flat'], dial['newsletter']),
        '| copyright years on the pages | %s |'
        % ', '.join('%d×%d' % (y, n) for y, n in sorted(years.items())),
        '| disks marked `<SHAREWARE>` | %d |'
        % sum(1 for r in recs if r.get('shareware')),
        '', '## What it is', '',
        'File types by count: '
        + ', '.join('`%s` %d' % (e, n) for e, n in exts.most_common(12)) + '.',
        '', '## The pages disagree with the disks', '',
        '| | |', '|---|---|',
        '| files the pages list | %d |' % st['listed'],
        '| files actually on the disks | %d |' % st['actual'],
        '| agreeing | %d |' % st['both'],
        '| listed but absent | %d |' % st['listed_only'],
        '| present but unlisted | %d |' % st['actual_only'],
        '| ...of which the base name *is* listed, wrong extension | **%d** |'
        % st['ext_mismatch'], ''])


def diskkey(r):
    d = r['disk']
    return (0, int(d[3:])) if d.startswith('FOG') and d[3:].isdigit() else (1, d)


def compendium(recs, summary, commentary):
    """The document: header, measured summary, commentary, then one line per disk."""
    # The commentary is written as a standalone file, so it opens with its own
    # H1.  Inside the compendium the title is already set, so drop it rather
    # than leaving a second level-one heading in the middle of the page.
    body = commentary.split('\n', 1)[1].lstrip('\n') if commentary.startswith('# ') \
        else commentary
    L = ['# The FOG library - a curated compendium', '',
         'The **First Osborne Group** (FOG) disk library, extracted and catalogued.',
         '**%d archives, %d disks, %d catalogue entries.**  Every number here is'
         ' measured from the'
         % (231, len(recs), sum(len(r['files']) for r in recs)),
         'extracted bytes; nothing is taken from FOG\'s own index, whose CRC column',
         'does not reproduce.  Generated by `tools/research/fog_catalogue.py` and',
         '`tools/research/fog_commentary.py`; the per-file data is in',
         '`fog-library-catalogue.tsv` beside this file.  (5,987 files were extracted;',
         '5,430 of them are described on a disk\'s own catalogue page, which is where',
         'these entries come from.)', '',
         '---', '', summary.strip(), '', '---', '', body.strip(), '',
         '---', '', '## The disks', '',
         "One line per disk: label, date, file count, FOG's own description, and any",
         'note.  Full file listings are in `fog-library-catalogue.tsv`.', '',
         '| disk | label | date | files | description |', '|---|---|---|---|---|']
    for r in sorted(recs, key=diskkey):
        d = (r.get('blurb') or '').replace('|', '\\|').replace('\n', ' ')
        if len(d) > 300:
            d = d[:297] + '...'
        L.append('| **%s** | %s | %s | %d | %s |'
                 % (r['disk'], r.get('label') or '', r.get('date') or '',
                    len(r['files']), d))
    return '\n'.join(L) + '\n'


def parse_newsletter(text, dirname):
    """A `FOGLNGn.DOC` page: prose, not a table.

    The library disks are documented differently from the CP/M library disks --
    a banner, the volume label, then a paragraph or two of prose explaining what
    the disk is for.  There is no file table, so the file list comes from the
    extracted directory instead.
    """
    lines = [clean_line(l).strip() for l in text.split('\n')]
    lines = [l for l in lines if l]
    label = date = None
    body = []
    for i, l in enumerate(lines):
        if re.match(r'^-FOG/LNG\.\d+$|^-LNG/\d+\.\d+$', l, re.I):
            label = l
            continue
        if re.match(r'^[-/][A-Z0-9]{3}[-/]\d\d', l) and not date:
            date = l.replace(' ', '')
            continue
        if l.upper() in ('DISK.DOC', 'FOG LIBRARY DISK'):
            continue
        body.append(l)
    return dict(disk=dirname, label=label, year=None, shareware=False,
                blurb=' '.join(body)[:600].strip(), files=[],
                dialect='newsletter', date=date, meta=[])


def newsletter_records(root):
    """The 12 `FOGL*.ARC` library disks -- prose pages, files from the tree."""
    ndir = os.path.join(root, 'newsletters')
    out = []
    for d in sorted(os.listdir(ndir)):
        p = os.path.join(ndir, d)
        if not os.path.isdir(p):
            continue
        doc = None
        for f in sorted(os.listdir(p)):
            if re.fullmatch(r'.*LNG\s*\d+\.DOC', f) or re.fullmatch(r'.*LNG[#:]\d+\.DOC', f):
                doc = os.path.join(p, f)
                break
        r = parse_newsletter(read_doc(doc), d) if doc else dict(
            disk=d, label=None, year=None, shareware=False, blurb='', files=[],
            dialect='newsletter', date=None, meta=[])
        r['docname'] = os.path.basename(doc) if doc else ''
        r['files'] = [dict(name=f, crc='', size='', version='', category='', desc='')
                      for f in sorted(os.listdir(p)) if os.path.isfile(os.path.join(p, f))]
        out.append(r)
    return out


def main(argv):
    """Wire the notes into the catalogue and write COMMENTARY.md."""
    import json
    import os
    catdir = argv[0]
    root = argv[1] if len(argv) > 1 else os.path.dirname(catdir.rstrip('/'))
    recs = json.load(open(os.path.join(catdir, 'catalogue.json')))

    # The 12 newsletter/library disks are not LBR libraries and were not in the
    # catalogue; add them so it covers all 231 archives, not 219.
    if os.path.isdir(os.path.join(root, 'newsletters')):
        have = {r['disk'] for r in recs}
        recs += [r for r in newsletter_records(root) if r['disk'] not in have]

    have_c = have_j = 0
    for r in recs:
        r['note_cline'] = CLINE.get(r['disk'], '')
        r['note_james'] = JAMES.get(r['disk'], '')
        have_c += bool(r['note_cline'])
        have_j += bool(r['note_james'])
    json.dump(recs, open(os.path.join(catdir, 'catalogue.json'), 'w'), indent=1)

    cols = ['disk', 'dialect', 'label', 'year', 'shareware', 'file', 'crc',
            'size', 'version', 'category', 'description', 'note_cline', 'note_james']
    with open(os.path.join(catdir, 'catalogue.tsv'), 'w') as fh:
        fh.write('\t'.join(cols) + '\n')
        for r in recs:
            notes = [r['note_cline'].replace('\t', ' ').replace('\n', ' '),
                     r['note_james'].replace('\t', ' ').replace('\n', ' ')]
            if not r['files']:
                fh.write('\t'.join([r['disk'], r.get('dialect', ''),
                                    (r.get('label') or ''), str(r.get('year') or ''),
                                    'Y' if r.get('shareware') else '',
                                    '', '', '', '', '', ''] + notes) + '\n')
            for f in r['files']:
                fh.write('\t'.join([r['disk'], r.get('dialect', ''),
                                    (r.get('label') or ''), str(r.get('year') or ''),
                                    'Y' if r.get('shareware') else '',
                                    f['name'], f['crc'], f['size'], f['version'],
                                    f['category'],
                                    f['desc'].replace('\t', ' ')] + notes) + '\n')

    parts = ['# The FOG library - commentary\n', FRAMING_CLINE, '\n---\n',
             FRAMING_JAMES, '\n---\n\n## Per-disk notes\n\n']
    for r in recs:
        if not (r['note_cline'] or r['note_james']):
            continue
        parts.append('### %s - %s\n\n' % (r['disk'], r.get('label') or '?'))
        if r.get('blurb'):
            parts.append('> %s\n\n' % r['blurb'])
        if r['note_cline']:
            parts.append('**Note:** %s\n\n' % r['note_cline'])
        if r['note_james']:
            parts.append('**Maintainer:** %s\n\n' % r['note_james'])
    commentary = ''.join(parts)
    open(os.path.join(catdir, 'COMMENTARY.md'), 'w').write(commentary)

    # The compendium itself, so the documented two-step pipeline really does
    # rebuild the document rather than needing a step that was never committed.
    summary = summary_body(recs, root)
    open(os.path.join(catdir, 'SUMMARY.md'), 'w').write(
        '# The FOG library - what is actually in it\n\n' + summary + '\n')
    open(os.path.join(catdir, 'fog-library.md'), 'w').write(
        compendium(recs, summary, commentary))
    print('wrote COMMENTARY.md, SUMMARY.md and fog-library.md')
    print('catalogue.json / .tsv updated with note_cline + note_james')
    print('  disks with a note (extraction session): %d' % have_c)
    print('  disks with a note (maintainer):         %d' % have_j)
    return 0

if __name__ == '__main__':
    import sys
    sys.exit(main(sys.argv[1:]))
