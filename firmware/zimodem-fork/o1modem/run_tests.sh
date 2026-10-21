#!/bin/sh
# Build and run the modem core's host tests (#318, #319, #322, part of #56).
#
# No board, no SDK, no ESP32 core: the rate table, the 6850 frame decoder, the
# double-sided buffer, the panel and the sound are plain C99 plus stdio, so the
# whole suite is a seconds-long compile and run.  CI runs this, and so should you
# before touching rate.c, frame.c, buffer.c, panel.c or tone.c.
#
#   firmware/zimodem-fork/o1modem/run_tests.sh        # tests only
#   firmware/zimodem-fork/o1modem/run_tests.sh -v     # ... and print the notes
set -eu

here=$(cd "$(dirname "$0")" && pwd)
cc=${CC:-cc}
bin=$(mktemp)
trap 'rm -f "$bin"' EXIT INT TERM

"$cc" -std=c99 -Wall -Wextra -Werror -I"$here" -o "$bin" \
    "$here/rate.c" "$here/frame.c" "$here/buffer.c" \
    "$here/panel.c" "$here/tone.c" "$here/test_o1modem.c"

"$bin" "$@"
