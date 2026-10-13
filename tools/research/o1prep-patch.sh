#!/bin/sh
# o1prep-patch.sh -- build a *runnable* PREP.COM disk for osborne1ng.
#
# WHY THIS EXISTS
#   #191's handoff is "read the MD-10's on-disk structure out of PREP.COM", and
#   PREP.COM will not tell you by being read: the disk header it writes is built
#   at run time from the drive geometry, so the only way to see it is to make
#   PREP write it.  Under MAME it cannot finish -- the verify pass that follows
#   the format is SEARCH DATA EQUAL (2F) and MAME's t10spc/t10sbc have no handler
#   for it (docs/osborne1ng-machine.md section 5).
#
#   The *Disk initialization* menu is where "Change disk label" and "Format disk
#   using present parameters" live, and it sits behind that format.  So the one
#   patch this applies is a 3-byte jump: main-menu option 1 lands on that menu
#   directly.  Nothing else is touched -- the menu, the label editor and the
#   format are the vendor's own bytes.
#
#   The archive image is never modified; the output is a new file.  This script
#   is the durable form of the work: the patched image itself is a 100 KiB
#   derivative that regenerates in under a second, so it is *not* committed
#   (research/ is for primary sources -- AGENTS.md).
#
# WHAT IT DOES NOT DO
#   It does not set the card's select byte.  PREP computes that at run time from
#   the drive-address prompt this patch steps over, so it stays 00h -- which is
#   not a one-of-eight ID mask, so every transaction is accepted by the card and
#   delivered to no target, *with no error reported*.  That has to be written
#   while the guest runs:
#
#       poke 0x8023 01
#
#   tools/research/o1keys.lua's `poke` directive is that lever.  The full recipe
#   is docs/osborne1ng-machine.md section 6, and this script writes it out too.
#
# USAGE
#   tools/research/o1prep-patch.sh [OUTDIR]
#
#   OUTDIR defaults to /tmp/o1prep.  Writes:
#     prep.img          the patched raw image (40x10x256B FM, 102400 bytes)
#     prep.imd          the same, wrapped for MAME
#     prep.recipe.txt   the keys script and the command line that uses them
#
# Issue: #191 -- docs/osborne1ng-machine.md section 6.
set -eu

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
OUT="${1:-/tmp/o1prep}"

SRC="$REPO/research/adaptec/Osborne Hard Disk Control Software Version 2.01 (1984).img"
[ -f "$SRC" ] || { echo "o1prep-patch.sh: no such image: $SRC" >&2; exit 1; }
mkdir -p "$OUT"

# The patches, as FILE:OFFSET:HEX.  OFFSET is a file offset inside the named
# member (md10patch.py's convention: for a .COM, memory address minus 0x100), and
# md10patch.py rewrites it through the image's skew table so the patch lands on
# the file's own bytes and not on a physical sector.
#
#   PREP.COM +0x0EE4   CD 9F 31   CALL sub_319fh     -- the "1\r\n\n" echo
#                  ->  C3 BA 12   JP   12BAh         -- the Disk initialization menu
#
# 12BAh is the menu's entry: it parks its own address in 320Ah (so a sub-menu
# returns to it) and prints the menu.  Main-menu option 1 jumps here from 0335h,
# so this replaces the first instruction of its handler and nothing else.
PATCHES="PREP.COM 0x0EE4:c3ba12"

cp "$SRC" "$OUT/prep.img"
# shellcheck disable=SC2086
python3 "$HERE/md10patch.py" "$OUT/prep.img" "$OUT/prep.patched.img" $PATCHES
python3 "$HERE/o1raw2imd.py" "$OUT/prep.patched.img" "$OUT/prep.imd" \
    --comment "PREP.COM patched to enter the Disk initialization menu directly (#191)"

cat > "$OUT/prep.recipe.txt" <<'EOF'
# o1prep-patch.sh -- how to run the patched disk (#191)
#
# 1. a drive to write on (tools/research/mkdrive.py needs chdman)
CHDMAN=/path/to/chdman tools/research/mkdrive.py --out /tmp/o1prep/hd.chd
#
# 2. the keys script.  main-menu 1 lands on the Disk initialization menu; the
#    poke is the select byte the patch stepped over; 5 = Change disk label,
#    or 1 = Format disk using present parameters (then the password
#    "It's OK to destroy all data" and a bare RETURN for the interleave).
wait A>
type PREP
wait Main function
key 1
sleep 2
poke 0x8023 01
key 5
sleep 2
type MYLABEL
#
# 3. run it (osborne1ng is the built binary, not `mame osborne1ng`)
cd /tmp && O1_MACHINE=osborne1ng O1_FLOP1=/tmp/o1prep/prep.imd \
  O1_KEYS="$(cat /tmp/o1prep/keys.txt)" SDL_VIDEODRIVER=dummy \
  /path/to/osborne1ng osborne1ng -flop1 /tmp/o1prep/prep.imd -hard /tmp/o1prep/hd.chd \
  -video none -sound none -nothrottle \
  -autoboot_script /path/to/o1nextgen/tools/research/o1keys.lua \
  -seconds_to_run 90 -rompath /path/to/o1nextgen/tools/emulator-setup/roms
#
# 4. read the label back -- its text sits at offset 14 of LBA 0
chdman extracthd -i /tmp/o1prep/hd.chd -o /tmp/o1prep/hd.raw -f
xxd -l 64 /tmp/o1prep/hd.raw
EOF

echo
echo "patched : $OUT/prep.patched.img"
echo "for MAME: $OUT/prep.imd"
echo "recipe  : $OUT/prep.recipe.txt"
echo
echo "the image differs from the archive only in the three bytes above:"
python3 - "$SRC" "$OUT/prep.patched.img" <<'PY'
import sys
a = open(sys.argv[1], 'rb').read()
b = open(sys.argv[2], 'rb').read()
diff = [i for i in range(min(len(a), len(b))) if a[i] != b[i]]
print("  %d of %d bytes differ, at %s" % (
    len(diff), len(a), ", ".join("0x%05X" % i for i in diff) or "(none)"))
PY
