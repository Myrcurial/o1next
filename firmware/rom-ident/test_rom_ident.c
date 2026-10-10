/* Host tests for the ROM identity table and the personality gate (#86).
 *
 * Build and run (no board, no SDK -- plain C):
 *
 *     cc -std=c99 -Wall -Wextra -o /tmp/t \
 *        firmware/rom-ident/rom_ident.c firmware/rom-ident/rom_table.c \
 *        firmware/rom-ident/test_rom_ident.c
 *     /tmp/t .            # repo root as argv[1]
 *
 * Two things are being tested:
 *
 *   1. The identity chain, end to end: for every entry in the generated table,
 *      read the file the entry names, CRC32 the bytes, and confirm the lookup
 *      returns that same entry.  This is the document's identification rule
 *      (two sources agreeing on a CRC) checked against the archive, and it also
 *      proves no two entries share a (CRC32, size) key.
 *   2. The gate: Drive C and the printer must refuse under OZROM rather than
 *      half-work, video must degrade rather than refuse, and the passive
 *      personalities must not be gated on the ROM at all.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "rom_ident.h"

static int failures;

#define CHECK(cond, ...)                                               \
    do {                                                               \
        if (!(cond)) {                                                 \
            printf("  FAIL line %d: ", __LINE__);                      \
            printf(__VA_ARGS__);                                       \
            printf("\n");                                              \
            failures++;                                                \
        }                                                              \
    } while (0)

static uint32_t crc32_of(const unsigned char *p, size_t n)
{
    uint32_t crc = 0xFFFFFFFFu;
    size_t i;
    int k;
    for (i = 0; i < n; i++) {
        crc ^= p[i];
        for (k = 0; k < 8; k++)
            crc = (crc >> 1) ^
                  (0xEDB88320u & (uint32_t)(-(int32_t)(crc & 1u)));
    }
    return ~crc;
}

static unsigned char *read_file(const char *path, size_t want)
{
    FILE *f = fopen(path, "rb");
    unsigned char *buf;
    size_t got;
    if (!f)
        return NULL;
    buf = malloc(want);
    if (!buf) {
        fclose(f);
        return NULL;
    }
    got = fread(buf, 1, want, f);
    fclose(f);
    if (got != want) {
        free(buf);
        return NULL;
    }
    return buf;
}

/* 1. every table entry identifies the file it names ---------------------- */
static void test_identity_chain(const char *root)
{
    size_t i;
    for (i = 0; i < O1_ROM_TABLE_LEN; i++) {
        const o1_rom_info_t *e = &o1_rom_table[i];
        char path[512];
        unsigned char *data;
        uint32_t crc;

        if (e->source == NULL)
            continue; /* recorded but not held, e.g. the 8 KiB daughterboard */

        snprintf(path, sizeof path, "%s/%s", root, e->source);
        data = read_file(path, e->size);
        CHECK(data != NULL, "cannot read %s", path);
        if (data == NULL)
            continue;

        crc = crc32_of(data, e->size);
        CHECK(crc == e->crc32,
              "%s: bytes are %08lx but the table says %08lx",
              e->source, (unsigned long)crc, (unsigned long)e->crc32);
        CHECK(o1_rom_lookup(crc, e->size) == e,
              "%s: lookup did not return its own entry", e->source);
        free(data);
    }

    /* A CRC we have never seen must not resolve to something. */
    CHECK(o1_rom_lookup(0xdeadbeefu, 4096u) == NULL, "0xdeadbeef resolved");
    /* Size is part of the key: the right CRC with the wrong size is not a hit. */
    CHECK(o1_rom_lookup(0xc0596b14u, 2048u) == NULL,
          "a monitor CRC matched at chargen size");
}

/* 2. the requirements are modelled, not just the refusal ----------------- */
static void test_requirements(void)
{
    const o1_personality_rom_req_t *req;

    req = o1_personality_requirement(O1_PERS_DRIVE_C);
    CHECK(req != NULL, "Drive C has no requirement");
    if (req) {
        CHECK(req->requires_ieee488 == 1,
              "Drive C must declare the IEEE-488 requirement");
        CHECK(req->preferred_rom == O1_ROM_OCC_144,
              "Drive C must name the ROM an overlay would serve");
    }

    req = o1_personality_requirement(O1_PERS_BUS_ANALYZER);
    CHECK(req != NULL && req->requires_ieee488 == 0 && req->min_video_kb == 0,
          "the analyzer must declare no ROM requirement");

    CHECK(o1_personality_requirement(O1_PERS_COUNT) == NULL,
          "out-of-range personality returned a requirement");
}

/* 3. the gate ------------------------------------------------------------- */
static void test_gate(void)
{
    const o1_rom_info_t *occ144 = o1_rom_lookup(0xc0596b14u, 4096u);
    const o1_rom_info_t *ozrom  = o1_rom_lookup(0xba1f6131u, 4096u);
    const o1_rom_info_t *nuevo  = o1_rom_lookup(0x298da402u, 4096u);
    const o1_rom_info_t *early  = o1_rom_lookup(0x5297c109u, 2048u);
    const o1_rom_info_t *late   = o1_rom_lookup(0x6c1eab0du, 2048u);
    const o1_rom_info_t *swp    = o1_rom_lookup(0x948556dbu, 4096u);
    o1_rom_info_t unknown;
    char why[256];
    o1_gate_result_t r;

    CHECK(occ144 && ozrom && nuevo && early && late && swp,
          "the table is missing an image these tests need");
    if (!(occ144 && ozrom && nuevo && early && late && swp))
        return;

    /* A ROM the probe read but could not name. */
    memset(&unknown, 0, sizeof unknown);
    unknown.crc32 = 0xdeadbeefu;
    unknown.size = 4096u;
    unknown.id = O1_ROM_UNKNOWN;
    unknown.kind = O1_ROM_KIND_MONITOR;
    unknown.socket = O1_ROM_SOCKET_UD11;
    unknown.ieee488 = O1_CAP_UNKNOWN;
    unknown.name = "unidentified";

    /* --- Drive C: runs only on a ROM with a verified IEEE-488 driver --- */
    r = o1_personality_gate(O1_PERS_DRIVE_C, occ144, late, why, sizeof why);
    CHECK(r == O1_GATE_OK, "Drive C + 1.44 should run, got %s (%s)",
          o1_gate_result_name(r), why);

    r = o1_personality_gate(O1_PERS_DRIVE_C, ozrom, late, why, sizeof why);
    CHECK(r == O1_GATE_REFUSED, "Drive C + OZROM should refuse, got %s",
          o1_gate_result_name(r));
    CHECK(strstr(why, "OZROM 1E") != NULL,
          "the refusal should name the fitted ROM: %s", why);
    CHECK(strstr(why, "IEEE-488") != NULL,
          "the refusal should name the missing capability: %s", why);
    CHECK(strstr(why, "1.44") != NULL,
          "the refusal should say what to fit instead: %s", why);

    r = o1_personality_gate(O1_PERS_DRIVE_C, nuevo, late, why, sizeof why);
    CHECK(r == O1_GATE_REFUSED,
          "Drive C + Nuevo should refuse (unverified), got %s",
          o1_gate_result_name(r));
    CHECK(strstr(why, "not been verified") != NULL,
          "the Nuevo refusal should say it is unverified: %s", why);

    r = o1_personality_gate(O1_PERS_DRIVE_C, &unknown, late, why, sizeof why);
    CHECK(r == O1_GATE_REFUSED, "Drive C + unidentified ROM should refuse");
    CHECK(strstr(why, "deadbeef") != NULL,
          "an unidentified ROM refusal should quote the CRC: %s", why);

    r = o1_personality_gate(O1_PERS_DRIVE_C, NULL, late, why, sizeof why);
    CHECK(r == O1_GATE_REFUSED, "Drive C with no probe at all should refuse");

    /* A chargen in the monitor socket means the probe is confused. */
    r = o1_personality_gate(O1_PERS_DRIVE_C, late, late, why, sizeof why);
    CHECK(r == O1_GATE_REFUSED,
          "a character generator in UD11 should refuse (inconsistent probe)");

    /* --- the printer: the same constraint, one layer less obvious --- */
    r = o1_personality_gate(O1_PERS_VIRTUAL_PRINTER, ozrom, late, why, sizeof why);
    CHECK(r == O1_GATE_REFUSED, "printer + OZROM should refuse, got %s",
          o1_gate_result_name(r));
    r = o1_personality_gate(O1_PERS_VIRTUAL_PRINTER, occ144, late, why, sizeof why);
    CHECK(r == O1_GATE_OK, "printer + 1.44 should run");

    /* --- video: OZROM's window is a limitation, not a refusal --- */
    r = o1_personality_gate(O1_PERS_VIDEO, ozrom, late, why, sizeof why);
    CHECK(r == O1_GATE_DEGRADED, "video + OZROM should degrade, got %s",
          o1_gate_result_name(r));
    CHECK(strstr(why, "3 KiB") != NULL,
          "the video warning should state the window size: %s", why);

    r = o1_personality_gate(O1_PERS_VIDEO, occ144, late, why, sizeof why);
    CHECK(r == O1_GATE_OK, "video + 1.44 + late font should run");
    r = o1_personality_gate(O1_PERS_VIDEO, occ144, early, why, sizeof why);
    CHECK(r == O1_GATE_OK, "video + 1.44 + early font should run (both are known)");
    r = o1_personality_gate(O1_PERS_VIDEO, occ144, NULL, why, sizeof why);
    CHECK(r == O1_GATE_DEGRADED, "video with no font probe should degrade");
    r = o1_personality_gate(O1_PERS_VIDEO, occ144, &unknown, why, sizeof why);
    CHECK(r == O1_GATE_DEGRADED, "video with an unknown font should degrade");
    r = o1_personality_gate(O1_PERS_VIDEO, occ144, occ144, why, sizeof why);
    CHECK(r == O1_GATE_REFUSED,
          "video with a monitor ROM in UA15 should refuse (inconsistent probe)");
    r = o1_personality_gate(O1_PERS_VIDEO, occ144, swp, why, sizeof why);
    CHECK(r == O1_GATE_REFUSED,
          "video with the 8088 image in UA15 should refuse");

    /* --- personalities that do not read the ROM are never gated on it --- */
    r = o1_personality_gate(O1_PERS_BUS_ANALYZER, ozrom, NULL, why, sizeof why);
    CHECK(r == O1_GATE_OK, "the analyzer should run on any ROM");
    r = o1_personality_gate(O1_PERS_BUS_ANALYZER, NULL, NULL, why, sizeof why);
    CHECK(r == O1_GATE_OK, "the analyzer should run with no probe at all");
    r = o1_personality_gate(O1_PERS_VIRTUAL_IO, ozrom, NULL, why, sizeof why);
    CHECK(r == O1_GATE_OK, "virtual I/O should run on any ROM");

    /* --- out of range --- */
    r = o1_personality_gate(O1_PERS_COUNT, occ144, late, why, sizeof why);
    CHECK(r == O1_GATE_REFUSED, "an unknown personality should refuse");
}

/* Print the decisions for a human.  The refusal text is user-facing, so it is
 * worth being able to read it without reading the source. */
static void show_decisions(void)
{
    const o1_rom_info_t *mons[4];
    const char *labels[4];
    const o1_rom_info_t *font = o1_rom_lookup(0x6c1eab0du, 2048u);
    char why[256];
    int i, j;

    mons[0] = o1_rom_lookup(0xc0596b14u, 4096u); labels[0] = "OCC 1.44";
    mons[1] = o1_rom_lookup(0xba1f6131u, 4096u); labels[1] = "OZROM 1E";
    mons[2] = o1_rom_lookup(0x298da402u, 4096u); labels[2] = "Nuevo 1.51";
    mons[3] = NULL;                              labels[3] = "no ROM probe";

    for (i = 0; i < 4; i++) {
        for (j = 0; j < O1_PERS_COUNT; j++) {
            o1_gate_result_t r = o1_personality_gate((o1_personality_t)j,
                                                     mons[i], font,
                                                     why, sizeof why);
            printf("  %-8s %-30s [%-13s] %s\n", o1_gate_result_name(r),
                   o1_personality_name((o1_personality_t)j), labels[i], why);
        }
        printf("\n");
    }
}

int main(int argc, char **argv)
{
    const char *root = (argc > 1) ? argv[1] : ".";
    int verbose = (argc > 2 && strcmp(argv[2], "-v") == 0);

    printf("rom-ident: %d images in the table, root %s\n",
           (int)O1_ROM_TABLE_LEN, root);
    test_identity_chain(root);
    test_requirements();
    test_gate();

    if (verbose) {
        printf("\ngate decisions:\n");
        show_decisions();
    }

    printf("%s (%d failure%s)\n", failures ? "FAILED" : "PASSED", failures,
           failures == 1 ? "" : "s");
    return failures ? 1 : 0;
}
