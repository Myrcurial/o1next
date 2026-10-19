# `library/` — the image library and the mailbox engine (RP2354B)

The firmware's one view of its storage: **what images are there, which one goes on
which drive, and the protocol a CP/M program or the ROM asks it through.** Portable
C, no board, no SDK, no RTOS — host-tested and in CI, exactly as
`firmware/acb4000-scsi/` and `firmware/rom-ident/` are.

Answers #283 (part of #192). The contract is `docs/mailbox-protocol.md`; the layout
is `docs/image-library-design.md`.

## The files

| File | What it is |
|---|---|
| `media.h` | the **port seam** — `list`/`stat`/`read`/`write`, indexed and allocation-free. The library never touches a filesystem, so the same code runs over a directory on a laptop and over FatFS on the board |
| `media_dir.c` / `.h` | a host implementation of that seam, over a directory tree |
| **`media_fatfs.c` / `.h`** | **the real one**: the seam over FatFS. The same code on the board, and what the FAT suite runs |
| `library.h` / `library.c` | the library: the 8.3 identity, the kind and size rules, the walk and the merge, the mount table, and `lib_read` for the personality that mounted an entry |
| `mailbox.h` / `mailbox.c` | the protocol engine: opcode dispatch by class, operand counting, result codes, the reply buffer, the abandon rule, both doors as constants |
| **`blockdev.h` / `blockdev.c`** | **the block-device seam**: what FatFS's `diskio` talks to. Three logical drives — 0 flash, 1 microSD, 2 USB |
| **`diskio.c`** | **FatFS's port** — the only file here that knows FatFS exists. Maps the five `disk_*` functions onto `blockdev` |
| **`blockdev_file.c` / `.h`** | a `blockdev` over a file on the host: a volume image, which is what makes the filesystem testable with no board |
| `suite.c` / `suite.h` | **the shared media suite** — the checks that must hold for *any* media set, run by both test binaries |
| `test_library.c` | the library and protocol suite, over a directory tree |
| **`test_fatfs.c`** | the same shared suite over **three real FAT volumes**, plus the FAT-specific checks |
| `third_party/fatfs/` | **FatFS R0.15, vendored** — see its `README.md` for the version, the hashes and what is ours |
| `run_tests.sh` | builds and runs both suites |

## The layout

Three media, one namespace. `docs/image-library-design.md` is the record:

| Directory | Kinds | Mounts |
|---|---|---|
| `floppy/` | `.imd`, `.hfe` → `KIND` 0 | `A:` or `B:` |
| `disk/` | `.img` → `KIND` 1 (Drive C blob, by exact size) or `KIND` 2 (hard-disk volume, 5 MiB and up) | slot 2, the storage personality |
| `printer/` | **none** — output, listed by the web UI (#182) | never |

The three media are **one USB stick** (transient — plugged in to test something, so
it wins), **one microSD** (the semi-permanent library) and the **external SPI flash
module** (FAT32, always fitted, so it is the floor and the guarantee) — in that
precedence order. They are merged into one library, de-duplicated on the 8.3
identity, and a copy that is **invalid for its kind falls through to the next
medium**, so a demo image on a stick that turns out to be the wrong size still lands
on the microSD or on the flash. Only when no copy is valid does the first one keep
the entry, listed with `VALID` clear.

The RP2354B's **in-package 2 MB flash is not a medium**: it holds the firmware and
its assets (the boot splash animation).

## The one rule worth stating twice

**The library does not parse a blob.** It identifies a file by directory and size
and hands the bytes over; the volume's own header (the ACB-4000's `M`/`D` label at
LBA 0, #179/#180) is that personality's business. A parser here would be a second,
drifting copy of a format that already has an owner.

## The media layer (#285)

Below `media.h` there is a second seam, and it is the one that makes a filesystem
testable:

```
library.c            the library and the merge      (media.h)
  media_fatfs.c      FatFS: opendir/readdir/stat/read/write
    diskio.c         FatFS's five disk_* functions   (the only FatFS-aware file)
      blockdev       the block-device seam           (blockdev.h)
        blockdev_file.c   host: a volume image in a file
        (the board: the external NOR flash behind the FTL, the microSD over SPI,
         the USB stick over TinyUSB MSC -- the follow-up sub-issue)
```

Three logical drives, numbered 0 flash, 1 microSD, 2 USB — that numbering is what
FatFS puts in a path (`"1:/floppy/boot.imd"`) and what `media_fatfs` is handed.

**FatFS R0.15 is vendored** in `third_party/fatfs/`, with its licence, the archive
hash, and per-file hashes that `third_party/fatfs/check.sh` re-checks in CI. The one
file there that is ours is `ffconf.h` — it *is* FatFs's configuration file — and its
header lists every value that differs from upstream.

### The finding worth knowing: a "FAT32" volume is not always FAT32

FatFS decides the FAT type from the **cluster count**, not from the BPB's `FAT32`
string. So with one 512-byte sector per cluster — which is what a library of
100–400 KB images wants — **16 MB is FAT16**, and only about 34 MB and up is FAT32.
The external flash is specced at 16–64 MB, which straddles that line.

It does not matter to us, because FatFS reads FAT12/16/32 transparently and a card
reader reads any of them, so the requirement ("a volume a user can read") holds
either way. But the test **asserts** what each size comes out as rather than
assuming, and `docs/image-library-design.md` records it — because "FAT32" was the
word in the decision and it is not always the thing on the media.

## Running the tests

```sh
firmware/library/run_tests.sh          # both suites
firmware/library/run_tests.sh -v       # ... and name each check group
```

Nothing but a C compiler, and it takes well under a second. Two binaries:

- `test_library.c` runs the library and protocol suite over a **directory tree**;
- `test_fatfs.c` builds **three real FAT volumes** (64 MB flash, 64 MB microSD,
  16 MB USB — the parts the interposer names) with FatFS's own `f_mkfs`, populates
  them *through the media seam*, and runs the same checks.

**The same suite, deliberately.** The checks that must hold for any media set live
in `suite.c` and are run by both binaries, so "the library cannot tell them apart"
is asserted rather than argued. The fixture is part of that contract: both build the
same eight entries with the same names, sizes and kinds — a duplicate name for the
merge, a wrong-sized blob for `VALID`, an invalid copy with a valid one below it for
the fallback, a long name for LFN, and a `printer/` PDF and a `.txt` that must not
appear at all.

CI runs both, re-checks the vendored FatFS hashes, and shellchecks the runners.

**Why the host harness is not a compromise here.** picoem (#192) has GPIO, PIO, the
core and XIP flash working but **SPI, DMA, UART, I2C and timers as stubs** — so the
storage path can never be exercised in the emulator. This harness is the only place
it can be proved, which is also why the repo's other firmware modules are
host-tested pure logic.

## What is not here

- **The board's transports.** FatFS is in, the seam is in, and the *devices* are
  not: the SPI transport to the external NOR flash (behind the FTL a wear-levelled
  FAT volume needs), the microSD over SPI, and the USB stick over TinyUSB MSC. They
  need a board, and they are the follow-up sub-issue of #285. The seam they plug into
  is `blockdev.h`, and the three slots are already there.
- **The board** — the PIO bus tap and the door decode are the personality work
  (#17, #179); the pin map is `hardware/interposer-upgrade/revb/README.md`.
- **The ROM service** — `PRESENT`/`INFO` on both doors is
  `firmware/rom-service/` (#284), built and host-tested; it registers through
  `mb_extension`, so this engine does not grow a payload it does not own.
- **The clock** (#18) — the same route, when it exists. `FF_FS_NORTC 1` in
  `ffconf.h` is the one line that turns file timestamps on when it does.
- **A card reader's opinion.** Everything here is FatFS reading volumes FatFS wrote.
  A volume made by `mkfs.vfat` on a PC, and a card a camera formatted, are the
  follow-ups — and they want the board, or at least a card and a reader.

## Two notes a reader will otherwise think are bugs

- **Result code `02h` is unreachable here.** The engine is operand-count-driven: it
  consumes exactly as many operands as the opcode takes, so a count can never be
  wrong. The code is in the table because the protocol defines it.
- **On an error the reply is the result code alone.** Section 4 gives each command
  a payload, and a payload is what a *successful* answer carries; there is no
  defined payload for a failure, so none is invented.
