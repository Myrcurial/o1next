# rom-ident — identify the fitted ROM, and gate personalities on it

**Issue:** #86. **Status:** the identity table and the gate are implemented and
tested on the host; the hardware half (reading the sockets) is described here but
lands with the interposer firmware, because it needs a board.

Some personalities are only valid with some monitor ROMs, and that is not a
constraint a user should have to remember. The interposer already sits in the Z80
socket, so it can identify the fitted ROM at boot and refuse the combinations
that cannot work.

## Why the gate exists

| Personality | Needs | Refused by |
|---|---|---|
| Drive C / TurboPac (#6, #22, #84) | a monitor ROM with the IEEE-488 driver | OZROM 1E (driver removed), Nuevo 1.51 (unverified), any unidentified ROM |
| virtual printer (#19) | the same IEEE-488 driver | the same |
| video / ScreenPac (#24) | a 4 KiB video window and a known font | not refused — **degraded** to a warning under OZROM 1E (3 KiB window) |
| virtual I/O peripherals (#18, #21, #23) | nothing | — |
| bus analyzer (#17) | nothing | — |

The printer is the less obvious case: OZROM 1E stubs the ROM's printer entry
points `0187-0190` to `OR 0FFH; RET`, so it cannot print over IEEE-488 either.
The evidence for every one of these is in `docs/o1-rom-variants.md` section
"Personality-relevant properties" — including the byte-level checks.

**A gate that half-works is worse than one that refuses**, so an unidentified ROM
is never assumed good. Every result carries a message that can be shown to the
user verbatim:

```
refused  Drive C (IEEE-488 storage)  [OZROM 1E]
         Drive C (IEEE-488 storage) needs a monitor ROM with the IEEE-488
         driver, but the fitted ROM "Micro Management OZROM 1E" does not have
         the IEEE-488 driver. Fit monitor ROM 1.44 instead.
degraded video / ScreenPac           [OZROM 1E]
         video / ScreenPac: "Micro Management OZROM 1E" gives the video only
         3 KiB (F000-FBFF; the top 1 KiB belongs to the ROM's keyboard
         features), not the 4 KiB assumed.
```

## The probe (hardware half, not yet implemented)

Read the two ROM sockets, CRC32 the bytes, look the result up:

| Socket | Size | Read how |
|---|---|---|
| UD11 (monitor) | 4096 | `/BUSRQ` bus master read of `0000-0FFF` |
| UA15 (char-gen) | 2048 | socket tap (the ScreenPac-style tap, #44) |

Two constraints decide how the UD11 read has to work, and they come from the
machine rather than from preference:

1. **Never drive I/O addresses `0x00-0x03`.** The bank latch decodes only the two
   low address bits and *ignores the data byte*, so any `OUT (0),A` / `OUT (1),A`
   toggles banks — including one emitted by accident. `docs/o1-memory-io-map.md`
   §4 makes this a standing rule for the interposer.
2. **Do not try to select the ROM bank.** It is chosen by hardware: power-on
   reset, the NMI flip-flop chain, and M1/IRQ-acknowledge qualification. The ROM
   source contains no `OUT 0`/`OUT 1` at all — the firmware never selects its own
   bank (`docs/o1-rom-source.md`). It also cannot be latched and assumed: the
   bank is re-derived on every instruction fetch.

So the probe does not *bank in* the ROM; it reads while the ROM bank is already
live. At boot, and again at the idle `A>` prompt (where the machine parks in a ROM
polling loop with bank 2 selected), `0000-0FFF` *is* the monitor ROM. Bus-master
it with `/BUSRQ` and read 4096 bytes.

**Open question (#86): is that safe on every revision?** The decode is sloppy
(MAME models it loosely) and the bank is re-derived per fetch, so the read window
has to be established against a real machine before the personality depends on
it. Until then the gate's refusal path is the safe default.

`size` is part of the identity key, not just the CRC: a 4 KiB monitor image and a
2 KiB char-gen image with the same CRC would otherwise be indistinguishable.

## The gate, and what is deliberately not built

The gate **refuses or degrades loudly**; it does not fix the machine. The
requirement for each personality is modelled separately from the check
(`o1_personality_rom_req_t`), including `preferred_rom` — the image an overlay
would serve (Drive C names OCC 1.44). Nothing serves an overlay today: ROM
shadowing would need the `/WAIT` and data-drive paths proven on hardware, and
the decision (2026-10-10) was to refuse now and keep the model so an overlay
personality can be added later without a redesign.

## Files

| File | Origin |
|---|---|
| `rom_table.h`, `rom_table.c` | **generated** — `tools/gen_rom_table.py`, from `docs/o1-rom-variants.md` |
| `rom_ident.h`, `rom_ident.c` | hand-written: lookup, requirements, gate |
| `test_rom_ident.c` | hand-written host tests |
| `run_tests.sh` | builds and runs them |

Do not edit the generated files: `python3 tools/gen_rom_table.py --check` fails CI
if they drift from the document or from the archive, exactly as
`tools/check_schematics.py` does for the generated KiCad schematics.

## Build and test

No board, no SDK, no dependencies — plain C99, so the logic is testable today:

```
firmware/rom-ident/run_tests.sh          # all tests
firmware/rom-ident/run_tests.sh -v       # ... and print the gate decisions
```

The tests read the real ROM files out of the archive, CRC32 them, and confirm the
table identifies each one — the document's own rule (two sources agreeing on a
CRC) applied mechanically. They also drive the gate through the combinations
above, including the refusals and the OZROM video degradation.

To regenerate the table after the document changes:

```
python3 tools/gen_rom_table.py           # rewrite the generated files
python3 tools/gen_rom_table.py -v        # ... listing every verified CRC
```
