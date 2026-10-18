/* A `blockdev` over a file on the host -- a FAT volume image in a file (#285).
 *
 * This is the piece that makes FatFS testable with no board: a volume is an image
 * file, the device reads and writes 512-byte sectors in it, and everything above
 * -- FatFS, `diskio.c`, `media_fatfs.c`, the library -- cannot tell it from a card.
 * Host-only, like `media_dir.c`, and for the same reason.
 *
 * The one thing to know: it buffers, so **`blockdev_file_sync()` before reading the
 * image behind its back**.  A real device has the same property (writes land when
 * the device says so), which is why the seam has a `sync` at all.
 */
#ifndef O1_BLOCKDEV_FILE_H
#define O1_BLOCKDEV_FILE_H

#include <stdio.h>

#include "blockdev.h"

#define BLOCKDEV_FILE_PATH_MAX 512

typedef struct {
    blockdev dev;                          /* .ops, .ctx and .name -- pass &b.dev */
    FILE    *f;
    char     path[BLOCKDEV_FILE_PATH_MAX];
    uint32_t sectors;
} blockdev_file;

/* Make an image of `sectors` 512-byte sectors, truncating any existing file.  It
 * is written sparsely -- a seek and one byte -- so a 64 MB image costs a block
 * rather than 64 MB, which is what keeps the test volumes cheap. */
int blockdev_file_create(const char *path, uint32_t sectors);

/* Open an existing image.  BLOCKDEV_OK, or BLOCKDEV_ERR if the file is missing,
 * empty, or not a whole number of sectors. */
int blockdev_file_init(blockdev_file *b, const char *path, const char *name);

/* Flush to the file, so a test can inspect the image. */
int blockdev_file_sync(blockdev_file *b);

void blockdev_file_close(blockdev_file *b);

#endif /* O1_BLOCKDEV_FILE_H */
