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
BLOB=""
WORK=""
while [ $# -gt 0 ]; do
    case "$1" in
        -o) OUT="${2:?rom2asm.sh: -o needs a path}"; shift 2 ;;
        -b) BLOB="${2:?rom2asm.sh: -b needs a path}"; shift 2 ;;
        -*) echo "rom2asm.sh: unknown option $1" >&2; exit 1 ;;
        *) WORK="$1"; shift ;;
    esac
done
[ -n "$WORK" ] || WORK="${O1_WORK:-/tmp/o1-rom2}"

# The shell moves into the work directory below, so a relative OUT or BLOB would
# be written *there* instead of where the caller meant.  Both are made absolute
# while this shell is still in the caller's directory.
abspath() {
    case "$1" in
        /*) printf '%s\n' "$1" ;;
        *) printf '%s\n' "$(pwd)/$1" ;;
    esac
}
OUT="$(abspath "$OUT")"
[ -z "$BLOB" ] || BLOB="$(abspath "$BLOB")"

ACT80="${O1_ACT80:-$REPO/research/act-assembler/ACT80.COM}"
SRC="$REPO/research/source-code/BIOS-144-source/rom144.asm"
DIFF="$REPO/research/source-code/BIOS-200-source/rom2.diff"
FRAG="$REPO/research/source-code/BIOS-200-source/rom2-screen.asm"
SYS="$REPO/research/shipped-software/OS1SYSD.IMD"
REF="$REPO/research/roms/os1-144.rom"
FMT=osborne1                     # cpmtools diskdef: 1024 B sectors, 5/track, 1K blocks

for f in "$ACT80" "$SRC" "$DIFF" "$FRAG" "$SYS" "$REF"; do
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

echo "== 3b. the screen code in the diff is the screen code in the fragment =="
# The new code exists twice: `rom2-screen.asm` is the record of it -- where the
# comments and the reasoning live -- and `rom2.diff` is what the assembler is
# actually given.  So they can drift, and this is one of the two guards against
# it: the fragment's code lines have to appear, in order, in the source about to
# be assembled.  It runs before the assembly, so a drift fails in a second rather
# than a minute.  It is *this script's* guard, though, not CI's: the source it
# checks is the patched one, and patching is step 3 of a build that needs MAME.
# CI's half is `rom2blob.py --check` -- the fragment moving on without the blob
# being remade, which needs nothing but the two files.
python3 - "$FRAG" "$WORK/ROM2.ASM" <<'PY'
import sys
frag = open(sys.argv[1], 'rb').read().decode('latin-1').split('\n')
src = open(sys.argv[2], 'rb').read().decode('latin-1').split('\r\n')
start = next((i for i, l in enumerate(frag) if l.strip().startswith('LIST')), None)
if start is None:
    raise SystemExit('rom2asm.sh: %s has no `LIST *`, so it is not the screen '
                     'fragment' % sys.argv[1])
code = [l.rstrip() for l in frag[start:]
        if l.strip() and not l.strip().startswith(';')]
pos, missing = 0, []
for c in code:
    for j in range(pos, len(src)):
        if (src[j].rstrip() == c or src[j].rstrip().startswith(c + '\t')
                or (c.startswith('\tENDM') and src[j].strip() == 'ENDM')):
            pos = j
            break
    else:
        missing.append(c)
if missing:
    raise SystemExit(
        'rom2asm.sh: %d of the screen fragment\'s %d code lines are not in the\n'
        '  source being assembled, in order -- the first is %r.  rom2-screen.asm\n'
        '  and rom2.diff have drifted, so the build would not be the fragment.\n'
        '  Regenerate rom2.diff from the fragment.'
        % (len(missing), len(code), missing[0]))
print('  %d code lines of the screen fragment are in the source, in order'
      % len(code))
PY


echo "== 4. run the assembly under MAME (this takes a few minutes) =="
# MAME writes the guest's changes back into these files, so work on copies.
cp "$WORK/a.imd" "$WORK/run_a.imd"
cp "$WORK/b.imd" "$WORK/run_b.imd"
O1_KEYS="$(printf 'sleep 2\ntype ACT80 B:ROM2 H=B:\nsleep 260\ndump assembled\n')" \
O1_WAIT=60 \
    "$HERE/o1keys.sh" osborne1 "$WORK/run_a.imd" "$WORK/run_b.imd" 400 \
    > "$WORK/act.log" 2>&1 || true
grep -E "no ERRORs|ERROR|SORCIM|Hex file write error|Pass 2" "$WORK/act.log" || true

# The assembler's own statement of how long each piece is -- and there are two
# pieces now that the screen code is in the build (#247 step 8, turn 3).
# `MSG 'LENGTH OF THIS ROM IS = ',RLWA-1` (rom144.asm, at the guard) is the
# *monitor's* last byte, and the summary's `Program LWA = 40B7h` is the location
# counter at the end of the whole program -- which is the blob's last byte plus
# one, because the blob is assembled last.  Steps 6 and 7 measure each artifact
# against its own number, so both are read rather than assumed: without them there
# is nothing to catch a build that lost part of the code on the way to the floppy.
MONEND="$(sed -n "s/.*LENGTH OF THIS ROM IS = \([0-9A-Fa-f]\{1,\}\).*/\1/p" \
          "$WORK/act.log" | head -1)"
PROGEND="$(sed -n "s/.*Program LWA = \([0-9A-Fa-f]\{1,\}\)h.*/\1/p" \
           "$WORK/act.log" | head -1)"
[ -n "$MONEND" ] || {
    echo "rom2asm.sh: the listing does not say how long the monitor is (no" >&2
    echo "  'LENGTH OF THIS ROM IS = ' in $WORK/act.log), so the image cannot" >&2
    echo "  be checked against the assembler's own extent." >&2
    exit 1; }
[ -n "$PROGEND" ] || {
    echo "rom2asm.sh: the listing does not say where the program ends (no" >&2
    echo "  'Program LWA = ' in $WORK/act.log), so the blob cannot be checked" >&2
    echo "  against the assembler's own extent." >&2
    exit 1; }
echo "  the assembler says the monitor ends at 0x$MONEND and the program at 0x${PROGEND}h"

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
# --covered-range is the *monitor's* own range, not the program's: the blob's
# records sit at 4000h and are not part of this image at all (rom2blob.py makes
# them into their own artifact), and a range that reached them would demand
# coverage of the 1FFFh bytes of empty space between the two.
HEXSTATUS=0
python3 "$HERE/acthex.py" "$WORK/ROM2.HEX" "$WORK/ROM2.bin" \
    --recover-ff --fill-reference "$REF" --reference "$REF" \
    --covered-range 0F67 "$MONEND" || HEXSTATUS=$?
if [ "$HEXSTATUS" -gt 1 ]; then
    echo "rom2asm.sh: acthex.py exited $HEXSTATUS -- the hex file is not this" >&2
    echo "  build, and no image was written." >&2
    exit 1
fi

echo "== 7. the invariant: nothing below the new code moved =="
python3 - "$REF" "$WORK/ROM2.bin" "$OUT" "$MONEND" "$PROGEND" <<'PY'
import sys, zlib
stock = open(sys.argv[1], 'rb').read()
built = open(sys.argv[2], 'rb').read()
out = sys.argv[3]
monend = int(sys.argv[4], 16)     # the monitor's last byte, from its own MSG
progend = int(sys.argv[5], 16)    # the program's end: the blob's last byte + 1

ENTRY, GUARD = 0x0F67, 0x0FFB     # the HCBOOT entry, and the vendor's own guard
BLOB_AT, BLOB_LIMIT = 0x4000, 0x4FFF   # where `ORG 4000H` puts the screen code
WINDOW_MAX = 64                   # the sign-on prompt is 28 bytes of it
# ONE ASSEMBLY, TWO ARTIFACTS (#247 step 8, turn 3).  The monitor is the 4096-byte
# image, and its new code has to stop at the vendor's guard.  The screen's code is
# *not* in that image: it is `ORG 4000H`, a page the interposer serves and the stub
# copies to RAM, and `rom2blob.py` turns its records into `screen.bin`.  So the
# checks below are per-artifact, and the rule that used to reject anything above
# the guard was rejecting the second artifact, not a mistake.
#
# And the sign-on prompt is the one place below ENTRY where ROM 2.0 may change a
# byte.  Two things change there, and they are not the same kind of thing:
#
#   * the two key immediates -- `CMP ESC` -> `CMP CR`, `CMP CR` -> `CMP ':'` --
#     so RETURN is the hard disk and ':' is floppy A.  `"` is unchanged, and START
#     clears DSKSWP on every pass, so ':' is always drive A.
#   * the sign-on hook: `LDK DE,IMSG` + `CALL OSTR` (6 bytes) -> `CALL SCRN`
#     (3 bytes).  That is a *length* change, and it is safe for a reason worth
#     naming: the sign-on is followed by `ORG NMIA`, an absolute address, so the
#     three bytes come back as an ORG hole rather than shifting everything below.
#     Every routine the CBIOS calls by absolute address stays put -- which is what
#     this check is really about, and why the window is allowed rather than the
#     rule being dropped.
#
# So: below ENTRY there is exactly one contiguous window of differing bytes, it
# contains both key addresses, and it is small.  Everything else below ENTRY must
# be byte-identical, and so must everything from the window's end to ENTRY.
#
# The two key immediates are checked *by value* rather than at a fixed address,
# and that is the same 3-byte shift: the stock's `CMP ESC` sits at 0x0048 and its
# `CMP CR` at 0x0050, and ROM 2.0's `CMP CR` and `CMP ':'` sit three bytes lower
# because the hook is shorter.  The stock addresses are still checked against the
# stock bytes, so the reference is the shipped 1.44 and nothing else.
STOCK_KEYS = {0x0048: 0x1B, 0x0050: 0x0D}
ROM2_KEYS = {b'\xfe\x0d': 'RETURN', b'\xfe\x3a': "':\'"}
RELEASED = b'\xfe\x1b'            # `CMP ESC`, which ROM 2.0 gives up


if len(stock) != 4096:
    raise SystemExit('rom2asm.sh: the reference is %d bytes, not 4096' % len(stock))
if len(built) != 4096:
    raise SystemExit('rom2asm.sh: the assembly is %d bytes, not 4096' % len(built))

diff = [i for i in range(4096) if stock[i] != built[i]]
if not diff:
    raise SystemExit('rom2asm.sh: the assembly is the stock 1.44 -- '
                     'HCBOOT was not filled in')
for a, was in sorted(STOCK_KEYS.items()):
    if stock[a] != was:
        raise SystemExit('rom2asm.sh: the reference holds 0x%02X at 0x%04X, not '
                         '0x%02X -- it is not the shipped 1.44'
                         % (stock[a], a, was))

# --- below the HCBOOT entry: one window, and it is the sign-on prompt ---------
below = [i for i in diff if i < ENTRY]
if not below:
    raise SystemExit('rom2asm.sh: nothing below the HCBOOT entry at 0x%04X '
                     'changed, so the sign-on prompt was not touched -- and ROM 2.0 '
                     'hooks the boot screen there (#247)' % ENTRY)
windows = []
for i in below:
    if windows and i == windows[-1][1] + 1:
        windows[-1][1] = i
    else:
        windows.append([i, i])
if len(windows) != 1:
    raise SystemExit(
        'rom2asm.sh: %d separate windows of change below the HCBOOT entry at '
        '0x%04X (%s) -- the sign-on prompt is one, and a second is a moved '
        'anchor, which is not ROM 2.0 (docs/o1-rom-2.0.md 4.2)'
        % (len(windows), ENTRY,
           ' '.join('%04x-%04x' % tuple(w) for w in windows[:4])))
win_lo, win_hi = windows[0]
if win_hi - win_lo + 1 > WINDOW_MAX:
    raise SystemExit('rom2asm.sh: the change below the HCBOOT entry runs '
                     '0x%04X-0x%04X, %d bytes -- the sign-on prompt is 28, so '
                     'this is more than the hook and the boot keys'
                     % (win_lo, win_hi, win_hi - win_lo + 1))
window = built[win_lo:win_hi + 1]
for pair, what in sorted(ROM2_KEYS.items()):
    if pair not in window:
        raise SystemExit('rom2asm.sh: the sign-on prompt at 0x%04X-0x%04X '
                         'compares no `CMP %s` -- ROM 2.0 boots the hard disk on '
                         'RETURN and the floppies on : and " '
                         '(docs/o1-rom-2.0.md 3.3)' % (win_lo, win_hi, what))
if RELEASED in window:
    raise SystemExit('rom2asm.sh: the sign-on prompt still compares ESC -- ROM 2.0 '
                     'releases it, and an unclaimed key falls through to the '
                     'prompt\'s own JR START (#247 step 4)')

# --- the monitor: the HCBOOT entry to the vendor's guard ----------------------
mon = [i for i in diff if ENTRY <= i < 0x1000]
if not mon:
    raise SystemExit('rom2asm.sh: nothing at or above the HCBOOT entry at 0x%04X '
                     'changed -- ROM 2.0 is not in this build' % ENTRY)
mon_hi = mon[-1]
if mon_hi > GUARD:
    raise SystemExit('rom2asm.sh: the monitor\'s new code reaches 0x%04X, past the '
                     'vendor\'s guard at 0x%04X (rom144.asm: `IF RLWA > 0FFBH`)'
                     % (mon_hi, GUARD))
if mon_hi != monend:
    raise SystemExit(
        'rom2asm.sh: the image changes up to 0x%04X, but the assembler says the '
        'monitor ends at 0x%04X (`MSG \'LENGTH OF THIS ROM IS = \'`).  The two '
        'have to agree -- everything above the code is the vendor\'s own FF fill '
        '-- so a different extent means the image is not the one the source '
        'describes, and the emulator\'s floppy write-back losing records is the '
        'usual cause (docs/rom-13-reconstruction.md 7).  Re-run the assembly.'
        % (mon_hi, monend))

# --- and the blob is not in this image at all ---------------------------------
# `ORG 4000H` is outside the monitor's 4096 bytes, so no diff above 0x1000 can
# ever appear and a check here could not see the blob.  What *can* be checked is
# that the program extends past the monitor into the blob's own page -- and if it
# does not, the screen code is not in the build and step 8 has nothing to extract.
# The blob's own extent is checked where its bytes are: `rom2blob.py --lwa`, on the
# same `Program LWA`.
if not BLOB_AT <= progend <= BLOB_LIMIT + 1:
    raise SystemExit(
        'rom2asm.sh: the assembler says the program ends at 0x%04X, which is not '
        'in the blob\'s page at 0x%04X-0x%04X -- so the screen code is not in this '
        'build, and there is no blob to extract (#247 step 8).  The blob is the '
        '`ORG 4000H` part of research/source-code/BIOS-200-source/rom2-screen.asm, '
        'and it goes *after* the vendor\'s `ENDM`: inside the `ECHO` block it is '
        'assembled 0FFFH-RLWA times and every one of its labels is a duplicate.'
        % (progend, BLOB_AT, BLOB_LIMIT))

print('  below 0x%04X: byte-identical to the 1.44%s'
      % (ENTRY, (', except one window at 0x%04X-0x%04X -- the sign-on prompt'
                 % (win_lo, win_hi)) if below else ', with no window at all'))
print('  the boot keys: RETURN -> HCBOOT, ":" -> floppy A, \'"\' -> floppy B')
print('  the monitor: 0x%04X-0x%04X, %d bytes, %d free to the guard'
      % (ENTRY, mon_hi, mon_hi - ENTRY + 1, GUARD - mon_hi))
print('  and the assembler says the monitor ends at 0x%04X: the image agrees'
      % monend)
print('  HCBOOT 0x%04X: %s' % (ENTRY, built[ENTRY:mon_hi + 1].hex(' ')))
print('  the blob: the program ends at 0x%04X, past the monitor and inside the '
      'page at 0x%04X -- its own artifact, and step 8 extracts it'
      % (progend, BLOB_AT))
open(out, 'wb').write(built)
print('  wrote %s (4096 bytes, CRC32 %08x)' % (out, zlib.crc32(built)))
PY

if [ -n "$BLOB" ]; then
    echo "== 8. the blob, as an artifact =="
    # The blob's records are in the same hex the monitor came from: one assembly,
    # two artifacts.  --lwa is the assembler's own `Program LWA`, so a build that
    # lost the blob's tail cannot pass as one that did not.
    python3 "$HERE/rom2blob.py" --extract "$WORK/ROM2.HEX" -o "$BLOB" \
        --lwa "$PROGEND"
fi

cat <<'NOTE'

NEXT: the image, the blob, and the machine that boots them.

  tools/research/rom2image.py --monitor OUT -o /tmp/rom2.rom
  tools/emulator-setup/mame-osborne1nx/rom2-check.sh    # what HCBOOT does, measured

The monitor alone is not bootable: the payload -- the CBIOS, the MD-10 BIOS and
the shim -- comes from rom2image.py, which is what puts them in the window at
1000h and 1800h, where HCBOOT copies them out of.

And the blob is not part of the monitor at all: it is the page the interposer
serves for PRESENT(3), and `-b` is what puts it in firmware/rom-service/screen.bin.

  tools/research/rom2asm.sh -o /tmp/rom2-monitor.rom \
                            -b firmware/rom-service/screen.bin

`tools/research/rom2blob.py --check` then verifies that the committed blob carries
the digest of rom2-screen.asm as it stands, and fails when the source has moved on
without it.  That is the CI check, because this script needs MAME and CI has none.
NOTE
