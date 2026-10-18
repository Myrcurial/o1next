# The image library — the layout, the merge, and the kinds (#283, #192)

**Status: decided.** The layout, the three media and the merge rule are the
maintainer's decision of 2026-10-18, recorded here so that `MOUNT.COM` (#27), the
web UI (#16, #182), the hard-disk menu (#181) and the firmware all cite one page
instead of four recollections. The library's *logic* is written and host-tested
(`firmware/library/`, #283); the media behind the seam are **not** (#285), and
nothing here has been measured on hardware.

**Revised the same day**, on the maintainer's correction: the precedence order is
USB stick first (§3) — the stick is the transient member and the flash is the
guarantee — the merge falls through an *invalid* copy to the next medium (§3), and
the hard-disk floor is 5 MiB rather than 1 MiB (§4).

Answers **#283** and **#285**. Reads alongside `docs/mailbox-protocol.md` (the
protocol, and §5.2's KIND and SIZE rules this doc extends),
`docs/rom-pico-protocol.md` §1 (the second client), `docs/drive-c-design.md` §4.2
(why a Drive C blob's length *is* its geometry), `docs/harddisk-decision.md` §7
(the sparse volume blob) and `hardware/interposer/README.md` (the onboard library
flash).

## 1. Three media, one namespace

| Precedence | Medium | What it is | Present |
|---|---|---|---|
| 1 | **USB stick** | exactly one, FAT32 | transient — plugged in to test something |
| 2 | **microSD** | exactly one, FAT32 | semi-permanent — the library that lives in the machine |
| 3 | **external SPI flash** | a W25Q-class part, 16–64 MB, FAT32 | always — the floor and the guarantee |

They are **merged into one library**, not presented as three. A file is identified
by its CP/M 8.3 identity (§5) and de-duplicated across the media, so a name that
exists in two places is **one** entry — and there is always something to pull from,
because the external flash is always fitted.

**The RP2354B's in-package 2 MB flash is not a medium.** It holds the firmware and
its assets — the boot splash animation (`firmware/rom-service/boot-animation.bin`,
#247) — and the library never reaches it. That is the one thing about "onboard
flash" worth being pedantic about, because the two parts are easy to conflate: the
in-package flash is *the firmware's own*, and the external module is *the user's
library*.

## 2. The layout

Three directories at the volume root of every medium:

| Directory | Accepts | Kind | Mounts |
|---|---|---|---|
| `floppy/` | `.imd`, `.hfe` | `KIND` 0 | `A:` or `B:` |
| `disk/` | `.img` | `KIND` 1 **or** 2 — see §4 | slot 2 |
| `printer/` | `.pdf` | **none** | never |

Extensions are matched case-insensitively, because FAT names arrive in whatever
case the user typed. A file that is not of the directory's kind — `notes.txt` in
`floppy/` — is **not a library entry** and is not listed.

**`printer/` is the exception that is stated rather than omitted.** The virtual
printer (#19) *writes* PDFs there and the web UI (#182) lists and serves them, but
they are output, not mountable images, so the mailbox never sees them and no KIND
is spent on them. It is in the table so that a later reader does not add it by
accident.

## 3. The merge rule

Precedence is the order the media are handed to the library, and it follows what
each medium *is*:

```
USB stick  →  microSD  →  external flash
```

The stick is the **transient** member: plugging one in with a demo image is how you
test something, so it wins. The microSD is the **semi-permanent** library — the one
that lives in the machine. The external flash is always fitted, so it is the floor
and the guarantee.

**And the fallback is per entry, not just per name.** A copy that is *invalid* for
its kind does not shadow a valid one further down the list: if the demo image on
the stick turns out to be the wrong size, the entry becomes the microSD's copy, or
the flash's. Only when *no* copy is valid does the highest-precedence one keep the
entry — listed with `VALID` clear (§4) so the user can see why nothing will mount.

The price is stated because it is real: an invalid file that has a valid copy below
it is **not listed at all**. That is the trade — a working disk over a diagnosis —
and it is the right way round for a machine whose whole point is to boot.

Two more consequences, both deliberate:

- **There is always something to pull from.** With no stick and no card, the
  library is whatever the external flash carries, which is where the factory images
  live.
- **A user can override a factory image by name.** Dropping `boot.imd` on a stick
  shadows the flash copy of `BOOT.IMD`; the entry is the same one, and the stick's
  bytes are what a personality reads.

It is one line to reorder, and it is stated here rather than left to the code so
that reordering it is a decision and not a discovery.

A **mount survives a refresh** when its entry is still there: the firmware's state
outlives the host's (`docs/mailbox-protocol.md` §6), and a CP/M program is reloaded
from disk every time it runs.

## 4. The kinds, and why `disk/` holds two of them

| `KIND` | Name | Directory | Valid sizes | Mounts |
|---|---|---|---|---|
| 0 | floppy image | `floppy/` | any (the image's own geometry is its business) | `A:` or `B:` |
| 1 | Drive C blob | `disk/` | **exactly** 196 608 or 393 216 | slot 2 |
| 2 | hard-disk volume | `disk/` | 5 MiB and up | slot 2 |

**One directory, two kinds, and the size band separates them.** A Drive C blob's
length *is* its geometry — 196 608 is the 192K unit and 393 216 the 384K one
(`docs/drive-c-design.md` §4.2) — while a hard-disk volume is megabytes and carries
its own geometry in its header (`docs/harddisk-decision.md` §7). So the library
never has to guess and never has to parse anything:

| Size of a `disk/` `.img` | Kind | Valid |
|---|---|---|
| 196 608 or 393 216 | 1 | yes |
| 5 MiB and up | 2 | yes |
| anything else | 1 if under 5 MiB, else 2 | **no** |

**The floor is 5 MiB, and the band is wide on purpose.** A Drive C blob tops out at
393 216 bytes; a real hard-disk volume is tens of MiB, so nothing we expect to see
lands in the 384 KiB – 5 MiB gap, and a file that does is a truncated volume rather
than a small one. Refusing it in the *menu* is much better than refusing it at the
controller, which is where a truncated image would otherwise be discovered. The
number is policy from the maintainer's expectation (2026-10-18), not a hardware
limit, and it is one line to move (`LIB_HARDDISK_MIN` in `firmware/library/`).

**A wrong-sized file is still listed, with `VALID` clear.** That is
`docs/mailbox-protocol.md` §5.2's rule and it is the right one: a user who copied
the wrong file onto a card needs to *see* it in the menu and be told why it will
not mount, rather than wondering whether the file is there at all. `MOUNT` refuses
it with result code `05h`.

`KIND` 2 is the space #181 already reserved for the hard-disk volume. Naming a
volume `A:`/`B:` — the MD-10's convention — is #181's drive-mapping table, not this
document's and not the library's: the library enforces only the kind-to-slot rule
below.

### 4.1 The kind-to-slot rule

| Kind | May mount to |
|---|---|
| 0 (floppy) | `A:` (0) or `B:` (1) |
| 1, 2 | slot 2 only |

Slot 2 is the interposer's **storage personality** — Drive C, or the ACB-4000 hard
disk. The two are mutually exclusive on one machine (`docs/mailbox-protocol.md`
§6), which is why one slot serves both. Anything else is result code `05h`.

## 5. The identity is the CP/M 8.3 name, not the file name

`NAME` in the record is the **CP/M 8.3 identity, upper case** —
`docs/mailbox-protocol.md` §5.3 question 1, unchanged here. It is:

- the stored name with any path dropped,
- upper-cased,
- the base truncated to 8 characters and the extension to 3,
- joined with `.`, NUL-padded to 16.

So `my-floppy.imd` is `MY-FLOPP.IMD` and `O1NEXT-HARDDISK.IMG` is
`O1NEXT-H.IMG`. FAT long names are **not** carried: the machine is 52 columns wide
and CP/M thinks in 8.3, so the long name is a web-UI nicety and the short name is
the identity.

**This is the merge key** (§3), which is the one place the truncation is load
bearing: two files that differ only past the eighth character of the base are the
same identity and therefore one entry. That is the honest reading of "the CP/M
visible name" — CP/M could not tell them apart either.

## 6. What this document adds to the protocol

`docs/mailbox-protocol.md` fixes the command set, the result codes and the record.
Three things it leaves implicit, and which writing the code settled (#283):

1. **The drive-state byte.** `MOUNT`, `UNMOUNT` and `DSTATUS` answer with a "drive
   state `u8`" that the protocol does not define. It is `00h` empty, `01h` mounted.
2. **`DSTATUS` on an empty drive is not an error.** It answers `OK` with state
   `00h` and entry index `FFFFh`. It is the *status* query, and "nothing mounted"
   is the status. `08h` ("nothing mounted on that drive") belongs to `UNMOUNT`,
   where asking to eject nothing is the mistake.
3. **On an error the reply is the result code alone.** §4 gives each command a
   payload, and a payload is what a *successful* answer carries; there is no
   defined payload for a failure, so none is invented.

These three should fold back into `docs/mailbox-protocol.md` §4 as a doc repair,
with the encoding marked as this implementation's proposal rather than a
measurement. They are recorded here first because the code that needed them exists
and the doc that owns them has not been revised.

## 7. What is not here

- **The media implementations.** FatFS vendored, the three transports, and the
  wear-levelling layer the external NOR flash needs — FAT32 rewrites its FAT and
  directory sectors constantly and SPI NOR erases in 4 KB blocks with a finite
  cycle count, so FAT32 directly on NOR needs a block-mapping layer under it. That
  is **#285**.
- **The web UI's listing.** `printer/` is its business (#182), and the long-name
  nicety §5 refuses is exactly the thing it can offer.
- **The hard disk's drive letters.** #181.
- **Anything measured.** No card, no stick, no flash part has been read by this
  firmware. The layout is a decision, and the code that reads it has been tested
  against a directory tree (`firmware/library/run_tests.sh`), which is a different
  claim and is labelled as one.

## Sources

- `docs/mailbox-protocol.md` — §3 the transaction, §4 the command set and result
  codes, §5.1 the 24-byte record, §5.2 KIND and SIZE, §5.3 the four listing
  questions, §6 mount semantics.
- `docs/drive-c-design.md` §4.1–§4.2 — why a Drive C blob's length is its geometry,
  and why a mounted blob needs no re-install.
- `docs/harddisk-decision.md` §7 — the sparse volume blob, the fill byte, and the
  geometry the volume carries.
- `hardware/interposer/README.md` — the onboard library flash decision (W25Q-class,
  16–64 MB, SPI NOR); `hardware/interposer/revb/README.md` — GP40–43 SPI to the SD,
  GP44 `/CS_FLASH`.
- `firmware/library/` — the implementation and its host tests (#283).
