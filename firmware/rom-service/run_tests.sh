#!/bin/sh
# Build and run the ROM service tests on the host (#284, part of #192).
#
# No board, no SDK, no dependencies beyond a C compiler and python3: the class, the
# engine it plugs into and the payload it presents are plain C99 plus stdio.  CI
# runs this, and so should you before touching rom_service.c.
#
# The payload is assembled, not committed.  `tools/research/rom2image.py
# --payload-only` builds the 3599 bytes out of the repo's own archive -- the same
# command romservice-check.sh runs for the emulator's -softrom image -- so the suite
# proves the module serves *the* payload rather than a fixture that happens to fit.
# A missing archive file is therefore a failure here, and says which one.
#
#   firmware/rom-service/run_tests.sh        # tests only
#   firmware/rom-service/run_tests.sh -v     # ... and name the payload's first bytes
set -eu

here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
lib="$root/firmware/library"
cc=${CC:-cc}
bin=$(mktemp)
work=$(mktemp -d)
trap 'rm -f "$bin"; rm -rf "$work"' EXIT INT TERM

payload="$work/payload.bin"
if ! "$root/tools/research/rom2image.py" --payload-only -o "$payload" \
        > "$work/rom2image.log" 2>&1; then
    cat "$work/rom2image.log" >&2
    echo "run_tests.sh: rom2image.py could not assemble the payload" >&2
    exit 1
fi

"$cc" -std=c99 -Wall -Wextra -Werror -I"$here" -I"$lib" -o "$bin" \
    "$here/rom_service.c" "$lib/mailbox.c" "$lib/library.c" \
    "$here/test_rom_service.c"

"$bin" "$payload" "$@"
