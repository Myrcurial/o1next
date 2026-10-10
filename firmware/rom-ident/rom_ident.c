/* ROM identity + personality gate -- implementation.  See rom_ident.h.
 *
 * Pure logic: no hardware access, so this compiles and runs on the host.
 * The hardware half (reading UD11/UA15 and CRC32-ing the bytes) is described in
 * README.md and lands with the interposer firmware.
 */
#include "rom_ident.h"

#include <stdio.h>

/* What each personality needs.  `preferred_rom` is what a ROM overlay would
 * serve if one is ever built -- nothing serves one today, the gate refuses. */
static const o1_personality_rom_req_t REQS[O1_PERS_COUNT] = {
    [O1_PERS_DRIVE_C]         = { 1, O1_ROM_OCC_144, 0 },
    [O1_PERS_VIRTUAL_PRINTER] = { 1, O1_ROM_OCC_144, 0 },
    [O1_PERS_VIDEO]           = { 0, O1_ROM_UNKNOWN, 4 },
    [O1_PERS_VIRTUAL_IO]      = { 0, O1_ROM_UNKNOWN, 0 },
    [O1_PERS_BUS_ANALYZER]    = { 0, O1_ROM_UNKNOWN, 0 },
};

static const char *const PERSONALITY_NAMES[O1_PERS_COUNT] = {
    [O1_PERS_DRIVE_C]         = "Drive C (IEEE-488 storage)",
    [O1_PERS_VIRTUAL_PRINTER] = "virtual printer (IEEE-488)",
    [O1_PERS_VIDEO]           = "video / ScreenPac",
    [O1_PERS_VIRTUAL_IO]      = "virtual I/O peripherals",
    [O1_PERS_BUS_ANALYZER]    = "bus analyzer",
};

#define SAY(...)                                                       \
    do {                                                               \
        if (why && why_len)                                            \
            snprintf(why, why_len, __VA_ARGS__);                       \
    } while (0)

const o1_personality_rom_req_t *o1_personality_requirement(o1_personality_t p)
{
    return (p < O1_PERS_COUNT) ? &REQS[p] : NULL;
}

const char *o1_personality_name(o1_personality_t p)
{
    return (p < O1_PERS_COUNT) ? PERSONALITY_NAMES[p] : "unknown personality";
}

const char *o1_gate_result_name(o1_gate_result_t r)
{
    switch (r) {
    case O1_GATE_OK:       return "ok";
    case O1_GATE_DEGRADED: return "degraded";
    case O1_GATE_REFUSED:  return "refused";
    }
    return "?";
}

const o1_rom_info_t *o1_rom_lookup(uint32_t crc32, size_t size)
{
    size_t i;
    for (i = 0; i < O1_ROM_TABLE_LEN; i++) {
        if (o1_rom_table[i].crc32 == crc32 &&
            (size_t)o1_rom_table[i].size == size)
            return &o1_rom_table[i];
    }
    return NULL; /* not an image we have ever seen */
}

static const o1_rom_info_t *rom_by_id(o1_rom_id_t id)
{
    size_t i;
    for (i = 0; i < O1_ROM_TABLE_LEN; i++) {
        if (o1_rom_table[i].id == id)
            return &o1_rom_table[i];
    }
    return NULL;
}

o1_gate_result_t o1_personality_gate(o1_personality_t p,
                                     const o1_rom_info_t *monitor,
                                     const o1_rom_info_t *chargen,
                                     char *why, size_t why_len)
{
    const o1_personality_rom_req_t *req;
    const char *pname;
    int identified;

    if (why && why_len)
        why[0] = '\0';

    if (p >= O1_PERS_COUNT) {
        SAY("unknown personality; refusing.");
        return O1_GATE_REFUSED;
    }
    req = &REQS[p];
    pname = PERSONALITY_NAMES[p];

    /* A personality that does not read the monitor ROM cannot be constrained by
     * it: the analyzer is passive, and the virtual I/O peripherals own their own
     * decode windows.  Gating those on the ROM would refuse work for no reason. */
    if (req->requires_ieee488 == 0 && req->min_video_kb == 0) {
        SAY("%s: independent of the fitted monitor ROM.", pname);
        return O1_GATE_OK;
    }

    identified = (monitor != NULL && monitor->id != O1_ROM_UNKNOWN);

    /* A requirement can only be checked against a ROM we can name.  That covers
     * every machine fitted with a BIOS revision nobody has dumped (A / 1.2 /
     * 1.2.1 / 1.3), which is why "unknown" is never treated as "probably fine". */
    if (!identified) {
        if (req->requires_ieee488) {
            if (monitor == NULL)
                SAY("%s: no monitor ROM was read, so the IEEE-488 driver cannot "
                    "be checked; refusing rather than guessing.", pname);
            else
                SAY("%s: the fitted monitor ROM (CRC32 %08lx) is not an image we "
                    "have, so its IEEE-488 driver cannot be checked; refusing "
                    "rather than guessing.", pname,
                    (unsigned long)monitor->crc32);
            return O1_GATE_REFUSED;
        }
        /* The only remaining requirement is the video window, and an
         * unidentified ROM means an unknown window: run, but say so. */
        SAY("%s: the fitted ROM is not identified, so its video window is "
            "unknown; assuming the full %u KiB and rendering accordingly.",
            pname, (unsigned)req->min_video_kb);
        return O1_GATE_DEGRADED;
    }

    if (monitor->kind != O1_ROM_KIND_MONITOR) {
        SAY("%s: the UD11 probe read \"%s\", which is not a monitor ROM; the "
            "probe result is inconsistent, so nothing is trusted.",
            pname, monitor->name);
        return O1_GATE_REFUSED;
    }

    /* The IEEE-488 constraint.  Drive C and the printer both need the ROM's
     * driver; OZROM 1E replaced those routines with crash code. */
    if (req->requires_ieee488 && monitor->ieee488 != O1_CAP_PRESENT) {
        const o1_rom_info_t *want = rom_by_id(req->preferred_rom);
        const char *detail = (monitor->ieee488 == O1_CAP_ABSENT)
            ? "does not have the IEEE-488 driver"
            : "has not been verified to have the IEEE-488 driver";
        if (want != NULL)
            SAY("%s needs a monitor ROM with the IEEE-488 driver, but the fitted "
                "ROM \"%s\" %s. Fit monitor ROM %s instead.",
                pname, monitor->name, detail, want->name);
        else
            SAY("%s needs a monitor ROM with the IEEE-488 driver, but the fitted "
                "ROM \"%s\" %s.", pname, monitor->name, detail);
        return O1_GATE_REFUSED;
    }

    /* The video window.  A smaller or unknown window degrades the video
     * personality rather than breaking it, so say so and carry on. */
    if (req->min_video_kb != 0 && monitor->video_kb < req->min_video_kb) {
        if (monitor->video_kb == 0)
            SAY("%s: the video window of \"%s\" is not known; assuming the full "
                "%u KiB and rendering accordingly.",
                pname, monitor->name, (unsigned)req->min_video_kb);
        else
            SAY("%s: \"%s\" gives the video only %u KiB (F000-FBFF; the top 1 KiB "
                "belongs to the ROM's keyboard features), not the %u KiB "
                "assumed.", pname, monitor->name,
                (unsigned)monitor->video_kb, (unsigned)req->min_video_kb);
        return O1_GATE_DEGRADED;
    }

    /* Video needs a font as well as a window. */
    if (p == O1_PERS_VIDEO) {
        if (chargen == NULL || chargen->id == O1_ROM_UNKNOWN) {
            SAY("%s: no character generator was identified in UA15, so the font "
                "is unknown; the socket tap will be read at init.", pname);
            return O1_GATE_DEGRADED;
        }
        if (chargen->kind != O1_ROM_KIND_CHARGEN) {
            SAY("%s: the UA15 probe read \"%s\", which is not a character "
                "generator; the probe result is inconsistent, so nothing is "
                "trusted.", pname, chargen->name);
            return O1_GATE_REFUSED;
        }
    }

    SAY("%s: ok, monitor ROM \"%s\".", pname, monitor->name);
    return O1_GATE_OK;
}
