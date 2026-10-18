/* The media layer, over real FAT volumes on the host (#285, #192).
 *
 * Build and run (no board, no SDK -- a C compiler and FatFS):
 *
 *     firmware/library/run_tests.sh            # both suites
 *     firmware/library/run_tests.sh -v         # ... and name each check group
 *
 * What this proves, and what it does not
 * --------------------------------------
 * Three volumes are made in a temp root -- 64 MB for the external flash, 64 MB for
 * the microSD, 16 MB for the USB stick, which are the parts `hardware/interposer/`
 * names -- formatted with `f_mkfs`, populated through the `media.h` seam, and then
 * handed to **the same suite the directory fixture gets** (`suite_media`).  So the
 * claim "the library cannot tell them apart" is run rather than argued.
 *
 * What it does not prove: that the SPI transport, the microSD's card protocol or
 * the USB host stack work.  Those need a board, and they are the follow-up
 * sub-issue.  Nothing here is measured on hardware.
 *
 * The one finding worth reading the code for
 * ------------------------------------------
 * **A "FAT32" volume is not always FAT32.**  FatFS decides the type from the
 * cluster count, not from the BPB's `FAT32` string, so with one 512-byte sector per
 * cluster a 16 MB volume is **FAT16** and only ~34 MB and up is FAT32.  The
 * external flash is specced at 16-64 MB, which straddles that line -- so the test
 * asserts what each size actually comes out as, and `docs/image-library-design.md`
 * records it.  Either type is readable by any card reader, which is what the
 * requirement was really about.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>

#include "blockdev.h"
#include "blockdev_file.h"
#include "ff.h"              /* first: diskio.h uses its integer types */
#include "diskio.h"
#include "library.h"
#include "media_fatfs.h"
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

#define FIXTURE(cond, ...)                                             \
    do {                                                               \
        if (!(cond)) {                                                 \
            printf("  FIXTURE line %d: ", __LINE__);                   \
            printf(__VA_ARGS__);                                       \
            printf("\n");                                              \
            exit(2);                                                   \
        }                                                              \
    } while (0)

/* The three volumes, sized like the parts `hardware/interposer/README.md` names:
 * the external flash module is 16-64 MB and the cards are what a user has. */
#define FLASH_SECTORS (64u * 1024u * 1024u / BLOCKDEV_SECTOR)
#define SD_SECTORS    (64u * 1024u * 1024u / BLOCKDEV_SECTOR)
#define USB_SECTORS   (16u * 1024u * 1024u / BLOCKDEV_SECTOR)

static char          root[512];
static blockdev_file flash_file, sd_file, usb_file;
static media_fatfs   flash, sd, usb;

static int mkdir_at(const char *path)
{
    return mkdir(path, 0700) == 0 ? 0 : -1;
}

/* The three directories the layout fixes, on one volume. */
static int make_dirs(media_fatfs *m, const char *const *dirs, unsigned n)
{
    char    path[MEDIA_FATFS_PATH_MAX];
    unsigned i;

    for (i = 0; i < n; i++) {
        snprintf(path, sizeof path, "%s/%s", m->prefix, dirs[i]);
        if (f_mkdir(path) != FR_OK && f_stat(path, NULL) != FR_OK)
            return -1;
    }
    return 0;
}

/* Write a file **through the media seam**, in chunks, so the seam's write path is
 * what builds the fixture rather than FatFS being driven directly.  `first` are the
 * leading bytes (a real image's magic, so a read can be checked against it). */
static int put_file(media_fatfs *m, const char *dir, const char *name,
                    uint32_t size, const char *first)
{
    static uint8_t chunk[4096];
    uint32_t       off = 0;

    if (size == 0u)
        return -1;
    memset(chunk, 'Z', sizeof chunk);
    if (first != NULL) {
        size_t n = strlen(first);
        if (n > sizeof chunk)
            return -1;
        memcpy(chunk, first, n);
    }

    while (off < size) {
        size_t n = size - off;

        if (n > sizeof chunk)
            n = sizeof chunk;
        if (m->media.ops->write(m->media.ctx, dir, name, off, chunk, n) != MEDIA_OK)
            return -1;
        off += (uint32_t)n;
    }
    return 0;
}

/* ---------------------------------------------------------------- the fixture
 *
 * The same eight entries the directory fixture builds, with the same names, sizes
 * and kinds -- because `suite_media` asserts the same things about both.  See
 * suite.h: the fixture is part of the contract.
 */
static void build_fixture(void)
{
    static const char *const dirs[] = { "floppy", "disk", "printer" };
    char     path[sizeof root + 64];
    MKFS_PARM opt;
    BYTE      work[4096];
    unsigned  try;

    /* A unique temp root, made with nothing POSIX-only -- the sibling runner
     * compiles with the same flags on purpose. */
    for (try = 0; try < 1000u; try++) {
        snprintf(root, sizeof root, "/tmp/o1next-fatfs-%lu-%u",
                 (unsigned long)time(NULL), try);
        if (mkdir_at(root) == 0)
            break;
    }
    FIXTURE(try < 1000u, "could not make a temp root");

    /* Three sparse images, sized like the parts the interposer names. */
    snprintf(path, sizeof path, "%s/flash.img", root);
    FIXTURE(blockdev_file_create(path, FLASH_SECTORS) == BLOCKDEV_OK, "the flash image");
    FIXTURE(blockdev_file_init(&flash_file, path, "flash") == BLOCKDEV_OK, "the flash device");
    snprintf(path, sizeof path, "%s/sd.img", root);
    FIXTURE(blockdev_file_create(path, SD_SECTORS) == BLOCKDEV_OK, "the microSD image");
    FIXTURE(blockdev_file_init(&sd_file, path, "sd") == BLOCKDEV_OK, "the microSD device");
    snprintf(path, sizeof path, "%s/usb.img", root);
    FIXTURE(blockdev_file_create(path, USB_SECTORS) == BLOCKDEV_OK, "the USB image");
    FIXTURE(blockdev_file_init(&usb_file, path, "usb") == BLOCKDEV_OK, "the USB device");

    blockdev_reset();
    blockdev_register(BLOCKDEV_FLASH, &flash_file.dev);
    blockdev_register(BLOCKDEV_SD, &sd_file.dev);
    blockdev_register(BLOCKDEV_USB, &usb_file.dev);

    FIXTURE(media_fatfs_init(&flash, BLOCKDEV_FLASH) == BLOCKDEV_OK, "the flash medium");
    FIXTURE(media_fatfs_init(&sd, BLOCKDEV_SD) == BLOCKDEV_OK, "the microSD medium");
    FIXTURE(media_fatfs_init(&usb, BLOCKDEV_USB) == BLOCKDEV_OK, "the USB medium");

    /* Format all three.  One FAT: nothing here needs the second copy, and it is
     * half the writing -- which on the NOR flash is half the wear.  One 512-byte
     * sector per cluster, because the library is full of 100-400 KB images. */
    memset(&opt, 0, sizeof opt);
    opt.fmt     = FM_ANY;
    opt.n_fat   = 1;
    opt.au_size = BLOCKDEV_SECTOR;
    FIXTURE(f_mkfs("0:", &opt, work, sizeof work) == FR_OK, "mkfs on the flash");
    FIXTURE(f_mkfs("1:", &opt, work, sizeof work) == FR_OK, "mkfs on the microSD");
    FIXTURE(f_mkfs("2:", &opt, work, sizeof work) == FR_OK, "mkfs on the USB stick");

    FIXTURE(make_dirs(&flash, dirs, 3u) == 0, "the flash directories");
    FIXTURE(make_dirs(&sd, dirs, 3u) == 0, "the microSD directories");
    FIXTURE(make_dirs(&usb, dirs, 3u) == 0, "the USB directories");

    /* the external flash: always fitted, so it is the floor and the guarantee */
    FIXTURE(put_file(&flash, "floppy", "boot.imd", 102400, "IMD 1.18: ") == 0, "flash boot.imd");
    FIXTURE(put_file(&flash, "disk", "o1next-harddrive.img", 6291456u, NULL) == 0, "the volume");
    FIXTURE(put_file(&flash, "disk", "demo.img", LIB_DRIVEC_192K, NULL) == 0, "the valid demo");
    FIXTURE(put_file(&flash, "printer", "printout.pdf", 2048, "%PDF-1.4") == 0, "the PDF");

    /* the microSD: the semi-permanent library, and the duplicate of BOOT.IMD */
    FIXTURE(put_file(&sd, "floppy", "boot.imd", 409600, "IMD 1.18: ") == 0, "the SD boot disk");
    FIXTURE(put_file(&sd, "floppy", "my-floppy.imd", 204800, "IMD 1.18: ") == 0, "my-floppy.imd");
    FIXTURE(put_file(&sd, "disk", "drivec-192.img", LIB_DRIVEC_192K, NULL) == 0, "the blob");
    FIXTURE(put_file(&sd, "disk", "drivec-bad.img", 300000, NULL) == 0, "the wrong-sized blob");
    FIXTURE(put_file(&sd, "disk", "broken.img", 400000, NULL) == 0, "the second broken copy");

    /* the USB stick: the transient member, and both of its disk/ files are wrong */
    FIXTURE(put_file(&usb, "floppy", "utility.imd", 102400, "IMD 1.18: ") == 0, "utility.imd");
    FIXTURE(put_file(&usb, "floppy", "notes.txt", 16, "not an image") == 0, "notes.txt");
    FIXTURE(put_file(&usb, "disk", "demo.img", 300000, NULL) == 0, "the bad demo");
    FIXTURE(put_file(&usb, "disk", "broken.img", 300000, NULL) == 0, "the first broken copy");

    blockdev_file_sync(&flash_file);
    blockdev_file_sync(&sd_file);
    blockdev_file_sync(&usb_file);
}

/* ------------------------------------------------- the volume is real, on disk
 *
 * The claim that this is "a real FAT32 volume" is worth checking at the byte level
 * rather than trusting the library that wrote it: the boot sector has the
 * signature, and sector 0 is an MBR with a partition table -- because `f_mkfs`
 * partitions by default, which is what makes the volume look like a card a PC
 * formatted rather than a bare super-floppy.
 */
static void test_on_media(void)
{
    char    path[sizeof root + 64];
    FILE   *f;
    uint8_t sec[BLOCKDEV_SECTOR];

    snprintf(path, sizeof path, "%s/flash.img", root);
    f = fopen(path, "rb");
    CHECK(f != NULL, "the flash image should be on disk");
    if (f == NULL)
        return;
    CHECK(fread(sec, 1, sizeof sec, f) == sizeof sec, "the first sector should read");
    fclose(f);

    CHECK(sec[510] == 0x55u && sec[511] == 0xAAu,
          "the boot sector carries the 55 AA signature");
    CHECK(sec[446 + 4] != 0u,
          "and sector 0 is an MBR -- the volume is partitioned like a real card (type %02X)",
          sec[446 + 4]);
}

/* ------------------------------------------------------------ the volume types
 *
 * FatFS decides the FAT type from the *cluster count*, not from the BPB's "FAT32"
 * string, so this is a measurement and not an assumption.  It is also the finding
 * the doc records: at one 512-byte sector per cluster, 16 MB is FAT16 and only
 * ~34 MB and up is FAT32 -- and the external flash is specced at 16-64 MB, which
 * straddles the line.  Either type is readable by any card reader, which is what
 * the requirement was really about.
 */
static void test_volume_types(void)
{
    CHECK(flash.fs.fs_type == FS_FAT32,
          "a 64 MB volume with 512-byte clusters comes out FAT32, got type %u",
          (unsigned)flash.fs.fs_type);
    CHECK(sd.fs.fs_type == FS_FAT32,
          "and so does the microSD's, got type %u", (unsigned)sd.fs.fs_type);
    CHECK(usb.fs.fs_type == FS_FAT16,
          "a 16 MB one comes out FAT16 -- which is the finding, got type %u",
          (unsigned)usb.fs.fs_type);
}

/* --------------------------------------------------------- the long name is real
 *
 * The medium hands back the file's own long name, and that is what the identity is
 * built from -- not the 8.3 short name FatFS also keeps for the same entry.  If
 * this regresses, the library's names become `O1NEXT~1.IMG` and the merge key
 * changes with them.
 */
static void test_long_name(void)
{
    DIR     dh;
    FILINFO fno;
    int     found = 0;

    if (f_opendir(&dh, "0:/disk") != FR_OK) {
        CHECK(0, "the flash disk/ directory should open");
        return;
    }
    for (;;) {
        if (f_readdir(&dh, &fno) != FR_OK || fno.fname[0] == '\0')
            break;
        if (fno.fsize == 6291456u) {
            found = 1;
            CHECK(strcmp(fno.fname, "o1next-harddrive.img") == 0,
                  "the volume holds the LONG name, not an 8.3 mangling, got %s", fno.fname);
            CHECK(strchr(fno.fname, '~') == NULL, "and there is no tilde in it");
        }
    }
    f_closedir(&dh);
    CHECK(found, "the 6 MiB volume should be in the directory listing");
}

/* ------------------------------------------------- the seam's write, round trip */
static void test_write_round_trip(void)
{
    static const char marker[] = "O1NEXT-LIBRARY";
    char              buf[sizeof marker];

    CHECK(flash.media.ops->write(flash.media.ctx, "printer", "roundtrip.pdf",
                                 100u, marker, sizeof marker - 1u) == MEDIA_OK,
          "a write at offset 100 should land");
    memset(buf, 0, sizeof buf);
    CHECK(flash.media.ops->read(flash.media.ctx, "printer", "roundtrip.pdf",
                                100u, buf, sizeof marker - 1u) == MEDIA_OK,
          "and read back through the seam");
    CHECK(memcmp(buf, marker, sizeof marker - 1u) == 0,
          "with the bytes that were written, got %.16s", buf);

    /* the file is 100 + 15 bytes, so this read overruns it by one and is refused */
    CHECK(flash.media.ops->read(flash.media.ctx, "printer", "roundtrip.pdf",
                                0u, buf, 100u + sizeof marker) == MEDIA_ERR,
          "and a read that overruns the end is refused, not shortened");
}

/* ------------------------------------------------------- a read-only medium
 *
 * A device with no write has to report itself write-protected, so FatFS refuses the
 * write instead of failing halfway through one.  This is `diskio.c`'s behaviour,
 * and it is the difference between a clean error and a half-written file.
 */
static void test_write_protected(void)
{
    blockdev_ops ops = *flash_file.dev.ops;
    blockdev     ro;

    ops.write = NULL;
    ro.ops  = &ops;
    ro.ctx  = &flash_file;
    ro.name = "flash (read-only)";

    blockdev_register(BLOCKDEV_USB, &ro);           /* borrow the slot */
    CHECK((disk_status(BLOCKDEV_USB) & STA_PROTECT) != 0,
          "a device with no write reports itself write-protected");
    CHECK(disk_write(BLOCKDEV_USB, (const BYTE *)"x", 0, 1) == RES_WRPRT,
          "and a write to it is refused rather than attempted");
    blockdev_register(BLOCKDEV_USB, &usb_file.dev); /* put the real one back */
}

/* ------------------------------------------------------------------------ main */

static int verbose;

int main(int argc, char **argv)
{
    const media *order[3];
    char         path[sizeof root + 64];
    int          i;

    /* Unbuffered, so a crash still shows every check that had already run. */
    setbuf(stdout, NULL);

    for (i = 1; i < argc; i++)
        if (strcmp(argv[i], "-v") == 0)
            verbose = 1;

    build_fixture();

    /* The precedence order, and it is a decision: the USB stick is the transient
     * member, the microSD is the semi-permanent library, and the external flash is
     * always fitted, so it is the floor and the guarantee. */
    order[0] = &usb.media;
    order[1] = &sd.media;
    order[2] = &flash.media;

    if (verbose)
        printf("  fatfs: the shared media suite -- the same one the directory fixture gets\n");
    failures += suite_media(order, 3u, "fatfs");

    if (verbose)
        printf("  fatfs: on-media, volume-type and seam checks\n");
    test_on_media();
    test_volume_types();
    test_long_name();
    test_write_round_trip();
    test_write_protected();

    /* Tidy up: the images are 144 MB of sparse file and they are not the point. */
    blockdev_file_close(&flash_file);
    blockdev_file_close(&sd_file);
    blockdev_file_close(&usb_file);
    snprintf(path, sizeof path, "%s/flash.img", root);
    remove(path);
    snprintf(path, sizeof path, "%s/sd.img", root);
    remove(path);
    snprintf(path, sizeof path, "%s/usb.img", root);
    remove(path);
    remove(root);

    if (failures == 0) {
        printf("fatfs: all tests passed (three FAT volumes, 64/64/16 MB)\n");
        return 0;
    }
    printf("fatfs: %d check(s) failed\n", failures);
    return 1;
}
