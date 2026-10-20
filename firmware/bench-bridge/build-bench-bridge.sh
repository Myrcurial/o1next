#!/bin/sh
# Build the o1next bench rig -- and produce ONE image you can flash.
#
#   firmware/bench-bridge/build-bench-bridge.sh                 # the board on the bench
#   firmware/bench-bridge/build-bench-bridge.sh --board c3      # an ESP32-C3
#   firmware/bench-bridge/build-bench-bridge.sh --board s2      # an ESP32-S2
#   firmware/bench-bridge/build-bench-bridge.sh --clean
#
# Why a script and not a documented command line: the build a person runs and the
# build CI runs have to be the same build, or CI can pass while the documented recipe
# is wrong.  The workflow calls this script, and so should you.  Same shape as the
# fork's tools/build-o1next.sh, for the same reason -- and deliberately NOT the same
# file, because the rig must not be built by the thing it tests.
#
# Output lands in build/bench-bridge-<board>/:
#
#   bench-bridge-merged.bin     <- flash THIS at 0x0: bootloader + partition table +
#                                  otadata + application, one file
#   bench-bridge.ino.bin        the application alone, and the other parts, for
#   bench-bridge.ino.bootloader.bin   anyone who wants them separately
#   bench-bridge.ino.partitions.bin
#   bench-bridge.ino.elf        symbols, for decoding a crash dump
#   SHA256SUMS, BUILD-INFO.txt  what went in, and from where
#
# THE BOARD IS A PARAMETER, AND THAT IS THE POINT
#
# The handover for this rig (#342) named an ESP32-S2, and the rig has since been built
# on a classic ESP32 and may move to a C3.  That is fine, and it is meant to be: the
# rig needs **two UARTs and WiFi** and nothing else.  It is not the product, and it
# needs none of the things the modem's part was chosen for -- the 20-bit auto-baud
# counter (#319) is a *modem* requirement, and a rig that only has to EMIT a paced
# rate can do it on anything with a UART.
#
# Two things DO change with the board, and both are in the table below:
#
#   the host door.  On an S2/C3 with USB CDC on boot, `Serial` is the native USB --
#   there is no wire, and the host cannot get the baud wrong.  On a classic ESP32,
#   `Serial` is UART0 through a bridge chip (CP2102/CH340), there IS a wire, and the
#   host's baud must match BRIDGE_HOST_BAUD.  That is why the classic entry is the
#   one that needs `identify-o1next.py --baud 115200`.
#
#   the UART1 pins.  They are UART1's IO-MUX default on each part (9/10 on a classic
#   ESP32, 17/18 on an S2), which is what the rig is wired to -- but **on a C3 that
#   default pair is not usable**, because GPIO18/19 are its USB pins, so the C3 entry
#   names a plain spare pair instead.  Override with BRIDGE_PINS when the header
#   disagrees; the sketch takes them as `-D` defines for exactly this reason.
set -eu

here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)

# Fail the build when the sketch passes this share of its application partition.
MAX_APP_PERCENT=${MAX_APP_PERCENT:-90}

# ---------------------------------------------------------------- the boards ---
#
# One row per board: FQBN, the UART1 pins, and a note about the host door.  The rows
# are a `case` rather than an `eval`ed variable name because a table built out of
# variable-name concatenation is a table shellcheck cannot see, and one that can
# execute a typo.
BOARD=${BOARD:-esp32}
clean=no

usage() {
    cat >&2 <<'EOF'
usage: build-bench-bridge.sh [--board esp32|c3|s2] [--clean]

  --board   which ESP32 to build for (default: esp32, the classic 38-pin devkit)
  --clean   throw the previous build's objects away first

Environment: BOARD, FQBN, BRIDGE_PINS, MAX_APP_PERCENT, BRIDGE_HOST_BAUD
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --board) BOARD=${2:?--board needs a value}; shift 2 ;;
        --clean) clean=yes; shift ;;
        -h|--help) usage; exit 0 ;;
        *) usage; echo "build-bench-bridge.sh: unknown argument: $1" >&2; exit 1 ;;
    esac
done

case "$BOARD" in
    esp32)
        board_fqbn='esp32:esp32:esp32'
        board_pins='-DBRIDGE_RXD=9 -DBRIDGE_TXD=10'
        board_note='host door is UART0 through a bridge chip -- the host MUST match the baud'
        board_usb_naming=''
        ;;
    c3)
        board_fqbn='esp32:esp32:esp32c3:CDCOnBoot=cdc'
        board_pins='-DBRIDGE_RXD=6 -DBRIDGE_TXD=7'
        board_note='host door is the native USB Serial/JTAG -- the baud is a decoration'
        board_usb_naming=''
        ;;
    s2)
        board_fqbn='esp32:esp32:esp32s2:CDCOnBoot=cdc'
        board_pins='-DBRIDGE_RXD=18 -DBRIDGE_TXD=17'
        board_note='host door is the native USB -- the baud is a decoration'
        board_usb_naming='-DUSB_MANUFACTURER="o1next" -DUSB_PRODUCT="o1next-bridge" -DUSB_SERIAL="o1next-bridge"'
        ;;
    *)
        usage
        echo "build-bench-bridge.sh: no such board: $BOARD" >&2
        exit 1
        ;;
esac

# Everything above is a default; anything named in the environment wins.
FQBN=${FQBN:-$board_fqbn}
BRIDGE_PINS=${BRIDGE_PINS:-$board_pins}
BRIDGE_HOST_BAUD=${BRIDGE_HOST_BAUD:-115200}

# What the board calls itself on a USB port -- **where that is possible at all**, and on
# a C3 it is not.
#
# `USB_PRODUCT` is honoured by exactly one file in the core, `cores/esp32/USB.cpp`, which
# is the **TinyUSB** stack: the S2 and the S3.  An ESP32-C3 with `CDCOnBoot=cdc` gets the
# **USB Serial/JTAG peripheral** (`HWCDC`) instead, and that peripheral's product string
# is its own -- `USB JTAG/serial debug unit` -- with no way to rename it.  Measured on
# the C3 that became this rig's board, 2026-10-20.
#
# So the C3 entry names nothing rather than setting a `-D` that reads like it does
# something and does not.  The identity a C3 bridge has is the **console's MAC** (which
# `status` prints, and `identify-o1next.py` reads) and the label somebody writes on the
# board -- the same rule the handover for this rig set for the modem, arrived at from the
# other direction: the port name is not the identity, and on a C3 it cannot even be a hint.
USB_NAMING=${USB_NAMING:-$board_usb_naming}

BUILD="$root/build/bench-bridge-$BOARD"
SKETCH="$here"

say() { printf '%s\n' "$*" >&2; }
die() { say "build-bench-bridge.sh: $*"; exit 1; }

command -v arduino-cli >/dev/null 2>&1 || \
    die "no arduino-cli -- see REQUIREMENTS.md in the o1next repository"
command -v python3 >/dev/null 2>&1 || \
    die "no python3 -- the partition table is read back with the core's gen_esp32part.py"

O1NEXT_CORE_VERSION=${O1NEXT_CORE_VERSION:-2.0.17}
DATA=$(arduino-cli config get directories.data 2>/dev/null | tr -d '"')
[ -n "$DATA" ] || die "arduino-cli would not say where its data directory is"
PLATFORM="$DATA/packages/esp32/hardware/esp32/$O1NEXT_CORE_VERSION"
[ -d "$PLATFORM" ] || die "the esp32 core $O1NEXT_CORE_VERSION is not installed --
 arduino-cli core install esp32:esp32@$O1NEXT_CORE_VERSION"

# esptool is a Mach-O binary on macOS and a Python script on Linux, and the core's own
# platform.txt makes the same distinction.  `-f` as well as `-x`: on Linux the package
# ships an `esptool/` *directory* beside `esptool.py`, and `[ -x ]` is true for a
# directory, so an executable regular file is the only thing that will do.
O1NEXT_ESPTOOL_BIN=""
O1NEXT_ESPTOOL_PY=""
for d in "$DATA"/packages/esp32/tools/esptool_py/*/; do
    if [ -f "$d/esptool" ] && [ -x "$d/esptool" ]; then O1NEXT_ESPTOOL_BIN="$d/esptool"; break; fi
    if [ -f "$d/esptool.py" ]; then O1NEXT_ESPTOOL_PY="$d/esptool.py"; break; fi
done
if [ -z "$O1NEXT_ESPTOOL_BIN" ] && [ -z "$O1NEXT_ESPTOOL_PY" ]; then
    die "no esptool in the esp32 core -- is the core installation complete?"
fi

esptool() {
    if [ -n "$O1NEXT_ESPTOOL_BIN" ]; then
        "$O1NEXT_ESPTOOL_BIN" "$@"
    else
        python3 "$O1NEXT_ESPTOOL_PY" "$@"
    fi
}

if [ "$clean" = yes ]; then
    rm -rf "$BUILD"
fi
mkdir -p "$BUILD"

# --------------------------------------------------------------- properties ----
# Everything the merge needs is READ FROM THE PLATFORM rather than written down here:
# the flash mode, frequency and size, and the bootloader's own offset.  A future core
# that changes them changes this build with them.
say "== reading the flash properties for $FQBN"
props=$(arduino-cli compile --fqbn "$FQBN" --show-properties "$SKETCH" 2>/dev/null)
prop() { printf '%s\n' "$props" | sed -n "s/^$1=//p" | head -1; }

mcu=$(prop 'build\.mcu')
boot_addr=$(prop 'build\.bootloader_addr')
flash_mode=$(prop 'build\.flash_mode')
flash_freq=$(prop 'build\.flash_freq')
flash_size=$(prop 'build\.flash_size')
platform_path=$(prop 'runtime\.platform\.path')

[ -n "$mcu" ]           || die "the platform gave no build.mcu"
[ -n "$boot_addr" ]     || die "the platform gave no build.bootloader_addr"
[ -n "$flash_mode" ]    || die "the platform gave no build.flash_mode"
[ -n "$flash_freq" ]    || die "the platform gave no build.flash_freq"
[ -n "$flash_size" ]    || die "the platform gave no build.flash_size"
[ -n "$platform_path" ] || die "the platform gave no runtime.platform.path"

# The three offsets that are NOT build properties.  They are the constants in the
# core's own upload recipe (tools.esptool_py.upload.pattern_args in platform.txt:
# 0x8000 partitions, 0xe000 boot_app0, 0x10000 application), which is also the ESP32
# family's standard layout.  They are ASSERTED below rather than trusted.
PART_ADDR=0x8000
OTADATA_ADDR=0xe000
APP_ADDR=0x10000

# ------------------------------------------------------------------ compile ----
# The output is captured rather than streamed, because two things in it are checked:
# that the compile succeeded at all, and that the sketch still fits.
#
# The log lives BESIDE the build directory, not inside it: arduino-cli REMOVES the
# build directory when the build options change -- which a new `-D` does -- and it
# does that *after* this shell has opened the log for writing.  The log vanishes with
# the directory, the redirect fails, and the failure reads as "the compile failed"
# with no compiler output at all.
say "== compiling ($BOARD: $FQBN)"
say "   pins: $BRIDGE_PINS   host baud: $BRIDGE_HOST_BAUD"
compile_log="$(dirname "$BUILD")/compile-$BOARD.log"
# The extra flags go through --build-property rather than a build_opt.h, and that is
# measured rather than preferred: build_opt.h is handed to the compiler as a gcc
# RESPONSE FILE, and a response file strips quotes and *then* splits on whitespace --
# so a `-D` whose value contains a space arrives as two stray arguments and the build
# dies with "'X' was not declared in this scope".  Through --build-property the shell
# does the quoting.
flags="$BRIDGE_PINS -DBRIDGE_HOST_BAUD=$BRIDGE_HOST_BAUD $USB_NAMING"
if ! arduino-cli compile --fqbn "$FQBN" --build-path "$BUILD" \
        --build-property "compiler.cpp.extra_flags=$flags" "$SKETCH" \
        > "$compile_log" 2>&1; then
    cat "$compile_log" >&2
    die "the compile failed -- the output above is the whole of it"
fi
cat "$compile_log" >&2

# The application partition is the whole story on this board: the rig has no OTA path
# and does not want one.  Failing at 90% with a sentence beats failing at 100% with a
# linker error.
used=$(sed -n 's/^Sketch uses [0-9]* bytes (\([0-9]*\)%).*/\1/p' "$compile_log" | head -1)
[ -n "$used" ] || die "could not read the sketch size out of the compile output"
if [ "$used" -gt "$MAX_APP_PERCENT" ]; then
    die "the sketch uses ${used}% of its application partition and the budget is ${MAX_APP_PERCENT}%."
fi
say "   ok   the sketch uses ${used}% of its application partition"

app="$BUILD/bench-bridge.ino.bin"
boot="$BUILD/bench-bridge.ino.bootloader.bin"
parts="$BUILD/bench-bridge.ino.partitions.bin"
otadata="$platform_path/tools/partitions/boot_app0.bin"

for f in "$app" "$boot" "$parts" "$otadata"; do
    [ -f "$f" ] || die "the build did not produce $f"
done

# -------------------------------------------------------------------- merge ----
merged="$BUILD/bench-bridge-merged.bin"
say "== merging into one image for offset 0x0"
esptool --chip "$mcu" merge_bin -o "$merged" \
    --flash_mode "$flash_mode" --flash_freq "$flash_freq" --flash_size "$flash_size" \
    "$boot_addr" "$boot" \
    "$PART_ADDR" "$parts" \
    "$OTADATA_ADDR" "$otadata" \
    "$APP_ADDR" "$app"

# ------------------------------------------------------------------- verify ----
# A wrong offset produces a file that looks fine and does not boot, so nothing here is
# trusted.  The application offset is not a free choice -- the partition table declares
# where the app partition is -- so the table is read back out of the build, with the
# core's own gen_esp32part.py, and the offsets are CROSS-CHECKED against it.  Merging
# the app to 0x20000 "succeeds" and bricks the board; this is the check that says so.
say "== verifying the merged image"

table=$(python3 "$platform_path/tools/gen_esp32part.py" "$parts" 2>/dev/null) || \
    die "could not read the partition table back out of $parts"

table_app=$(printf '%s\n' "$table" | awk -F, '$2 == "app" { print $4; exit }')
table_otadata=$(printf '%s\n' "$table" | awk -F, '$1 == "otadata" { print $4; exit }')

[ -n "$table_app" ] || die "the partition table declares no app partition"
[ -n "$table_otadata" ] || die "the partition table declares no otadata partition"

same_hex() { [ "$(printf '%s' "$1" | tr 'A-F' 'a-f')" = "$(printf '%s' "$2" | tr 'A-F' 'a-f')" ]; }

if ! same_hex "$table_app" "$APP_ADDR"; then
    die "the application offset here is $APP_ADDR but the partition table puts the app partition at $table_app -- flashing it elsewhere would not boot"
fi
if ! same_hex "$table_otadata" "$OTADATA_ADDR"; then
    die "the otadata offset here is $OTADATA_ADDR but the partition table puts it at $table_otadata"
fi
say "   ok   the partition table agrees: app $table_app, otadata $table_otadata"

# And that each image really landed where it was put: 0xE9 opens an ESP application
# image (the bootloader is one too) and 0xAA 0x50 opens a partition table.  This
# catches a merge that dropped or misplaced a file.
bytes_at() { od -An -tx1 -j "$2" -N "$3" "$1" | tr -d ' \n'; }
check_magic() {
    got=$(bytes_at "$merged" "$1" "$3")
    if [ "$got" != "$2" ]; then
        die "the merged image has 0x$got at $1, wanted 0x$2 -- the $4 image is not there"
    fi
    say "   ok   $1: 0x$got  ($4)"
}

check_magic "$boot_addr" "e9" 1 "bootloader"
check_magic "$PART_ADDR" "aa50" 2 "partition table"
check_magic "$APP_ADDR" "e9" 1 "application"

# ----------------------------------------------------------------- manifest ----
sha_of() {
    if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$@"
    else sha256sum "$@"
    fi
}

say "== checksums and build info"
( cd "$BUILD" && sha_of bench-bridge-merged.bin bench-bridge.ino.bin \
    bench-bridge.ino.bootloader.bin bench-bridge.ino.partitions.bin > SHA256SUMS )

{
    echo "o1next bench rig firmware (#342, part of #334)"
    echo "board:           $BOARD  ($board_note)"
    echo "built:           $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    echo "git:             $(cd "$root" && git describe --always --dirty 2>/dev/null || echo 'not a git tree')"
    echo "arduino-cli:     $(arduino-cli version 2>/dev/null | head -1)"
    echo "esp32 core:      $O1NEXT_CORE_VERSION"
    echo "fqbn:            $FQBN"
    echo "mcu:             $mcu"
    echo "pins:            $BRIDGE_PINS   (UART1: the machine side)"
    echo "host baud:       $BRIDGE_HOST_BAUD   (UART0 / the native USB)"
    echo "flash:           mode $flash_mode, freq $flash_freq, size $flash_size"
    echo "bootloader at:   $boot_addr"
    echo "partition table: $PART_ADDR"
    echo "otadata:         $OTADATA_ADDR"
    echo "application at:  $APP_ADDR"
    echo "merged size:     $(wc -c < "$merged" | tr -d ' ') bytes"
    echo
    echo "Flash it with:"
    echo "  esptool --chip $mcu write_flash 0x0 bench-bridge-merged.bin"
    echo
    echo "On a board with no auto-reset circuit -- a native-USB S2 with no button -- the"
    echo "chip has to be in download mode first: hold BOOT, tap EN, release BOOT."
} > "$BUILD/BUILD-INFO.txt"

say ""
say "== done"
say "   $(basename "$merged")  -- flash at 0x0"
say "   $BUILD/BUILD-INFO.txt, $BUILD/SHA256SUMS"
