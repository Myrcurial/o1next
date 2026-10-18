/* The block-device seam -- what FatFS's `diskio` talks to (#285).
 *
 * FatFS wants five functions (`disk_initialize`, `disk_status`, `disk_read`,
 * `disk_write`, `disk_ioctl`) and knows nothing about SPI, USB or NOR flash.  So
 * the port is split in two, and the split is the same trick as `media.h` one layer
 * up: `diskio.c` is the *port* -- portable, and the only file that knows FatFS --
 * and a `blockdev` is a *device*.
 *
 * That is what lets the filesystem be exercised on a laptop.  The host build
 * registers three file-backed devices (`blockdev_file.c`); the board registers the
 * real transports (the external NOR flash behind the FTL, the microSD over SPI,
 * and the USB stick over TinyUSB MSC).  Nothing above `blockdev` changes.
 *
 * **The three logical drives are the three library media, and the numbering is
 * load-bearing** -- it is what FatFS puts in a path ("0:/floppy/boot.imd") and
 * what `media_fatfs` is handed.
 *
 * Everything here is 512-byte sectors, because `ffconf.h` pins
 * `FF_MIN_SS == FF_MAX_SS == 512`: one size means FatFS never asks
 * `GET_SECTOR_SIZE`, and the buffers are a known size.
 */
#ifndef O1_BLOCKDEV_H
#define O1_BLOCKDEV_H

#include <stddef.h>
#include <stdint.h>

/* The three library media, as FatFS logical drives.  Fixed: see above. */
#define BLOCKDEV_FLASH 0u
#define BLOCKDEV_SD    1u
#define BLOCKDEV_USB   2u
#define BLOCKDEV_COUNT 3u

#define BLOCKDEV_OK    0
#define BLOCKDEV_ERR (-1)

#define BLOCKDEV_SECTOR 512u

/* The DSTATUS bits FatFS defines, restated so this header stands alone. */
#define BLOCKDEV_NOINIT  0x01u
#define BLOCKDEV_NODISK  0x02u
#define BLOCKDEV_PROTECT 0x04u

typedef struct {
    /* Bring the device up.  BLOCKDEV_OK, or BLOCKDEV_ERR.  Called once per mount,
     * not once per read. */
    int (*initialize)(void *ctx);

    /* The DSTATUS bits: 0 ready, else BLOCKDEV_NOINIT / NODISK / PROTECT. */
    int (*status)(void *ctx);

    /* `count` sectors from/to `sector`.  BLOCKDEV_OK, or BLOCKDEV_ERR.  A short
     * transfer is an error, never a partial success. */
    int (*read)(void *ctx, uint32_t sector, void *buf, unsigned count);
    int (*write)(void *ctx, uint32_t sector, const void *buf, unsigned count);

    /* The whole device, in sectors.  Needed by `f_mkfs`, and by anything that wants
     * to report free space. */
    int (*sectors)(void *ctx, uint32_t *count);

    /* The device's erase block, in sectors -- what `f_mkfs` aligns to, and what
     * tells it whether a 512-byte cluster is even sensible.  Optional: NULL means
     * one sector. */
    int (*block_size)(void *ctx, uint32_t *sectors);

    /* Everything written is on the media.  Optional; NULL means "nothing to do".
     * The host device buffers, so this is `fflush` and it matters to a test that
     * inspects the image. */
    int (*sync)(void *ctx);
} blockdev_ops;

typedef struct {
    const blockdev_ops *ops;
    void               *ctx;
    const char         *name;   /* "flash", "sd", "usb" -- for logs */
} blockdev;

/* The table `diskio.c` dispatches through.  Registering NULL clears a slot, which
 * is how a test puts the table back the way it found it. */
void            blockdev_register(unsigned pdrv, const blockdev *dev);
const blockdev *blockdev_get(unsigned pdrv);

/* Clear all three slots. */
void            blockdev_reset(void);

#endif /* O1_BLOCKDEV_H */
