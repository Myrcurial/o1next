#!/bin/sh
# stage-o1next.sh [DEST]
#
# Stage **the O1NEXT itself** -- one directory you cd into and run, with the hard
# disk in it, ROM 2.0 in the window, the serial port on a pty, and the pico staged
# beside it -- as a self-contained build artifact that owes the repo nothing.
#
# WHY THIS IS NOT stage.sh
#   `stage.sh` stages the *test* machine (#247): the card-only `osborne1nx`, its
#   ROM set, a launcher and some floppies to feed it.  This stages the *thing the
#   project is for*: the machine with the interposer's own firmware running beside
#   it (picoem, #286/#192), booting ROM 2.0 off the MD-10 drive at 104 columns,
#   with nothing in either floppy drive and its serial port attached.  Same
#   launcher -- `boot-o1next.sh` is one file and finds what is beside it -- but a
#   different set of things beside it, and a README that says how to use it.
#
# USAGE
#   tools/emulator-setup/mame-osborne1nx/stage-o1next.sh
#   tools/emulator-setup/mame-osborne1nx/stage-o1next.sh /tmp/o1next
#
#   DEST defaults to $O1_STAGE_ROOT/o1next, and $O1_STAGE_ROOT to
#   $HOME/Documents/O1NEXT.
#
# WHAT IT WRITES
#   $DEST/mame/osborne1nx        the patched binary (it carries osborne1nx *and*
#                                osborne1nxp -- the picoem machine)
#   $DEST/roms/osborne1nx/       the ROM set the machine declares, CRC-checked
#   $DEST/assets/rom2.rom        ROM 2.0's window image, with the 11-drive driver
#   $DEST/assets/hd.chd          the MD-10 drive, 11 partitions, 88 MB
#   $DEST/pico/                  the bridge, the firmware, the mask ROM, the Lua
#   $DEST/cfg/                   the rs232 cfg at 1200 and at 300 baud
#   $DEST/serial-relay-o1next.py the relay, for a modem on the bench rig
#   $DEST/boot-o1next.sh         the launcher
#   $DEST/README.md              what this is, and how to use it
#   $DEST/MANIFEST               what went in, from where, with CRCs
#
# ENVIRONMENT
#   O1_MAME          the binary to stage (default: the usual build trees)
#   O1_STAGE_ROOT    where machines go (default $HOME/Documents/O1NEXT)
#   O1_ROM2_IMAGE    ROM 2.0's window image.  Default: $O1_WORK/rom2.rom, and if
#                    that is absent it is BUILT (rom2asm.sh is a few minutes)
#   O1_HARD          the drive to stage.  Default: $O1_WORK/hd-eq11.chd, and if
#                    that is absent it is built (md10prep.sh eq11, needs chdman)
#   O1_WORK          scratch for the two builds (default /tmp/o1next-stage)
set -eu

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"
MACHINE=osborne1nx

ROM_MAIN=3a10082-00rev-e.ud11
ROM_CHAR=7a3007-00.ud15
CRC_MAIN=c0596b14
CRC_CHAR=6c1eab0d

STAGE_ROOT="${O1_STAGE_ROOT:-$HOME/Documents/O1NEXT}"
DEST="${1:-$STAGE_ROOT/o1next}"
WORK="${O1_WORK:-/tmp/o1next-stage}"
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
    echo "stage-o1next.sh: no $MACHINE binary." >&2
    echo "  Build one with tools/emulator-setup/mame-osborne1nx/apply.sh, or set" >&2
    echo "  O1_MAME to an existing build." >&2
    exit 1
fi
[ -x "$MAME" ] || { echo "stage-o1next.sh: not executable: $MAME" >&2; exit 1; }

# The binary has to carry the picoem machine too, or the pico cannot be in the
# loop and this is not the O1NEXT.  Checked rather than assumed.
if ! "$MAME" -listfull 2>/dev/null | grep -q '^osborne1nxp'; then
    echo "stage-o1next.sh: $MAME has no osborne1nxp machine -- the picoem patch" >&2
    echo "  (tools/emulator-setup/mame-osborne1nx/picoem-link.patch) is not in that" >&2
    echo "  tree.  See issue #192; the staged machine wants the pico." >&2
    exit 1
fi

for f in "$ROM_SRC/$ROM_MAIN" "$ROM_SRC/$ROM_CHAR"; do
    [ -f "$f" ] || { echo "stage-o1next.sh: missing ROM: $f" >&2; exit 1; }
done

mkdir -p "$WORK"
mkdir -p "$DEST/mame" "$DEST/roms/$MACHINE" "$DEST/assets" "$DEST/pico" "$DEST/cfg" "$DEST/run"

echo "staging the O1NEXT into $DEST"
cp "$MAME" "$DEST/mame/$MACHINE"
chmod +x "$DEST/mame/$MACHINE"
cp "$ROM_SRC/$ROM_MAIN" "$DEST/roms/$MACHINE/$ROM_MAIN"
cp "$ROM_SRC/$ROM_CHAR" "$DEST/roms/$MACHINE/$ROM_CHAR"

# The staged copies are copies, so check them rather than trusting them.
got_main="$(crc32 "$DEST/roms/$MACHINE/$ROM_MAIN")"
got_char="$(crc32 "$DEST/roms/$MACHINE/$ROM_CHAR")"
if [ "$got_main" != "$CRC_MAIN" ] || [ "$got_char" != "$CRC_CHAR" ]; then
    echo "stage-o1next.sh: staged ROMs do not match the machine's own ROM_START." >&2
    echo "  $ROM_MAIN: got $got_main, want $CRC_MAIN" >&2
    echo "  $ROM_CHAR: got $got_char, want $CRC_CHAR" >&2
    exit 1
fi


# --- the two images ---------------------------------------------------------
# ROM 2.0's window, and the drive it boots.  Both are *built* -- the monitor is
# assembled by the vendor's own ACT80 on an emulated Osborne, and the drive is
# configured by the 1984 installer -- so they are taken ready-made when they are
# there, and built when they are not.  The driver in the window and the partition
# table on the drive have to agree, which is why they are staged as a pair: 11
# partitions, 11 hard-disk drives (docs/md10-system.md 9.4-9.5).

ROM2="${O1_ROM2_IMAGE:-$WORK/rom2.rom}"
HARD="${O1_HARD:-$WORK/hd-eq11.chd}"

if [ ! -f "$ROM2" ] || [ ! -f "$HARD" ]; then
    echo
    echo "the images are not built yet; building them (this takes a few minutes)"
    echo "  ROM 2.0's monitor      tools/research/rom2asm.sh"
    echo "  the drive, 11 parts    tools/research/md10prep.sh 1200,8,18 eq11"
    echo "  the driver, 11 drives  tools/research/md10dpb.py --grow"
    echo
    O1_MAME="$MAME" "$REPO/tools/research/rom2asm.sh" \
        -o "$WORK/rom2-monitor.rom" "$WORK/rom2asm" \
        || { echo "stage-o1next.sh: rom2asm.sh failed" >&2; exit 1; }
    if [ ! -f "$WORK/bootable.raw" ]; then
        O1_MAME="$MAME" O1_CHDMAN="${O1_CHDMAN:-chdman}" \
            "$REPO/tools/research/md10prep.sh" 1200,8,18 eq11 "$WORK" \
            || { echo "stage-o1next.sh: md10prep.sh failed" >&2; exit 1; }
    fi
    # the 11-drive driver, built from the drive's own label
    python3 "$REPO/tools/research/md10dpb.py" --utils \
        "$REPO/research/adaptec/Osborne Hard Disk Control Software Version 2.01 (1984).img" \
        --extract "$WORK/HARD.COM" >/dev/null
    python3 "$REPO/tools/research/md10dpb.py" "$WORK/HARD.COM" "$WORK/HARD11.COM" \
        --grow --drive "$WORK/bootable.raw" >/dev/null \
        || { echo "stage-o1next.sh: md10dpb.py --grow failed" >&2; exit 1; }
    python3 "$REPO/tools/research/rom2image.py" --monitor "$WORK/rom2-monitor.rom" \
        --hard "$WORK/HARD11.COM" -o "$ROM2" --work "$WORK/rom2image" >/dev/null \
        || { echo "stage-o1next.sh: rom2image.py failed" >&2; exit 1; }
    if [ ! -f "$HARD" ] && [ -f "$WORK/bootable.chd" ]; then HARD="$WORK/bootable.chd"; fi
fi

[ -f "$ROM2" ] || { echo "stage-o1next.sh: no ROM 2.0 image at $ROM2" >&2; exit 1; }
[ -f "$HARD" ] || { echo "stage-o1next.sh: no drive at $HARD" >&2; exit 1; }
cp "$ROM2" "$DEST/assets/rom2.rom"
cp "$HARD" "$DEST/assets/hd.chd"

# The drive is the maximized layout or this is not the machine this stages: 11
# partitions, ending where the grown driver's table ends.
if ! python3 "$REPO/tools/research/md10table.py" "$DEST/assets/hd.chd" 2>/dev/null \
        | grep -q 'CP/M-K'; then
    echo "stage-o1next.sh: $HARD is not the 11-partition layout." >&2
    echo "  (build it with: tools/research/md10prep.sh 1200,8,18 eq11)" >&2
    exit 1
fi


# --- the pico ---------------------------------------------------------------
# The firmware the bridge holds.  picoem-smoke is the one built here today; the
# ACB-4000 personality is what belongs in it once #179/#293 land, and swapping it
# is replacing this file.
FW="${O1_PICOEM_BIN:-$REPO/firmware/picoem-smoke/build/picoem-smoke.bin}"
BRIDGE="${O1_PICOEM_BRIDGE:-$REPO/tools/picoem-bridge/target/release/picoem-bridge}"
BOOTROM="${O1_PICOEM_BOOTROM:-}"
if [ -z "$BOOTROM" ]; then
    for cand in "$STAGE_ROOT/picoem-286/roms/rp2350/bootrom-combined.bin" \
                "$STAGE_ROOT/picoem/roms/rp2350/bootrom-combined.bin"; do
        if [ -f "$cand" ]; then BOOTROM="$cand"; break; fi
    done
fi
for f in "$FW" "$BRIDGE" "$BOOTROM"; do
    if [ ! -f "$f" ]; then
        echo "stage-o1next.sh: missing pico piece: $f" >&2
        echo "  (firmware/picoem-smoke/build.sh, tools/picoem-bridge, and picoem's" >&2
        echo "   own roms/ -- REQUIREMENTS.md has the rows)" >&2
        exit 1
    fi
done
cp "$BRIDGE" "$DEST/pico/picoem-bridge"
chmod +x "$DEST/pico/picoem-bridge"
cp "$FW" "$DEST/pico/firmware.bin"
cp "$BOOTROM" "$DEST/pico/bootrom.bin"
cp "$HERE/o1next-picoem.lua" "$DEST/pico/o1next-picoem.lua"

# --- the serial port --------------------------------------------------------
cp "$HERE/rs232-pty-1200.cfg" "$DEST/cfg/rs232-pty-1200.cfg"
# 300 is what the archive's MDM740 comes up at, and the pty and the ACIA have to
# agree; the values are RS232_BAUD_300 = 2 and RS232_BAUD_1200 = 4 (rs232.h).
sed 's/value="4"/value="2"/' "$HERE/rs232-pty-1200.cfg" > "$DEST/cfg/rs232-pty-300.cfg"
cp "$REPO/tools/serial-relay-o1next.py" "$DEST/serial-relay-o1next.py"
chmod +x "$DEST/serial-relay-o1next.py"

cp "$HERE/boot-o1next.sh" "$DEST/boot-o1next.sh"
chmod +x "$DEST/boot-o1next.sh"

# --- what this is, and what went into it ------------------------------------

cat > "$DEST/MANIFEST" <<EOF
# the O1NEXT -- a staged machine, built by
#   tools/emulator-setup/mame-osborne1nx/stage-o1next.sh
#
# Regenerate it with that command; delete it whenever.  Nothing in the repo
# depends on this directory and it depends on nothing in the repo.

staged      $(date -u '+%Y-%m-%dT%H:%M:%SZ')
machine     $MACHINE + osborne1nxp (MAME 0.289 + osborne1nx.patch + picoem-link.patch)
binary      mame/$MACHINE   $("$MAME" -version 2>/dev/null | head -1)
built-from  $MAME

roms/$MACHINE/$ROM_MAIN   crc32 $got_main
roms/$MACHINE/$ROM_CHAR   crc32 $got_char

assets/rom2.rom   crc32 $(crc32 "$DEST/assets/rom2.rom")   ROM 2.0's window: the 1.44 monitor with the sign-on dispatch and HCBOOT, plus the payload and the 11-drive HARD.COM
assets/hd.chd     crc32 $(crc32 "$DEST/assets/hd.chd")   the MD-10 drive: 11 partitions of 15706 blocks, the maximized layout (docs/md10-system.md 9.5)

pico/picoem-bridge   crc32 $(crc32 "$DEST/pico/picoem-bridge")   the RP2354B in picoem
pico/firmware.bin    crc32 $(crc32 "$DEST/pico/firmware.bin")   from $FW
pico/bootrom.bin     crc32 $(crc32 "$DEST/pico/bootrom.bin")   from $BOOTROM
pico/o1next-picoem.lua   the machine side of the bridge

cfg/rs232-pty-1200.cfg   the pty at the guest's 1200
cfg/rs232-pty-300.cfg    the same at 300, for MDM740's default
serial-relay-o1next.py    pty <-> the bench rig's relay door (#342)

boot-o1next.sh    copied from $HERE/boot-o1next.sh
EOF

cat > "$DEST/README.md" <<EOF
# The O1NEXT

One directory you \`cd\` into and run. It is a **build artifact**: regenerate it
with \`tools/emulator-setup/mame-osborne1nx/stage-o1next.sh\`, delete it whenever,
and keep nothing here you would miss.

\`\`\`sh
cd $DEST
./boot-o1next.sh
\`\`\`

That gives you the machine this project is for:

- **ROM 2.0** in the window (\`assets/rom2.rom\`) -- press **RETURN** at the sign-on
  and it boots the hard disk with **no floppy in either drive**;
- **the MD-10 drive** (\`assets/hd.chd\`): 11 partitions of 15706 blocks, the
  maximized layout, so \`A0>\` through \`K0>\`;
- **104 columns** on the same tube the stock machine uses -- the SCREEN-PAC's
  doubled dot clock, not a wider window (\`docs/osborne1nx-machine.md\` 8);
- **the serial port on a pty**, printed at launch, with the relay ready for a
  modem on the bench rig;
- **the pico staged beside it**, one flag away: \`O1_PICOEM=1\` runs the interposer's
  own firmware in the loop (\`picoem\`, \`pico/bridge.log\`). It is off by default
  because the card's window is then the *firmware's*, and the smoke firmware is
  not the ACB-4000 personality -- so the hard disk stops coming up until #179/#293
  land. Measured, not assumed: with it on, the guest reads \`32h\` in a loop and
  gets \`10h\` back for ever.

## Going on a BBS

The Osborne's own modem software drives the emulated ACIA, and the ACIA is on a
real pty. A pty is host-local, so the far end is reached through
\`serial-relay-o1next.py\` -- point it at the bench rig's relay door, or at a USB
serial adapter:

\`\`\`sh
O1_RIG=192.168.2.3:2323 ./boot-o1next.sh                 # the rig's RELAY door
O1_RIG_SERIAL=/dev/cu.usbmodem2144201 ./boot-o1next.sh   # the rig's USB door
\`\`\`

\`O1_BAUD=300\` for MDM740's default (that cfg is staged too); the pty and the ACIA
must agree on the rate, or the bytes arrive as garbage that looks like a wiring
fault (\`docs/o1-modem-serial.md\`).

## Knobs

| | |
|---|---|
| \`O1_PICOEM=1\` | the pico in the loop: the interposer's firmware answers the card's window instead of MAME's ACB-4000 -- and the drive stops coming up, because that firmware is a smoke test and not the personality (#179/#293) |
| \`O1_SOFTROM=none\` | the machine's own 1.44 ROM instead of ROM 2.0 |
| \`O1_HARD=none\` | no hard disk |
| \`O1_RS232=0\` | no serial port |
| \`O1_BAUD=300\` | the pty at the guest's other rate |
| \`O1_SECONDS=30\` | run 30 emulated seconds and exit -- a smoke test |
| two arguments | floppy images for drive A and drive B, as on any machine's launcher |

What MAME writes -- \`cfg/\`, \`snap/\`, \`run/mame.log\`, and the pico's own logs --
lands in \`run/\`.
EOF

echo
echo "staged:"
echo "  $DEST/mame/$MACHINE          $("$MAME" -version 2>/dev/null | head -1)"
echo "  $DEST/roms/$MACHINE/         the ROM set (crc32 checked)"
echo "  $DEST/assets/rom2.rom        ROM 2.0's window"
echo "  $DEST/assets/hd.chd          the 11-partition drive"
echo "  $DEST/pico/                  the bridge, the firmware, the mask ROM"
echo "  $DEST/cfg/                   the rs232 cfg, 1200 and 300"
echo "  $DEST/boot-o1next.sh         the launcher"
echo
echo "run it:  cd $DEST && ./boot-o1next.sh"


