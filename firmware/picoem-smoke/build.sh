#!/bin/sh
# build.sh -- build the smoke firmware for the picoem bridge (#286, part of #192).
#
#   firmware/picoem-smoke/build.sh              # build (finds the SDK + toolchain)
#   firmware/picoem-smoke/build.sh --clean      # wipe build/ first
#
# Output: firmware/picoem-smoke/build/picoem-smoke.bin -- the flash image
# tools/picoem-bridge loads into the emulated chip's XIP flash.
#
# Two host tools this cannot vendor, both pinned in REQUIREMENTS.md:
#
#   * the **Pico SDK**, used from $PICO_SDK_PATH, else a clone at
#     $HOME/Documents/O1NEXT/pico-sdk-<version>.  Submodules are NOT needed:
#     this firmware links only pico_stdlib with stdio off, so none of tinyusb /
#     mbedtls / lwip / cyw43 / btstack is referenced.
#   * the **Arm GNU Toolchain**, used from $PICO_TOOLCHAIN_PATH, else a
#     downloaded official toolchain under $HOME/Documents/O1NEXT/toolchain/.
#     **Not** Homebrew's `arm-none-eabi-gcc` formula: that ships no C library at
#     all, so `-lc` fails at link time and the failure reads like a broken
#     linker rather than a missing libc.  The check below is the check that
#     catches it, and it is the reason this script does not simply trust PATH.
#
# Both live outside the repo on purpose: they are large third-party trees, and
# the repo's archive is for material the project cannot complete without
# (AGENTS.md).
set -eu

here=$(cd "$(dirname "$0")" && pwd)
sdk_version=2.3.1
sdk_remote=https://github.com/raspberrypi/pico-sdk.git
build=${BUILD_DIR:-$here/build}

clean=no
[ "${1:-}" = "--clean" ] && clean=yes

# ---------------------------------------------------------------- the SDK ----
sdk=${PICO_SDK_PATH:-$HOME/Documents/O1NEXT/pico-sdk-$sdk_version}
if [ ! -f "$sdk/pico_sdk_init.cmake" ]; then
    echo "picoem-smoke: no Pico SDK at $sdk" >&2
    echo "  clone it with:" >&2
    echo "    git clone --depth 1 --branch $sdk_version $sdk_remote $sdk" >&2
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
        echo "picoem-smoke: $tool is not on PATH -- see REQUIREMENTS.md" >&2
        exit 1
    }
done

# A toolchain that resolves but cannot link is the trap here.
libc=$(arm-none-eabi-gcc -print-file-name=libc.a)
case "$libc" in
    /*) ;;
    *)
        echo "picoem-smoke: $(command -v arm-none-eabi-gcc) has no C library" >&2
        echo "  (it reports libc.a as '$libc', not a path)." >&2
        echo "  Homebrew's arm-none-eabi-gcc formula is compiler-only; use the" >&2
        echo "  official Arm GNU Toolchain -- REQUIREMENTS.md has the row." >&2
        exit 1
        ;;
esac

[ "$clean" = yes ] && rm -rf "$build"

# ------------------------------------------------------------------ build ----
set -- -S "$here" -B "$build" -G Ninja -DCMAKE_BUILD_TYPE=Release -DPICO_SDK_PATH="$sdk"
[ -n "$toolchain" ] && set -- "$@" -DPICO_TOOLCHAIN_PATH="$toolchain"

cmake "$@" >/dev/null
cmake --build "$build"

echo "picoem-smoke: $build/picoem-smoke.bin"
