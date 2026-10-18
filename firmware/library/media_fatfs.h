/* A `media` over FatFS -- the library's view of a FAT volume (#285).
 *
 * This is the implementation the board runs, not a host stand-in: it is the same
 * code over the external flash, the microSD and the USB stick, because all three
 * arrive as a block device and FatFS is above that.  `media_dir.c` is the host's
 * convenience; this is the real thing, and the suite runs it over volume images so
 * that what is tested is what ships.
 *
 * One instance per drive.  FatFS keeps one `FATFS` object per logical drive in a
 * global table, so two `media_fatfs` on the same `pdrv` would fight over it -- and
 * there is no reason for two, because the library wants exactly one view per
 * medium.
 */
#ifndef O1_MEDIA_FATFS_H
#define O1_MEDIA_FATFS_H

#include "ff.h"

#include "media.h"

/* "<pdrv>:/" + a directory + MEDIA_NAME_MAX, with room to spare. */
#define MEDIA_FATFS_PATH_MAX 128

typedef struct {
    media    media;                     /* .ops and .ctx -- pass &m.media */
    FATFS    fs;                        /* FatFS's own state for this drive */
    unsigned pdrv;                      /* BLOCKDEV_FLASH / _SD / _USB */
    char     prefix[4];                 /* "0:" */
} media_fatfs;

/* Register the volume with FatFS.  BLOCKDEV_OK, or BLOCKDEV_ERR if the drive
 * number is out of range.
 *
 * It does **not** mount: FatFS mounts on the first access, which is what makes a
 * missing card or an unformatted stick a normal answer ("nothing there") rather
 * than a failure at start-up.  The library is built to work with no card and no
 * stick, so that is the behaviour it wants. */
int media_fatfs_init(media_fatfs *m, unsigned pdrv);

#endif /* O1_MEDIA_FATFS_H */
