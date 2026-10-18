/* The block-device table -- see blockdev.h (#285).
 *
 * It is its own file rather than part of diskio.c so that the table can be used
 * (and tested) without FatFS: `diskio.c` is the only place that includes FatFS's
 * headers, and everything else in the module stays free of them.
 */
#include "blockdev.h"

static const blockdev *slots[BLOCKDEV_COUNT];

void blockdev_register(unsigned pdrv, const blockdev *dev)
{
    if (pdrv < BLOCKDEV_COUNT)
        slots[pdrv] = dev;
}

const blockdev *blockdev_get(unsigned pdrv)
{
    return pdrv < BLOCKDEV_COUNT ? slots[pdrv] : NULL;
}

void blockdev_reset(void)
{
    unsigned i;

    for (i = 0; i < BLOCKDEV_COUNT; i++)
        slots[i] = NULL;
}
