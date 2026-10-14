#!/bin/sh
# boot-o1next.sh [FLOP1.imd] [FLOP2.imd]
#
# Boot the `osborne1nx` machine **in a window, so it can actually be used** --
# video and sound on, real time, up to two floppy images in drive A and drive B.
#
# WHY THIS EXISTS
#   Every other script in this repo is headless.  `-video none` and
#   `SDL_VIDEODRIVER=dummy` are what make the automated checks reproducible, and
#   they are the right default for a test -- and the wrong default for *using*
#   the machine.  So each emulated machine gets one of these beside it once it
#   reaches a milestone.  See AGENTS.md, "The MAME machines, and boot-o1next.sh".
#
# USAGE
#   tools/emulator-setup/mame-osborne1nx/boot-o1next.sh
#   tools/emulator-setup/mame-osborne1nx/boot-o1next.sh OS1SYSD.IMD
#   tools/emulator-setup/mame-osborne1nx/boot-o1next.sh A.IMD B.IMD
#
#   With no floppy it boots the 1.44 monitor's "Insert disk in Drive A and press
#   RETURN."  Press RETURN with an empty drive and it says so.
#
#   To boot the MD-10's CP/M off the hard disk as well -- three partitions at
#   `A0>` / `B0>` / `C0>` -- build the floor-pin drive and point O1_HARD at it.
#   Note the utilities disk in the archive is a **bare raw image**, so it needs
#   wrapping as an IMD before MAME will take it:
#
#     tools/research/md10drive.py --out /tmp/md10/hd.chd --force
#     tools/research/o1raw2imd.py \
#       'research/adaptec/Osborne Hard Disk Control Software Version 2.01 (1984).img' \
#       /tmp/md10/prep.imd
#     O1_HARD=/tmp/md10/hd.chd \
#       tools/emulator-setup/mame-osborne1nx/boot-o1next.sh /tmp/md10/prep.imd
#
#   then type `HARD` at the `A>` prompt.  (Both the raw image and any in-repo IMD
#   are staged as copies -- see below.)
#
# ENVIRONMENT
#   O1_MAME     the patched `osborne1nx` binary.  `mame` on PATH has no such
#               machine -- it is a patch, see README.md -- so this is looked for
#               in the usual build trees first and must be set otherwise.
#   O1_ROMPATH  ROM path (default tools/emulator-setup/roms); must be absolute.
#   O1_HARD     a CHD to mount as the ACB-4000's hard disk.
#   O1_BIOS     an optional MAME BIOS slot.
#   O1_RUNDIR   where MAME keeps cfg/ snap/ and staged floppies (default
#               ~/.o1next-mame).  MAME writes those into the *current* directory,
#               so this script never runs it in the repo.
#   O1_SECONDS  if set, add `-seconds_to_run` and exit -- for a smoke test.
#
#   A floppy image **inside the repo is copied** to $O1_RUNDIR/floppies/ and the
#   copy is mounted, because MAME writes back into a floppy image in place and
#   `research/` and `tools/` are archives that must not be modified.  Images
#   outside the repo are mounted as given, so your own disks keep your changes.
set -eu

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"

abspath() {
    d="$(cd "$(dirname "$1")" && pwd)"
    printf '%s/%s' "$d" "$(basename "$1")"
}

if [ "$#" -gt 2 ]; then
    echo "boot-o1next.sh: at most two floppy images (drive A, drive B)" >&2
    exit 1
fi
FLOP1="${1:-}"
FLOP2="${2:-}"

ROMPATH="${O1_ROMPATH:-$REPO/tools/emulator-setup/roms}"
case "$ROMPATH" in
    /*) ;;
    *) echo "boot-o1next.sh: O1_ROMPATH must be absolute" >&2; exit 1;;
esac
[ -d "$ROMPATH" ] || { echo "boot-o1next.sh: no such ROM path: $ROMPATH" >&2; exit 1; }

MAME="${O1_MAME:-}"
if [ -z "$MAME" ]; then
    for cand in "$HOME/scratch/mame-verify/mame-mame0289/osborne1nx" \
                "$HOME/scratch/mame-mame0289/osborne1nx" \
                "$HOME/scratch/mame-clean/mame-mame0289/osborne1nx"; do
        if [ -x "$cand" ]; then MAME="$cand"; break; fi
    done
fi
if [ -z "$MAME" ]; then
    echo "boot-o1next.sh: no osborne1nx binary." >&2
    echo "  The 'mame' on PATH has no such machine -- it is a patch." >&2
    echo "  Build one with tools/emulator-setup/mame-osborne1nx/apply.sh, or set" >&2
    echo "  O1_MAME to an existing build." >&2
    exit 1
fi
case "$MAME" in
    /*) ;;
    *) MAME="$(abspath "$MAME")";;
esac
[ -x "$MAME" ] || { echo "boot-o1next.sh: not executable: $MAME" >&2; exit 1; }

RUNDIR="${O1_RUNDIR:-$HOME/.o1next-mame}"
mkdir -p "$RUNDIR/floppies"

stage() {   # stage IMAGE -- mount a copy of anything inside the repo
    img="$1"
    [ -f "$img" ] || { echo "boot-o1next.sh: no such image: $img" >&2; exit 1; }
    # MAME's own failure for a bare raw image is "Unable to identify image file
    # format", which says nothing about the fix.  These are IMD files, and the
    # archive's Osborne images are often bare raw, so say so here instead.
    if [ "$(head -c 3 "$img" 2>/dev/null)" != "IMD" ]; then
        echo "boot-o1next.sh: $img is not an IMD file." >&2
        echo "  A bare raw image needs wrapping first:" >&2
        echo "    tools/research/o1raw2imd.py '$img' /tmp/$(basename "$img").imd" >&2
        exit 1
    fi
    abs="$(abspath "$img")"
    case "$abs" in
        "$REPO"/*)
            base="$(basename "$img")"
            cp "$abs" "$RUNDIR/floppies/$base"
            echo "  (in the repo -- mounting a copy, so the archive is not" >&2
            echo "   written through: $RUNDIR/floppies/$base)" >&2
            printf '%s' "$RUNDIR/floppies/$base"
            ;;
        *) printf '%s' "$abs" ;;
    esac
}

if [ -n "$FLOP1" ]; then FLOP1="$(stage "$FLOP1")"; fi
if [ -n "$FLOP2" ]; then FLOP2="$(stage "$FLOP2")"; fi

HARD="${O1_HARD:-}"
if [ -n "$HARD" ]; then
    [ -f "$HARD" ] || { echo "boot-o1next.sh: no such hard disk: $HARD" >&2; exit 1; }
    HARD="$(abspath "$HARD")"
fi

# MAME's default is full screen, and `-window` is the only thing that keeps the
# mac OSD off the whole display; it is harmless for the SDL OSD.
set -- osborne1nx -window -skip_gameinfo -rompath "$ROMPATH"
if [ -n "${O1_BIOS:-}" ]; then set -- "$@" -bios "$O1_BIOS"; fi
if [ -n "$FLOP1" ]; then set -- "$@" -flop1 "$FLOP1"; fi
if [ -n "$FLOP2" ]; then set -- "$@" -flop2 "$FLOP2"; fi
if [ -n "$HARD" ]; then set -- "$@" -harddisk "$HARD"; fi
if [ -n "${O1_SECONDS:-}" ]; then set -- "$@" -seconds_to_run "$O1_SECONDS"; fi

echo "osborne1nx -- the emulated interposer, 1.44 ROM, windowed"
echo "  binary:    $MAME"
echo "  rompath:   $ROMPATH"
echo "  drive A:   ${FLOP1:-<empty>}"
echo "  drive B:   ${FLOP2:-<empty>}"
echo "  hard disk: ${HARD:-<none>}"
echo "  cfg/snap:  $RUNDIR"
echo "  quit with  Esc, or the window's close button"
if [ -z "$HARD" ]; then
    echo
    echo "No hard disk mounted.  For the MD-10's CP/M on three partitions, build"
    echo "the floor-pin drive and set O1_HARD, then type HARD at the A> prompt:"
    echo "  tools/research/md10drive.py --out /tmp/md10/hd.chd --force"
    echo "  tools/research/o1raw2imd.py '<raw utilities image>' /tmp/md10/prep.imd"
    echo "  O1_HARD=/tmp/md10/hd.chd $0 /tmp/md10/prep.imd"
fi
echo

cd "$RUNDIR"
exec "$MAME" "$@"

