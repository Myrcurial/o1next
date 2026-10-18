#!/bin/sh
# stage.sh [DEST]
#
# Stage a **self-contained test machine** out of the repo: the patched
# `osborne1nx` binary, its ROM set, and `boot-o1next.sh`, in one directory that
# owes the repo nothing.  cd into it and run it.
#
# WHY THIS EXISTS
#   The repo's copy of `boot-o1next.sh` reaches into a MAME build tree and the
#   repo's ROMs -- right while you are working in the repo, and useless when you
#   are not.  A staged machine is the other half: a **build artifact**, named for
#   the issue the way a build product is named, that you can cd into, copy, keep
#   or delete.  Regenerating it is one command.  Nothing in the repo depends on
#   it and it depends on nothing in the repo.
#
# USAGE
#   tools/emulator-setup/mame-osborne1nx/stage.sh
#   tools/emulator-setup/mame-osborne1nx/stage.sh /tmp/o1next-machine
#
#   DEST defaults to $O1_STAGE_ROOT/test-machine-issue-247, and $O1_STAGE_ROOT
#   to $HOME/Documents/O1NEXT.
#
# WHAT IT WRITES
#   $DEST/mame/osborne1nx      the patched binary
#   $DEST/roms/osborne1nx/     the ROM set the machine declares
#   $DEST/boot-o1next.sh       the launcher, which finds those beside itself
#   $DEST/README.md            what this is, and how to regenerate it
#   $DEST/MANIFEST             what went in, from where, with CRCs
#   $DEST/run/                 MAME's cfg/ snap/ and copies of archive images
#   $ROOT/floppies/            a few disks to feed it -- **only if absent**
#
#   The floppies are staged **once and never overwritten**, because they are
#   inputs: MAME writes back into a floppy image as it runs, so refreshing them
#   would throw away whatever you had done on them.
#
# ENVIRONMENT
#   O1_MAME            the binary to stage (default: the usual build trees)
#   O1_STAGE_ROOT      where test machines go (default $HOME/Documents/O1NEXT)
#   O1_STAGE_FLOPPIES  set to 0 to skip the floppies directory
set -eu

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"
MACHINE=osborne1nx

# The ROMs the machine declares, with the CRCs MAME's own ROM_START asserts, so
# the staged copy verifies itself rather than being a hopeful copy.
ROM_MAIN=3a10082-00rev-e.ud11
ROM_CHAR=7a3007-00.ud15
CRC_MAIN=c0596b14
CRC_CHAR=6c1eab0d

STAGE_ROOT="${O1_STAGE_ROOT:-$HOME/Documents/O1NEXT}"
DEST="${1:-$STAGE_ROOT/test-machine-issue-247}"
FLOPPIES="${O1_STAGE_FLOPPIES:-1}"
ROM_SRC="$REPO/tools/emulator-setup/roms"

crc32() {
    python3 -c 'import sys,zlib
print("%08x" % (zlib.crc32(open(sys.argv[1],"rb").read()) & 0xffffffff))' "$1"
}

MAME="${O1_MAME:-}"
if [ -z "$MAME" ]; then
    for cand in "$HOME/scratch/mame-verify/mame-mame0289/$MACHINE" \
                "$HOME/scratch/mame-mame0289/$MACHINE" \
                "$HOME/scratch/mame-clean/mame-mame0289/$MACHINE"; do
        if [ -x "$cand" ]; then MAME="$cand"; break; fi
    done
fi
if [ -z "$MAME" ]; then
    echo "stage.sh: no $MACHINE binary." >&2
    echo "  Build one with tools/emulator-setup/mame-osborne1nx/apply.sh, or set" >&2
    echo "  O1_MAME to an existing build." >&2
    exit 1
fi
[ -x "$MAME" ] || { echo "stage.sh: not executable: $MAME" >&2; exit 1; }

for f in "$ROM_SRC/$ROM_MAIN" "$ROM_SRC/$ROM_CHAR"; do
    [ -f "$f" ] || { echo "stage.sh: missing ROM: $f" >&2; exit 1; }
done

# --- the machine ------------------------------------------------------------

mkdir -p "$DEST/mame" "$DEST/roms/$MACHINE" "$DEST/run"

echo "staging $MACHINE into $DEST"
cp "$MAME" "$DEST/mame/$MACHINE"
chmod +x "$DEST/mame/$MACHINE"
cp "$ROM_SRC/$ROM_MAIN" "$DEST/roms/$MACHINE/$ROM_MAIN"
cp "$ROM_SRC/$ROM_CHAR" "$DEST/roms/$MACHINE/$ROM_CHAR"
cp "$HERE/boot-o1next.sh" "$DEST/boot-o1next.sh"
chmod +x "$DEST/boot-o1next.sh"

# The interposer's flash asset (#247; one of them, since #278): the **animation**.
# The boot frame and the screen's code were what the ROM asked the door for, and the
# ROM-side frame path retired on 2026-10-17 -- the RP2354B plays the animation
# itself, and the monitor draws its own fallback out of its own tail -- so there is
# nothing to derive and nothing else to stage.
ASSETS="$REPO/firmware/rom-service"
[ -f "$ASSETS/boot-animation.bin" ] || {
    echo "stage.sh: missing asset: $ASSETS/boot-animation.bin" >&2; exit 1; }
mkdir -p "$DEST/assets"
cp "$ASSETS/boot-animation.bin" "$DEST/assets/boot-animation.bin"
python3 "$REPO/tools/research/bootanim.py" --check "$ASSETS/boot-animation.bin" >/dev/null || {
    echo "stage.sh: the animation is not the asset it says it is:" >&2
    python3 "$REPO/tools/research/bootanim.py" --check "$ASSETS/boot-animation.bin" >&2
    exit 1; }

# The staged copy is a copy, so check it rather than trusting it.
got_main="$(crc32 "$DEST/roms/$MACHINE/$ROM_MAIN")"
got_char="$(crc32 "$DEST/roms/$MACHINE/$ROM_CHAR")"
if [ "$got_main" != "$CRC_MAIN" ] || [ "$got_char" != "$CRC_CHAR" ]; then
    echo "stage.sh: staged ROMs do not match the machine's own ROM_START." >&2
    echo "  $ROM_MAIN: got $got_main, want $CRC_MAIN" >&2
    echo "  $ROM_CHAR: got $got_char, want $CRC_CHAR" >&2
    echo "  The binary and the ROMs are out of step -- check which build tree" >&2
    echo "  O1_MAME pointed at (a patched tree, not a stock one)." >&2
    exit 1
fi

# --- the disks to feed it ---------------------------------------------------
# Only if absent.  These are inputs, and MAME writes back into a floppy image as
# it runs, so refreshing them would throw away whatever you had done on them.

stage_disk() {   # stage_disk SRC NAME
    src="$1"
    dst="$STAGE_ROOT/floppies/$2"
    if [ -f "$dst" ]; then
        echo "  floppies/$2 -- already there, left alone"
    elif [ -f "$src" ]; then
        cp "$src" "$dst"
        echo "  floppies/$2"
    fi
}

if [ "$FLOPPIES" = 1 ]; then
    mkdir -p "$STAGE_ROOT/floppies"
    echo
    echo "floppies in $STAGE_ROOT/floppies (never overwritten):"
    stage_disk "$REPO/research/shipped-software/OS1SYSD.IMD"   system-disk.imd
    stage_disk "$REPO/research/shipped-software/OS1UTLS.IMD"   utilities-disk.imd
    stage_disk "$REPO/research/shipped-software/OS1WRDST.IMD"  wordstar.imd
    stage_disk "$REPO/research/shipped-software/OS1BASIC.IMD"  basic.imd
fi

# --- what this is, and what went into it ------------------------------------

cat > "$DEST/MANIFEST" <<EOF
# $MACHINE -- a staged test machine, built by
#   tools/emulator-setup/mame-osborne1nx/stage.sh
#
# Regenerate it with that command; delete it whenever.  Nothing in the repo
# depends on this directory and it depends on nothing in the repo.

staged      $(date -u '+%Y-%m-%dT%H:%M:%SZ')
machine     $MACHINE (MAME 0.289 + tools/emulator-setup/mame-osborne1nx/osborne1nx.patch)
binary      mame/$MACHINE   $($MAME -version 2>/dev/null | head -1)
built-from  $MAME

roms/$MACHINE/$ROM_MAIN   crc32 $got_main
roms/$MACHINE/$ROM_CHAR   crc32 $got_char

assets/boot-animation.bin crc32 $(crc32 "$DEST/assets/boot-animation.bin")   the boot screen: a 32-byte O1SPLASH header and 90 sealed frames

boot-o1next.sh    copied from $HERE/boot-o1next.sh
EOF

cat > "$DEST/README.md" <<EOF
# $MACHINE -- a staged test machine

A **self-contained** copy of the emulated O1NEXT: the patched MAME binary, its
ROM set, and a launcher that finds both beside itself. It owes the repo nothing.

Staged $(date -u '+%Y-%m-%dT%H:%M:%SZ') by
\`tools/emulator-setup/mame-osborne1nx/stage.sh\`. **Regenerate it with that
command, or delete it whenever** -- it is a build artifact, not a source.

## Run it

\`\`\`sh
cd $DEST
./boot-o1next.sh                                   # empty machine
./boot-o1next.sh ../floppies/system-disk.imd       # boot CP/M
./boot-o1next.sh ../floppies/utilities-disk.imd    # the MD-10 utilities disk
\`\`\`

Video and sound are on and it runs at real time -- this is the machine to *use*,
not a test harness. Esc (or the window's close button) quits.

Two floppy images at most, in drive A and drive B. The disks in
\`$STAGE_ROOT/floppies/\` are:

| | |
|---|---|
| \`system-disk.imd\` | bootable CP/M (OS1SYSD) |
| \`utilities-disk.imd\` | the Osborne utilities (OS1UTLS) |
| \`wordstar.imd\` | WordStar (OS1WRDST) |
| \`basic.imd\` | MBASIC (OS1BASIC) |

They are staged **once and never overwritten** -- MAME writes back into a floppy
image as it runs, so those copies are yours to keep. Add your own anywhere and
pass the path.

## The boot screen

The interposer's flash asset is staged in \`assets/\` (#247), and since #278 it is
the **animation**, one file: the \`-frame\` and \`-bootsplash\` slots the ROM used to be
served through retired with the ROM-side frame path, so there is nothing to mount
and nothing to derive:

\`\`\`sh
O1_SOFTROM=/path/to/rom2.rom ./boot-o1next.sh
\`\`\`

**The asset is the animation** (\`assets/boot-animation.bin\`): a 32-byte \`O1SPLASH\`
header and 90 sealed frames, 128 x 32, 8 fps, played once. It is not the ROM's to
draw: the RP2354B plays it out of its own flash and stops on the Z80's first
video-RAM write, and the Z80's whole role is the *trigger* -- the fallback the
monitor's own screen code prints. Nothing here looks at the animation's content: the
ROM side can only say that the asset is *valid*, and
\`tools/research/bootanim.py --check\` is what says it (container sum, geometry, flags,
and every frame's own trailer).

ROM 2.0's *image* is not staged: it is assembled in the repo, by
\`tools/research/rom2asm.sh\` and \`rom2image.py\`, both of which need MAME and the
ACT80. Without one the machine boots the stock 1.44 and the asset is inert.

## The hard disk

The MD-10's CP/M, three partitions at \`A0>\` / \`B0>\` / \`C0>\`, needs a drive
image and the utilities disk to boot it from:

\`\`\`sh
tools/research/md10drive.py --out /tmp/md10/hd.chd --force
O1_HARD=/tmp/md10/hd.chd ./boot-o1next.sh /tmp/md10/prep.imd
\`\`\`

then type \`HARD\` at the \`A>\` prompt. (Both of those tools are in the repo --
this directory is self-contained for *running* the machine, not for building
drives.)

## What is in here

| | |
|---|---|
| \`boot-o1next.sh\` | the launcher |
| \`mame/$MACHINE\` | the patched binary |
| \`roms/$MACHINE/\` | the ROM set |
| \`assets/\` | the interposer's flash asset: \`boot-animation.bin\`, the boot screen the RP2354B plays (#278) |
| \`run/\` | MAME's \`cfg/\` and \`snap/\`, and copies of images from git trees |
| \`MANIFEST\` | what went in, and from where |

An image **inside a git working tree** is copied into \`run/floppies/\` and the
copy is mounted, because MAME writes back into a floppy image in place and a
checkout is not a working copy. Images anywhere else are mounted as given.
EOF

echo
echo "staged, in $DEST:"
echo "  boot-o1next.sh   mame/$MACHINE   roms/$MACHINE/   assets/   run/   MANIFEST   README.md"
echo
echo "  cd $DEST && ./boot-o1next.sh ../floppies/system-disk.imd"

