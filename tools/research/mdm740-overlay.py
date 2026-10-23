#!/usr/bin/env python3
"""mdm740-overlay.py - install a Comm-Pac overlay into MDM740.COM, off the drive.

WHY THIS EXISTS

    FOG126 carries MDM740 as the **uninstalled distribution**: one .COM with a
    placeholder overlay, and the note "An overlay for your specific computer is
    required" on the disk's own page.  The overlay this machine needs is
    **M7OD-5** -- "Osborne 1 w/Comm-Pac or CTS Datacomm modem" -- which FOG129
    stores as `M7OD-5.AQM`, i.e. `M7OD-5.ASM`, *source*, squeezed.

    Without it the program does not know it is on a Comm-Pac: its banner reads
    "Version for PMMI S-100 modem starting at port: C0H", it leaves the modem
    control bit alone, and the 300-baud default that the Comm-Pac needs is not
    the one it sets.  A drive carrying the uninstalled copy cannot talk to this
    machine's modem, which is what "that's not a useful mdm740" meant.

HOW IT IS DONE, AND WHY NOT WITH DDT

    M7OD-5.ASM's own header says:

        A>ASM M7OD-5                 (CP/M 2.2's 8080 assembler)
        A>DDT MDM740.COM
        -IM7OD-5.HEX
        -R
        -G0
        A>SAVE 73 MDM740.COM         (73 pages = 18688 bytes)

    That is the only route to a correct overlay, because this project has no
    8080 assembler on the host and the FOG library has none at all -- but
    **ASM.COM is on the shipped system disk**, and `populate-hd.py --stage` puts
    it, DDT and the overlay's source on the drive, so the machine can assemble
    it itself.  That is the step before this one:

        SDL_VIDEODRIVER=dummy mame osborne1nx -video none -sound none \\
          -nothrottle -rompath tools/emulator-setup/roms \\
          -softrom <staged>/assets/rom2.rom -harddisk <staged>/assets/hd.chd \\
          -autoboot_script tools/research/mdm740-assemble.lua -seconds_to_run 200

    and it leaves `M7OD-5.HEX` on B:.  This tool then does what DDT would have
    done -- and DDT *is* a byte copy: each Intel HEX record's bytes go to its own
    absolute address, less the 0x100 a CP/M .COM is loaded at -- but on the host,
    where it is repeatable, and where the result can be diffed.

USAGE

    tools/research/mdm740-overlay.py --drive <hd.chd> --tree ~/Documents/O1NEXT/hd
    tools/research/mdm740-overlay.py --hex /tmp/M7OD-5.HEX --tree ~/Documents/O1NEXT/hd

    The patched file replaces `<tree>/B/MDM740.COM`, so `populate-hd.py --write`
    puts the *installed* build on the drive, and the tree's manifest records
    where it came from.
"""
import argparse
import importlib.util
import os
import shutil
import subprocess
import sys
import tempfile

PAGE = 256                # CP/M's record size; DDT's SAVE counts these
PAGES = 73                # what M7OD-5's recipe saves: 18688 bytes
OVERLAY = 'M7OD-5.HEX'
BANNER = b'Version for Osborne COMM-PAC modem'


def load_populate():
    """populate-hd.py owns the drive's geometry; import it rather than copy it."""
    here = os.path.dirname(os.path.abspath(__file__))
    spec = importlib.util.spec_from_file_location(
        'populate_hd', os.path.join(here, 'populate-hd.py'))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def read_overlay_from_drive(ph, drive, chdman):
    """Extract B: as its own image and read M7OD-5.HEX out of it."""
    work = tempfile.mkdtemp(prefix='mdm740-overlay-')
    raw = os.path.join(work, 'drive.raw')
    subprocess.run([chdman, 'extracthd', '-i', drive, '-o', raw, '-f'],
                   check=True, stdout=subprocess.DEVNULL)
    parts = ph.partitions(raw)
    cpm = parts[1:12]
    if len(cpm) < 2:
        sys.exit('%s: %d CP/M partitions, so there is no drive B:' % (drive, len(cpm)))
    b = cpm[1]
    with open(raw, 'rb') as f:
        f.seek(b['start'] * 512)
        part = f.read(b['blocks'] * 512)
    partfile = os.path.join(work, 'b.part')
    open(partfile, 'wb').write(part)

    # cpmtools reads `./diskdefs` from the *working directory* -- the same
    # discovery populate-hd.py's --write is built on -- so run it there.
    defs = tempfile.mkdtemp(prefix='mdm740-defs-')
    ph.diskdefs(defs)
    out = os.path.join(work, OVERLAY)
    r = subprocess.run(['cpmcp', '-T', 'raw', '-f', 'md10', partfile,
                        '0:' + OVERLAY, out], cwd=defs)
    if r.returncode or not os.path.exists(out):
        sys.exit('no %s on drive B: -- assemble it on the machine first '
                 '(mdm740-assemble.lua)' % OVERLAY)
    return out


def patch(hexfile, comfile):
    """Place each Intel HEX record at its own address, less the 0x100 origin."""
    image = bytearray(open(comfile, 'rb').read())
    placed, high = 0, 0
    for line in open(hexfile):
        line = line.strip()
        if not line.startswith(':'):
            continue
        n = int(line[1:3], 16)
        addr = int(line[3:7], 16)
        for i, byte in enumerate(bytes.fromhex(line[9:9 + n * 2])):
            at = addr + i - 0x100
            if at >= len(image):
                image.extend(b'\x00' * (at + 1 - len(image)))
            image[at] = byte
        placed += n
        high = max(high, addr + n)
    image = bytes(image[:PAGES * PAGE]).ljust(PAGES * PAGE, b'\x00')
    open(comfile, 'wb').write(image)
    return placed, high


def note_manifest(tree, text):
    """Say what the file now is, in the manifest the tree carries."""
    path = os.path.join(tree, 'B', 'MANIFEST.txt')
    if not os.path.exists(path):
        return
    out = []
    for line in open(path):
        if line.startswith('MDM740.COM\t'):
            line = 'MDM740.COM\tFOG126 + FOG129\t%s\n' % text
        out.append(line)
    open(path, 'w').writelines(out)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[1])
    ap.add_argument('--tree', default='~/Documents/O1NEXT/hd',
                    help='the staging tree (default ~/Documents/O1NEXT/hd)')
    ap.add_argument('--drive', help='the staged hd.chd to take M7OD-5.HEX from')
    ap.add_argument('--hex', help='an already-extracted M7OD-5.HEX (no drive needed)')
    ap.add_argument('--chdman', help='chdman, if it is not where the stage script '
                                     'looks for it')
    args = ap.parse_args()

    tree = os.path.expanduser(args.tree)
    com = os.path.join(tree, 'B', 'MDM740.COM')
    if not os.path.exists(com):
        sys.exit('%s: no MDM740.COM -- run populate-hd.py --stage first' % com)

    if args.hex:
        hexfile = os.path.expanduser(args.hex)
    else:
        drive = args.drive or os.path.expanduser('~/Documents/O1NEXT/o1next/assets/hd.chd')
        chdman = args.chdman or shutil.which('chdman')
        if not chdman:
            for cand in ('~/scratch/mame-mame0289/chdman',
                         '~/scratch/mame-verify/mame-mame0289/chdman'):
                cand = os.path.expanduser(cand)
                if os.path.exists(cand):
                    chdman = cand
                    break
        if not chdman:
            sys.exit('no chdman: pass --chdman, or --hex with the file already out')
        hexfile = read_overlay_from_drive(load_populate(), os.path.expanduser(drive),
                                          chdman)

    placed, high = patch(hexfile, com)
    installed = BANNER in open(com, 'rb').read()
    note_manifest(tree, 'MDM740.COM installed with the M7OD-5 Comm-Pac overlay '
                        '(assembled on the machine, patched here)')
    print('%s: %d bytes from %s, highest address %04X' % (com, placed, hexfile, high))
    print('banner "%s": %s' % (BANNER.decode(), installed))
    return 0 if installed else 1


if __name__ == '__main__':
    sys.exit(main())
