#!/bin/sh
# Are the vendored FatFs files still the ones we vendored? (#285)
#
# The claim in README.md is that these five files are byte-identical to the R0.15
# archive.  That is worth checking rather than asserting, because the failure it
# prevents is silent: somebody fixes a bug in ff.c, it works, and the next
# re-vendor quietly throws the fix away.
#
# ffconf.h is deliberately absent -- it is FatFs's configuration file, ours by
# design, and it is *meant* to differ.
#
#   firmware/library/third_party/fatfs/check.sh
set -eu

here=$(cd "$(dirname "$0")" && pwd)
cd "$here"

if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 -c SHA256SUMS
elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum -c SHA256SUMS
else
    # Like the jsdom test: say how to check rather than fail on the checker's
    # absence, so this is never a broken check.
    echo "no shasum or sha256sum on this machine, so the vendored FatFs hashes are" >&2
    echo "unchecked.  Install one (perl's shasum, or coreutils) to check them." >&2
    exit 0
fi
