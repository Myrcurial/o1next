#!/bin/sh
# Build and run the image library, mailbox and media tests on the host (#283, #285).
#
# No board, no SDK, no dependencies: the library, the protocol engine, the media
# seam, the FatFS port and the host block device are all plain C plus stdio.  CI
# runs this, and so should you before touching anything here.
#
# Two suites, and the point is that they are the *same* suite: `suite.c` holds the
# checks that must hold for any media set, `test_library.c` runs it over a directory
# tree and `test_fatfs.c` runs it over three real FAT volumes built with FatFS.  The
# library cannot tell them apart, and that is asserted rather than argued.
#
# The storage path is the one thing picoem cannot exercise -- it has SPI and DMA as
# stubs -- so this harness is not a fallback for it, it is the only place the media
# layer can be proved.
#
#   firmware/library/run_tests.sh        # both suites
#   firmware/library/run_tests.sh -v     # ... and name each check group
set -eu

here=$(cd "$(dirname "$0")" && pwd)
fatfs="$here/third_party/fatfs"
cc=${CC:-cc}
bin_dir=$(mktemp)
bin_fatfs=$(mktemp)
trap 'rm -f "$bin_dir" "$bin_fatfs"' EXIT INT TERM

# Our code is held to -Wall -Wextra -Werror.  The vendored FatFS is not: it is
# third-party code we do not edit, and holding it to our bar would mean either
# patching it (which breaks "vendored unmodified") or a warning list to maintain.
cflags="-std=c99 -Wall -Wextra -Werror -I$here"
fatfs_cflags="-std=c99 -w -I$here -I$fatfs"

# shellcheck disable=SC2086  # the flags are meant to split into words
"$cc" $cflags -o "$bin_dir" \
    "$here/library.c" "$here/mailbox.c" "$here/media_dir.c" "$here/suite.c" \
    "$here/test_library.c"

# shellcheck disable=SC2086  # the flags are meant to split into words
"$cc" $fatfs_cflags -o "$bin_fatfs" \
    "$here/library.c" "$here/mailbox.c" "$here/blockdev.c" "$here/diskio.c" \
    "$here/blockdev_file.c" "$here/media_fatfs.c" "$here/suite.c" \
    "$here/test_fatfs.c" \
    "$fatfs/ff.c" "$fatfs/ffunicode.c"

"$bin_dir" "$@"
"$bin_fatfs" "$@"
