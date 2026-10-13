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
import shutil
import subprocess
import sys

def main(argv):
    out = argv[0]
    lbrdir = os.path.join(out, 'lbr')
    disks = os.path.join(out, 'disks')
    logdir = os.path.join(out, 'log')
    # Start clean.  Running this twice is not idempotent otherwise: unar does
    # not overwrite an existing file on a name collision even with -f, it
    # writes `NAME 2` beside it, so a second pass silently doubles the tree.
    shutil.rmtree(disks, ignore_errors=True)
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
    return 0

if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
