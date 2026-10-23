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
#   To see **the boot screen**, mount ROM 2.0's image and nothing else (#278): the
#   monitor's own 26 bytes of screen code fill the attribute array bright and print
#   the fallback, which is the trigger the RP2354B watches for.  There are no flash
#   assets to mount any more -- the -frame and -bootsplash slots retired with the
#   ROM-side frame path:
#
#     O1_SOFTROM=/tmp/rom2.rom \
#       tools/emulator-setup/mame-osborne1nx/boot-o1next.sh
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
#   O1_PICOEM   1 to run the interposer's own firmware beside the machine -- the
#               `osborne1nxp` machine, a picoem bridge holding the chip, and the
#               card's window answered by it.  Default: on when `pico/` is staged
#               beside this script.  0 for the card-only `osborne1nx`.
#   O1_RS232    1 (default) to give the machine a serial port on a pty -- the
#               guest's own modem software drives it.  0 for none.
#   O1_RIG      host[:port] of the bench rig's relay door, to put the relay on
#               that pty (#342).  With neither this nor O1_RIG_SERIAL the port is
#               still there and its path is printed.
#   O1_RIG_SERIAL  the rig's USB serial device, instead of its network door.
#   O1_BAUD     the pty's rate: 1200 (default) or 300.  It must match the ACIA's,
#               and MDM740's default is 300.
#   O1_SOFTROM  a ROM image to serve the ROM window from -- the interposer's
#               softROM (#247).  With none the window is the machine's own 1.44,
#               so the machine is a stock `osborne1`.  Unlike a floppy, this is
#               read-only: MAME never writes back into it.  `none` means the
#               machine's own even when `assets/rom2.rom` is staged.
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

# A staged O1NEXT carries the two images the machine runs on -- ROM 2.0's window
# and the MD-10 drive -- so they are the defaults when nothing is set: the staged
# machine *is* the O1NEXT, and launching it should give the O1NEXT.  `none` means
# the machine's own, which is the stock 1.44 ROM and no disk.
if [ -z "${O1_HARD:-}" ] && [ -f "$HERE/assets/hd.chd" ]; then
    O1_HARD="$HERE/assets/hd.chd"
fi
HARD="${O1_HARD:-}"
if [ "$HARD" = "none" ]; then HARD=""; fi
if [ -n "$HARD" ]; then
    [ -f "$HARD" ] || { echo "boot-o1next.sh: no such hard disk: $HARD" >&2; exit 1; }
    HARD="$(abspath "$HARD")"
fi

# The softROM image is read-only to MAME (the device is not writeable), so it is
# mounted as given -- there is nothing to copy it away from.
if [ -z "${O1_SOFTROM:-}" ] && [ -f "$HERE/assets/rom2.rom" ]; then
    O1_SOFTROM="$HERE/assets/rom2.rom"
fi
SOFTROM="${O1_SOFTROM:-}"
if [ "$SOFTROM" = "none" ]; then SOFTROM=""; fi
if [ -n "$SOFTROM" ]; then
    [ -f "$SOFTROM" ] || { echo "boot-o1next.sh: no such ROM image: $SOFTROM" >&2; exit 1; }
    SOFTROM="$(abspath "$SOFTROM")"
fi

# There are no flash assets to mount any more (#278).  The `-frame` and
# `-bootsplash` slots retired with the ROM-side frame path: the RP2354B plays the
# animation out of its own flash, and the monitor's screen code -- 26 bytes in its
# own tail -- prints the fallback that is the trigger.

# --- the pico, when one is staged beside this machine ------------------------
# The interposer's own silicon is the RP2354B, and `picoem` can run its firmware
# in the loop: a bridge process holds the chip, the card's window is answered by
# the firmware instead of by the C++ card, and that is the `osborne1nxp` machine
# (#286, #192 Gate A).
#
# **It is OFF by default, and that is a measurement rather than a preference.**
# With the firmware in the card's place the MD-10's presence probe never sees an
# ACB-4000 -- the guest reads 32h in a loop and gets 10h back from the smoke
# firmware, forever -- so the hard disk stops working.  The personality that
# answers the card is #179/#293, and it is not in the firmware yet.  `O1_PICOEM=1`
# puts the pico in the loop for its own sake (the bridge reports the firmware
# running, its PC and its cycle count) with the drive as the price.
PICOEM="${O1_PICOEM:-0}"
if [ "$PICOEM" != 0 ] && [ "$PICOEM" != 1 ]; then
    echo "boot-o1next.sh: O1_PICOEM is 0 or 1, not '$PICOEM'" >&2
    exit 1
fi
PICO_FIFO_IN=""
PICO_FIFO_OUT=""
PICO_BRIDGE_PID=""
RELAY_PID=""
if [ "$PICOEM" = 1 ]; then
    BRIDGE="${O1_PICOEM_BRIDGE:-$HERE/pico/picoem-bridge}"
    FIRMWARE="${O1_PICOEM_BIN:-$HERE/pico/firmware.bin}"
    BOOTROM="${O1_PICOEM_BOOTROM:-$HERE/pico/bootrom.bin}"
    PICO_LUA="${O1_PICOEM_LUA:-$HERE/pico/o1next-picoem.lua}"
    for f in "$BRIDGE" "$FIRMWARE" "$BOOTROM" "$PICO_LUA"; do
        [ -e "$f" ] || { echo "boot-o1next.sh: O1_PICOEM is on but $f is missing." >&2
                         echo "  Stage it, or set O1_PICOEM=0 for the card-only machine." >&2
                         exit 1; }
    done
    MACHINE=osborne1nxp
    PICO_FIFO_IN="$RUNDIR/pico/in"
    PICO_FIFO_OUT="$RUNDIR/pico/out"
    mkdir -p "$RUNDIR/pico"
    rm -f "$PICO_FIFO_IN" "$PICO_FIFO_OUT"
    "$BRIDGE" --flash "$FIRMWARE" --bootrom "$BOOTROM" \
        --in "$PICO_FIFO_IN" --out "$PICO_FIFO_OUT" \
        ${O1_PICOEM_CYCLES:+--cycles "$O1_PICOEM_CYCLES"} \
        > "$RUNDIR/pico/bridge.log" 2>&1 &
    PICO_BRIDGE_PID=$!
    n=0
    while [ ! -p "$PICO_FIFO_IN" ] && [ "$n" -lt 300 ]; do sleep 0.1; n=$((n + 1)); done
    if [ ! -p "$PICO_FIFO_IN" ]; then
        echo "boot-o1next.sh: the pico bridge never made $PICO_FIFO_IN -- see" >&2
        echo "  $RUNDIR/pico/bridge.log" >&2
        exit 1
    fi
fi

# --- the serial port, and whatever is on the far end of it -------------------
# The Osborne's ACIA is wired to MAME's rs232 slot, so `-rs232 pty` gives the
# emulated machine a *real* serial port on the host, and the guest's own modem
# software drives it.  A pty is host-local, so something has to sit between it and
# the far end -- the bench rig's relay door, or a USB serial adapter -- and that
# is tools/serial-relay-o1next.py.  `O1_RIG` (host[:port]) or `O1_RIG_SERIAL`
# (a device) names that far end; with neither, the port is still there, its path
# is printed, and the relay is the only thing missing.
RS232="${O1_RS232:-1}"
RIG="${O1_RIG:-}"
RIG_SERIAL="${O1_RIG_SERIAL:-}"
RELAY="${O1_RELAY:-}"
if [ -z "$RELAY" ]; then
    for cand in "$HERE/serial-relay-o1next.py" "$REPO/tools/serial-relay-o1next.py"; do
        [ -f "$cand" ] && { RELAY="$cand"; break; }
    done
fi
# The pty and the ACIA have to agree on a rate, and neither end is 9600: the pty
# defaults to it and the machine's is 300 or 1200.  The cfg is how that is set
# (the ports are not command-line options), so the one for the guest's rate is
# copied into place before MAME starts.  1200 is the default; 300 is what the
# archive's MDM740 comes up at.
BAUD="${O1_BAUD:-1200}"
if [ "$RS232" = 1 ]; then
    for cand in "$HERE/cfg/rs232-pty-$BAUD.cfg" "$HERE/rs232-pty-$BAUD.cfg" \
                "$REPO/tools/emulator-setup/mame-osborne1nx/rs232-pty-$BAUD.cfg"; do
        if [ -f "$cand" ]; then
            mkdir -p "$RUNDIR/cfg"
            # the tag inside the file is the machine's own name
            sed "s/<system name=\"[^\"]*\">/<system name=\"$MACHINE\">/" "$cand" \
                > "$RUNDIR/cfg/$MACHINE.cfg"
            break
        fi
    done
fi

# MAME's default is full screen, and `-window` is the only thing that keeps the
# mac OSD off the whole display; it is harmless for the SDL OSD.
set -- "$MACHINE" -window -skip_gameinfo -rompath "$ROMPATH"
if [ -n "${O1_BIOS:-}" ]; then set -- "$@" -bios "$O1_BIOS"; fi
if [ -n "$FLOP1" ]; then set -- "$@" -flop1 "$FLOP1"; fi
if [ -n "$FLOP2" ]; then set -- "$@" -flop2 "$FLOP2"; fi
if [ -n "$HARD" ]; then set -- "$@" -harddisk "$HARD"; fi
if [ -n "$SOFTROM" ]; then set -- "$@" -softrom "$SOFTROM"; fi
if [ "$PICOEM" = 1 ]; then set -- "$@" -autoboot_script "$PICO_LUA"; fi
if [ "$RS232" = 1 ]; then set -- "$@" -rs232 pty; fi
if [ -n "${O1_SECONDS:-}" ]; then set -- "$@" -seconds_to_run "$O1_SECONDS"; fi

if [ "$PICOEM" = 1 ]; then
    echo "$MACHINE -- the emulated O1NEXT, with the pico in the loop, windowed"
elif [ -f "$HERE/assets/hd.chd" ] || [ -f "$HERE/assets/rom2.rom" ]; then
    echo "$MACHINE -- the emulated O1NEXT, windowed"
elif [ "$STAGED" = 1 ]; then
    echo "$MACHINE -- a staged test machine, windowed"
else
    echo "$MACHINE -- the emulated interposer, 1.44 ROM, windowed"
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
if [ "$PICOEM" = 1 ]; then
    echo "  pico:      $BRIDGE, holding $FIRMWARE (log: $RUNDIR/pico/bridge.log)"
    echo "             the card's window is the firmware's -- and the smoke firmware"
    echo "             is not the ACB-4000 personality, so the hard disk will not"
    echo "             come up until #179/#293 land.  Measured, not assumed."
else
    echo "  pico:      none -- the card is MAME's own ACB-4000, so the drive works."
    echo "             O1_PICOEM=1 runs the interposer's firmware in the loop instead."
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

# ---------------------------------------------------------------------------
# The machine, and the two processes that live beside it
# ---------------------------------------------------------------------------
# Without either of them MAME is the only process and `exec` is right.  With the
# pico and/or the serial relay, MAME has to be a child: the bridge is killed on
# every exit path, and the relay cannot be attached until MAME has published the
# pty it made (which is what the one-line print in the patched pty.cpp is for --
# upstream publishes the path only to the UI's "Pseudo Terminals" screen).

if [ "$PICOEM" = 0 ] && [ "$RS232" = 0 ]; then
    exec "$MAME" "$@"
fi

cleanup() {
    if [ -n "$PICO_BRIDGE_PID" ]; then
        kill "$PICO_BRIDGE_PID" 2>/dev/null || true
        wait "$PICO_BRIDGE_PID" 2>/dev/null || true
    fi
    if [ -n "$RELAY_PID" ]; then
        kill "$RELAY_PID" 2>/dev/null || true
        wait "$RELAY_PID" 2>/dev/null || true
    fi
}
trap cleanup EXIT INT TERM

MAME_LOG="$RUNDIR/mame.log"
if [ "$PICOEM" = 1 ]; then
    O1_PICOEM_IN="$PICO_FIFO_IN" O1_PICOEM_OUT="$PICO_FIFO_OUT" \
    O1NEXT_LOG="$RUNDIR/pico/mame.log" \
        "$MAME" "$@" > "$MAME_LOG" 2>&1 &
else
    "$MAME" "$@" > "$MAME_LOG" 2>&1 &
fi
MAME_PID=$!

if [ "$RS232" = 1 ]; then
    # Wait for the pty, then put the relay on it if a far end was named.
    PTY=""
    n=0
    while [ "$n" -lt 150 ]; do
        PTY="$(sed -n "s/^Pseudo Terminal '\(.*\)'$/\1/p" "$MAME_LOG" 2>/dev/null | head -1)"
        [ -n "$PTY" ] && break
        kill -0 "$MAME_PID" 2>/dev/null || break
        sleep 0.2
        n=$((n + 1))
    done
    if [ -n "$PTY" ]; then
        echo "  serial:    $PTY (${BAUD} baud, the guest's own rate)"
    else
        echo "  serial:    no pty in $MAME_LOG -- is -rs232 pty still on the command line?" >&2
    fi
    if [ -n "$PTY" ] && { [ -n "$RIG" ] || [ -n "$RIG_SERIAL" ]; }; then
        if [ -z "$RELAY" ]; then
            echo "  relay:     tools/serial-relay-o1next.py not found -- attach one yourself" >&2
        else
            if [ -n "$RIG_SERIAL" ]; then
                python3 "$RELAY" --pty "$PTY" --serial "$RIG_SERIAL" \
                    ${O1_RIG_BAUD:+--baud "$O1_RIG_BAUD"} &
            else
                # host[:port], because that is how a person writes an address
                RIG_HOST="${RIG%%:*}"
                RIG_PORT="${RIG#*:}"
                if [ "$RIG_PORT" = "$RIG" ]; then RIG_PORT="${O1_RIG_PORT:-}"; fi
                python3 "$RELAY" --pty "$PTY" --host "$RIG_HOST" \
                    ${RIG_PORT:+--port "$RIG_PORT"} &
            fi
            RELAY_PID=$!
            echo "  relay:     $RELAY -> ${RIG_SERIAL:-$RIG} (pid $RELAY_PID)"
        fi
    elif [ -n "$PTY" ]; then
        echo "  relay:     none -- set O1_RIG=<host[:port]> or O1_RIG_SERIAL=<device>"
        echo "             to reach a modem on the bench rig, e.g."
        echo "               O1_RIG=192.168.2.3:2325 ./boot-o1next.sh"
    fi
fi
echo

wait "$MAME_PID"
STATUS=$?
cleanup
trap - EXIT INT TERM
exit "$STATUS"

