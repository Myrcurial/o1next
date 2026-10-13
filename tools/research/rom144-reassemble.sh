#!/bin/sh
# rom144-reassemble.sh [WORKDIR]
#
# Reassemble the Osborne 1 monitor ROM, rev 1.44, with the vendor's *own*
# assembler -- SORCIM's ACT80.COM -- run on an emulated Osborne 1, and check the
# result byte-for-byte against the shipped image. Written for #203, which is
# #83's deliverable 2 and #72's open question 1; see docs/o1-rom-source.md.
#
# WHY IT IS A SCRIPT
#   The 2026-10-13 session found the vendor's toolchain in the local archive and
#   spent most of its time on everything *around* the assembly. Each of the
#   steps below cost at least one wasted MAME run to learn:
#
#   * the program is ACT80.COM, so the command is ACT80 -- typing the "ACT" of
#     tran.txt gets CP/M's "<name>?" (command not found), which reads exactly
#     like an ACT usage error and is not one;
#   * OS1SYSD.IMD boots to AUTOST.COM, which prints "LOADING CP/M AND HELP..."
#     and runs HELP.COM's menu; ESC would be needed to get out and posting ESC
#     segfaults MAME's Lua layer, so AUTOST.COM is removed from the disk instead;
#   * research/source-code/BIOS-144-source/rom144.asm is LF-only with three
#     stray CRs where a line break was lost, and CP/M text wants CRLF -- the
#     normalisation below treats each stray CR as the line break it was;
#   * drive B needs room for the 12 KB hex file *plus* the 83 KB source, and a
#     full system disk does not have it: the first attempt assembled with
#     "no ERRORs" and then wrote a 0-byte ROM144.HEX behind two "Hex file write
#     error." lines;
#   * MAME only flushes a modified floppy on a clean shutdown, so o1keys.sh is
#     used as-is (it never calls os.exit()).
#
# ENVIRONMENT
#   O1_ACT80    path to an ACT80.COM to use instead of the safety copy in
#               research/act-assembler/ (#203). The archive's SORCIM kit and
#               LOOSECPM/119 both work: 3.0 and 3.2 produce byte-identical hex
#               for this source.
#   O1_WORK     default work directory (default /tmp/o1-rom144)
set -eu

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
WORK="${1:-${O1_WORK:-/tmp/o1-rom144}}"
ACT80="${O1_ACT80:-$REPO/research/act-assembler/ACT80.COM}"
SRC="$REPO/research/source-code/BIOS-144-source/rom144.asm"
SYS="$REPO/research/shipped-software/OS1SYSD.IMD"
REF="$REPO/research/roms/os1-144.rom"
FMT=osborne1                     # cpmtools diskdef: 1024 B sectors, 5/track, 1K blocks

for f in "$ACT80" "$SRC" "$SYS" "$REF"; do
    [ -f "$f" ] || { echo "rom144-reassemble.sh: missing $f" >&2; exit 1; }
done
for t in cpmcp cpmrm mame python3; do
    command -v "$t" >/dev/null || { echo "rom144-reassemble.sh: $t not on PATH" >&2; exit 1; }
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
    --comment "ACT80.COM reassembly of ROM 1.44: drive A (#203)"

echo "== 3. drive B: the source, as CRLF, on an otherwise empty disk =="
cp "$WORK/sys.raw" "$WORK/b.raw"
cpmrm -f "$FMT" "$WORK/b.raw" '0:*.*'
python3 - "$SRC" "$WORK/ROM144.ASM" <<'PY'
import sys
# rom144.asm as captured from GitHub is LF-only with three stray CRs (offsets
# 56819, 59483, 60178) where the original CP/M file's line break lost its LF.
# Normalise CRLF -> LF -> CRLF, treating each stray CR as the break it was:
# the source then has 4658 lines rather than 4655.
d = open(sys.argv[1], 'rb').read()
d = d.replace(b'\r\n', b'\n').replace(b'\r', b'\n')
open(sys.argv[2], 'wb').write(b'\r\n'.join(d.split(b'\n')))
PY
cpmcp -f "$FMT" "$WORK/b.raw" "$WORK/ROM144.ASM" 0:ROM144.ASM
python3 "$HERE/o1raw2imd.py" --dd "$WORK/b.raw" "$WORK/b.imd" \
    --comment "ACT80.COM reassembly of ROM 1.44: drive B (#203)"

echo "== 4. run the assembly under MAME =="
# MAME writes the guest's changes back into these files, so work on copies.
cp "$WORK/a.imd" "$WORK/run_a.imd"
cp "$WORK/b.imd" "$WORK/run_b.imd"
O1_KEYS="$(printf 'sleep 2\ntype ACT80 B:ROM144 H=B:\nsleep 260\ndump assembled\n')" \
O1_WAIT=60 \
    "$HERE/o1keys.sh" osborne1 "$WORK/run_a.imd" "$WORK/run_b.imd" 400 \
    > "$WORK/act.log" 2>&1 || true
grep -E "no ERRORs|ERROR|SORCIM|Hex file write error|Pass 2" "$WORK/act.log" || true

echo "== 5. take ROM144.HEX off drive B =="
python3 "$HERE/imdinfo.py" --raw "$WORK/run_b.raw" "$WORK/run_b.imd" >/dev/null
cpmcp -f "$FMT" "$WORK/run_b.raw" 0:ROM144.HEX "$WORK/ROM144.HEX"

echo "== 6. hex -> image, and compare with the shipped ROM =="
# acthex.py reports any record it cannot read and any record whose checksum
# disagrees with its own bytes. On this build one record arrives with 6 non-hex
# bytes in it (docs/o1-rom-source.md): its checksum is intact and correct for
# the 16 bytes of FF it should have held, so --recover-ff fills that range from
# the record's own checksum rather than from the reference. The comparison is
# then the real test -- it says whether all 4096 bytes match.
python3 "$HERE/acthex.py" "$WORK/ROM144.HEX" "$WORK/ROM144.bin" \
    --recover-ff --reference "$REF"
