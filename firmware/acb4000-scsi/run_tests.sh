#!/bin/sh
# Build and run the ACB-4000 SCSI personality tests on the host (#179).
#
# No board, no SDK, no dependencies: the target, the shim and the store are pure
# logic, so they compile and run anywhere a C compiler does.  CI runs this, and
# so should you before touching acb4000_target.c or acb4000_shim.c.
#
#   firmware/acb4000-scsi/run_tests.sh        # tests only
#   firmware/acb4000-scsi/run_tests.sh -v     # ... and print more
set -eu

here=$(cd "$(dirname "$0")" && pwd)
cc=${CC:-cc}
bin=$(mktemp)
trap 'rm -f "$bin"' EXIT INT TERM

"$cc" -std=c99 -Wall -Wextra -Werror -I"$here" -o "$bin" \
    "$here/acb4000_target.c" "$here/acb4000_shim.c" "$here/acb4000_store.c" \
    "$here/test_acb4000.c"

"$bin" "$@"
