/* Host tests for the image library and the mailbox engine (#283, #192).
 *
 * Build and run (no board, no SDK -- plain C):
 *
 *     firmware/library/run_tests.sh          # tests only
 *     firmware/library/run_tests.sh -v       # ... and print more
 *
 * What is being tested, and why each thing earns its place:
 *
 *   1. the identity          -- the 8.3 conversion is the merge key *and* what the
 *      menu shows, so a wrong one makes two different disks look like one;
 *   2. the kind rules        -- the directory plus the size is the whole
 *      identification, and the wrong-sized Drive C blob is the case that decides
 *      whether a user can see why their file will not mount;
 *   3. the walk and the merge -- three media, one namespace, one entry per name,
 *      with the precedence order deciding which copy it is;
 *   4. the mount rules       -- the kind-to-slot rule, and that an empty drive is a
 *      *status* while ejecting nothing is an error;
 *   5. the bytes             -- that a personality can actually pull the image;
 *   6. the protocol          -- the echo probe, the length-then-bytes read, the
 *      abandon rule, and the one that would be a real bug: an operand byte that
 *      happens to equal an opcode must be read as an operand.
 *
 * The fixture is a directory tree, because that is what media_dir.c reads -- so
 * the tests exercise the real file path rather than a mock.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>

#include "library.h"
#include "mailbox.h"
#include "media_dir.h"
#include "suite.h"

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

/* The fixture has to exist or nothing below means anything. */
#define FIXTURE(cond, ...)                                             \
    do {                                                               \
        if (!(cond)) {                                                 \
            printf("  FIXTURE line %d: ", __LINE__);                   \
            printf(__VA_ARGS__);                                       \
            printf("\n");                                              \
            exit(2);                                                   \
        }                                                              \
    } while (0)

/* ------------------------------------------------------------------- the fixture
 *
 * Three media, in precedence order USB / microSD / flash, with the layout
 * `docs/image-library-design.md` fixes -- plus the files that must NOT appear: a
 * printer PDF, a .txt in floppy/, and two `.img` files of a size no kind allows.
 *
 * Two pairs earn their place:
 *
 *   - BOOT.IMD is on two media at two different sizes, so which copy won is visible
 *     in the record rather than inferred;
 *   - DEMO.IMG is valid on the flash and invalid on the USB stick, so the fallback
 *     -- a bad copy does not shadow a good one below it -- is a test, not a hope.
 */
static char      root[512];
static media_dir flash, sd, usb;
static lib       library;
static mailbox   mbox;

static int mkdir_at(const char *path)
{
    return mkdir(path, 0700) == 0 ? 0 : -1;
}

static int file_at(const char *path, uint32_t size, const char *first)
{
    FILE *f = fopen(path, "wb");

    if (f == NULL)
        return -1;
    if (first != NULL && fwrite(first, 1, strlen(first), f) != strlen(first)) {
        fclose(f);
        return -1;
    }
    if (size > 0) {
        if (fseek(f, (long)(size - 1u), SEEK_SET) != 0 || fputc('Z', f) == EOF) {
            fclose(f);
            return -1;
        }
    }
    fclose(f);
    return 0;
}

static int tree_dir(const char *rel)
{
    char path[sizeof root + 128];

    snprintf(path, sizeof path, "%s/%s", root, rel);
    return mkdir_at(path);
}

static int tree_file(const char *rel, uint32_t size, const char *first)
{
    char path[sizeof root + 128];

    snprintf(path, sizeof path, "%s/%s", root, rel);
    return file_at(path, size, first);
}

static void build_fixture(void)
{
    char     path[sizeof root + 64];
    unsigned try;

    /* A unique root, made with nothing POSIX-only: `mkdtemp` is not declared under
     * -std=c99 on macOS, and the sibling runners compile with the same flags on
     * purpose, so the flags stay identical rather than gaining a feature macro. */
    for (try = 0; try < 1000u; try++) {
        snprintf(root, sizeof root, "/tmp/o1next-library-%lu-%u",
                 (unsigned long)time(NULL), try);
        if (mkdir_at(root) == 0)
            break;
    }
    FIXTURE(try < 1000u, "could not make a temp root");

    /* the three volume roots, and the three directories in each */
    FIXTURE(tree_dir("flash") == 0, "flash/");
    FIXTURE(tree_dir("flash/floppy") == 0, "flash/floppy/");
    FIXTURE(tree_dir("flash/disk") == 0, "flash/disk/");
    FIXTURE(tree_dir("flash/printer") == 0, "flash/printer/");
    FIXTURE(tree_dir("sd") == 0, "sd/");
    FIXTURE(tree_dir("sd/floppy") == 0, "sd/floppy/");
    FIXTURE(tree_dir("sd/disk") == 0, "sd/disk/");
    FIXTURE(tree_dir("sd/printer") == 0, "sd/printer/");
    FIXTURE(tree_dir("usb") == 0, "usb/");
    FIXTURE(tree_dir("usb/floppy") == 0, "usb/floppy/");
    FIXTURE(tree_dir("usb/disk") == 0, "usb/disk/");

    /* the external flash module: always fitted, so it is the floor and the guarantee */
    FIXTURE(tree_file("flash/floppy/boot.imd", 102400, "IMD 1.18: ") == 0, "boot.imd");
    FIXTURE(tree_file("flash/disk/o1next-harddrive.img", 6291456u, NULL) == 0, "the volume");
    FIXTURE(tree_file("flash/disk/demo.img", LIB_DRIVEC_192K, NULL) == 0, "the valid demo");
    FIXTURE(tree_file("flash/printer/printout.pdf", 2048, "%PDF-1.4") == 0, "the PDF");

    /* the microSD: the semi-permanent library */
    FIXTURE(tree_file("sd/floppy/boot.imd", 409600, "IMD 1.18: ") == 0, "the SD boot disk");
    FIXTURE(tree_file("sd/floppy/my-floppy.imd", 204800, "IMD 1.18: ") == 0, "my-floppy.imd");
    FIXTURE(tree_file("sd/disk/drivec-192.img", LIB_DRIVEC_192K, NULL) == 0, "the Drive C blob");
    FIXTURE(tree_file("sd/disk/drivec-bad.img", 300000, NULL) == 0, "the wrong-sized blob");
    FIXTURE(tree_file("sd/disk/broken.img", 400000, NULL) == 0, "the second broken copy");

    /* the USB stick: the transient member, so it wins -- and it is where the
     * fallback gets exercised, because both of its disk/ files are the wrong size
     * and only one of them has a valid copy further down the list */
    FIXTURE(tree_file("usb/floppy/utility.imd", 102400, "IMD 1.18: ") == 0, "utility.imd");
    FIXTURE(tree_file("usb/floppy/notes.txt", 16, "not an image") == 0, "notes.txt");
    FIXTURE(tree_file("usb/disk/demo.img", 300000, NULL) == 0, "the bad demo");
    FIXTURE(tree_file("usb/disk/broken.img", 300000, NULL) == 0, "the first broken copy");

    snprintf(path, sizeof path, "%s/flash", root);
    FIXTURE(media_dir_init(&flash, path) == 0, "the flash medium");
    snprintf(path, sizeof path, "%s/sd", root);
    FIXTURE(media_dir_init(&sd, path) == 0, "the microSD medium");
    snprintf(path, sizeof path, "%s/usb", root);
    FIXTURE(media_dir_init(&usb, path) == 0, "the USB medium");
}

/* ------------------------------------------------------------------- 1. the name */

static void test_identity(void)
{
    char id[LIB_NAME_LEN];

    lib_identity("boot.imd", id);
    CHECK(strcmp(id, "BOOT.IMD") == 0, "boot.imd should be BOOT.IMD, got %s", id);
    CHECK(id[9] == '\0' && id[10] == '\0' && id[15] == '\0',
          "and the rest of the 16 bytes should be NUL padded");

    lib_identity("my-floppy.imd", id);
    CHECK(strcmp(id, "MY-FLOPP.IMD") == 0, "a base longer than 8 truncates, got %s", id);

    lib_identity("O1NEXT-HARDDISK.IMG", id);
    CHECK(strcmp(id, "O1NEXT-H.IMG") == 0,
          "8 + '.' + 3 is the longest identity there is, got %s", id);

    lib_identity("disk/sub/BootSystem.hfe", id);
    CHECK(strcmp(id, "BOOTSYST.HFE") == 0, "the path drops and the case folds, got %s", id);

    lib_identity("noextension", id);
    CHECK(strcmp(id, "NOEXTENS") == 0, "no dot means no extension, got %s", id);

    lib_identity("", id);
    CHECK(id[0] == '\0', "an empty name is an empty identity, not a crash");
}

/* ------------------------------------------------------------------ 2. the kinds */

static void test_kinds(void)
{
    uint8_t k = 0xFFu;

    CHECK(lib_kind_of("floppy", "boot.imd", 102400, &k) == 0 && k == LIB_KIND_FLOPPY,
          "a .imd in floppy/ is a floppy image");
    CHECK(lib_kind_of("floppy", "BOOT.HFE", 102400, &k) == 0 && k == LIB_KIND_FLOPPY,
          "the extension match folds case, and .hfe counts too");
    CHECK(lib_kind_of("floppy", "notes.txt", 102400, &k) != 0,
          "anything else in floppy/ is not a library file");

    CHECK(lib_kind_of("disk", "drivec.img", LIB_DRIVEC_192K, &k) == 0 &&
          k == LIB_KIND_DRIVEC, "196608 bytes in disk/ is the 192K Drive C blob");
    CHECK(lib_kind_of("disk", "drivec.img", LIB_DRIVEC_384K, &k) == 0 &&
          k == LIB_KIND_DRIVEC, "393216 bytes is the 384K one");
    CHECK(lib_kind_of("disk", "o1next-harddrive.img", 6291456u, &k) == 0 &&
          k == LIB_KIND_HARDDISK, "6 MiB in disk/ is a hard-disk volume");
    CHECK(lib_kind_of("disk", "hd.img", LIB_HARDDISK_MIN, &k) == 0 &&
          k == LIB_KIND_HARDDISK, "and the floor itself is one");
    CHECK(lib_kind_of("disk", "hd.img", LIB_HARDDISK_MIN - 1u, &k) == 0 &&
          k == LIB_KIND_DRIVEC,
          "just under the floor is in the Drive C band, so it is listed rather than hidden");
    CHECK(lib_size_valid(LIB_KIND_DRIVEC, LIB_HARDDISK_MIN - 1u) == 0,
          "... and valid for no kind, which is the explicit gap between the two");
    CHECK(lib_kind_of("disk", "drivec-bad.img", 300000, &k) == 0 && k == LIB_KIND_DRIVEC,
          "300000 bytes is in the Drive C band, so it is still a library entry");
    CHECK(lib_size_valid(k, 300000) == 0,
          "... but that size is valid for no kind, which is what clears VALID");
    CHECK(lib_kind_of("disk", "empty.img", 0u, &k) != 0, "an empty file is not a drive");
    CHECK(lib_kind_of("disk", "o1next-harddrive.raw", 4194304u, &k) != 0,
          "only .img is a disk image");
    CHECK(lib_kind_of("printer", "printout.pdf", 2048, &k) != 0,
          "printer/ is output, not a library kind");

    CHECK(lib_size_valid(LIB_KIND_DRIVEC, LIB_DRIVEC_192K) == 1, "192K is a valid Drive C size");
    CHECK(lib_size_valid(LIB_KIND_DRIVEC, LIB_DRIVEC_384K) == 1, "384K is a valid Drive C size");
    CHECK(lib_size_valid(LIB_KIND_DRIVEC, LIB_DRIVEC_192K + 1u) == 0, "one byte over is not");
    CHECK(lib_size_valid(LIB_KIND_HARDDISK, LIB_HARDDISK_MIN) == 1, "the floor is a valid disk size");
    CHECK(lib_size_valid(LIB_KIND_HARDDISK, LIB_HARDDISK_MIN - 1u) == 0, "just under it is not");
}

/* ----------------------------------------------------------------- 3. the record */

static void test_record(void)
{
    lib_record rec;
    uint8_t    wire[LIB_RECORD_LEN];

    memset(&rec, 0, sizeof rec);
    memcpy(rec.name, "BOOT.IMD", 9);
    rec.kind  = LIB_KIND_FLOPPY;
    rec.flags = LIB_FLAG_VALID | LIB_FLAG_MOUNTED;
    rec.size  = 0x00012345u;

    lib_record_encode(&rec, wire);
    CHECK(memcmp(wire, "BOOT.IMD", 9) == 0, "the name is at offset 0");
    CHECK(wire[9] == 0 && wire[15] == 0, "and NUL padded to 16");
    CHECK(wire[16] == LIB_KIND_FLOPPY, "the kind is at 16");
    CHECK(wire[17] == 0x03u, "the flags are at 17");
    CHECK(wire[18] == 0x45u && wire[19] == 0x23u && wire[20] == 0x01u && wire[21] == 0x00u,
          "the size is little-endian at 18..21");
    CHECK(wire[22] == 0 && wire[23] == 0, "22..23 are reserved and zero");
    CHECK(LIB_RECORD_LEN == 24u, "and the whole record is the protocol's 24 bytes");
}

/* ------------------------------------------------------ 4. the walk and the merge */

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

static void test_walk_and_merge(void)
{
    lib_record rec;
    unsigned   n = 0, k;
    int        i;

    CHECK(lib_count(&library) == 8u,
          "eight entries over three media -- 1 USB, 4 SD, 3 flash, with two names "
          "de-duplicated -- got %u", lib_count(&library));

    /* the merge: one name, two media, one entry, and the SD copy wins */
    i = find_identity(&library, "BOOT.IMD");
    CHECK(i >= 0, "BOOT.IMD should be listed");
    if (i >= 0) {
        CHECK(lib_get(&library, (unsigned)i, &rec) == LIB_OK, "and readable");
        CHECK(rec.size == 409600u,
              "the microSD copy beats the flash one, so the size is the SD's, got %u",
              (unsigned)rec.size);
        CHECK(rec.kind == LIB_KIND_FLOPPY, "and it is a floppy image");
        CHECK((rec.flags & LIB_FLAG_VALID) != 0, "and it is VALID");
    }
    for (k = 0; k < lib_count(&library); k++) {
        lib_record r;
        if (lib_get(&library, k, &r) == LIB_OK && strcmp(r.name, "BOOT.IMD") == 0)
            n++;
    }
    CHECK(n == 1u, "the merge de-duplicates: one BOOT.IMD, not %u", n);

    /* the rest of the library */
    CHECK(find_identity(&library, "MY-FLOPP.IMD") >= 0, "my-floppy.imd -> MY-FLOPP.IMD");
    CHECK(find_identity(&library, "UTILITY.IMD") >= 0, "utility.imd -> UTILITY.IMD");
    CHECK(find_identity(&library, "DRIVEC-1.IMG") >= 0, "drivec-192.img -> DRIVEC-1.IMG");
    i = find_identity(&library, "O1NEXT-H.IMG");
    CHECK(i >= 0, "o1next-harddrive.img -> O1NEXT-H.IMG");
    if (i >= 0) {
        CHECK(lib_get(&library, (unsigned)i, &rec) == LIB_OK, "and readable");
        CHECK(rec.kind == LIB_KIND_HARDDISK, "a 6 MiB .img in disk/ is a hard-disk volume");
        CHECK(rec.size == 6291456u, "of the size the file is");
    }

    /* and what must NOT be there */
    CHECK(find_identity(&library, "PRINTOUT.PDF") < 0,
          "printer/ is not enumerated at all -- it is the web UI's (#182)");
    CHECK(find_identity(&library, "NOTES.TXT") < 0,
          "a .txt in floppy/ is not a library file");
}

static void test_wrong_sized_blob(void)
{
    lib_record rec;
    int        i = find_identity(&library, "DRIVEC-B.IMG");

    CHECK(i >= 0, "a wrong-sized Drive C blob is still listed (section 5.2)");
    if (i < 0)
        return;

    CHECK(lib_get(&library, (unsigned)i, &rec) == LIB_OK, "and readable");
    CHECK((rec.flags & LIB_FLAG_VALID) == 0,
          "but with VALID clear, so a user can see it and be told why");
    CHECK(rec.kind == LIB_KIND_DRIVEC, "its kind is still what the directory says");
    CHECK(lib_mount(&library, (unsigned)i, LIB_DRIVE_C) == LIB_ERR_KIND,
          "and MOUNT refuses it with 05h rather than mounting something broken");
}

/* The fallback, which is what the precedence order buys: a copy that is invalid for
 * its kind does not shadow a valid one below it -- so a demo image on a stick that
 * turns out to be the wrong size lands on the microSD or the flash -- and when *no*
 * copy is valid the first one still keeps the entry, so the user can see it. */
static void test_invalid_copy_falls_through(void)
{
    lib_record rec;
    int        i;

    /* DEMO.IMG: 300000 bytes on the USB stick (invalid), 196608 on the flash (valid) */
    i = find_identity(&library, "DEMO.IMG");
    CHECK(i >= 0, "DEMO.IMG should be listed");
    if (i >= 0) {
        CHECK(lib_get(&library, (unsigned)i, &rec) == LIB_OK, "and readable");
        CHECK(rec.size == LIB_DRIVEC_192K,
              "the invalid USB copy fell through to the flash one, so this is the flash's size (%u)",
              (unsigned)rec.size);
        CHECK((rec.flags & LIB_FLAG_VALID) != 0, "and the entry is VALID");
        CHECK(lib_mount(&library, (unsigned)i, LIB_DRIVE_C) == LIB_OK,
              "so it mounts -- which is the whole point of falling through");
        lib_unmount(&library, LIB_DRIVE_C);
    }

    /* BROKEN.IMG: invalid on the USB stick *and* on the microSD, so nothing below it
     * works and the first one keeps the entry, listed with VALID clear. */
    i = find_identity(&library, "BROKEN.IMG");
    CHECK(i >= 0, "BROKEN.IMG should still be listed, because nothing below it is valid");
    if (i >= 0) {
        CHECK(lib_get(&library, (unsigned)i, &rec) == LIB_OK, "and readable");
        CHECK((rec.flags & LIB_FLAG_VALID) == 0, "with VALID clear");
        CHECK(rec.size == 300000u,
              "and it is the USB copy -- the highest precedence of the two broken ones (%u)",
              (unsigned)rec.size);
    }
}

static void test_precedence_is_the_order(void)
{
    const media *order[3];
    lib          l2;
    lib_record   rec;
    int          i;

    /* the same three media in the other order: the flash copy wins */
    order[0] = &flash.media;
    order[1] = &usb.media;
    order[2] = &sd.media;
    lib_init(&l2, order, 3u);
    CHECK(lib_refresh(&l2) == LIB_OK, "the walk should succeed in either order");

    i = find_identity(&l2, "BOOT.IMD");
    CHECK(i >= 0, "BOOT.IMD is listed whichever order the media are in");
    if (i >= 0) {
        CHECK(lib_get(&l2, (unsigned)i, &rec) == LIB_OK, "and readable");
        CHECK(rec.size == 102400u,
              "with the flash first the flash copy wins -- precedence is the array, not luck, got %u",
              (unsigned)rec.size);
    }
}

/* ----------------------------------------------------------------- 5. the mounts */

static void test_mounts(void)
{
    unsigned entry = 0;
    int      i;

    i = find_identity(&library, "MY-FLOPP.IMD");
    CHECK(i >= 0, "MY-FLOPP.IMD should be listed");
    if (i < 0)
        return;

    CHECK(lib_drive_state(&library, LIB_DRIVE_A) == LIB_DRIVE_EMPTY, "A: starts empty");
    CHECK(lib_mount(&library, (unsigned)i, LIB_DRIVE_A) == LIB_OK, "a floppy mounts to A:");
    CHECK(lib_drive_state(&library, LIB_DRIVE_A) == LIB_DRIVE_MOUNTED, "and A: is mounted");
    CHECK(lib_drive_entry(&library, LIB_DRIVE_A, &entry) == LIB_OK && entry == (unsigned)i,
          "and A: names that entry");

    /* the kind-to-slot rule */
    CHECK(lib_mount(&library, (unsigned)i, LIB_DRIVE_C) == LIB_ERR_KIND,
          "a floppy will not mount to slot 2, which is the storage personality");
    CHECK(lib_mount(&library, 99u, LIB_DRIVE_A) == LIB_ERR_INDEX,
          "an index past the end is 03h");
    CHECK(lib_mount(&library, (unsigned)i, 3u) == LIB_ERR_DRIVE, "drive 3 is out of range");

    /* one entry, one drive */
    CHECK(lib_mount(&library, (unsigned)i, LIB_DRIVE_B) == LIB_OK, "it moves to B:");
    CHECK(lib_drive_state(&library, LIB_DRIVE_A) == LIB_DRIVE_EMPTY,
          "and A: is empty again, because one entry is on one drive");

    /* a Drive C blob goes to slot 2 and nowhere else */
    i = find_identity(&library, "DRIVEC-1.IMG");
    CHECK(i >= 0, "DRIVEC-1.IMG should be listed");
    if (i >= 0) {
        CHECK(lib_mount(&library, (unsigned)i, LIB_DRIVE_A) == LIB_ERR_KIND,
              "a Drive C blob will not mount to A:");
        CHECK(lib_mount(&library, (unsigned)i, LIB_DRIVE_C) == LIB_OK, "it mounts to slot 2");
    }

    /* unmount */
    CHECK(lib_unmount(&library, LIB_DRIVE_B) == LIB_OK, "B: ejects");
    CHECK(lib_unmount(&library, LIB_DRIVE_B) == LIB_ERR_EMPTY,
          "ejecting an empty drive is 08h, not a silent success");
    CHECK(lib_unmount(&library, 7u) == LIB_ERR_DRIVE, "drive 7 is out of range");
}

static void test_read_and_refresh(void)
{
    char     buf[16];
    unsigned entry = 0;
    int      i = find_identity(&library, "UTILITY.IMD");

    CHECK(i >= 0, "UTILITY.IMD should be listed");
    if (i < 0)
        return;

    /* the personality's path: the bytes come out of whichever medium owns it */
    memset(buf, 0, sizeof buf);
    CHECK(lib_read(&library, (unsigned)i, 0u, buf, 3u) == LIB_OK, "the first bytes read");
    CHECK(memcmp(buf, "IMD", 3) == 0, "and they are the image's own magic, got %.3s", buf);
    CHECK(lib_read(&library, (unsigned)i, 0u, buf, 999999u) == LIB_ERR_MEDIA,
          "a read past the end is refused, not shortened");
    CHECK(lib_read(&library, 999u, 0u, buf, 1u) == LIB_ERR_INDEX,
          "and so is an index past the end");

    /* a mount outlives a refresh, because the firmware's state outlives the host's */
    CHECK(lib_mount(&library, (unsigned)i, LIB_DRIVE_A) == LIB_OK, "mount it");
    CHECK(lib_refresh(&library) == LIB_OK, "a refresh succeeds");
    CHECK(lib_drive_state(&library, LIB_DRIVE_A) == LIB_DRIVE_MOUNTED,
          "and the mount survives it");
    if (lib_drive_entry(&library, LIB_DRIVE_A, &entry) == LIB_OK) {
        lib_record rec;
        CHECK(lib_get(&library, entry, &rec) == LIB_OK, "A: still names an entry");
        CHECK(strcmp(rec.name, "UTILITY.IMD") == 0, "and it is the same one, got %s", rec.name);
        CHECK((rec.flags & LIB_FLAG_MOUNTED) != 0, "with the MOUNTED flag set");
    }
    lib_unmount(&library, LIB_DRIVE_A);
}

/* -------------------------------------------------------------- 6. the protocol
 *
 * A faithful host-side client: write the request bytes, then read the length and
 * that many bytes.  Everything below goes through this, so what is tested is the
 * wire behaviour rather than the internals.
 */
typedef struct {
    uint8_t  code;             /* reply[0] */
    uint8_t  payload[32];      /* reply[1..] */
    unsigned len;
    unsigned wire_len;         /* N, the length the reply register handed out */
} xact;

static int xact_run(const uint8_t *req, unsigned nreq, xact *x)
{
    unsigned i, n;
    uint8_t  b;

    for (i = 0; i < nreq; i++)
        mb_write(&mbox, req[i]);

    memset(x, 0, sizeof *x);
    x->code = 0xFFu;

    if (!mb_read(&mbox, &b))
        return -1;                       /* the reply register read 0: no reply */
    n = b;
    if (n == 0)
        return -1;                       /* 0 means "not ready", so never a length */
    x->wire_len = n;

    for (i = 0; i < n; i++) {
        if (!mb_read(&mbox, &b))
            return -1;                   /* a reply shorter than its own length */
        if (i == 0)
            x->code = b;
        else if (x->len < sizeof x->payload)
            x->payload[x->len++] = b;
    }
    return 0;
}

static void test_echo_probe(void)
{
    xact    x;
    uint8_t req[2];

    req[0] = MB_OP_ECHO;
    req[1] = 0x5Au;
    CHECK(xact_run(req, 2, &x) == 0, "an ECHO should answer");
    CHECK(x.code == LIB_OK, "with OK, got %02X", x.code);
    CHECK(x.len == 1u && x.payload[0] == 0x5Au, "and the byte echoed back");

    /* the probe is the echo *twice with two patterns*: an absent interposer leaves
     * the register answering the floating bus, and one pattern cannot catch that */
    req[1] = 0xA5u;
    CHECK(xact_run(req, 2, &x) == 0, "a second ECHO should answer");
    CHECK(x.code == LIB_OK && x.len == 1u && x.payload[0] == 0xA5u,
          "with the other pattern back -- which is what makes it a presence probe");
}

static void test_nop_and_id(void)
{
    xact    x;
    uint8_t req;

    req = MB_OP_NOP;
    CHECK(xact_run(&req, 1, &x) == 0, "NOP should answer");
    CHECK(x.code == LIB_OK && x.len == 0u,
          "with OK and nothing else -- and a reply is never empty, so N is 1");

    req = MB_OP_ID;
    CHECK(xact_run(&req, 1, &x) == 0, "ID should answer");
    CHECK(x.code == LIB_OK && x.len == 2u, "with two payload bytes");
    CHECK(x.payload[0] == MB_PROTOCOL_VERSION && x.payload[1] == MB_DEVICE_ID,
          "the protocol version and the device id");
}

static void test_unknown_opcode_and_recovery(void)
{
    xact    x;
    uint8_t req;

    req = 0x77u;   /* not the mailbox's, not the clock's, not the ROM service's */
    CHECK(xact_run(&req, 1, &x) == 0, "an unknown opcode still answers");
    CHECK(x.code == LIB_ERR_OPCODE, "with 01h, got %02X", x.code);
    CHECK(x.len == 0u, "and no payload");

    req = MB_OP_NOP;
    CHECK(xact_run(&req, 1, &x) == 0, "and NOP is a way back to a known state");
    CHECK(x.code == LIB_OK, "answering OK");
}

static void test_count_and_get(void)
{
    xact     x;
    uint8_t  req[3];
    unsigned n;

    req[0] = MB_OP_COUNT;
    CHECK(xact_run(req, 1, &x) == 0, "COUNT should answer");
    CHECK(x.code == LIB_OK && x.len == 2u, "with a u16");
    n = (unsigned)x.payload[0] | ((unsigned)x.payload[1] << 8);
    CHECK(n == lib_count(&library), "which is the library's count, got %u", n);

    req[0] = MB_OP_GET;
    req[1] = 0u;
    req[2] = 0u;
    CHECK(xact_run(req, 3, &x) == 0, "GET 0 should answer");
    CHECK(x.code == LIB_OK, "with OK, got %02X", x.code);
    CHECK(x.len == LIB_RECORD_LEN, "and exactly one 24-byte record, got %u", x.len);
    CHECK(x.wire_len == LIB_RECORD_LEN + 1u,
          "so the reply length is always 25 -- the property section 5.1 is built on, got %u",
          x.wire_len);

    /* past the end is a defined end-of-list, not a hang */
    req[0] = MB_OP_GET;
    req[1] = 0xFFu;
    req[2] = 0x00u;
    CHECK(xact_run(req, 3, &x) == 0, "GET 255 should answer");
    CHECK(x.code == LIB_ERR_INDEX && x.len == 0u, "with 03h and no payload");
}

static void test_operands_are_operands(void)
{
    xact    x;
    uint8_t req[3];

    /* Index 16 is the operand bytes 10h, 00h -- and 10h is COUNT's opcode.  A byte
     * arriving mid-request has to be read as an operand, or this request would be
     * silently answered as a COUNT and MOUNT.COM would mount the wrong disk. */
    req[0] = MB_OP_GET;
    req[1] = 0x10u;
    req[2] = 0x00u;
    CHECK(xact_run(req, 3, &x) == 0, "GET 16 should answer");
    CHECK(x.code == LIB_ERR_INDEX,
          "with 03h (16 is past this fixture's end) -- a COUNT reply here would mean the operand was misread, got %02X",
          x.code);
}

static void test_mount_through_the_mailbox(void)
{
    xact    x;
    uint8_t req[4];
    int     i = find_identity(&library, "UTILITY.IMD");

    CHECK(i >= 0, "UTILITY.IMD should be listed");
    if (i < 0)
        return;

    req[0] = MB_OP_MOUNT;
    req[1] = (uint8_t)((unsigned)i & 0xFFu);
    req[2] = (uint8_t)(((unsigned)i >> 8) & 0xFFu);
    req[3] = LIB_DRIVE_A;
    CHECK(xact_run(req, 4, &x) == 0, "MOUNT should answer");
    CHECK(x.code == LIB_OK, "with OK, got %02X", x.code);
    CHECK(x.len == 1u && x.payload[0] == LIB_DRIVE_MOUNTED, "and the drive state");

    req[0] = MB_OP_DSTATUS;
    req[1] = LIB_DRIVE_A;
    CHECK(xact_run(req, 2, &x) == 0, "DSTATUS should answer");
    CHECK(x.code == LIB_OK && x.len == 4u, "with state, index and flags");
    CHECK(x.payload[0] == LIB_DRIVE_MOUNTED, "the state");
    CHECK(((unsigned)x.payload[1] | ((unsigned)x.payload[2] << 8)) == (unsigned)i,
          "the entry index");
    CHECK((x.payload[3] & LIB_FLAG_MOUNTED) != 0u, "and the MOUNTED flag");

    /* an empty drive is a status, not an error -- this is the status query */
    req[1] = LIB_DRIVE_B;
    CHECK(xact_run(req, 2, &x) == 0, "DSTATUS on an empty drive should answer");
    CHECK(x.code == LIB_OK && x.payload[0] == LIB_DRIVE_EMPTY,
          "with EMPTY, not an error, got %02X", x.code);
    CHECK(((unsigned)x.payload[1] | ((unsigned)x.payload[2] << 8)) == LIB_DRIVE_NONE,
          "and the no-entry index");

    /* ... but a drive that does not exist is an error */
    req[1] = 9u;
    CHECK(xact_run(req, 2, &x) == 0, "DSTATUS on drive 9 should answer");
    CHECK(x.code == LIB_ERR_DRIVE, "with 04h, got %02X", x.code);

    req[0] = MB_OP_UNMOUNT;
    req[1] = LIB_DRIVE_A;
    CHECK(xact_run(req, 2, &x) == 0, "UNMOUNT should answer");
    CHECK(x.code == LIB_OK && x.payload[0] == LIB_DRIVE_EMPTY, "and the drive is empty");

    req[0] = MB_OP_UNMOUNT;
    req[1] = LIB_DRIVE_A;
    CHECK(xact_run(req, 2, &x) == 0, "UNMOUNT again should answer");
    CHECK(x.code == LIB_ERR_EMPTY, "with 08h -- ejecting nothing is the mistake");
}

static void test_abandon_rule(void)
{
    uint8_t  b;
    unsigned i;

    /* start a GET and read only part of the reply */
    mb_write(&mbox, MB_OP_GET);
    mb_write(&mbox, 0u);
    mb_write(&mbox, 0u);
    CHECK(mb_read(&mbox, &b) == 1, "the reply length should come out");
    CHECK(b == (uint8_t)(LIB_RECORD_LEN + 1u), "which for GET is 25, got %u", b);
    CHECK(mb_read(&mbox, &b) == 1 && b == LIB_OK, "then the result code");

    /* ... and now abandon it mid-reply: a write while a reply is pending starts a
     * new transaction, which is the whole recovery story (section 3, rule 4) */
    mb_write(&mbox, MB_OP_NOP);
    CHECK(mb_read(&mbox, &b) == 1, "the abandoned reply is gone and NOP answers");
    CHECK(b == 1u, "with a one-byte reply, got %u", b);
    CHECK(mb_read(&mbox, &b) == 1 && b == LIB_OK, "which is OK");
    CHECK(mb_read(&mbox, &b) == 0, "and then the register reads 0 again");

    for (i = 0; i < 8u; i++)
        CHECK(mb_read(&mbox, &b) == 0, "an exhausted reply register keeps reading 0");
}

/* ------------------------------------------------------------------- 7. the cap
 *
 * LIB_MAX_ENTRIES is a RAM bound, and a bound that is not tested is a bound that
 * overflows.  A separate root keeps this out of the fixture's counts.
 */
static void test_entry_cap(void)
{
    char         caproot[sizeof root + 16];
    char         path[sizeof root + 128];
    media_dir    cap;
    const media *order[1];
    lib          l;
    unsigned     i;

    snprintf(caproot, sizeof caproot, "%s/cap", root);
    FIXTURE(mkdir_at(caproot) == 0, "the cap root");
    snprintf(path, sizeof path, "%s/floppy", caproot);
    FIXTURE(mkdir_at(path) == 0, "the cap floppy/");

    for (i = 0; i < LIB_MAX_ENTRIES + 2u; i++) {
        snprintf(path, sizeof path, "%s/floppy/f%03u.imd", caproot, i);
        FIXTURE(file_at(path, 512u, "IMD 1.18: ") == 0, "cap fixture file %u", i);
    }
    FIXTURE(media_dir_init(&cap, caproot) == 0, "the cap medium");

    order[0] = &cap.media;
    lib_init(&l, order, 1u);
    CHECK(lib_refresh(&l) == LIB_OK, "the walk should succeed");
    CHECK(lib_count(&l) == LIB_MAX_ENTRIES,
          "%u files fill the index to its cap and stop cleanly, got %u",
          LIB_MAX_ENTRIES + 2u, lib_count(&l));
}

/* ------------------------------------------------------------------------ main */

static int verbose;

static void step(const char *name)
{
    if (verbose)
        printf("  %s\n", name);
}

int main(int argc, char **argv)
{
    const media *order[3];
    int          i;

    /* Unbuffered, so that a crash still shows every check that had already run --
     * a buffered stdout loses the lot to an abort. */
    setbuf(stdout, NULL);

    for (i = 1; i < argc; i++)
        if (strcmp(argv[i], "-v") == 0)
            verbose = 1;

    build_fixture();

    /* The precedence order, and it is a decision: the USB stick is the transient
     * member -- plugging one in with a demo image is how you test something, so it
     * wins -- the microSD is the semi-permanent library, and the external flash is
     * always fitted, so it is the floor and the guarantee. */
    order[0] = &usb.media;
    order[1] = &sd.media;
    order[2] = &flash.media;
    lib_init(&library, order, 3u);
    CHECK(lib_refresh(&library) == LIB_OK, "the fixture should walk");
    mb_init(&mbox, &library, NULL);

    /* The shared suite -- the same checks test_fatfs.c runs over three real FAT
     * volumes, so that "the library cannot tell them apart" is run, not argued. */
    step("shared media suite");
    failures += suite_media(order, 3u, "directory");

    step("identity");
    test_identity();
    step("kinds");
    test_kinds();
    step("record");
    test_record();
    step("walk and merge");
    test_walk_and_merge();
    step("wrong-sized blob");
    test_wrong_sized_blob();
    step("invalid copy falls through");
    test_invalid_copy_falls_through();
    step("precedence");
    test_precedence_is_the_order();
    step("mounts");
    test_mounts();
    step("read and refresh");
    test_read_and_refresh();
    step("echo probe");
    test_echo_probe();
    step("nop and id");
    test_nop_and_id();
    step("unknown opcode");
    test_unknown_opcode_and_recovery();
    step("count and get");
    test_count_and_get();
    step("operands are operands");
    test_operands_are_operands();
    step("mount through the mailbox");
    test_mount_through_the_mailbox();
    step("abandon rule");
    test_abandon_rule();
    step("entry cap");
    test_entry_cap();

    if (failures == 0) {
        printf("library: all tests passed (%u entries over three media)\n",
               lib_count(&library));
        return 0;
    }
    printf("library: %d check(s) failed\n", failures);
    return 1;
}
