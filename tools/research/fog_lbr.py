#!/usr/bin/env python3
"""fog_lbr.py - layer two: the 219 CP/M LBR libraries into per-disk dirs.

unar reads the LBR container natively (libxad has an LBR handler), including
the CP/M member compression schemes, so this only has to drive it and record
what failed.  Per-member failures are expected to be *interesting*: unar
checks each member's LBRCRC16, so a failure is either real damage in the
archive or a decompressor disagreement -- and the two are worth telling
apart, which is what the per-member log is for.
"""
import os
import re
import shutil
import subprocess
import sys
import time

def wipe(path):
    """Remove a directory, and *verify* it is gone.

    This is not paranoia.  `shutil.rmtree(..., ignore_errors=True)` was here
    first, and it silently left the tree behind on a volume where Finder keeps
    recreating `.DS_Store` mid-delete -- after which unar, which does not
    overwrite on a name collision even with -f, wrote `NAME 2` beside every file
    instead of replacing it.  The result was a doubled tree that still passed
    every check the script made, because nothing was checking the thing that had
    actually gone wrong.

    So: retry a few times, then raise.
    """
    if not os.path.exists(path):
        return
    for _ in range(5):
        shutil.rmtree(path, ignore_errors=True)
        if not os.path.exists(path):
            return
        time.sleep(0.5)
    raise RuntimeError('could not remove %s -- refusing to extract into it' % path)


def main(argv):
    out = argv[0]
    lbrdir = os.path.join(out, 'lbr')
    disks = os.path.join(out, 'disks')
    logdir = os.path.join(out, 'log')
    # Start clean, and *prove* it.  See wipe() for why this matters.
    wipe(disks)
    for d in (disks, logdir):
        os.makedirs(d, exist_ok=True)

    lbrs = sorted(f for f in os.listdir(lbrdir) if f.upper().endswith('.LBR'))
    clean, partial = [], []
    for f in lbrs:
        p = os.path.join(lbrdir, f)
        r = subprocess.run(['unar', '-q', '-f', '-o', disks, p],
                           capture_output=True, text=True)
        msg = (r.stdout + r.stderr).strip()
        open(os.path.join(logdir, f + '.log'), 'w').write(msg)
        dest = os.path.join(disks, os.path.splitext(f)[0])
        n = sum(len(fs) for _, _, fs in os.walk(dest))
        if r.returncode == 0:
            clean.append((f, n))
        else:
            bad = [l.strip() for l in msg.splitlines()
                   if 'Failed' in l or 'failed' in l]
            partial.append((f, n, bad))

    print('LBR layer: %d libraries' % len(lbrs))
    print('  fully extracted: %d' % len(clean))
    print('  with failed members: %d' % len(partial))
    total = sum(n for _, n in clean) + sum(n for _, n, _ in partial)
    print('  files extracted: %d' % total)
    for f, n, bad in partial:
        print('    %-14s %2d files, %s' % (f, n, '; '.join(bad) or 'see log'))

    # ---------------------------------------------------------------- verify
    #
    # The check that was missing.  unar does not overwrite on a name collision
    # even with -f: it writes `NAME 2` beside the original.  So a run against a
    # directory that was not actually wiped does not fail -- it doubles, and
    # every count the script reports still looks plausible.  That is exactly
    # what happened, and the doubled tree then fed a catalogue.
    #
    # `NAME <n>` is unar's collision marker, so its presence is the signature of
    # the bug rather than a style question.  A CP/M filename cannot contain a
    # space, so there is no legitimate match.
    stray = re.compile(r' [0-9]+(\.[A-Za-z0-9]+)?$')
    hits = []
    for f in sorted(os.listdir(disks)):
        d = os.path.join(disks, f)
        if os.path.isdir(d):
            hits += ['%s/%s' % (f, n) for n in os.listdir(d) if stray.search(n)]
    if hits:
        print('  ** %d collision-named files -- the tree is doubled or worse **'
              % len(hits))
        for h in hits[:10]:
            print('       %s' % h)
        return 1
    print('  no collision-named files: the tree is not doubled')
    return 0

if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
