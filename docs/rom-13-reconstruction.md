# ROM 1.3 — the source is on the disk, the ROM is not yet certified

**Status: Partially solved.** The disk is read
and the source is **extracted, indexed and readable**. What is *verified*: the
`DBE`/`DCE` rule, and a rev-B control build that reproduces a shipped Osborne ROM
to 3759 of its 4096 bytes. What is **not**: the 1.3 image itself, which is
reconstructible but **not certified**, and must not be handed upstream as the real
ROM. Two things stand in the way and both are *tooling*, not knowledge: the 1.3
source uses the `DBE`/`DCE` pseudo-ops, which only ACT **3.5E** has, and every
build loses 337 bytes of its hex output to an emulation defect (§7). Everything
needed to finish it is in this repo or named below, and the recommendation is to
record the result and stop (§10). **Issues:** #205, #72, #70, #203.

> **Vocabulary:** `rev B` here is the **Osborne 1's monitor ROM** (9/12/81) — a
> 1979-era ROM part, **not a board revision**. Board revisions belong to the
> boards; see [`hardware/README.md`](../hardware/README.md).

MAME carries BIOS A, 1.2, 1.2.1 and 1.3 as `NO_DUMP` placeholders, so
`mame osborne1 -bios ver13` cannot run. We hold the 1.3 **source disk** —
`research/source-code/OSROM13.IMD`, whose own comment reads
`rom 1.3, cbios .3   osborne source 12/16/81` — and this is what came of
trying to turn it into the missing `osb13.bin`.

## The answer, up front

1. **The disk reads, and the source is complete.** `OSROM13.IMD` is an
   **8-inch** disk, not an Osborne 1 5.25" one, which is why no earlier reader in
   the tree could describe it. It yields 19 files —
   `OCCROM0..9.ASM` (the monitor ROM, split into modules) and `OCCBIO0..8.ASM`
   (the CBIOS) — all of them clean text that starts with a `TITLE` and ends
   with `; END OCCROMn?.???`. They are committed at
   `research/source-code/ROM-13-source/`.
2. **The build needs ACT 3.5E, and we do not have it.** The source uses two
   pseudo-ops, `DBE` and `DCE`, that exist in no ACT the archive holds — every
   `ACT80.COM` in the local archive is 3.0 or 3.2 (or ACT II 8086 3.4), and
   none of them carries those strings in its mnemonic table. The rev-B listing
   on `OCCROM.IMD` names the version it *was* built with:
   `SORCIM 808x Assembler ver  3.5E`.
3. **What `DBE`/`DCE` do is recovered exactly**, from a shipped ROM we *do*
   have: the rev-B disk carries `OCCROM0B.COM` (4096 B) and its full listing,
   and comparing the two gives one rule holding over every line. See below.
4. **A 1.3 image can be produced** — `tools/research/rom13-reassemble.sh` does
   it, by rewriting `DBE`/`DCE` into `DB` so ACT 3.0 emits the same bytes — but
   **it is not certified**: three errors in the 1.3 build are still
   unidentified, and 337 bytes of every build's hex output are lost before they
   reach the disk. It must not be handed upstream as the real 1.3 until the
   control build passes. §6.
5. **The hex output arrives damaged at about six fixed *file offsets* per
   build** — identically on a double-density disk and on a single-density one,
   and on drive A or drive B — so it is not the disk layer. §7.
6. **Recommendation: stop here, as "record it and stop".** The source work is
   done and committed; what is left is two *tooling* defects (§6, §7) whose
   clean fix is the assembler we cannot get. Nothing in the project needs a 1.3
   ROM, and the durable half of the result — the disk read, the source, the
   recovered `DBE`/`DCE` semantics, and a control build that reproduces **3759
   of a shipped Osborne ROM's 4096 bytes exactly** — is already banked. §10.

## 1. What the disk is

`imdinfo.py` reports the geometry; `tools/research/o1imd8.py` reads it.

| | |
|---|---|
| Cylinders | 77, one head, 630 784 bytes |
| Track 0 | 250 kbit/s **FM**, 26 sectors of **128** bytes (the IBM-3740 boot track) |
| Tracks 1–76 | 250 kbit/s **MFM**, 8 sectors of **1024** bytes |
| Filesystem | CP/M 2.2, 2 KiB blocks, **128** directory entries (4096 B = two blocks), two reserved tracks |
| **Skew** | **3** — the sectors of a track are interleaved |

Seven disks in `research/source-code/` share this format (`OCCCBIOS`, `OCCROM`,
`OCCUTIL`, `OSBIOSSR`, `OSBROM`, `OSROM13`, `OSUTLSRC`), so the reader is a
tool, not a one-off.

### The skew is the whole difficulty

`o1imd8.py` writes the image in the linear shape a `cpmtools` diskdef expects
(track 0's 3328 bytes padded out to 8192, `boottrk 2`), and the diskdef carries
`skew 3`. Without the skew the read **still works** — the directory parses and
every file comes back — from the wrong sectors. That is the failure mode
`docs/ozrom-1e.md` §10.4 warns about, and it is how this one was found:
content chaining. At skew 3 every sector boundary in `occrom33.asm` joins
mid-token to the next —

```
BDOS (f     + unction  ->  BDOS (function
\tJMP\t     + LIST      ->  \tJMP\tLIST
;HOUSE      + KEEPING   ->  ;HOUSEKEEPING
\tLD\tA,PIAB + D        ->  \tLD\tA,PIABD
```

— and at skew 1 the joins are `;continueT`, `indicate RY` and a sector that
should not follow. `skew 3` is also exactly `tools/cpmfs.py`'s
`skew_table(3, 8)` = `0 3 6 1 4 7 2 5`, i.e. `cpmtools`' own table
(`cpmfs.c`), which is the cross-check that the two agree.

## 2. The source set, and what is missing from it

`OCCROM03.ASM` is the master. It sets `ORG 0`, defines `ALPUSH`/`ALLPOP`, and
`LINK`s the rest:

```
	LINK	OCCROM13.ASM	;ROM STANDARDS
	LINK	OCCROM23.ASM	;CPM BOOT
	LINK	OCCROM33.ASM	;CONSOL ROUTINES
	LINK	OCCROM43.ASM	;PIA ROUTINES
	LINK	OCCROM53.ASM	;SIA ROUTINES
	LINK	OCCROM63.ASM	;DISK ROUTINES
	LINK	OCCROM73.ASM	;DIAGNOSIC ROUTINES
	LINK	OCCROM83.ASM	;FORMAT ROUTINE
	LINK	OCCROM93.ASM	;UTILITES
	LINK	OCCRAM2.ASM	;RAM LOCATIONS
```

| File | Size | On `OSROM13.IMD`? |
|---|---|---|
| `occrom03.asm` … `occrom93.asm` (10) | 896 … 32 512 B | yes |
| `occbio03.asm` … `occbio83.asm` (9) | 640 … 16 896 B | yes |
| `occram2.asm` | 3840 B | **no** — recovered from `OSUTLSRC.IMD` |
| `occtxt6.ast` | 9472 B | **no** — recovered from `OSUTLSRC.IMD` |

Two files the build needs are not on the ROM disk at all. `OCCRAM2.ASM` is the
`;RAM LOCATIONS` module (`ORG MRAMEXT`, `ORG MRAM`); the utilities-source disk
`OSUTLSRC.IMD` carries it. The systext (`OCCTXT`) is the equates file the ROM
reads for `CR`, `LF`, `MTRK`, `EOFC`, `MRAM`, `MRAMEXT`, `KL_LEN`, `ALVS`,
`CSVS` and the rest; **no `OCCTXT` is on the 1.3 disk either**, and the one
committed here is `occtxt6.ast` from `OSUTLSRC.IMD` — the nearest revision we
hold to 12/16/81. That is an *assumption*, and it is the one place a future
find could change the bytes: `occtxt5.ast` and `occtxt6.ast` are identical
apart from the header and `BIOS`, and `BIOS` is referenced by no ROM source
line, so the choice is inert *for this source* — but a later `OCCTXT` is not
guaranteed to be.

## 3. Obstacle one: `CCP` is defined twice

The vendor's recipe for the CBIOS is `ACT OCCBIO05.ASM S=OCCTXT6.AST R=F L=A:`
(`bios141.gen`), so `S=` is how the systext is fed in. Feeding `occtxt6.ast` to
the ROM master fails immediately and *fatally*:

```
 *Error page   0        SORCIM 808x Assembler ver  3.0   00/00/00 00:00  Page   1
  Osborne Computer Corp System Text.                             A:OCCTXT6 .AST
D       = D000      CCP	=	BIOS-1600h	;CCP entry
   1 ERRORs,  716 Labels, 75A7h bytes not used.	Program LWA = 0000h.
```

The master sets `CCP = 0` ("Developed for use with the new cbios") and every
`OCCTXT` we hold defines `CCP = BIOS-1600h`. ACT 3.0 treats the duplicate as
fatal and abandons the assembly. The 1.44-era systext (`SVER = 14`) has
*removed* `MSIZE`/`BIOS`/`BDOS`/`CCP` altogether, which is evidence that this
line was on its way out; the revision contemporary with 12/16/81 is not in the
archive.

`rom13-reassemble.sh` therefore disables that one line in its *copy* of the
systext, leaving the source alone. **`CCP` is not referenced by any ROM source
line** (it appears only in the master's own definition and in comments), so the
change cannot move a byte of object code — and the rev-B control build, whose
master does *not* define `CCP`, needs no such change and passes the same way.
The edit lives in the script rather than in a source file, and the tooling
hazards that surround the build are in §7.

## 4. Obstacle two: `DBE`/`DCE` are ACT 3.5E only

Assembling without a systext gives **241 errors**, all `U` (undefined symbol)
on things like `CMP MTRK`, `CPI EOFC`, `LK C,CR`, `LDK HL,D.TRKR` — the systext
fixes those. With the systext and the `CCP` line disabled the count drops to
**27**, and every one of them is on a `DBE` or `DCE` line:

```
I 0E3B  000000      :xmsg:  DBE     cr,lf,'Program begins'   ! DCE ':'
```

Neither mnemonic exists in ACT 3.0 or 3.2 — not in `DOCOP80.ASM` (which lists
all 130 ACT mnemonics) and not in the mnemonic table inside `ACT80.COM`, which
is plain text: `… DA DB DCR DCX DC DEC DI DJNZ DS DW …`, with nothing between
`DB` and `DCR`.

### What they emit, recovered from a shipped ROM

`OCCROM.IMD` (the rev-B ROM source, 9/12/81) is the disk that makes this
answerable: it carries the *source* (which uses `DBE`/`DCE`), the **shipped
image** `OCCROM0B.COM` (4096 B), and the **full listing** `OCCROM0B.PRN` — so
every DBE/DCE line can be read against the bytes it produced. The listing gives
the address of each line and the ROM gives the bytes:

```
  0D3A  34          DIAMSG:	DBE	'Z'-40h
  0D3B  404040A49E  	DBE	'   ROM DIAGNOSTICs'
  0D4D  1A14A6CAD8  	DBE	cr,lf,'Select Test:'
  0D9E  A6CAD8CAC6  	DCE	'Select (A,B): '
```

Decoding those (and the other eleven lines) gives one rule, with no exceptions:

```
byte = value * 2          DBE — every byte even
byte = value * 2 + 1      DCE — the *last* byte only
```

`0D3B`: `' '`=0x20→0x40 ×3, `'R'`=0x52→0xA4, `'O'`=0x4F→0x9E, … `'s'`=0x73→0xE6.
`0D4D`: `cr`=0x0D→0x1A, `lf`=0x0A→0x14, `'S'`=0x53→0xA6, … `':'`=0x3A→0x74.
`0D9E` (a `DCE`) is the same shift, and its **last** byte is `0x41` = 0x20×2+1 —
the end-of-string marker. The rev-B ROM contains 18 literal `0x7F` bytes, but
none of them falls inside a DBE/DCE string, so the "`7F`, repeat count, char"
escape `rom144.asm` documents is not exercised here.

`tools/research/actdbe.py` rewrites each `DBE`/`DCE` statement into `DB`
statements whose operands are the same expressions multiplied by two, leaving
ACT to evaluate `cr`, `lf` and the rest itself, and keeping the original
statement as a trailing comment so the result is auditable. Two things the
translation has to get right, and both fail silently: the CP/M source is **CRLF**
(emit bare LF and the source text lands in the hex file as object code), and
`!` is ACT's **statement separator** while ACT's local labels are `:name:`
with a leading colon.

## 5. What is verified, and what is not

| Claim | Evidence |
|---|---|
| The disk reads and the source is complete | 19 files, sizes matching the directory, all clean text, all `; END OCCROMn?.???` terminators |
| The format is skew 3 | every sector boundary in `occrom33.asm` chains mid-token at skew 3 and nowhere else; matches `cpmfs.py`/`cpmtools`' own table |
| `DBE` = value×2, `DCE` = value×2 with the last byte +1 | 15/15 lines in the rev-B listing against the shipped `OCCROM0B.COM` |
| **The translated rev-B build reproduces the shipped rev-B ROM, as far as its output survives** | `no ERRORs`; `LENGTH OF THIS ROM IS = 0FC6`, the shipped listing's own number; and **0 differing records** against the shipped hex — **3759 of the shipped image's 4096 bytes byte-identical**. The other 337 bytes are the 16 records lost to §7, so they are *unverified*, not verified |
| The translated 1.3 build is **the ROM** | **NO** — 3 errors remain and 337 bytes are lost to §7; see §6 |
| The built 1.3 image boots | **NO — run, and it fails.** MAME renders it as a full screen of block glyphs, no banner. Method and screenshot: §6.1 |
| The vendor-built rev-B image boots | **YES** — `OCCROM0B.COM` (CRC32 `f5f697c7`) prints `OSBORNE SYSTEM ONE.M / REV B  227` and `INSERT DISK IN DRIVE ... AND PRESS RETURN.` under MAME. §6.1 |

## 6. The control build, and what still stands in the way

The check that matters is the rev-B control build: build rev B from
`OCCROM.IMD` with the same translated source and the same ACT 3.0, and compare
against the `OCCROM0B.COM` that shipped on that very disk.

**The assembler half of that passes.** One `actdbe.py` defect had to be fixed
first: an unmatched optional group in the label regex emitted the literal text
`None` as a label on every unlabelled `DBE`/`DCE` statement, so ACT defined a
symbol called `None` over and over — 25 errors in the 1.3 build, and in the
rev-B build an `LWA` of `0FAAh` against the shipped listing's `0FC6h`, with
labels late in the ROM resolving 28 bytes low. With the regex fixed
(`label or ''`), rev B gives:

```
        'LENGTH OF THIS ROM IS = 0FC6'
  no ERRORs,  696 Labels, 75D7h bytes not used.     Program LWA = EFEFh.
```

`0FC6` is the shipped listing's own number, and **every record the build emits
is byte-identical to the shipped hex** — 0 differing records, checked record by
record. That is **3759 of the shipped image's 4096 bytes verified identical**,
and the 337 bytes that are not are the 16 records §7 loses: unverified, not
verified. So ACT 3.0 plus `actdbe.py` reproduces a shipped Osborne ROM *as far
as its output survives*, and the `DBE`/`DCE` recovery is sound.

**Why that is checkable for rev B and not for 1.3 is the whole point.** The
rev-B disk carries the *answer*: `OCCROM0B.COM`, 4096 bytes, CRC32 `f5f697c7`.
So the damage shows up as a discrepancy against a reference, and what it ate can
be read off that reference. Our own build of the same source is CRC32
`5f48a26a`, and the 337 bytes between the two are exactly §7's damage — nothing
else differs. **For 1.3 there is no reference.** The same defect eats the same
kind of bytes and nothing can tell us what they were.

So the toolchain is *verified* for rev B and only *trusted* for 1.3, and that
difference is not a property of the toolchain — it is a property of whether the
answer already exists. A control build is a check, not a generator: it can tell
you that a build is right, and it cannot supply the bytes a build failed to
produce.

There is a second, independent blocker: **the 1.3 build carries three errors
that the rev-B build of the same code does not.** Even with a clean output path
the 1.3 image would not be right until those are found.

### 6.1 The boot test, which the issue makes the pass/fail

It runs, and it says no. Two things had to be learned to run it at all:

- **`o1keys.sh` segfaults whenever `-bios` is passed** — with *any* ROM,
  including the stock `rev1.40.ud11`. MAME itself runs fine with `-bios`
  (`exit 0`), so it is the harness's VRAM reader, not the guest. The way round
  it is the one `docs/mame-emulation.md` §4 already uses: put the candidate ROM
  in as the **default** BIOS file (`3a10082-00rev-e.ud11`) in a scratch rompath
  and pass no `-bios` at all. MAME prints `WRONG CHECKSUMS` and continues.
- **A screenshot is the only readable output**, since the harness cannot be
  used. A four-line Lua script — `emu.register_frame_done`, then
  `screen:snapshot()` — writes a PNG that can be looked at.

With that, booting a scratch rompath whose default BIOS is **the vendor-built
rev-B image** (`OCCROM0B.COM`, CRC32 `f5f697c7`, extracted from `OCCROM.IMD`)
gives its own sign-on and prompt:

```
 LOSBORNE SYSTEM ONE.M
     REV B   227

 INSERT DISK IN DRIVE LAM AND PRESS RETURN.
```

That is a boot, and the banner matches the rev-B source's own `;VER = REV B` /
`;DATE = 227`. (The stray `L`s are the ROM's
`DB ESC,'L'` / `DB ESC,'M'` video escapes printing literally; rev B escapes with
`ESC`+letter where 1.3 and 1.44 use single control bytes, and MAME's `osborne1`
video model does not decode the older form. Unexplained beyond that, and it is
recorded rather than guessed at.)

Booting **our built 1.3 image** the same way gives a full screen of block
glyphs and no banner. **So the 1.3 image fails its own pass/fail** — the check
#205 asks for, and it fails it — and the failure is
consistent with the two defects above rather than with anything about the
source.

**What stops the comparison passing outright is §7**: the emulated write-back
damages six hex records per build, and the damage is identical on every run, so
neither `--recover-ff` nor a union of runs can put them back. That is now the
*only* thing between us and a certified rev-B reproduction — and therefore
between us and a certified 1.3 image.

**The 1.3 build carries three further errors that are not yet identified.** It
is not the translation (the rev-B build has none), it is not `.siz` (ACT 3.0
handles the `occtxta.ast` that has it, and `occtxt6.ast` does not), and it is
not `~` (NOT) or the `RRC`/`DAA`/`ADC A,40H` instructions — all three were
tested directly. Its `LENGTH` comes out `0FFA`, inside the 4 KB window, so no
overflow error is firing.

**So: a 1.3 image can be built, and `rom13-reassemble.sh` builds one, but it is
not the shipped 1.3 ROM and must not be presented as one.**

**ACT 3.5E is the clean answer and it is unobtainable — the maintainer has
said so, and it is recorded here so nobody goes looking again.** It is in no
local archive (nine `ACT80.COM` copies checked, plus the schorn.ch `act.dsk`)
and not on bitsavers. That matters because it means the two defects below have
no clean fix available, which is the whole basis of the recommendation in
§10.

What is left, in order of how much it would buy:

1. **The output damage in §7** — locate it and the rev-B control build passes,
   and the 1.3 image falls out of the same toolchain.
2. **The three 1.3 errors** — a source-level difference from rev B, still
   unidentified; the rev-B build has none.
3. The **`OCCTXT` revision contemporary with 12/16/81**, in case the equates
   differ from `occtxt6.ast` (the choice is inert for this source, but a later
   revision is not guaranteed to be).
4. The **`OCCRAM2.ASM` from the 1.3 era** — the copy used here is from
   10/9/81.

## 7. A tooling hazard: MAME's floppy write-back

The assembler's hex output arrives on the floppy image with **runs of
`0xDE 0xC0`** where hex digits should be — about six records per build, each
one truncated mid-record with the next record's text running on behind it:

```
:1001C00\xde\xc0\xde\xc0\xde\xc0…:1001D00…
```

`acthex.py` reports them as `not a usable record`; a clean build has none.
Five measurements narrow it down, and the last two are what close the
question:

- the *source* files and `ACT80.COM` read back off the same floppy **byte
  identical** to what was written, so the disk is not generally corrupt, and
  the guest's *read* path is sound;
- **three runs of the same build are byte-identical files** (`md5` equal) —
  deterministic, not flaky, so a union of runs recovers nothing;
- the damaged bytes land at the same **output-file offsets** in both builds
  (0x480 in each) while the *object addresses* underneath them differ (0x1C0
  for rev B, 0x1F0 for 1.3) — so it follows the output stream, not the object;
- every damaged run starts on a **128-byte boundary inside its sector**, i.e. a
  CP/M record boundary;
- it is **identical on a single-density disk (256-byte sectors) and on a
  double-density one (1024-byte sectors)**, and on drive A or drive B — so it
  is not the disk format, the sector size, or the image layout.

That leaves the output path *above* the disk layer: the bytes are already
wrong when they are handed to the emulated controller. It is the same class as
#203's one damaged record — `acthex.py`'s `--recover-ff` exists for the shape
seen there — but this is six records, and their content is not FF, so that
recovery does not apply.

### 7.1 What the ROM 2.0 build measured about the same damage

The ROM 2.0 build (#247) hit this again, in the `C0 DE` shape `acthex.py` names,
and those measurements narrow it further: they rule out the disk, the drive and
the host's speed, and leave the *build's own byte stream*:

- the damaged bytes are in the **raw image the emulator wrote back**, not in the
  read path: `imdinfo.py` fills an *unavailable* sector with `E5`, and these runs
  are `C0 DE`, so the image already held them (measured on `run_b.raw`);
- **sending the hex to the other drive changes nothing.** The same record was
  damaged with `ACT80 B:ROM2 H=B:` and with `ACT80 B:ROM2 H=A:` — a different
  disk, a different allocation, the same `C0 DE` at the same record;
- **throttling changes nothing.** Five `-nothrottle` runs and one run at the
  machine's real speed (`O1_MAME_EXTRA=`) produced byte-identical damage — the
  same result §7's five measurements give for the 1.3 build;
- what *did* change it was the source. The preceding build of the same code — with
  two bytes of inline prose in `rom2.diff` that emit nothing — had **no** damaged
  records at all, and moving that prose out of the diff's code lines (so the
  assembled `ROM2.ASM` went from 90676 bytes to 90607, both inside the same 177
  CP/M blocks) brought the clean build back. The damaged record is the same one
  either way, with the same bytes under it.

So the variable this build can control is the size and content of what the guest
writes, not where it writes it. What that means in practice is recorded where it
bites: `rom2asm.sh`'s step 8 refuses the build rather than padding the hole, and
`rom2blob.py` refuses it a second time — so the next person to hit this gets a
failure, not a silent artifact. `acthex.py --merge` and
`rom13-reassemble.sh`'s `O1_RUNS` remain the union-of-runs answer, and they only
help once the damage moves between runs, which for this shape it did not.

## 8. What upstream gets, and what it should be told

**MAME wants `osb13.bin`, 4096 bytes, inside `osborne1.zip`.** We can hand over
the *source*, the *method*, and the two things we cannot supply. The honest
note to the MAME devs is:

> Osborne 1 ROM 1.3 is not a dump — we do not have a 1.3 machine. It is
> reconstructed from Osborne's own source, which survives on the OCC
> engineering source disk `OSROM13.IMD` (bitsavers; also in the o1next
> repo), read as an 8-inch 77-track FM/MFM disk with CP/M skew 3. The source
> is 10 modules (`OCCROM0..9.ASM`) linked by `OCCROM03.ASM`, plus
> `OCCRAM2.ASM` and the `OCCTXT` systext from `OSUTLSRC.IMD`.
> **The source needs SORCIM ACT 3.5E** — it uses the `DBE`/`DCE` pseudo-ops,
> which 3.0 and 3.2 do not have, and the shipped rev-B ROM on `OCCROM.IMD`
> was itself built with `ver 3.5E`. We recovered what those two pseudo-ops
> emit (each byte is the value shifted left one; `DCE` sets bit 0 of the last
> byte) from that disk's own `OCCROM0B.COM`, and can build a 1.3 image with
> ACT 3.0 and a mechanical source rewrite. The toolchain checks out: a control
> build of the rev-B ROM from that same disk gives no errors and reproduces 3759
> of the shipped image's 4096 bytes byte for byte — the other 337 are lost to a
> defect in the emulation we build under, which damages a handful of hex records
> on the way back out. So the 1.3 image is **not certified**, and it should not
> go into a romset as if it were a dump.
>
> So: this is a *reconstruction recipe*, not a dump. If you have ACT 3.5E the
> rewrite is unnecessary and it finishes in one run — **we have stopped looking
> for it ourselves**, and we will update this note if it ever turns up.

The point of handing that over rather than a hopeful 4 KB blob is that a wrong
`osb13.bin` in a romset is worse than a placeholder: it would be
indistinguishable from a dump afterwards.

## 9. Reproducing this

```sh
# the source, read out of the disk (needs cpmtools)
python3 tools/research/o1imd8.py research/source-code/OSROM13.IMD /tmp/rom13.raw
cd /tmp && cpmls -T raw -f occ8 rom13.raw          # 19 files

# the whole build, plus the rev-B control, under MAME
tools/research/rom13-reassemble.sh --validate /tmp/o1-rom13

# what a build reports
grep -E "ERROR|LWA|not used" /tmp/o1-rom13/act.log
```

`rom13-reassemble.sh` writes `/tmp/o1-rom13/OCCROM03.HEX` (ACT's own output),
`os1-13.rom` (the 4096-byte image), and — with `--validate` — `revb.bin` for
comparison against the shipped `OCCROM0B.COM`. It exits non-zero when the
control build does not match, which is the honest state today.

## 10. What this closes, and what it does not

| | Status |
|---|---|
| `research/source-code/*.IMD` are readable | **Closed** — `tools/research/o1imd8.py`; all seven disks, not just 1.3 |
| The 1.3 source is extracted and indexed | **Closed** — `research/source-code/ROM-13-source/` |
| `DBE`/`DCE` semantics | **Closed** — recovered and verified against the shipped rev-B ROM |
| MAME's `osb13.bin` | **Open, and recommended to stay so** — see below |
| The other `NO_DUMP` slots (A, 1.2, 1.2.1) | **Open, and closer than they were** — `OSBROM.IMD`, `OCCROM.IMD` and `OSBIOSSR.IMD` hold the rev A/rev B source sets and `OCCROM.IMD` even carries a *shipped* rev-B image (`OCCROM0B.COM`, 4096 B). Whether that image is one of MAME's missing slots is a separate question and is not answered here. |

### Recommendation: stop here

**We do not have a 1.3 ROM, and the side quest should stop at this point** —
"record it and stop", which is what #205 allows for.

The reason is not that the source is short of anything. It is that the two
things still in the way are **tooling defects, not knowledge**, and the clean
fix for both is an assembler that is unobtainable:

- the hex output is damaged before it reaches the disk (§7), and
- three errors in the 1.3 build are unidentified while the rev-B build of the
  same code has none (§6).

Against that, the durable half is already banked: the disk reads, the source is
committed, the `DBE`/`DCE` semantics are recovered and verified, the control
build reproduces 3759 of a **shipped** Osborne ROM's 4096 bytes exactly, and the
recipe is written down. None of that needs a 1.3 ROM to be useful, and no project path does
either — we build from the 1.44 source.

**What would justify picking it up again:** a clean output path (a fixed
emulation, or any environment where ACT's hex file survives), or the
`OCCTXT`/`OCCRAM2` of the right vintage. Both are cheap to test and both are
written down here. Until then, more hours buy nothing, and a *wrong* `osb13.bin`
in a romset would be worse than the placeholder it replaced.

Related: #72 (the ROM source index), #70 (ROM inventory), #203 (the 1.44
reassembly and the ACT80 safety copy), `docs/o1-rom-variants.md`.

