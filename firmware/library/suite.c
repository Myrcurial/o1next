/* The shared media suite -- see suite.h for what it is and why (#285). */
#include "suite.h"

#include <stdio.h>
#include <string.h>

#include "library.h"
#include "mailbox.h"

static int failures;

#define CHECK(cond, ...)                                               \
    do {                                                               \
        if (!(cond)) {                                                 \
            printf("  FAIL [%s] line %d: ", label, __LINE__);          \
            printf(__VA_ARGS__);                                       \
            printf("\n");                                              \
            failures++;                                                \
        }                                                              \
    } while (0)

static int find_identity(const lib *l, const char *id)
{
    unsigned   i;
    lib_record rec;

    for (i = 0; i < lib_count(l); i++) {
        if (lib_get(l, i, &rec) != LIB_OK)
            continue;
        if (strcmp(rec.name, id) == 0)
            return (int)i;
    }
    return -1;
}

/* A host-side client, the same one test_library.c uses: write the request bytes,
 * then read the length and that many bytes. */
typedef struct {
    uint8_t  code;
    uint8_t  payload[32];
    unsigned len;
    unsigned wire_len;
} xact;

static int xact_run(mailbox *mb, const uint8_t *req, unsigned nreq, xact *x)
{
    unsigned i, n;
    uint8_t  b;

    for (i = 0; i < nreq; i++)
        mb_write(mb, req[i]);

    memset(x, 0, sizeof *x);
    x->code = 0xFFu;

    if (!mb_read(mb, &b))
        return -1;
    n = b;
    if (n == 0)
        return -1;
    x->wire_len = n;

    for (i = 0; i < n; i++) {
        if (!mb_read(mb, &b))
            return -1;
        if (i == 0)
            x->code = b;
        else if (x->len < sizeof x->payload)
            x->payload[x->len++] = b;
    }
    return 0;
}

int suite_media(const media *const *order, unsigned nmedia, const char *label)
{
    lib        library;
    mailbox    mbox;
    lib_record rec;
    char       buf[16];
    unsigned   i, k, n;
    int        idx;

    failures = 0;

    lib_init(&library, order, nmedia);
    CHECK(lib_refresh(&library) == LIB_OK, "the walk should succeed");

    /* ------------------------------------------ the merge and its de-duplication */
    CHECK(lib_count(&library) == 8u,
          "eight entries over three media, got %u", lib_count(&library));

    for (i = 0; i < lib_count(&library); i++) {
        lib_record a, b;

        CHECK(lib_get(&library, i, &a) == LIB_OK, "entry %u should read", i);
        for (k = i + 1u; k < lib_count(&library); k++) {
            if (lib_get(&library, k, &b) != LIB_OK)
                continue;
            CHECK(strcmp(a.name, b.name) != 0,
                  "the merge de-duplicates: %s appears twice (%u and %u)", a.name, i, k);
        }
    }

    /* The identity comes from the long name.  A tilde in one means the medium
     * handed back an 8.3 short name instead -- which is the thing that must not
     * happen on FAT. */
    for (i = 0; i < lib_count(&library); i++) {
        lib_record r;

        if (lib_get(&library, i, &r) != LIB_OK)
            continue;
        CHECK(strchr(r.name, '~') == NULL,
              "no identity may be an 8.3 short name: %s has a tilde", r.name);
    }

    /* BOOT.IMD is on two media at two sizes: the higher-precedence copy wins */
    idx = find_identity(&library, "BOOT.IMD");
    CHECK(idx >= 0, "BOOT.IMD should be listed");
    if (idx >= 0) {
        CHECK(lib_get(&library, (unsigned)idx, &rec) == LIB_OK, "and readable");
        CHECK(rec.size == 409600u,
              "the microSD copy beats the flash one, so the size is the SD's, got %u",
              (unsigned)rec.size);
        CHECK(rec.kind == LIB_KIND_FLOPPY && (rec.flags & LIB_FLAG_VALID) != 0,
              "and it is a VALID floppy image");
    }
    n = 0;
    for (i = 0; i < lib_count(&library); i++) {
        lib_record r;

        if (lib_get(&library, i, &r) == LIB_OK && strcmp(r.name, "BOOT.IMD") == 0)
            n++;
    }
    CHECK(n == 1u, "one BOOT.IMD, not %u", n);

    /* The fallback: an invalid copy does not shadow a valid one below it */
    idx = find_identity(&library, "DEMO.IMG");
    CHECK(idx >= 0, "DEMO.IMG should be listed");
    if (idx >= 0) {
        CHECK(lib_get(&library, (unsigned)idx, &rec) == LIB_OK, "and readable");
        CHECK(rec.size == LIB_DRIVEC_192K,
              "the invalid USB demo fell through to the flash copy, so %u",
              (unsigned)rec.size);
        CHECK((rec.flags & LIB_FLAG_VALID) != 0, "and the entry is VALID");
    }

    /* ... and when nothing below it is valid, the first copy keeps the entry */
    idx = find_identity(&library, "BROKEN.IMG");
    CHECK(idx >= 0, "BROKEN.IMG should be listed -- nothing below it is valid");
    if (idx >= 0) {
        CHECK(lib_get(&library, (unsigned)idx, &rec) == LIB_OK, "and readable");
        CHECK((rec.flags & LIB_FLAG_VALID) == 0, "with VALID clear");
        CHECK(rec.size == 300000u, "and it is the USB copy, got %u", (unsigned)rec.size);
    }

    /* A wrong-sized Drive C blob is listed, and refused by MOUNT */
    idx = find_identity(&library, "DRIVEC-B.IMG");
    CHECK(idx >= 0, "a wrong-sized Drive C blob is still listed");
    if (idx >= 0) {
        CHECK(lib_get(&library, (unsigned)idx, &rec) == LIB_OK, "and readable");
        CHECK((rec.flags & LIB_FLAG_VALID) == 0, "with VALID clear");
        CHECK(lib_mount(&library, (unsigned)idx, LIB_DRIVE_C) == LIB_ERR_KIND,
              "and MOUNT refuses it with 05h");
    }

    /* The rest of the library, and the two files that must not be in it */
    idx = find_identity(&library, "O1NEXT-H.IMG");
    CHECK(idx >= 0, "o1next-harddrive.img -> O1NEXT-H.IMG");
    if (idx >= 0) {
        CHECK(lib_get(&library, (unsigned)idx, &rec) == LIB_OK, "and readable");
        CHECK(rec.kind == LIB_KIND_HARDDISK, "a 6 MiB .img is a hard-disk volume");
        CHECK(rec.size == 6291456u, "of the size the file is, got %u", (unsigned)rec.size);
    }
    CHECK(find_identity(&library, "MY-FLOPP.IMD") >= 0, "my-floppy.imd -> MY-FLOPP.IMD");
    CHECK(find_identity(&library, "UTILITY.IMD") >= 0, "utility.imd -> UTILITY.IMD");
    CHECK(find_identity(&library, "DRIVEC-1.IMG") >= 0, "drivec-192.img -> DRIVEC-1.IMG");
    CHECK(find_identity(&library, "PRINTOUT.PDF") < 0, "printer/ is not enumerated");
    CHECK(find_identity(&library, "NOTES.TXT") < 0, "a .txt in floppy/ is not a library file");

    /* ------------------------------------------------------------- the mounts */
    idx = find_identity(&library, "UTILITY.IMD");
    if (idx >= 0) {
        CHECK(lib_drive_state(&library, LIB_DRIVE_A) == LIB_DRIVE_EMPTY, "A: starts empty");
        CHECK(lib_mount(&library, (unsigned)idx, LIB_DRIVE_A) == LIB_OK, "a floppy mounts to A:");
        CHECK(lib_drive_state(&library, LIB_DRIVE_A) == LIB_DRIVE_MOUNTED, "and A: is mounted");
        CHECK(lib_mount(&library, (unsigned)idx, LIB_DRIVE_C) == LIB_ERR_KIND,
              "a floppy will not mount to slot 2");
        CHECK(lib_unmount(&library, LIB_DRIVE_A) == LIB_OK, "A: ejects");
        CHECK(lib_unmount(&library, LIB_DRIVE_A) == LIB_ERR_EMPTY,
              "ejecting an empty drive is 08h, not a silent success");
    }
    idx = find_identity(&library, "DRIVEC-1.IMG");
    if (idx >= 0) {
        CHECK(lib_mount(&library, (unsigned)idx, LIB_DRIVE_A) == LIB_ERR_KIND,
              "a Drive C blob will not mount to A:");
        CHECK(lib_mount(&library, (unsigned)idx, LIB_DRIVE_C) == LIB_OK, "it mounts to slot 2");
        lib_unmount(&library, LIB_DRIVE_C);
    }

    /* -------------------------------------------------------------- the bytes */
    idx = find_identity(&library, "UTILITY.IMD");
    if (idx >= 0) {
        memset(buf, 0, sizeof buf);
        CHECK(lib_read(&library, (unsigned)idx, 0u, buf, 3u) == LIB_OK,
              "the first bytes of the image read");
        CHECK(memcmp(buf, "IMD", 3) == 0, "and they are its own magic, got %.3s", buf);

        /* The regression test for the bug the host media had: the length has to be
         * refused *before* the read, or the read has already written past buf. */
        CHECK(lib_read(&library, (unsigned)idx, 0u, buf, 999999u) == LIB_ERR_MEDIA,
              "a read past the end is refused, not shortened");
    }
    CHECK(lib_read(&library, 999u, 0u, buf, 1u) == LIB_ERR_INDEX,
          "and so is an index past the end");

    /* ------------------------------------------------------- and the protocol
     *
     * The engine never reaches a medium except through `lib_*`, so these are
     * media-independent -- but they are run here anyway, because "the library
     * cannot tell them apart" is worth demonstrating rather than arguing. */
    mb_init(&mbox, &library, NULL);

    {
        uint8_t req[3];
        xact    x;

        req[0] = MB_OP_ECHO;
        req[1] = 0x5Au;
        CHECK(xact_run(&mbox, req, 2u, &x) == 0 && x.code == LIB_OK && x.len == 1u &&
              x.payload[0] == 0x5Au, "the echo probe, first pattern");

        req[1] = 0xA5u;
        CHECK(xact_run(&mbox, req, 2u, &x) == 0 && x.code == LIB_OK && x.len == 1u &&
              x.payload[0] == 0xA5u, "the echo probe, second pattern");

        req[0] = MB_OP_COUNT;
        CHECK(xact_run(&mbox, req, 1u, &x) == 0 && x.code == LIB_OK && x.len == 2u,
              "COUNT answers a u16");
        n = (unsigned)x.payload[0] | ((unsigned)x.payload[1] << 8);
        CHECK(n == lib_count(&library), "which is this media set's count, got %u", n);

        req[0] = MB_OP_GET;
        req[1] = 0u;
        req[2] = 0u;
        CHECK(xact_run(&mbox, req, 3u, &x) == 0 && x.code == LIB_OK &&
              x.wire_len == LIB_RECORD_LEN + 1u,
              "GET 0 answers one 24-byte record, so the reply is 25");

        req[0] = 0x77u;
        CHECK(xact_run(&mbox, req, 1u, &x) == 0 && x.code == LIB_ERR_OPCODE,
              "an unknown opcode answers 01h");

        req[0] = MB_OP_NOP;
        CHECK(xact_run(&mbox, req, 1u, &x) == 0 && x.code == LIB_OK,
              "and NOP is the way back to a known state");
    }

    return failures;
}
