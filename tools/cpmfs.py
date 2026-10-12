#!/usr/bin/env python3
"""cpmfs.py - minimal read-only CP/M 2.x filesystem tool (list/extract).

Built after cpmtools 2.23 (homebrew) silently misread a valid Kaypro
DSDD image; this tool makes all geometry explicit and verifiable.

Usage:
  cpmfs.py image format ls [user]
  cpmfs.py image format get USER:FILE out       (USER omitted = 0)
  cpmfs.py image format getall outdir

Formats (raw sector images):
  osb1sssd  Osborne 1 SD: 40 cyl x 10 sec x 256B FM, boottrk 3, 2K blocks,
            skew 2
  kp2x      Kaypro DSDD: 80 logical trk (side-per-track) x 10 sec x 512B,
            boottrk 1, 2K blocks
  kpiv      alias for kp2x
  drivec    Drive C RAM disk blob: 1536 trk x 2 sec x 128B, boottrk 0, 2K blocks

`skew` is the format's sector interleave, in the same sense as cpmtools'
`skew` diskdef field: a raw image stores a track's sectors in *physical*
order, and `skewtab[logical] = physical` maps the CP/M sector number onto
it.  The Osborne 1 SD layout interleaves 2:1 -- without it the *directory*
still reads (every used directory sector happens to land somewhere in block
0) while every *file body* comes back from sectors that were never written,
i.e. 0xE5.  That misread is the one that made OZROM's Utilities disk look
partially erased; see docs/ozrom-1e.md 10.2/10.4 and #170.  Formats whose
disks are not interleaved leave `skew` at the default of 1 (identity).

CP/M semantics implemented: extents (EXM), record counts, 8/16-bit
block numbers (chosen by DSM>255), deleted entries skipped, duplicate
basename extents folded.
"""
import os
import sys

FORMATS = {
    'osb1sssd': dict(seclen=256, sectrk=10, boottrk=3, blocksize=2048, maxdir=64, skew=2),
    'kp2x':     dict(seclen=512, sectrk=10, boottrk=1, blocksize=2048, maxdir=64),
    # The Drive C RAM disk as a raw blob (384 KiB).  The geometry derives the
    # DPB that DCL.COM installs, field for field -- docs/drive-c-design.md 4.2.
    'drivec':   dict(seclen=128, sectrk=2, boottrk=0, blocksize=2048, maxdir=128),
}
FORMATS['kpiv'] = FORMATS['kp2x']
FORMATS['zorba'] = dict(FORMATS['kp2x'], boottrk=2)

def skew_table(skew, sectrk):
    """cpmtools' skew table (cpmfs.c): skewtab[logical] = physical sector.

    `skew` is the interleave factor; 1 is identity.  Reproduced exactly, so a
    raw image read here matches `cpmcp -T raw -f <diskdef>` on the same file.
    """
    tab = []
    j = 0
    for _ in range(sectrk):
        while j in tab:
            j = (j + 1) % sectrk
        tab.append(j)
        j = (j + skew) % sectrk
    return tab

class CPM:
    def __init__(self, path, fmt):
        self.d = open(path, 'rb').read()
        f = FORMATS[fmt]
        self.seclen, self.sectrk = f['seclen'], f['sectrk']
        self.skewtab = skew_table(f.get('skew', 1), self.sectrk)
        self.bootsect = f['boottrk'] * self.sectrk
        self.bootoff = self.bootsect * self.seclen
        self.blocksize, self.maxdir = f['blocksize'], f['maxdir']
        self.diroff = self.bootoff
        self.dirblks = (self.maxdir * 32 + self.blocksize - 1) // self.blocksize
        self.datablocks_off = self.diroff  # block 0 = directory block(s)
        # DSM: total data blocks - 1
        dsm = (len(self.d) - self.datablocks_off) // self.blocksize - 1
        self.ext16 = dsm > 255          # 16-bit block numbers
        self.exm = (self.blocksize // 1024) - (1 if dsm > 255 else 0)
        # EXM: blocksize/1024 for 8-bit DSM, half that for 16-bit (CP/M 2.2)
        self.exm = (self.blocksize // 1024) - 1 if dsm <= 255 else (self.blocksize // 2048) - 1
        self.entries = self._read_dir()

    def _read_dir(self):
        dirdata = bytearray()
        for b in range(self.dirblks):
            dirdata += self.block_bytes(b)
        out = []
        for i in range(self.maxdir):
            e = bytes(dirdata[i*32 : i*32 + 32])
            if len(e) < 32 or e[0] > 15:
                continue
            blocks = []
            if self.ext16:
                for j in range(8):
                    blocks.append(e[16 + 2*j] | (e[17 + 2*j] << 8))
            else:
                blocks = list(e[16:32])
            out.append(dict(user=e[0], name=e[1:9].decode('ascii', 'replace'),
                            ext=e[9:12].decode('ascii', 'replace'),
                            ex=e[12] + self.exm * e[14] + (e[14] << 5 if False else 0),
                            exlo=e[12], s2=e[14], rc=e[15], blocks=blocks))
        return out

    def sector_bytes(self, logical):
        """The `logical`th sector of the disk, wherever the skew put it."""
        track, sec = divmod(logical, self.sectrk)
        phys = track * self.sectrk + self.skewtab[sec]
        off = phys * self.seclen
        return self.d[off:off + self.seclen]

    def block_bytes(self, b):
        nsec = self.blocksize // self.seclen
        out = bytearray()
        for i in range(nsec):
            out += self.sector_bytes(self.bootsect + b * nsec + i)
        return bytes(out)

    def files(self):
        """group extents by (user, name, ext)"""
        groups = {}
        for e in self.entries:
            groups.setdefault((e['user'], e['name'], e['ext']), []).append(e)
        return groups

    def read_file(self, ents):
        data = bytearray()
        for e in sorted(ents, key=lambda x: (x['exlo'], x['s2'])):
            nrec = e['rc']
            nbytes = nrec * 128
            buf = bytearray()
            for b in e['blocks']:
                if b == 0:
                    continue
                buf += self.block_bytes(b)
            data += buf[:nbytes]
        return bytes(data)

def parse_spec(spec):
    if ':' in spec:
        u, f = spec.split(':', 1)
        user = int(u) if u else 0
    else:
        user, f = 0, spec
    f = f.upper().replace('.', ' ')
    if ' ' in f:
        n, x = f.split(' ', 1)
    else:
        n, x = f, ''
    return user, n.strip().ljust(8), x.strip().ljust(3)

def main():
    img, fmt, cmd = sys.argv[1:4]
    fs = CPM(img, fmt)
    groups = fs.files()
    if cmd == 'ls':
        userfilt = int(sys.argv[4]) if len(sys.argv) > 4 else None
        seen = set()
        for (u, n, x), ents in sorted(groups.items()):
            if userfilt is not None and u != userfilt:
                continue
            total = sum(e['rc'] * 128 for e in ents)
            print(f'{u}: {n.strip():8s}.{x.strip():3s} ~{total}B')
            seen.add((u, n, x))
    elif cmd == 'get':
        user, n, x = parse_spec(sys.argv[4])
        ents = groups.get((user, n, x))
        if not ents:
            sys.exit(f'not found: {user}:{n.strip()}.{x.strip()}')
        open(sys.argv[5], 'wb').write(fs.read_file(ents))
    elif cmd == 'getall':
        outdir = sys.argv[4]
        os.makedirs(outdir, exist_ok=True)
        for (u, n, x), ents in sorted(groups.items()):
            fn = f'{n.strip().lower()}.{x.strip().lower()}'
            if u:
                fn = f'u{u}_' + fn
            open(os.path.join(outdir, fn), 'wb').write(fs.read_file(ents))
            print(fn)

if __name__ == '__main__':
    main()
