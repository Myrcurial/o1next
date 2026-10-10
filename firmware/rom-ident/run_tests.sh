#!/bin/sh
# Build and run the ROM identity / personality gate tests on the host (#86).
#
# No board, no SDK, no dependencies: the generated table and the gate are pure
# logic, so they compile and run anywhere a C compiler does.  CI runs this, and
# so should you before touching rom_ident.c.
#
#   firmware/rom-ident/run_tests.sh        # tests only
#   firmware/rom-ident/run_tests.sh -v     # ... and print the gate decisions
set -eu

here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
cc=${CC:-cc}
bin=$(mktemp)
trap 'rm -f "$bin"' EXIT INT TERM

"$cc" -std=c99 -Wall -Wextra -Werror -I"$here" -o "$bin" \
    "$here/rom_ident.c" "$here/rom_table.c" "$here/test_rom_ident.c"

"$bin" "$root" "$@"
