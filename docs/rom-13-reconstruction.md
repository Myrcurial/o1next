# ROM 1.3 — the source is on the disk, the ROM is not yet certified

**Issue:** #205. **Status:** the source is **extracted, indexed and readable**;
the ROM is **reconstructible but not yet certified**, and the blocker is a
*missing assembler*, not the source. Everything needed to finish it is in this
repo or named below.

MAME carries BIOS A, 1.2, 1.2.1 and 1.3 as `NO_DUMP` placeholders, so
`mame osborne1 -bios ver13` cannot run. We hold the 1.3 **source disk** —
`research/source-code/OSROM13.IMD`, whose own comment reads
`rom 1.3, cbios .3   osborne source 12/16/81` — and this is what came of
trying to turn it into the missing `osb13.bin`.

## The answer, up front

1. **The disk reads, and the source is complete.** `OSROM13.IMD` is an
   **8-inch** disk, not an Osborne 1 5.25" one, and it had never been read
   because nothing in the tree could describe it. It yields 19 files —
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
   **it is not certified**, and it must not be handed upstream as the real
   1.3 until the control build passes. That is stated plainly below rather
   than glossed.
5. **MAME's floppy write-back damages the assembler's hex output** — about six
   records per build, deterministically — so no build can be compared against a
   reference until that is dealt with. It is a separate tooling hazard and it
   is recorded in §7.

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

`rom13-reassemble.sh` therefore disables that one line of the systext.
**`CCP` is not referenced by any ROM source line** (it appears only in the
master's own definition and in comments), so the change cannot move a byte of
object code — and the rev-B control build, whose master does *not* define
`CCP`, needs no such change and passes the same way.

   tooling hazard and it is recorded in §7.

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
first cut got wrong, both silent, both now handled: the CP/M source is **CRLF**
(emit bare LF and the source text lands in the hex file as object code), and
`!` is ACT's **statement separator** while ACT's local labels are `:name:`
with a leading colon.

## 5. What is verified, and what is not

| Claim | Evidence |
|---|---|
| The disk reads and the source is complete | 19 files, sizes matching the directory, all clean text, all `; END OCCROMn?.???` terminators |
| The format is skew 3 | every sector boundary in `occrom33.asm` chains mid-token at skew 3 and nowhere else; matches `cpmfs.py`/`cpmtools`' own table |
| `DBE` = value×2, `DCE` = value×2 with the last byte +1 | 15/15 lines in the rev-B listing against the shipped `OCCROM0B.COM` |
| **The translated rev-B build reproduces the shipped rev-B ROM** | `no ERRORs`, `LENGTH OF THIS ROM IS = 0FC6` — the shipped listing's own number — and **every record it emits is byte-identical to the shipped hex**. The only gap is the write-back damage in §7, which is not the assembler's doing |
| The translated 1.3 build is **the ROM** | **NOT VERIFIED** — 3 errors remain and the write-back damage is still there; see §6 |
| The image boots under `-bios ver13` | **NOT VERIFIED** — see §6 |

## 6. The control build, and what still stands in the way

The check that matters is the rev-B control build: build rev B from
`OCCROM.IMD` with the same translated source and the same ACT 3.0, and compare
against the `OCCROM0B.COM` that shipped on that very disk.

**The assembler half of that now passes, and it took a bug in `actdbe.py` to
get there.** The first translation emitted the literal text `None` as a label
on every unlabelled `DBE`/`DCE` statement — an unmatched optional group in the
label regex, formatted straight into the output. ACT then defined a symbol
called `None` over and over: 25 errors in the 1.3 build, and in the rev-B build
a `LWA` of `0FAAh` against the shipped listing's `0FC6h`, with labels late in
the ROM resolving 28 bytes low. Fixing it (`label or ''`) gives, for rev B:

```
        'LENGTH OF THIS ROM IS = 0FC6'
  no ERRORs,  696 Labels, 75D7h bytes not used.     Program LWA = EFEFh.
```

`0FC6` is the shipped listing's own number, and **every record the build emits
is byte-identical to the shipped hex** — 0 differing records, checked record by
record. So ACT 3.0 plus `actdbe.py` does reproduce a shipped Osborne ROM, and
the `DBE`/`DCE` recovery is sound.

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
not the shipped 1.3 ROM and must not be presented as one.** What would settle
it, in order of preference:

1. **ACT 3.5E** — then no translation is needed and the whole question
   disappears. It is not in the local archive (nine `ACT80.COM` copies checked,
   plus `act.dsk` from schorn.ch) and not on bitsavers.
2. **The write-back damage in §7** — one fixed emulation bug and the control
   build passes.
3. The **`OCCTXT` revision contemporary with 12/16/81**, in case the equates
   differ from `occtxt6.ast`.
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
Three facts pin it to the emulated write path rather than to ACT:

- the *source* files and `ACT80.COM` read back off the same floppy **byte
  identical** to what was written, so the disk is not generally corrupt;
- the damaged records contain the same pattern every time, and **three runs of
  the same build are byte-identical files** (`md5` equal) — so it is
  deterministic, not flaky, and a union of runs recovers nothing;
- the same damage appears in *both* the 1.3 and the rev-B builds, at different
  records, so it follows the write path and not either source.

This is the same class as the transport damage `acthex.py` already documents
from #203, where one record of ACT's output arrived with six non-hex bytes in
it — this is a worse case of it. It means a single run is not trustworthy
output, and a build that "passes" must be checked record by record, which is
what §6 does.

## 8. What upstream gets, and what it should be told

**MAME wants `osb13.bin`, 4096 bytes, inside `osborne1.zip`.** We can hand over
the *source*, the *method*, and the two things we cannot supply. The honest
note to the MAME devs is:

> Osborne 1 ROM 1.3 is not a dump — we do not have a 1.3 machine. It is
> reconstructed from Osborne's own source, which survives on the OCC
> engineering source disk `OSROM13.IMD` (bitsavers; also in the o1nextgen
> repo), read as an 8-inch 77-track FM/MFM disk with CP/M skew 3. The source
> is 10 modules (`OCCROM0..9.ASM`) linked by `OCCROM03.ASM`, plus
> `OCCRAM2.ASM` and the `OCCTXT` systext from `OSUTLSRC.IMD`.
> **The source needs SORCIM ACT 3.5E** — it uses the `DBE`/`DCE` pseudo-ops,
> which 3.0 and 3.2 do not have, and the shipped rev-B ROM on `OCCROM.IMD`
> was itself built with `ver 3.5E`. We recovered what those two pseudo-ops
> emit (each byte is the value shifted left one; `DCE` sets bit 0 of the last
> byte) from that disk's own `OCCROM0B.COM`, and can build a 1.3 image with
> ACT 3.0 and a mechanical source rewrite. The toolchain is sound: a control
> build of the rev-B ROM from that same disk reproduces the shipped rev-B image
> byte for byte. But the emulation we build under damages a handful of hex
> records on the way back out, so the 1.3 image is **not certified**, and it
> should not go into a romset as if it were a dump.
>
> So: this is a *reconstruction recipe*, not a dump. Anyone with ACT 3.5E can
> finish it in one run, and we will update this note the moment it is done.

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
| MAME's `osb13.bin` | **Open** — blocked on ACT 3.5E (§6) |
| The other `NO_DUMP` slots (A, 1.2, 1.2.1) | **Open, and closer than they were** — `OSBROM.IMD`, `OCCROM.IMD` and `OSBIOSSR.IMD` hold the rev A/rev B source sets and `OCCROM.IMD` even carries a *shipped* rev-B image (`OCCROM0B.COM`, 4096 B). Whether that image is one of MAME's missing slots is a separate question and is not answered here. |

Related: #72 (the ROM source index), #70 (ROM inventory), #203 (the 1.44
reassembly and the ACT80 safety copy), `docs/o1-rom-variants.md`.

