#!/bin/sh
# rom2asm.sh [-o OUT.rom] [WORKDIR]
#
# Assemble **ROM 2.0's monitor** -- the vendor's 1.44 source with the new code in
# the free tail of it -- with the vendor's own ACT80, run on an emulated Osborne
# 1, and check the result against the invariant the design rests on. Written for
# #247; see docs/o1-rom-2.0.md 4.6 and 4.7, and
# research/source-code/BIOS-200-source/.
#
# WHY IT IS A SCRIPT
#   The pipeline is rom144-reassemble.sh's (#203), which is the one that already
#   works: ACT80.COM on drive A of a system disk with AUTOST.COM removed, the
#   source on drive B, a scripted keystroke session (o1keys.sh), and acthex.py to
#   turn the HEX back into an image.  The traps are the ones that script lists,
#   and they are worth re-reading before changing anything here.
#
# WHAT IT CHECKS, AND WHY THAT IS THE POINT
#   ROM 2.0's monitor is the shipped 1.44 with new code *only* where the vendor's
#   own guard left room: the HCBOOT entry at 0F67h and the free tail after it
#   (`IF RLWA > 0FFBH`, rom144.asm).  The CBIOS calls ROM routines by absolute
#   address (docs/o1-rom-2.0.md 4.2), so a byte moved anywhere below that is a
#   moved anchor, not a feature -- and the assembler's own guard is the only
#   other thing standing between us and a monitor that is subtly not the 1.44.
#   So this fails if anything below 0F67h differs from the shipped ROM, with one
#   deliberate exception: the sign-on dispatch's two key immediates, which the
#   boot-key change moves (#247 step 4, docs/o1-rom-2.0.md 3.3), and which are
#   checked *for value* rather than merely tolerated.  It also reports the new
#   code's extent against the guard.
#
# WHAT THE EMULATOR DOES TO THE HEX FILE
#   The ACT80's hex output arrives on the floppy with runs of 0xC0DE where hex
#   digits should be -- a handful of records per build, deterministically, the
#   same damage docs/rom-13-reconstruction.md 7 diagnosed on the 1.44 build.
#   It lands in the vendor's FF fill, so the image is *repaired* rather than
#   guessed at: acthex.py fills the addresses no record covers from the shipped
#   ROM (which is what a ROM 2.0 build is -- the 1.44 with new code above
#   0F67h), and refuses the build outright if a hole falls inside the new
#   code's own range, the one place a hole must never be.  Step 7 then checks
#   that the image changes exactly as far as the assembler says the code goes,
#   so a build that lost part of the code cannot pass as a longer one.
#
# ENVIRONMENT
#   O1_ACT80    path to an ACT80.COM to use instead of the safety copy in
#               research/act-assembler/ (#203)
#   O1_WORK     work directory (default /tmp/o1-rom2)
set -eu

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"

OUT="/tmp/rom2-monitor.rom"
WORK=""
while [ $# -gt 0 ]; do
    case "$1" in
        -o) OUT="${2:?rom2asm.sh: -o needs a path}"; shift 2 ;;
        -*) echo "rom2asm.sh: unknown option $1" >&2; exit 1 ;;
        *) WORK="$1"; shift ;;
    esac
done
[ -n "$WORK" ] || WORK="${O1_WORK:-/tmp/o1-rom2}"

ACT80="${O1_ACT80:-$REPO/research/act-assembler/ACT80.COM}"
SRC="$REPO/research/source-code/BIOS-144-source/rom144.asm"
DIFF="$REPO/research/source-code/BIOS-200-source/rom2.diff"
SYS="$REPO/research/shipped-software/OS1SYSD.IMD"
REF="$REPO/research/roms/os1-144.rom"
FMT=osborne1                     # cpmtools diskdef: 1024 B sectors, 5/track, 1K blocks

for f in "$ACT80" "$SRC" "$DIFF" "$SYS" "$REF"; do
    [ -f "$f" ] || { echo "rom2asm.sh: missing $f" >&2; exit 1; }
done
for t in cpmcp cpmrm mame python3; do
    command -v "$t" >/dev/null || { echo "rom2asm.sh: $t not on PATH" >&2; exit 1; }
done

mkdir -p "$WORK"
cd "$WORK"

echo "== 1. unpack the DD system disk =="
python3 "$HERE/imdinfo.py" --raw "$WORK/sys.raw" "$SYS" >/dev/null

echo "== 2. drive A: system disk + ACT80.COM, without AUTOST.COM =="
cp "$WORK/sys.raw" "$WORK/a.raw"
cpmrm -f "$FMT" "$WORK/a.raw" '0:AUTOST.COM'
cpmcp -f "$FMT" "$WORK/a.raw" "$ACT80" 0:ACT80.COM
python3 "$HERE/o1raw2imd.py" --dd "$WORK/a.raw" "$WORK/a.imd" \
    --comment "ACT80.COM assembly of ROM 2.0: drive A (#247)"

echo "== 3. drive B: ROM 2.0's source, as CRLF, on an otherwise empty disk =="
# The vendor's capture is LF-only with three stray CRs (rom144-reassemble.sh),
# and CP/M text wants CRLF, so normalise the same way before the diff goes on:
# the diff is against the normalised source, which is what a CP/M file is.
cp "$WORK/sys.raw" "$WORK/b.raw"
cpmrm -f "$FMT" "$WORK/b.raw" '0:*.*'
python3 - "$SRC" "$WORK/ROM2.ASM" <<'PY'
import sys
d = open(sys.argv[1], 'rb').read()
d = d.replace(b'\r\n', b'\n').replace(b'\r', b'\n')
norm = b'\r\n'.join(d.split(b'\n'))
open(sys.argv[2], 'wb').write(norm)
print("  normalised: %d bytes, %d lines" % (len(norm), norm.count(b'\r\n')))
PY
# The diff names a/ROM144.ASM and b/ROM2.ASM, so -p1 takes it as the whole file.
patch -p1 --forward < "$DIFF"
cpmcp -f "$FMT" "$WORK/b.raw" "$WORK/ROM2.ASM" 0:ROM2.ASM
python3 "$HERE/o1raw2imd.py" --dd "$WORK/b.raw" "$WORK/b.imd" \
    --comment "ACT80.COM assembly of ROM 2.0: drive B (#247)"


echo "== 4. run the assembly under MAME (this takes a few minutes) =="
# MAME writes the guest's changes back into these files, so work on copies.
cp "$WORK/a.imd" "$WORK/run_a.imd"
cp "$WORK/b.imd" "$WORK/run_b.imd"
O1_KEYS="$(printf 'sleep 2\ntype ACT80 B:ROM2 H=B:\nsleep 260\ndump assembled\n')" \
O1_WAIT=60 \
    "$HERE/o1keys.sh" osborne1 "$WORK/run_a.imd" "$WORK/run_b.imd" 400 \
    > "$WORK/act.log" 2>&1 || true
grep -E "no ERRORs|ERROR|SORCIM|Hex file write error|Pass 2" "$WORK/act.log" || true

# The assembler's own statement of how long the code is -- `LENGTH OF THIS ROM
# IS = 0FB3` (rom144.asm's MSG, at the guard).  Steps 6 and 7 measure the image
# against it, so it is read rather than assumed: without it there is nothing to
# catch a build that lost part of the code on the way to the floppy.
LWA="$(sed -n "s/.*LENGTH OF THIS ROM IS = \([0-9A-Fa-f]\{1,\}\).*/\1/p" \
       "$WORK/act.log" | head -1)"
[ -n "$LWA" ] || {
    echo "rom2asm.sh: the listing does not say how long the ROM is (no" >&2
    echo "  'LENGTH OF THIS ROM IS = ' in $WORK/act.log), so the image cannot" >&2
    echo "  be checked against the assembler's own extent." >&2
    exit 1; }
echo "  the assembler says the code ends at 0x$LWA"

echo "== 5. take ROM2.HEX off drive B =="
python3 "$HERE/imdinfo.py" --raw "$WORK/run_b.raw" "$WORK/run_b.imd" >/dev/null
cpmcp -f "$FMT" "$WORK/run_b.raw" 0:ROM2.HEX "$WORK/ROM2.HEX"

echo "== 6. hex -> image =="
# --fill-reference is what makes the image: a ROM 2.0 build *is* the shipped
# 1.44 with new code above 0F67h, so a hole goes to the shipped ROM's own byte
# -- which repairs the write-back damage in the vendor's FF fill, and restores
# the stock byte for the source's own ORG holes (docs/rom-13-reconstruction.md
# 7).  --reference also compares, and exits 1 when the images differ, which for
# ROM 2.0 they are meant to, so status 1 is expected and step 7 is the verdict.
# A *coverage* failure exits 2 and stops here instead: it means the new code's
# own range has a hole in it, so the image would not be the one the source wrote.
HEXSTATUS=0
python3 "$HERE/acthex.py" "$WORK/ROM2.HEX" "$WORK/ROM2.bin" \
    --recover-ff --fill-reference "$REF" --reference "$REF" \
    --covered-range 0F67 "$LWA" || HEXSTATUS=$?
if [ "$HEXSTATUS" -gt 1 ]; then
    echo "rom2asm.sh: acthex.py exited $HEXSTATUS -- the hex file is not this" >&2
    echo "  build, and no image was written." >&2
    exit 1
fi

echo "== 7. the invariant: nothing below the new code moved =="
python3 - "$REF" "$WORK/ROM2.bin" "$OUT" "$LWA" <<'PY'
import sys, zlib
stock = open(sys.argv[1], 'rb').read()
built = open(sys.argv[2], 'rb').read()
out = sys.argv[3]
lwa = int(sys.argv[4], 16)        # where the assembler says the code ends

ENTRY, GUARD = 0x0F67, 0x0FFB     # the HCBOOT entry, and the vendor's own guard
# The sign-on dispatch's two key immediates, and the *only* bytes below the
# HCBOOT entry that ROM 2.0 moves (#247 step 4): `CMP ESC` -> `CMP CR`, so
# RETURN is the hard disk, and `CMP CR` -> `CMP ':'`, so ':' is floppy A.  `"`
# is unchanged, and START clears DSKSWP on every pass, so ':' is always drive A.
# Everything else below ENTRY is an anchor the CBIOS calls by absolute address
# (docs/o1-rom-2.0.md 4.2), so it is not allowed to move at all.
KEYS = {0x0048: (0x1B, 0x0D), 0x0050: (0x0D, 0x3A)}
if len(stock) != 4096:
    raise SystemExit('rom2asm.sh: the reference is %d bytes, not 4096' % len(stock))
if len(built) != 4096:
    raise SystemExit('rom2asm.sh: the assembly is %d bytes, not 4096' % len(built))

diff = [i for i in range(4096) if stock[i] != built[i]]
if not diff:
    raise SystemExit('rom2asm.sh: the assembly is the stock 1.44 -- '
                     'HCBOOT was not filled in')
for a, (was, now) in sorted(KEYS.items()):
    if stock[a] != was:
        raise SystemExit('rom2asm.sh: the reference holds 0x%02X at 0x%04X, not '
                         '0x%02X -- it is not the shipped 1.44' % (stock[a], a, was))
    if built[a] != now:
        raise SystemExit('rom2asm.sh: the sign-on dispatch at 0x%04X is 0x%02X, not '
                         '0x%02X -- ROM 2.0 boots the hard disk on RETURN and the '
                         'floppies on : and " (docs/o1-rom-2.0.md 3.3)'
                         % (a, built[a], now))
below = [i for i in diff if i < ENTRY]
odd = [i for i in below if i not in KEYS]
if odd:
    raise SystemExit('rom2asm.sh: the assembly differs from the 1.44 at 0x%04X, '
                     'below the HCBOOT entry at 0x%04X -- that is a moved anchor, '
                     'not ROM 2.0' % (odd[0], ENTRY))
above = [i for i in diff if i >= ENTRY]
lo, hi = above[0], above[-1]
if hi > GUARD:
    raise SystemExit('rom2asm.sh: the new code reaches 0x%04X, past the vendor\'s '
                     'guard at 0x%04X (rom144.asm: `IF RLWA > 0FFBH`)'
                     % (hi, GUARD))
if hi != lwa:
    raise SystemExit(
        'rom2asm.sh: the image changes up to 0x%04X, but the assembler says the '
        'code ends at 0x%04X.  The two have to agree -- everything above the '
        'code is the vendor\'s own FF fill -- so a longer extent means the image '
        'is not the one the source describes, and the emulator\'s floppy '
        'write-back losing records is the usual cause '
        '(docs/rom-13-reconstruction.md 7).  Re-run the assembly.' % (hi, lwa))

print('  the stock 1.44 below 0x%04X: byte-identical, except the two sign-on key '
      'bytes (#247 step 4)' % ENTRY)
print('  the boot keys: RETURN -> HCBOOT, ":" -> floppy A, \'"\' -> floppy B')
print('  the new code: 0x%04X-0x%04X, %d bytes, %d free to the guard'
      % (lo, hi, hi - lo + 1, GUARD - hi))
print('  and the assembler says the code ends at 0x%04X: the image agrees' % lwa)
print('  HCBOOT 0x%04X: %s' % (ENTRY, built[ENTRY:hi + 1].hex(' ')))
open(out, 'wb').write(built)
print('  wrote %s (4096 bytes, CRC32 %08x)' % (out, zlib.crc32(built)))
PY

cat <<'NOTE'

NEXT: the image, and the machine that boots it.

  tools/research/rom2image.py --monitor OUT -o /tmp/rom2.rom
  tools/emulator-setup/mame-osborne1nx/rom2-check.sh    # what HCBOOT does, measured

The monitor alone is not bootable: the payload -- the CBIOS, the MD-10 BIOS and
the shim -- comes from rom2image.py, which is what puts them in the window at
1000h and 1800h, where HCBOOT copies them out of.
NOTE
