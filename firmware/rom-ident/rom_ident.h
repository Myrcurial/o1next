/* ROM identity probe and personality gate for the O1 interposer (#86).
 *
 * Why this exists
 * ---------------
 * Some interposer personalities are only valid with some monitor ROMs, and that
 * is not a constraint the user should have to remember:
 *
 *   - Drive C and the virtual printer both need the ROM's IEEE-488 driver, which
 *     OZROM 1E does not have (docs/o1-rom-variants.md, "Personality-relevant
 *     properties").
 *   - The video personality has to cope with OZROM's 3 KiB video window.
 *   - A machine fitted with a BIOS revision nobody has ever dumped cannot be
 *     identified at all, so nothing can be assumed about it.
 *
 * So the interposer identifies the fitted ROM at boot (it is already in the Z80
 * socket) and gates the personalities on the result.  A gate that half-works is
 * worse than one that refuses: every refusal carries a message that can be shown
 * to the user verbatim.
 *
 * This file is pure logic over the generated table -- no hardware access -- so it
 * builds and is tested on the host (see test_rom_ident.c).
 */
#ifndef O1_ROM_IDENT_H
#define O1_ROM_IDENT_H

#include <stddef.h>
#include <stdint.h>

#include "rom_table.h"

/* Personalities that care which ROM is fitted.  Deliberately not every
 * personality: the bus analyzer and the virtual I/O peripherals do not care. */
typedef enum {
    O1_PERS_DRIVE_C = 0,     /* IEEE-488 storage: Drive C / TurboPac (#6, #22, #84) */
    O1_PERS_VIRTUAL_PRINTER, /* Centronics-on-IEEE-488 capture -> PDF (#19) */
    O1_PERS_VIDEO,           /* ScreenPac-style video + HDMI out (#24) */
    O1_PERS_VIRTUAL_IO,      /* the 2300+ virtual I/O peripherals (#18, #21, #23) */
    O1_PERS_BUS_ANALYZER,    /* passive capture (#17) */
    O1_PERS_COUNT
} o1_personality_t;

typedef enum {
    O1_GATE_OK = 0,   /* run it */
    O1_GATE_DEGRADED, /* run it, with a limitation the user should see */
    O1_GATE_REFUSED   /* do not run it; show the reason */
} o1_gate_result_t;

/* What a personality needs from the fitted ROMs.  Kept separate from the check
 * itself so that a future ROM-overlay personality can read the requirement and
 * satisfy it (serve `preferred_rom`) instead of re-deriving it from scratch.
 * Nothing serves an overlay today: the gate refuses. */
typedef struct {
    uint8_t     requires_ieee488; /* 1 = the ROM must have the driver */
    o1_rom_id_t preferred_rom;    /* what an overlay would serve, or O1_ROM_UNKNOWN */
    uint8_t     min_video_kb;     /* video window needed, 0 = does not care */
} o1_personality_rom_req_t;

const o1_personality_rom_req_t *o1_personality_requirement(o1_personality_t p);
const char *o1_personality_name(o1_personality_t p);
const char *o1_gate_result_name(o1_gate_result_t r);

/* The gate.
 *
 * `monitor` is the image read from UD11 (4 KiB) and `chargen` the one read from
 * UA15 (2 KiB); either may be NULL if that socket was not read.  `why` receives
 * a message for *every* result, so a caller can log a success and show a refusal
 * verbatim.  Returns O1_GATE_REFUSED for anything it cannot verify -- an
 * unidentified ROM is never assumed good.
 */
o1_gate_result_t o1_personality_gate(o1_personality_t p,
                                     const o1_rom_info_t *monitor,
                                     const o1_rom_info_t *chargen,
                                     char *why, size_t why_len);

/* Convenience: identify an image read from a socket, by the (CRC32, size) key.
 * Returns NULL when the pair is not in the table. */
const o1_rom_info_t *o1_rom_lookup(uint32_t crc32, size_t size);

#endif /* O1_ROM_IDENT_H */
