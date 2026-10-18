# `third_party/fatfs/` — FatFs, vendored (#285)

**FatFs R0.15** by ChaN — a small, portable FAT12/16/32 filesystem module. It is
vendored rather than written because a filesystem is exactly the kind of thing that
should be a known-good implementation, and because the requirement is a **FAT32
volume a user can read with a card reader** — which is what FatFs gives us on the
external flash, the microSD and the USB stick alike.

## Provenance

| | |
|---|---|
| Upstream | <https://elm-chan.org/fsw/ff/> — the FatFs module home page |
| Archive | `https://elm-chan.org/fsw/ff/arc/ff15.zip` |
| Archive SHA-256 | `e0d76654d877e6c74be5ea3c395808794d495169514e98cbf6046168b8f4f070` |
| Revision | `FF_DEFINED 80286` / `FFCONF_DEF 80286` (R0.15) |
| Licence | FatFs License — BSD-style, 1-clause: source redistributions keep the notice, binary redistributions need no attribution at all. Full text in `LICENSE.txt` |

## What is here, and what was changed

**Vendored verbatim** — byte-identical to the archive, CRLF line endings and all, so
that re-vendoring is a comparison rather than a merge:

| File | SHA-256 |
|---|---|
| `ff.c` | `cd849b935e2c41f294e1f5420754a61df92a96044fd885d0346cf33c4a755ef8` |
| `ff.h` | `d8a6671be75cc8ce2e4ebf79edd3bcc37a28676060a90de5d43604208464e3f9` |
| `ffunicode.c` | `3f1632c1f1e64b0b683b0d7e51341b9870728f398604869dd8211f1819509a8e` |
| `diskio.h` | `43b63bc5d1c35b2aa4a57c4e1cd7b66ab318748b51e9c6b12aded2574896e73c` |
| `LICENSE.txt` | `2576183a3e1c2d2f4b3628a7ef93c2f937879698abdd6d554dd718e79062e079` |

`check.sh` re-checks those hashes; CI runs it, so "unmodified" is a fact rather than
a promise. The hashes are in `SHA256SUMS`.

**Ours, not upstream's** — and this is the only one:

| File | Why |
|---|---|
| `ffconf.h` | it *is* FatFs's configuration file; upstream ships it for the user to edit. Its header lists every value that differs from R0.15 and why |

The configuration, in short: `FF_USE_MKFS 1`, `FF_CODE_PAGE 437`, `FF_USE_LFN 1`,
`FF_VOLUMES 3` (flash, microSD, USB), `FF_FS_NORTC 1`, and
`FF_MIN_SS == FF_MAX_SS == 512`.

**Deliberately not vendored:**

- `diskio.c` — upstream ships a **template**. Ours is `../../diskio.c`, which
  dispatches to the block devices in `../../blockdev.h`.
- `ffsystem.c` — it provides `ff_memalloc`/`ff_memfree` (needed only by
  `FF_USE_LFN == 3`) and the RTOS hooks (needed only by `FF_FS_REENTRANT == 1`).
  Neither is configured. **If either is ever turned on, this file has to be
  vendored too**, and the build will say so by failing to link.
- `documents/`, `source/00readme.txt`, `source/00history.txt` — the archive's
  documentation. The option reference is in `ffconf.h`'s own comments.

## Re-vendoring

```sh
curl -O https://elm-chan.org/fsw/ff/arc/ff15.zip
shasum -a 256 ff15.zip          # must be e0d76654…f070, or this is a different release
unzip -q ff15.zip
cp ff15/source/{ff.c,ff.h,ffunicode.c,diskio.h} ff15/LICENSE.txt third_party/fatfs/
shasum -a 256 ff15/source/ff.c  # compare against SHA256SUMS
```

Then re-apply the `ffconf.h` values listed in its header — and change the version
and hashes in this file, `SHA256SUMS`, and `REQUIREMENTS.md` in the same commit.

## One thing worth knowing before reading `ffunicode.c`

It is 15 593 lines and 1.9 MB, and almost none of it compiles. The code page tables
are guarded by `FF_CODE_PAGE`, and `FF_CODE_PAGE 0` — which reads like "no code
page" — actually compiles **all of them**. That is why the configuration picks 437
explicitly.
