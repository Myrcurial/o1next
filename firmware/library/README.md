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
| `media_dir.c` / `media_dir.h` | the host implementation of that seam, over a directory tree. What the tests use |
| `library.h` / `library.c` | the library: the 8.3 identity, the kind and size rules, the walk and the merge, the mount table, and `lib_read` for the personality that mounted an entry |
| `mailbox.h` / `mailbox.c` | the protocol engine: opcode dispatch by class, operand counting, result codes, the reply buffer, the abandon rule, both doors as constants |
| `test_library.c` | the host suite |
| `run_tests.sh` | builds and runs it |

## The layout

Three media, one namespace. `docs/image-library-design.md` is the record:

| Directory | Kinds | Mounts |
|---|---|---|
| `floppy/` | `.imd`, `.hfe` → `KIND` 0 | `A:` or `B:` |
| `disk/` | `.img` → `KIND` 1 (Drive C blob, by exact size) or `KIND` 2 (hard-disk volume, 1 MiB and up) | slot 2, the storage personality |
| `printer/` | **none** — output, listed by the web UI (#182) | never |

The three media are the **external SPI flash module** (FAT32, always fitted, so it
is the floor) and **one microSD and one USB stick**. They are merged into one
library, de-duplicated on the 8.3 identity, with the precedence order deciding
which copy wins — so there is always something to pull from, and a user can still
override a factory image by name.

The RP2354B's **in-package 2 MB flash is not a medium**: it holds the firmware and
its assets (the boot splash animation).

## The one rule worth stating twice

**The library does not parse a blob.** It identifies a file by directory and size
and hands the bytes over; the volume's own header (the ACB-4000's `M`/`D` label at
LBA 0, #179/#180) is that personality's business. A parser here would be a second,
drifting copy of a format that already has an owner.

## Running the tests

```sh
firmware/library/run_tests.sh          # tests only
firmware/library/run_tests.sh -v       # ... and name each test as it runs
```

Nothing but a C compiler. The fixture is a directory tree built in a temp root, so
the tests exercise the real file path rather than a mock. CI runs this and
shellchecks the runner.

**Why the host harness is not a compromise here.** picoem (#192) has GPIO, PIO, the
core and XIP flash working but **SPI, DMA, UART, I2C and timers as stubs** — so the
storage path can never be exercised in the emulator. This harness is the only place
it can be proved, which is also why the repo's other firmware modules are
host-tested pure logic.

## What is not here

- **The media implementations** — FatFS over the external flash, the microSD and the
  USB stick, plus the FTL the NOR flash needs — are **#285**. This module is the
  logic behind `media.h`; the board fills the seam in.
- **The board** — the PIO bus tap and the door decode are the personality work
  (#17, #179), and the pin map is `hardware/interposer/revb/README.md`.
- **The ROM service** — `PRESENT`/`INFO` on the ROM's own door is **#284**; it
  registers through `mb_extension`, so this engine does not grow a payload it does
  not own.
- **The clock** (#18) — same route, when it exists.

## Two notes a reader will otherwise think are bugs

- **Result code `02h` is unreachable here.** The engine is operand-count-driven: it
  consumes exactly as many operands as the opcode takes, so a count can never be
  wrong. The code is in the table because the protocol defines it.
- **On an error the reply is the result code alone.** Section 4 gives each command
  a payload, and a payload is what a *successful* answer carries; there is no
  defined payload for a failure, so none is invented.
