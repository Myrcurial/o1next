#!/bin/sh
# rom13-reassemble.sh [--validate] [WORKDIR]
#
# Reconstruct the Osborne 1 **ROM 1.3** image from the OCC engineering source
# disk `research/source-code/OSROM13.IMD`, and -- with `--validate` -- rebuild
# the *rev B* ROM from `OCCROM.IMD` as a control, because that disk carries the
# shipped image (`OCCROM0B.COM`) and its listing, so the rev-B build can be
# checked byte for byte.
#
# Written for #205; see docs/rom-13-reconstruction.md for the full story and for
# what is still *not* certified.
#
# WHY IT IS A SCRIPT, AND WHAT IT DOES NOT HIDE
#   Two things stand between this source and a ROM, and neither is a bug to be
#   papered over:
#
#   1. **`DBE`/`DCE` need ACT 3.5E.**  Those two pseudo-ops are not in 3.0 or
#      3.2 -- the versions the archive holds -- and the rev-B listing names the
#      assembler it was built with (`SORCIM 808x Assembler ver  3.5E`).  The
#      bytes they emit are recovered exactly from the shipped rev-B ROM (each
#      byte is the value shifted left one; `DCE` sets bit 0 of the last byte),
#      and tools/research/actdbe.py rewrites them into `DB` so 3.0 can assemble
#      the same bytes.  That translation is what `--validate` checks.
#
#   2. **The ROM master defines `CCP` and every `OCCTXT` we hold defines it
#      too.**  ACT 3.0 treats the duplicate as fatal and stops with an "Error
#      page" after the first line of the systext.  `CCP` is not referenced by
#      any ROM source line, so the copy below disables the systext's line; the
#      rev-B control build needs no such change, which is how we know the
#      change is inert.
#
#   Everything else here is the same shape as rom144-reassemble.sh, and the
#   traps it records apply: work on copies because MAME writes the guest's
#   changes back, `cpmrm 0:*.*` because the DD system disk is nearly full once
#   ACT80 and 85 KB of source are on it, and the CP/M text must be CRLF.
#
# ENVIRONMENT
#   O1_ACT80    path to an ACT80.COM to use (default the safety copy in
#               research/act-assembler/, SORCIM 3.0)
#   O1_WORK     default work directory (default /tmp/o1-rom13)
set -eu

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
VALIDATE=0
if [ "${1:-}" = "--validate" ]; then
    VALIDATE=1
    shift
fi
WORK="${1:-${O1_WORK:-/tmp/o1-rom13}}"
ACT80="${O1_ACT80:-$REPO/research/act-assembler/ACT80.COM}"
SRC13="$REPO/research/source-code/OSROM13.IMD"
SRCUTL="$REPO/research/source-code/OSUTLSRC.IMD"
SRCREVB="$REPO/research/source-code/OCCROM.IMD"
SYS="$REPO/research/shipped-software/OS1SYSD.IMD"
SYSTEXT="$REPO/research/source-code/ROM-13-source/occtxt6.ast"
FMT=osborne1                     # cpmtools diskdef for the DD system disk
ROM13_MODULES="occrom03 occrom13 occrom23 occrom33 occrom43 occrom53
               occrom63 occrom73 occrom83 occrom93 occram2"
REVB_MODULES="occrom0b occrom1b occrom2b occrom3b occrom4b occrom5b occrom6b
              occrom7b occrom8b occrom9b occrama"
# How many times to run each build.  One is the default and is normally right.
# The MAME floppy write-back damages a handful of hex records per build, and
# the damage has so far been *identical* between runs (three runs of the rev-B
# control build are byte-identical files), so merging does not rescue anything
# today -- see docs/rom-13-reconstruction.md 7.  `O1_RUNS=3` turns the merge on
# anyway: it costs only time, and it is the fix if the damage ever moves.
RUNS="${O1_RUNS:-1}"

for f in "$ACT80" "$SRC13" "$SRCUTL" "$SYS" "$SYSTEXT"; do
    [ -f "$f" ] || { echo "rom13-reassemble.sh: missing $f" >&2; exit 1; }
done
for t in cpmcp cpmrm mame python3; do
    command -v "$t" >/dev/null || { echo "rom13-reassemble.sh: $t not on PATH" >&2; exit 1; }
done

mkdir -p "$WORK"
cd "$WORK"

# One ACT run: boot the given floppy, type the command, take the hex off it.
#   run_act DISK.imd "ACT command line" HEXNAME
# HEXNAME is both the output tag and the name of the hex file on the guest.
run_act() {
    _disk="$1"; _cmd="$2"; _hex="$3"; _i=1
    while [ "$_i" -le "$RUNS" ]; do
        _tag="${_hex%.HEX}"
        cp "$_disk" "$WORK/run_${_tag}_$_i.imd"
        O1_KEYS="$(printf 'sleep 2\ntype %s\nsleep 280\ndump assembled\n' "$_cmd")" \
        O1_WAIT=60 \
            "$HERE/o1keys.sh" osborne1 "$WORK/run_${_tag}_$_i.imd" "" 420 \
            > "$WORK/${_tag}_$_i.log" 2>&1 || true
        grep -E "ERROR|no ERROR|LWA|not used|OPEN error" "$WORK/${_tag}_$_i.log" \
            | tail -2 || true
        python3 "$HERE/imdinfo.py" --raw "$WORK/run_${_tag}_$_i.raw" \
            "$WORK/run_${_tag}_$_i.imd" >/dev/null
        cpmcp -f "$FMT" "$WORK/run_${_tag}_$_i.raw" "0:$_hex" \
            "$WORK/${_tag}_$_i.HEX" 2>/dev/null || true
        [ -s "$WORK/${_tag}_$_i.HEX" ] || {
            echo "rom13-reassemble.sh: run $_i left no $_hex on the floppy" >&2
            return 1
        }
        _i=$((_i + 1))
    done
}


# ---------------------------------------------------------------------------
# 1. Unpack the 1.3 source disk and take the source off it.
# ---------------------------------------------------------------------------
echo "== 1. unpack OSROM13.IMD (8-inch, 77 tracks, skew 3) =="
# The 8-inch work goes in its own directory, because o1imd8.py writes a
# `diskdefs` beside the image and cpmtools looks for a file of that name in the
# *current* directory before its own share directory -- so a generated one in
# $WORK would hide the stock `osborne1` definition the later steps need.
OCC8="$WORK/occ8"
mkdir -p "$OCC8" "$WORK/src"
python3 "$HERE/o1imd8.py" "$SRC13" "$OCC8/rom13.raw" >/dev/null
for m in $ROM13_MODULES; do
    case "$m" in occram2) continue ;; esac
    (cd "$OCC8" && cpmcp -T raw -f occ8 rom13.raw "0:$m.asm" "$WORK/src/$m.asm")
done

echo "== 2. OCCRAM2.ASM is not on that disk -- take it from OSUTLSRC.IMD =="
python3 "$HERE/o1imd8.py" "$SRCUTL" "$OCC8/util.raw" >/dev/null
(cd "$OCC8" && cpmcp -T raw -f occ8 util.raw 0:occram2.asm "$WORK/src/occram2.asm")

echo "== 3. rewrite DBE/DCE as DB (ACT 3.5E pseudo-ops, see actdbe.py) =="
for m in $ROM13_MODULES; do
    python3 "$HERE/actdbe.py" "$WORK/src/$m.asm" "$WORK/src/tr-$m.asm"
done

echo "== 4. drive A: system disk, cleared, + ACT80 + the translated source =="
python3 "$HERE/imdinfo.py" --raw "$WORK/sys.raw" "$SYS" >/dev/null
cp "$WORK/sys.raw" "$WORK/a.raw"
cpmrm -f "$FMT" "$WORK/a.raw" '0:*.*'
cpmcp -f "$FMT" "$WORK/a.raw" "$ACT80" 0:ACT80.COM
for m in $ROM13_MODULES; do
    cpmcp -f "$FMT" "$WORK/a.raw" "$WORK/src/tr-$m.asm" "0:$m.asm"
done
# The systext, with the one line that collides with the master's `CCP = 0`
# disabled -- see the header.  It is not a symbol any ROM line references.
python3 - "$SYSTEXT" "$WORK/occtxt6.ast" <<'PY'
import sys
d = open(sys.argv[1], 'rb').read()
open(sys.argv[2], 'wb').write(d.replace(b'CCP\t=\tBIOS-1600h', b';CCP\t=\tBIOS-1600h'))
PY
cpmcp -f "$FMT" "$WORK/a.raw" "$WORK/occtxt6.ast" 0:OCCTXT6.AST
python3 "$HERE/o1raw2imd.py" --dd "$WORK/a.raw" "$WORK/a.imd" \
    --comment "ACT80.COM assembly of ROM 1.3 (#205)" >/dev/null

echo "== 5. run the assembly under MAME, $RUNS times, and merge the hex =="
run_act "$WORK/a.imd" "ACT80 OCCROM03 S=OCCTXT6.AST H=A:" OCCROM03.HEX

set --
i=2
while [ "$i" -le "$RUNS" ]; do
    set -- "$@" --merge "$WORK/OCCROM03_$i.HEX"
    i=$((i + 1))
done
echo "== 6. hex -> the 4 KB image =="
python3 "$HERE/acthex.py" "$WORK/OCCROM03_1.HEX" "$WORK/os1-13.rom" --size 4096 "$@"

if [ "$VALIDATE" = 0 ]; then
    echo "== done: $WORK/os1-13.rom =="
    exit 0
fi

# ---------------------------------------------------------------------------
# 7. Control build: rev B, whose shipped image is on the same disk.
#    This is the check that decides whether the 1.3 image may be called a
#    reconstruction.  It builds rev B from OCCROM.IMD with the same translated
#    source and the same ACT80, and compares the result with the OCCROM0B.COM
#    that shipped on that very disk.
# ---------------------------------------------------------------------------
echo "== 7. control build: rev B from OCCROM.IMD vs its shipped OCCROM0B.COM =="
mkdir -p "$WORK/revb"
python3 "$HERE/o1imd8.py" "$SRCREVB" "$OCC8/revb.raw" >/dev/null
for n in $REVB_MODULES; do
    (cd "$OCC8" && cpmcp -T raw -f occ8 revb.raw "0:$n.asm" "$WORK/revb/$n.asm")
done
(cd "$OCC8" && cpmcp -T raw -f occ8 revb.raw 0:occtxta.ast "$WORK/revb/occtxta.ast" \
    && cpmcp -T raw -f occ8 revb.raw 0:occrom0b.com "$WORK/revb/shipped.com")
for n in $REVB_MODULES; do
    python3 "$HERE/actdbe.py" "$WORK/revb/$n.asm" "$WORK/revb/tr-$n.asm"
done
cp "$WORK/sys.raw" "$WORK/b.raw"
cpmrm -f "$FMT" "$WORK/b.raw" '0:*.*'
cpmcp -f "$FMT" "$WORK/b.raw" "$ACT80" 0:ACT80.COM
for n in $REVB_MODULES; do
    cpmcp -f "$FMT" "$WORK/b.raw" "$WORK/revb/tr-$n.asm" "0:$n.asm"
done
cpmcp -f "$FMT" "$WORK/b.raw" "$WORK/revb/occtxta.ast" 0:OCCTXTA.AST
python3 "$HERE/o1raw2imd.py" --dd "$WORK/b.raw" "$WORK/revb.imd" \
    --comment "rev B control build (#205)" >/dev/null

run_act "$WORK/revb.imd" "ACT80 OCCROM0B S=OCCTXTA.AST H=A:" OCCROM0B.HEX
set --
i=2
while [ "$i" -le "$RUNS" ]; do
    set -- "$@" --merge "$WORK/OCCROM0B_$i.HEX"
    i=$((i + 1))
done
python3 "$HERE/acthex.py" "$WORK/OCCROM0B_1.HEX" "$WORK/revb.bin" --size 4096 "$@"
if cmp "$WORK/revb.bin" "$WORK/revb/shipped.com"; then
    echo "== control build PASSED: rev B reproduced byte for byte =="
    echo "   the 1.3 image at $WORK/os1-13.rom rests on the same toolchain."
else
    echo "== control build FAILED: rev B does not match the shipped image =="
    echo "   a 1.3 image built this way may NOT be called a reconstruction"
    echo "   until this passes; see docs/rom-13-reconstruction.md."
    exit 1
fi

