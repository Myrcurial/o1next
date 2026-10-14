# Reading the monitor ROM from a real Osborne 1 (#205)

**Why this exists:** MAME carries BIOS A, 1.2, 1.2.1 and 1.3 as `NO_DUMP`, and
the one thing that would settle 1.3 is a **dump from a machine that has one**.
This is the procedure for reading it off a real Osborne 1 — what can be done
from inside the machine, what each route needs, and what the bytes should look
like so the answer is unambiguous.

Nothing here writes to a diskette. Every route below is read-only on the media.

## 1. First, the free answer: read the *upper* line of the sign-on

The sign-on has two lines and **they are framed by different video escapes** —
the upper one by `ESC 'l'` … `ESC 'm'`, the lower one by `ESC ')'` … `ESC '('`.
They are the **underline** pair and the **half-intensity** pair respectively, and
that is why a machine with a faulty dim bit loses exactly the revision line and
nothing else. Confirmed on a real machine: the upper line renders
**underlined**, and the revision line is the one that goes.

The two attributes live in different places, which is the whole reason the
fault is so selective. Underline is **bit 7 of the main video RAM**; dim is
**bit 8 — the dedicated 4116 in bank 3** (`docs/o1-memory-io-map.md` §2). So a
fault in the bank-3 attribute path (that 4116, or the `BIT 9` latch that maps
it) costs the dim line and leaves the underlined one perfectly legible. One
chip, not the video RAM.

So: **the upper line is readable even when the version line is not, and the
upper line differs by revision.**

| Upper line reads | ROM |
|---|---|
| `OSBORNE SYSTEM ONE.` (all caps) | **rev B**, 9/12/81 |
| `Osborne System ONE.` (mixed case) | **1.3**, 12/16/81 |
| `OSBORNE 1` | 1.4 / 1.43 / 1.44 and later |

The lower line, for completeness: ` MONITOR 1.3 ` on 1.3,
`  Rev 1.44 (c) 1983 OCC ` on 1.44, `REV B   227` on rev B.

This is derived from the sources, not from a guess: `occrom1b.asm` line 338 is
`DB 'OSBORNE SYSTEM ONE.'`; the 1.3 source (`occrom13.asm`, `IBMSG`) is
`DB 'Osborne System ONE.'` and then `DB ' MONITOR 1.3  '`; and
`research/roms/os1-144.rom` at `0x1C3` is `OSBORNE 1`.

**If the upper line reads `Osborne System ONE.`, stop and dump it** — that is
the ROM nobody has.

## 1a. The second free test, and the one that matters most: press `^D`

The early ROMs carry a **resident diagnostic section**, entered from the boot
prompt with `^D` (the 1.3 source says so in `occrom73.asm`'s header). The later
ones **do not have it at all**. Checked against every ROM we hold:

| ROM | `^D` diagnostic menu? |
|---|---|
| rev B, 9/12/81 | **yes** — `   ROM DIAGNOSTICs` |
| **1.3**, 12/16/81 | **yes** — `   ROM DIAGNOSTICs` |
| 1.40 | **no** |
| 1.43 | **no** |
| 1.44 | **no** |

So, at the boot prompt, before pressing RETURN:

- **a `ROM DIAGNOSTICs` menu appears** → the ROM is an **early** one: rev B,
  1.2, 1.2.1 or 1.3. Combined with the title test above, that excludes rev B and
  1.3 — so it is **1.2 or 1.2.1, both of which are `NO_DUMP`.** Dump it.
- **nothing happens** → it is 1.40, 1.43 or 1.44, all of which we already hold.
  Nothing is gained and the trip is not worth making.

The menu is bright text, so the faulty dim bit does not hide it, and the test
needs no disk, no tool and no typing beyond `^D`. The 1.3-era menu reads
`A,B Boot Sys / D isk / K ey-vdt / M emory / R ead in test`; a *different* set of
entries is itself evidence of an earlier revision still.

## 2. Reading the bytes: the ROM is *not* visible from CP/M

This is the part that catches people out. `DUMP.COM` and `DDT`'s `D` command
will **not** show the ROM: the monitor ROM is banked into `0000–0FFF` only when
`ROM MODE*` is selected, and a CP/M program runs with the RAM bank in place.
The mechanism is in `docs/o1-memory-io-map.md` §2 and §4:

- `OUT (0),A` selects **bank 2** — the ROM at `0000–0FFF`, the memory-mapped I/O
  window at `2000–2FFF`, and **`4000–FFFF` still bank 1 RAM**;
- `OUT (1),A` selects **bank 1** — main RAM;
- the port number selects and the data byte is ignored;
- an interrupt acknowledge reselects the ROM bank, so **`DI` for the duration of
  the copy**, or a 60 Hz video interrupt will put RAM back under the read;
- the program itself must live **above `4000`**, because with bank 2 selected
  `2000–3FFF` is the I/O window and code there would vanish.

So reading the ROM is a three-instruction preamble plus a copy: select bank 2,
copy `0000–0FFF` to somewhere in `4000+`, select bank 1, return.

## 3. What is on the disks, so nothing is planned around a missing tool

Checked against the in-repo images, both **single-density**:

| Disk | Tools |
|---|---|
| `OS1SYSS.IMD` — *CP/M 2.2 System Disk*, SSSD 92K | `autost copy help movcpm pip setup stat sysgen xdir` — **no `ddt`, no `asm`, no `dump`** |
| `OS1UTLS.IMD` — *CP/M 2.2 Utilities Disk*, SSSD 92K | `asm autost ddt dump ed install load movcpm stat submit sysgen xdir xsub` |
| `OS1XUTLS.IMD` — *Extended utilities* (80-col card) | `autost copy movcpm pip setup sysgen xdir` |

So: **`DDT` is on the Utilities disk, not the System disk.** Boot the System
disk, then swap the Utilities disk into drive A and run `DDT` from it. (CP/M is
already in RAM; nothing is written to either disk.)

## 4. The DDT procedure (needs only the two SD disks above)

`DDT`'s `A` command assembles straight into memory, so the program is *typed in
mnemonics* — no assembler, no source file, no disk write. Type it at `0x4000`
and it copies the ROM to `0x5000`, where `DDT`'s `D` can show it.

```
A>DDT
-DDT
-A4000
4000 DI
4001 XRA A
4002 OUT 0
4004 LXI H,0000
4007 LXI D,5000
400A LXI B,1000
400D MOV A,M
400E STAX D
400F INX H
4010 INX D
4011 DCX B
4012 MOV A,B
4013 ORA C
4014 JNZ 400D
4017 MVI A,1
4019 OUT 1
401B EI
401C RET
401D                     <- a blank line ends assembly
-G4000
-D51C0,5200             <- the banner, copied
```

Bytes, so the assembled listing can be checked by eye:

```
4000 F3        DI
4001 AF        XRA A
4002 D3 00     OUT 0        ; bank 2: ROM at 0000-0FFF
4004 21 00 00  LXI H,0000
4007 11 00 50  LXI D,5000
400A 01 00 10  LXI B,1000
400D 7E        MOV A,M      <- loop
400E 12        STAX D
400F 23        INX H
4010 13        INX D
4011 0B        DCX B
4012 78        MOV A,B
4013 B1        ORA C
4014 C2 0D 40  JNZ 400D
4017 3E 01     MVI A,1
4019 D3 01     OUT 1        ; bank 1: back to RAM
401B FB        EI
401C C9        RET
```

`D51C0` then shows `0000+1C0`'s bytes — the banner. `MONITOR 1.3` in hex is
`4D 4F 4E 49 54 4F 52 20 31 2E 33`; `OSBORNE 1` is
`4F 53 42 4E 4F 52 4E 45 20 31` — either is unmistakable in a dump.

**Honest status:** this is *reasoned from the sources and the memory map*, not
yet run end to end. It was attempted in MAME and the harness
(`tools/research/o1keys.lua`) segfaulted partway through typing the program in —
the harness's known VRAM-reader fault, not the program. What has been checked
directly is the *mechanism* (`docs/o1-memory-io-map.md` §4 was measured on the
running machine with `tools/check_o1_map.sh`) and the byte offsets below, which
come from the shipped ROMs.

## 5. Fingerprints, so the answer is not a judgement call

Offsets are into the 4096-byte image.

| ROM | Offset | Bytes | Text |
|---|---|---|---|
| 1.44 | `0x1C3` | `4F 53 42 4F 52 4E 45 20 31` | `OSBORNE 1` |
| 1.44 | `0x1F7` | `52 65 76 20 31 2E 34 34 …` | `Rev 1.44 (c) 1983 OCC` |
| 1.43 | `0x1F7` | `52 65 76 20 31 2E 34 33 …` | `Rev 1.43 (c) 1982 OCC` |
| **1.3** | `0x19E` | `4F 73 62 6F 72 6E 65 20 53 79 73 74 65 6D 20 4F 4E 45 2E` | `Osborne System ONE.` |
| **1.3** | `0x1D2` | `20 4D 4F 4E 49 54 4F 52 20 31 2E 33 20 20` | ` MONITOR 1.3  ` |
| **1.3** | `0x0F4` | `63 2E 20 31 39 38 31 20 4F 43 43` | `c. 1981 OCC` |
| rev B | — | from `occrom1b.asm` | `OSBORNE SYSTEM ONE.` (caps) |

**And check the encoding of the *messages*, not just the text.** The banner is
plain ASCII in every revision. What differs is how the **message strings** are
written: rev B and 1.3 use the `DBE`/`DCE` pseudo-ops, so each byte is stored
**doubled** (`value * 2`, which is why `   ROM DIAGNOSTICs` appears as
`40 40 40 A4 9E 9A …`), while 1.44 uses `DB`/`DC` throughout and stores plain
ASCII. Shift a doubled string right one bit to read it. See
`docs/rom-13-reconstruction.md` §4.

The 1.3 offsets come from the reconstructed image, and **not** from the damaged
regions (`0x1F0`, `0x8B0`, `0xA80`, `0xAB0`, `0xFA0`, `0xFD0` — see
`docs/rom-13-reconstruction.md` §7), so they are trustworthy. `c. 1981 OCC` at
`0x0F4` is a `COPYR:` label the 1.3 ROM never references — dead data, but a
unique and very convenient fingerprint.

A rev-B image from `OCCROM.IMD` (`OCCROM0B.COM`, CRC32 `f5f697c7`) is also on
record, and it boots — `docs/o1-rom-variants.md`.

## 6. A dead end, recorded so it is not repeated

**`SETUP.COM` does not identify the ROM.** It offers *"press M to get source
from memory"*, which reads the running system's **CBIOS configuration block**,
not the monitor ROM — its six items (printer, baud, screen size, auto-scroll,
function keys, arrow keys) are the CBIOS's, and its own banner (`Rev 2.2`) is
`SETUP`'s version, not the ROM's. Checked by running it under MAME. The ROM and
the system disk version independently; that is the same trap as reading
`CBIOSV` out of the CBIOS.

## 7. For a real dump — what MAME actually wants

Everything above is a *software copy through the machine*: fine for
identification, and usable as evidence, but it is not a chip read.

**`UD11` is a socketed 2732.** Pulling it and reading it in an EPROM programmer
is the only true dump, and it needs no software, no banking subtleties and no
serial transfer. That is the artifact to hand upstream; the DDT copy is the
thing to do first because it takes two minutes and tells you whether the trip
is worth making.

Getting a 4 KB file off the machine otherwise means either transcribing a hex
dump from the screen, or a serial capture — the ROM's own SIO init is
`SI.S16`, "16x clock for 1200 baud" (`occrom13.asm`), and CP/M's `PIP` can send
a file to `PUN:`/`LST:`, but binary down a 1200-baud line wants a cable and
care.

## 7a. Status: the machine this was written for is out of play

The single-density machine that prompted this doc is **out of play** — it blew
a RIFA capacitor in the PSU. The `^D` test in §1a was **never run**, so its ROM
was **never identified**, and the question of whether it held a `NO_DUMP`
revision is still open. The other two machines on hand are 1.44, which is
already held (`docs/o1-rom-variants.md`), so there is at present **no hardware
route to any `NO_DUMP` slot** — §1a and §4 are procedures waiting on a machine,
not instructions for one.

One repository fact worth recording with it: **the tree holds no power-supply
material.** The Osborne 1 Technical Manual in-repo
(`research/osborne1/2F00153-01_Osborne1TechnicalManual_1982.pdf`) has only
**§1.2 "Power On"** — two pages of power-up procedure, no supply theory and no
schematic. The only mention of the PSU anywhere in the tree is a design note in
`docs/design/o1next-lunchbox-concept.svg` recording that the original supply "and
its RIFA caps" are retired in that concept.

## 8. What the result would settle

- **A 1.3 dump fills `osb13.bin`** and closes the `NO_DUMP` slot outright.
- **It would also grade the reconstruction in `docs/rom-13-reconstruction.md`.**
  Our built 1.3 image is 3759/4096 bytes from being certified; a real dump would
  say whether the recovered `DBE`/`DCE` rule, the `occtxt6.ast` assumption and
  the 28-byte question were right — a *positive* answer would validate the
  method for rev B, BIOS A, 1.2 and 1.2.1 as well, and a negative one would say
  exactly where the method is wrong.

Related: #205, #70, #72, #222, `docs/o1-rom-variants.md`,
`docs/o1-memory-io-map.md`, `docs/rom-13-reconstruction.md`.

