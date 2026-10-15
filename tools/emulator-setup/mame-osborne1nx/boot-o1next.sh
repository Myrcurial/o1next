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
#   then type `HARD` at the `A>` prompt.
#
#   To boot **ROM 2.0's own boot** -- the hard disk entered from the ROM, with no
#   floppy in the machine at all (#247) -- build the monitor and the image, point
#   O1_SOFTROM at it, and press RETURN at the sign-on prompt:
#
#     tools/research/rom2asm.sh -o /tmp/rom2-monitor.rom     # a few minutes
#     tools/research/rom2image.py --monitor /tmp/rom2-monitor.rom -o /tmp/rom2.rom
#     O1_SOFTROM=/tmp/rom2.rom O1_HARD=/tmp/md10/hd.chd \
#       tools/emulator-setup/mame-osborne1nx/boot-o1next.sh
#
#   and the machine reaches `A0>` with nothing in either drive: RETURN is the
#   monitor's `HCBOOT` entry (`:` is floppy A and `"` is floppy B, #247 step 4),
#   and the store that makes the hand-over work is in the ROM.  `rom2-check.sh` is
#   this, headless and measured.
#
# THE SAME SCRIPT RUNS IN A *STAGED* TEST MACHINE
#   `stage.sh` copies this script out of the repo with the patched binary and the
#   ROM set beside it, into a directory that owes the repo nothing:
#
#     ~/Documents/O1NEXT/test-machine-issue-247/
#       boot-o1next.sh   mame/osborne1nx   roms/osborne1nx/   run/   floppies/
#
#   cd into it and run `./boot-o1next.sh ../floppies/games.imd`.  That is what
#   this script looks for **first**: if `mame/<machine>` and `roms/` sit beside
#   it, it uses those and never reaches for a build tree.  A staged directory is a
#   build artifact -- disposable, regenerable, and deliberately not committed.
#
# ENVIRONMENT
#   O1_MAME     the patched `osborne1nx` binary, when it is not beside this
#               script.  `mame` on PATH has no such machine -- it is a patch, see
#               README.md -- so this is looked for in the usual build trees first
#               and must be set otherwise.
#   O1_ROMPATH  ROM path, when it is not beside this script; must be absolute.
#   O1_HARD     a CHD to mount as the ACB-4000's hard disk.
#   O1_BIOS     an optional MAME BIOS slot.
#   O1_SOFTROM  a ROM image to serve the ROM window from -- the interposer's
#               softROM (#247).  With none the window is the machine's own 1.44,
#               so the machine is a stock `osborne1`.  Unlike a floppy, this is
#               read-only: MAME never writes back into it.
#   O1_RUNDIR   where MAME keeps cfg/ snap/ and copied floppies.  Default: `run/`
#               beside this script when it is staged, `~/.o1next-mame` otherwise.
#               MAME writes those into the *current* directory, so this script
#               never runs it in the repo.
#   O1_SECONDS  if set, add `-seconds_to_run` and exit -- for a smoke test.
#
#   A floppy image **inside a git working tree is copied** to $O1_RUNDIR/floppies/
#   and the copy is mounted, because MAME writes back into a floppy image in place
#   and a checkout is not a working copy -- `research/` and `tools/` are archives.
#   Anywhere else it is mounted as given, so your own disks keep your changes.
set -eu

HERE="$(cd "$(dirname "$0")" && pwd)"
MACHINE=osborne1nx

# A staged test machine has the binary and the ROMs beside this script and owes
# the repo nothing; the repo's own copy reaches into a build tree instead.
STAGED=0
if [ -x "$HERE/mame/$MACHINE" ] && [ -d "$HERE/roms" ]; then STAGED=1; fi

# The repo root, only if this script is actually in one.  A staged copy is not,
# and the floppy rule below then falls back to the git-tree check, which needs no
# repo path at all.
REPO=""
if [ -f "$HERE/../../../AGENTS.md" ]; then REPO="$(cd "$HERE/../../.." && pwd)"; fi

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

MAME="${O1_MAME:-}"
if [ -z "$MAME" ] && [ "$STAGED" = 1 ]; then MAME="$HERE/mame/$MACHINE"; fi
if [ -z "$MAME" ]; then
    for cand in "$HOME/scratch/mame-verify/mame-mame0289/$MACHINE" \
                "$HOME/scratch/mame-mame0289/$MACHINE" \
                "$HOME/scratch/mame-clean/mame-mame0289/$MACHINE"; do
        if [ -x "$cand" ]; then MAME="$cand"; break; fi
    done
fi
if [ -z "$MAME" ]; then
    echo "boot-o1next.sh: no $MACHINE binary." >&2
    echo "  The 'mame' on PATH has no such machine -- it is a patch." >&2
    echo "  Build one with tools/emulator-setup/mame-osborne1nx/apply.sh, stage one" >&2
    echo "  with stage.sh, or set O1_MAME to an existing build." >&2
    exit 1
fi
case "$MAME" in
    /*) ;;
    *) MAME="$(abspath "$MAME")";;
esac
[ -x "$MAME" ] || { echo "boot-o1next.sh: not executable: $MAME" >&2; exit 1; }

if [ -n "${O1_ROMPATH:-}" ]; then
    ROMPATH="$O1_ROMPATH"
elif [ "$STAGED" = 1 ]; then
    ROMPATH="$HERE/roms"
else
    [ -n "$REPO" ] || {
        echo "boot-o1next.sh: not in the repo and not a staged machine --" >&2
        echo "  set O1_ROMPATH, or run the one in tools/emulator-setup/." >&2
        exit 1
    }
    ROMPATH="$REPO/tools/emulator-setup/roms"
fi
case "$ROMPATH" in
    /*) ;;
    *) echo "boot-o1next.sh: O1_ROMPATH must be absolute" >&2; exit 1;;
esac
[ -d "$ROMPATH" ] || { echo "boot-o1next.sh: no such ROM path: $ROMPATH" >&2; exit 1; }

if [ -n "${O1_RUNDIR:-}" ]; then
    RUNDIR="$O1_RUNDIR"
elif [ "$STAGED" = 1 ]; then
    RUNDIR="$HERE/run"
else
    RUNDIR="$HOME/.o1next-mame"
fi
mkdir -p "$RUNDIR/floppies"

stage() {   # stage IMAGE -- mount a copy of anything inside a git working tree
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
    # A checkout is not a working copy: MAME writes back into a floppy image as it
    # runs, so an image under version control is mounted as a fresh copy.  Stated
    # as a git-tree test rather than a repo-path test because a staged machine
    # knows nothing about where the repo is.
    if git -C "$(dirname "$abs")" rev-parse --show-toplevel >/dev/null 2>&1; then
        base="$(basename "$img")"
        cp "$abs" "$RUNDIR/floppies/$base"
        echo "  (inside a git tree -- mounting a fresh copy each run, so the" >&2
        echo "   archive is never written through: $RUNDIR/floppies/$base)" >&2
        printf '%s' "$RUNDIR/floppies/$base"
    else
        printf '%s' "$abs"
    fi
}

if [ -n "$FLOP1" ]; then FLOP1="$(stage "$FLOP1")"; fi
if [ -n "$FLOP2" ]; then FLOP2="$(stage "$FLOP2")"; fi

HARD="${O1_HARD:-}"
if [ -n "$HARD" ]; then
    [ -f "$HARD" ] || { echo "boot-o1next.sh: no such hard disk: $HARD" >&2; exit 1; }
    HARD="$(abspath "$HARD")"
fi

# The softROM image is read-only to MAME (the device is not writeable), so it is
# mounted as given -- there is nothing to copy it away from.
SOFTROM="${O1_SOFTROM:-}"
if [ -n "$SOFTROM" ]; then
    [ -f "$SOFTROM" ] || { echo "boot-o1next.sh: no such ROM image: $SOFTROM" >&2; exit 1; }
    SOFTROM="$(abspath "$SOFTROM")"
fi

# MAME's default is full screen, and `-window` is the only thing that keeps the
# mac OSD off the whole display; it is harmless for the SDL OSD.
set -- osborne1nx -window -skip_gameinfo -rompath "$ROMPATH"
if [ -n "${O1_BIOS:-}" ]; then set -- "$@" -bios "$O1_BIOS"; fi
if [ -n "$FLOP1" ]; then set -- "$@" -flop1 "$FLOP1"; fi
if [ -n "$FLOP2" ]; then set -- "$@" -flop2 "$FLOP2"; fi
if [ -n "$HARD" ]; then set -- "$@" -harddisk "$HARD"; fi
if [ -n "$SOFTROM" ]; then set -- "$@" -softrom "$SOFTROM"; fi
if [ -n "${O1_SECONDS:-}" ]; then set -- "$@" -seconds_to_run "$O1_SECONDS"; fi

if [ "$STAGED" = 1 ]; then
    echo "osborne1nx -- a staged test machine, windowed"
else
    echo "osborne1nx -- the emulated interposer, 1.44 ROM, windowed"
fi
echo "  binary:    $MAME"
echo "  rompath:   $ROMPATH"
echo "  drive A:   ${FLOP1:-<empty>}"
echo "  drive B:   ${FLOP2:-<empty>}"
echo "  hard disk: ${HARD:-<none>}"
if [ -n "$SOFTROM" ]; then
    echo "  softROM:   $SOFTROM"
else
    echo "  softROM:   none -- the machine's own ROM"
fi
echo "  cfg/snap:  $RUNDIR"
echo "  quit with  Esc, or the window's close button"
if [ -z "$HARD" ]; then
    echo
    echo "No hard disk mounted.  For the MD-10's CP/M on three partitions, build"
    echo "the floor-pin drive and set O1_HARD, then type HARD at the A> prompt."
    echo "Both tools live in the repo, under tools/research/:"
    echo "  md10drive.py --out /tmp/md10/hd.chd --force"
    echo "  o1raw2imd.py '<raw utilities image>' /tmp/md10/prep.imd"
    echo "  O1_HARD=/tmp/md10/hd.chd $0 /tmp/md10/prep.imd"
fi
echo

cd "$RUNDIR"
exec "$MAME" "$@"

