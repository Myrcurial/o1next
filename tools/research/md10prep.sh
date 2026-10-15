#!/bin/sh
# md10prep.sh CHS PARTITIONS OUTDIR [LABEL]
#
# Configure a blank MD-10 drive of a given geometry with the archive's own
# PREP.COM, and read back what the 1984 installer wrote.
#
# WHY THIS EXISTS
#   The three-partition PYXIS27 drive (#247) was produced by hand-driving
#   PREP.COM's menus through MAME and then reading the drive back with a
#   throwaway script.  A new geometry should not cost that again: this is the
#   same session, scripted and parameterised, so "here is a geometry, give me a
#   configured drive" is one command.
#
#   It is a *host* script, not shipped tooling -- it wants MAME, the patched
#   `osborne1nx` machine, and the archive's 2.01 utilities disk.  See
#   docs/md10-system.md.
#
# USAGE
#   tools/research/md10prep.sh 321,8,18 3 /tmp/md10            # PYXIS27, MD-20
#   tools/research/md10prep.sh 321,4,18 2 /tmp/md10 MD10SYS    # PYXIS13, MD-10
#
#   PARTITIONS is 2, 3 or 6 -- PREP.COM's "Two / Three / Six logical drives"
#   (MD-10 / MD-20 / MD-44), each a *fixed* layout -- or `eqN`, which is
#   PREP.COM's option 4, "Non-standard equal drive partitioning", N drives
#   dividing the disk.  That is the only way to a bigger partition, and it is
#   also capped: PREP.COM refuses a partition over **16384 blocks (8 MiB)**,
#   measured -- see md10dpb.py, and docs/md10-system.md 9.2.
#
#   A trap worth knowing, because it cost a reproduction: after the partition step
#   PREP.COM returns to the *main* menu by itself, for every option, so an `esc`
#   there exits the program.  The session below waits for "Initializing all
#   partitions" and then presses nothing until it is back at the main menu.
#
#   The O/S is *not* left ready to boot.  PREP.COM relocates it to whatever base
#   its own arithmetic picks, which is not always the load address (two captures
#   measured, two different bases -- md10reloc.py).  This script reports what it
#   found and does not guess; pass the extracted O/S through md10reloc.py.
#
# ENVIRONMENT
#   O1_MAME     the patched `osborne1nx` binary (required).  The `mame` on PATH
#               has no osborne1nx machine -- see
#               tools/emulator-setup/mame-osborne1nx/.
#   O1_ROMPATH  ROM path (default $REPO/tools/emulator-setup/roms); must be
#               absolute, because MAME runs from a neutral directory.
#   O1_CHDMAN   chdman (default `chdman` on PATH, then a MAME source tree)
#   O1_WAIT     seconds to wait for a `wait` pattern (default 45)
#   O1_SECONDS  emulated seconds for the PREP.COM session (default 420)
#
# Written for #247.  Traps that cost time are in docs/md10-system.md 2.
set -eu

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"

CHS="${1:?usage: md10prep.sh CHS PARTITIONS OUTDIR [LABEL]}"
PARTS="${2:?usage: md10prep.sh CHS PARTITIONS OUTDIR [LABEL]}"
OUTDIR="${3:?usage: md10prep.sh CHS PARTITIONS OUTDIR [LABEL]}"
LABEL="${4:-MD10SYS}"

MAME="${O1_MAME:?set O1_MAME to the patched osborne1nx binary (tools/emulator-setup/mame-osborne1nx/)}"
ROMPATH="${O1_ROMPATH:-$REPO/tools/emulator-setup/roms}"
WAIT="${O1_WAIT:-45}"
SECONDS_BUDGET="${O1_SECONDS:-420}"
UTILS="$REPO/research/adaptec/Osborne Hard Disk Control Software Version 2.01 (1984).img"

case "$ROMPATH" in
    /*) ;;
    *) echo "md10prep.sh: O1_ROMPATH must be absolute" >&2; exit 1;;
esac
[ -x "$MAME" ] || { echo "md10prep.sh: O1_MAME is not executable: $MAME" >&2; exit 1; }
[ -d "$ROMPATH" ] || { echo "md10prep.sh: no such ROM path: $ROMPATH" >&2; exit 1; }
[ -f "$UTILS" ] || { echo "md10prep.sh: the 2.01 utilities disk is missing: $UTILS" >&2; exit 1; }

case "$PARTS" in
    2) MENU_KEY=1 ; EXTRA="" ;;
    3) MENU_KEY=2 ; EXTRA="" ;;
    6) MENU_KEY=3 ; EXTRA="" ;;
    eq*) N="${PARTS#eq}"
         case "$N" in
             ''|*[!0-9]*) echo "md10prep.sh: eq needs a count, e.g. eq3" >&2; exit 1 ;;
         esac
         MENU_KEY=4
         EXTRA="wait number of logical drives
type $N" ;;
    *) echo "md10prep.sh: PARTITIONS must be 2, 3, 6 or eqN (PREP.COM's menu)" >&2
       exit 1;;
esac

mkdir -p "$OUTDIR"

# chdman is needed by the first step, not just the last, so resolve it now.
# The MAME source tree the patched osborne1nx machine was built in also builds
# it, and it is not on PATH (REQUIREMENTS.md).
CHDMAN="${O1_CHDMAN:-${CHDMAN:-chdman}}"
if ! command -v "$CHDMAN" >/dev/null 2>&1; then
    for cand in "$HOME/scratch/mame-mame0289/chdman" \
                "$HOME/scratch/mame-verify/mame-mame0289/chdman"; do
        if [ -x "$cand" ]; then CHDMAN="$cand"; break; fi
    done
fi
command -v "$CHDMAN" >/dev/null 2>&1 || {
    echo "md10prep.sh: no chdman; set O1_CHDMAN or \$CHDMAN (REQUIREMENTS.md)" >&2
    exit 1
}

# 1. a labelled, formatted blank drive of the requested geometry
"$HERE/mkdrive.py" --chs "$CHS" --label "$LABEL" --out "$OUTDIR/work.chd" \
    --chdman "$CHDMAN" --force

# 2. the utilities disk as an IMD (it is a bare raw image)
"$HERE/o1raw2imd.py" "$UTILS" "$OUTDIR/prep.imd"

# 3. the PREP.COM session.  The order is load-bearing (docs/md10-system.md 2):
#    the label must be written BEFORE the partition, because writing the label
#    is also what terminates the partition table with FFh; and main-menu option
#    3 (configure the O/S) needs an O/S partition, which the partition step
#    creates.  The format options are skipped -- mkdrive.py already wrote the
#    6Ch fill a format would produce.
cat > "$OUTDIR/keys.txt" <<EOF
type PREP
wait Main function
key 1
wait drive address
key cr
wait Disk initialization menu
key 5
wait disk label
type $LABEL
sleep 3
key 4
wait Partition definition menu
key $MENU_KEY
$EXTRA
wait Initializing all partitions
sleep 30
key 3
wait drive address
key cr
sleep 100
key esc
sleep 2
key esc
sleep 3
EOF

# 4. run it, headless, from the output directory -- MAME writes cfg/ and snap/
#    into the current directory and must not litter the repo.  Its exit status
#    is meaningless once the guest is warm-booted, so the log is the evidence.
(
    cd "$OUTDIR"
    O1_MACHINE=osborne1nx O1_FLOP1="$OUTDIR/prep.imd" \
    O1_KEYS="$(cat "$OUTDIR/keys.txt")" O1_WAIT="$WAIT" SDL_VIDEODRIVER=dummy \
    "$MAME" osborne1nx \
        -flop1 "$OUTDIR/prep.imd" -harddisk "$OUTDIR/work.chd" \
        -video none -sound none -nothrottle \
        -autoboot_script "$HERE/o1keys.lua" \
        -seconds_to_run "$SECONDS_BUDGET" -rompath "$ROMPATH"
) > "$OUTDIR/prep.log" 2>&1 || true

# 5. read the drive back
"$CHDMAN" extracthd -i "$OUTDIR/work.chd" -o "$OUTDIR/configured.raw" -f >/dev/null

# the first sixteen blocks, and the O/S at LBA 5 for eleven
dd if="$OUTDIR/configured.raw" of="$OUTDIR/lba0-15.bin" bs=512 count=16 2>/dev/null
dd if="$OUTDIR/configured.raw" of="$OUTDIR/md10-os.bin" bs=512 skip=5 count=11 2>/dev/null

echo
echo "=== what PREP.COM wrote ==="
"$HERE/md10table.py" --chdman "$CHDMAN" "$OUTDIR/configured.raw"

echo
echo "=== the operating system's relocation base (md10reloc.py) ==="
if "$HERE/md10reloc.py" --os "$OUTDIR/md10-os.bin" \
        --out "$OUTDIR/md10-os-fixed.bin"; then
    echo "  -> $OUTDIR/md10-os-fixed.bin is the bootable O/S for this drive"
else
    echo "  md10reloc.py refused to write; read its report above before using" >&2
    echo "  this drive -- an O/S at the wrong base warm-boots for ever (#198)" >&2
fi

cat <<'NOTE'

NOTE: whatever partition size PREP.COM chose, the MD-10 *driver* carries ONE
shared DPB for all hard-disk drives (DSM=1923 -> 7.5 MiB usable), so a partition
larger than 15399 blocks is bigger than CP/M will ever use, and a smaller one is
over-claimed by CP/M -- writing a large file to it runs into the next partition
(docs/md10-system.md 9).  PYXIS27 with three 15399-block partitions is the layout
that matches, and it is `md10drive.py --layout md20`.

`tools/research/md10dpb.py` is the patch for that: give it the three partition
sizes and it rewrites the DPB and the three ALV pointers in HARD.COM, placing the
ALVs in the RAM that is actually free.  At the shipped 15399 it reproduces the
vendor's file byte for byte; at PREP.COM's 16384-block (8 MiB) ceiling it fits
with 683 bytes of the 1451 to spare.  Past 8 MiB, PREP.COM will not make the
partition and three *different* sizes need three DPBs, which HARD.COM has no room
for -- docs/md10-system.md 9.2.
NOTE

echo
echo "wrote, in $OUTDIR:"
echo "  work.chd          the configured drive (as MAME left it)"
echo "  configured.raw    the same drive, extracted"
echo "  lba0-15.bin       its first sixteen blocks (a header artifact)"
echo "  md10-os.bin       the O/S PREP.COM wrote (LBA 5, 11 blocks)"
echo "  keys.txt          the PREP.COM session, for the record"
echo "  prep.log          the session's output -- the evidence"

