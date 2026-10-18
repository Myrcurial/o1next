/* FatFS's port -- the only file in this module that knows FatFS exists (#285).
 *
 * FatFS wants five functions and nothing else; this maps them onto `blockdev`, so
 * a filesystem can be mounted on a file in a test, a microSD on the board, or the
 * external NOR flash behind the FTL, with no change above this file.
 *
 * Three things here are worth more than they look:
 *
 *  - **A device with no `write` reports itself write-protected** (`STA_PROTECT`),
 *    so a read-only medium is refused by FatFS rather than failing halfway
 *    through a write.
 *  - **A missing or absent device is `STA_NOINIT`**, not a crash: the library is
 *    built to work with no card and no stick, so "no medium" is a normal answer.
 *  - **A short transfer is an error** (`RES_ERROR`), never a partial success --
 *    which is the same rule `media.h` states one layer up.
 *
 * `ff.h` comes first because `diskio.h` uses its integer types and says so; that is
 * FatFS's own convention, and its `diskio.c` template does the same.
 */
#include "ff.h"
#include "diskio.h"

#include "blockdev.h"

DSTATUS disk_status(BYTE pdrv)
{
    const blockdev *d = blockdev_get(pdrv);
    DSTATUS         st;

    if (d == NULL || d->ops == NULL)
        return STA_NOINIT;

    st = d->ops->status != NULL ? (DSTATUS)d->ops->status(d->ctx) : 0;
    if (d->ops->write == NULL)
        st |= STA_PROTECT;          /* read-only medium */
    return st;
}

DSTATUS disk_initialize(BYTE pdrv)
{
    const blockdev *d = blockdev_get(pdrv);

    if (d == NULL || d->ops == NULL || d->ops->initialize == NULL)
        return STA_NOINIT;
    if (d->ops->initialize(d->ctx) != BLOCKDEV_OK)
        return STA_NOINIT;
    return disk_status(pdrv);
}

DRESULT disk_read(BYTE pdrv, BYTE *buff, LBA_t sector, UINT count)
{
    const blockdev *d = blockdev_get(pdrv);

    if (d == NULL || d->ops == NULL || d->ops->read == NULL)
        return RES_NOTRDY;
    if (buff == NULL || count == 0)
        return RES_PARERR;
    if (d->ops->read(d->ctx, (uint32_t)sector, buff, (unsigned)count) != BLOCKDEV_OK)
        return RES_ERROR;
    return RES_OK;
}

DRESULT disk_write(BYTE pdrv, const BYTE *buff, LBA_t sector, UINT count)
{
    const blockdev *d = blockdev_get(pdrv);

    if (d == NULL || d->ops == NULL)
        return RES_NOTRDY;
    if (d->ops->write == NULL)
        return RES_WRPRT;
    if (buff == NULL || count == 0)
        return RES_PARERR;
    if (d->ops->write(d->ctx, (uint32_t)sector, buff, (unsigned)count) != BLOCKDEV_OK)
        return RES_ERROR;
    return RES_OK;
}

DRESULT disk_ioctl(BYTE pdrv, BYTE cmd, void *buff)
{
    const blockdev *d = blockdev_get(pdrv);

    if (d == NULL || d->ops == NULL)
        return RES_NOTRDY;

    switch (cmd) {
    case CTRL_SYNC:
        if (d->ops->sync == NULL)
            return RES_OK;
        return d->ops->sync(d->ctx) == BLOCKDEV_OK ? RES_OK : RES_ERROR;

    case GET_SECTOR_COUNT: {
        uint32_t n = 0;

        if (buff == NULL || d->ops->sectors == NULL)
            return RES_PARERR;
        if (d->ops->sectors(d->ctx, &n) != BLOCKDEV_OK)
            return RES_ERROR;
        *(DWORD *)buff = (DWORD)n;
        return RES_OK;
    }

    case GET_SECTOR_SIZE:
        /* FatFS is configured with FF_MIN_SS == FF_MAX_SS, so it never asks -- but
         * answering is one line and it keeps the port complete. */
        if (buff == NULL)
            return RES_PARERR;
        *(WORD *)buff = (WORD)BLOCKDEV_SECTOR;
        return RES_OK;

    case GET_BLOCK_SIZE: {
        uint32_t n = 1;

        if (buff == NULL)
            return RES_PARERR;
        if (d->ops->block_size != NULL &&
            d->ops->block_size(d->ctx, &n) != BLOCKDEV_OK)
            return RES_ERROR;
        *(DWORD *)buff = (DWORD)n;
        return RES_OK;
    }

    case CTRL_TRIM:
    default:
        /* FF_USE_TRIM is 0 so nothing asks, and a device that cannot trim should
         * say so rather than pretend it did. */
        return RES_PARERR;
    }
}
