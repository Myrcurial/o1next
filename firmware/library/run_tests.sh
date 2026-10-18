#!/bin/sh
# Build and run the image library and mailbox tests on the host (#283, #192).
#
# No board, no SDK, no dependencies: the library, the protocol engine and the
# host-backed media are pure logic plus stdio, so they compile and run anywhere a
# C compiler does.  CI runs this, and so should you before touching library.c,
# mailbox.c or media_dir.c.
#
# The storage path is the one thing picoem cannot exercise -- it has SPI and DMA
# as stubs -- so this harness is not a fallback for it, it is the only place the
# library can be proved.
#
#   firmware/library/run_tests.sh        # tests only
#   firmware/library/run_tests.sh -v     # ... and print more
set -eu

here=$(cd "$(dirname "$0")" && pwd)
cc=${CC:-cc}
bin=$(mktemp)
trap 'rm -f "$bin"' EXIT INT TERM

"$cc" -std=c99 -Wall -Wextra -Werror -I"$here" -o "$bin" \
    "$here/library.c" "$here/mailbox.c" "$here/media_dir.c" \
    "$here/test_library.c"

"$bin" "$@"
