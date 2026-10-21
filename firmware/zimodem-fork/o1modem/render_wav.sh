#!/bin/sh
# Render the modem sounds to .wav, so they can be heard without a board (#322).
#
#   firmware/zimodem-fork/o1modem/render_wav.sh [outdir]
#
# Default outdir is build/modem-tones/, which is gitignored with the rest of
# build/.  The same split as run_tests.sh: plain C99, stdio, no Arduino, no SDK.
set -eu

here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../../.." && pwd)
cc=${CC:-cc}

out=${1:-"$root/build/modem-tones"}
mkdir -p "$out"

bin=$(mktemp)
trap 'rm -f "$bin"' EXIT INT TERM

"$cc" -std=c99 -Wall -Wextra -Werror -I"$here" -o "$bin" \
    "$here/tone.c" "$here/render_wav.c"

# Absolute, because the renderer is handed the path and does not care where it
# was started from.
out=$(cd "$out" && pwd)
exec "$bin" "$out"
