Files extracted from `../OSROM13.IMD` and `../OSUTLSRC.IMD` (bitsavers) with
`tools/research/o1imd8.py` + `cpmtools`; see `docs/rom-13-reconstruction.md`.

`occrom03.asm` … `occrom93.asm` and `occbio03.asm` … `occbio83.asm` come from
`OSROM13.IMD` (comment: `rom 1.3, cbios .3   osborne source 12/16/81`), which
is an **8-inch** disk — 77 tracks, track 0 FM 26 x 128, tracks 1-76 MFM
8 x 1024, CP/M 2.2 with **skew 3**.

Two files the build needs are **not** on that disk and come from
`OSUTLSRC.IMD` instead: `occram2.asm` (the `;RAM LOCATIONS` module that
`OCCROM03.ASM` links) and `occtxt6.ast` (the `OCCTXT` systext). `occtxt6.ast`
is the nearest revision we hold to 12/16/81 and is an assumption — see
`docs/rom-13-reconstruction.md` §2.

The files are byte-for-byte as extracted, including the trailing CP/M `0x1A`
padding; `cpmcp` puts them back on a floppy verbatim, which is what the build
expects.
