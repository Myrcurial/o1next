#!/bin/sh
# build.sh -- build the fabric firmware for the picoem bridge (#304, part of #192).
#
#   firmware/picoem-fabric/build.sh            # build
#   firmware/picoem-fabric/build.sh --clean    # wipe build/ first
#
# Output: firmware/picoem-fabric/build/picoem-fabric.bin -- the flash image
# `tools/picoem-bridge --fabric-test` loads into the emulated chip's XIP flash.
#
# The discovery below is `firmware/picoem-smoke/build.sh`'s, repeated rather than shared
# because the two are one script each and the *reasoning* for every check -- the SDK
# version, and why Homebrew's `arm-none-eabi-gcc` formula is not the tool -- lives there
# in full. If a third firmware appears, that is the point to factor it out.
set -eu

here=$(cd "$(dirname "$0")" && pwd)
sdk_version=2.3.1
build=${BUILD_DIR:-$here/build}

[ "${1:-}" = "--clean" ] && rm -rf "$build"

# ---------------------------------------------------------------- the SDK ----
sdk=${PICO_SDK_PATH:-$HOME/Documents/O1NEXT/pico-sdk-$sdk_version}
if [ ! -f "$sdk/pico_sdk_init.cmake" ]; then
    echo "picoem-fabric: no Pico SDK at $sdk" >&2
    echo "  firmware/picoem-smoke/build.sh has the clone command and REQUIREMENTS.md" >&2
    echo "  has the pin." >&2
    exit 1
fi

# ---------------------------------------------------------- the toolchain ----
toolchain=${PICO_TOOLCHAIN_PATH:-}
if [ -z "$toolchain" ]; then
    for cand in "$HOME"/Documents/O1NEXT/toolchain/arm-gnu-toolchain-*-arm-none-eabi; do
        [ -x "$cand/bin/arm-none-eabi-gcc" ] && toolchain=$cand
    done
fi
if [ -n "$toolchain" ]; then
    PATH="$toolchain/bin:$PATH"
    export PATH
fi

for tool in cmake ninja arm-none-eabi-gcc; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "picoem-fabric: $tool is not on PATH -- see REQUIREMENTS.md" >&2
        exit 1
    }
done

# A toolchain that resolves but cannot link is the trap here.
libc=$(arm-none-eabi-gcc -print-file-name=libc.a)
case "$libc" in
    /*) ;;
    *)
        echo "picoem-fabric: $(command -v arm-none-eabi-gcc) has no C library" >&2
        echo "  Homebrew's arm-none-eabi-gcc formula is compiler-only; use the" >&2
        echo "  official Arm GNU Toolchain -- REQUIREMENTS.md has the row." >&2
        exit 1
        ;;
esac

# ------------------------------------------------------------------ build ----
set -- -S "$here" -B "$build" -G Ninja -DCMAKE_BUILD_TYPE=Release -DPICO_SDK_PATH="$sdk"
if [ -n "$toolchain" ]; then
    set -- "$@" -DPICO_TOOLCHAIN_PATH="$toolchain"
fi

cmake "$@" >/dev/null
cmake --build "$build"

echo "picoem-fabric: $build/picoem-fabric.bin"
