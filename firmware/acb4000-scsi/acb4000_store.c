/* The ACB-4000's backing store -- layer 3 of the personality (#179).
 *
 * The controller sees its drive through five calls, so the target never has to
 * know whether it is talking to a malloc'd buffer (here, and in the host tests)
 * or the FAT32 blob the interposer will really use (#180).  Keeping the split at
 * this seam is what makes the target testable without a board.
 *
 * The one property worth stating: `format()` writes the fill byte across the
 * *whole* unit, which is what the controller's FORMAT command does -- so a
 * freshly formatted volume is one repeated byte and #180's sparse encoding has
 * something to key on.  `fill` is remembered rather than assumed, because the
 * controller's default (6Ch) and CP/M's (E5h) are different bytes.
 */
#include "acb4000.h"

#include <stdlib.h>
#include <string.h>

static uint32_t mem_capacity(void *ctx)
{
    const acb4000_mem_store *m = (const acb4000_mem_store *)ctx;
    /* READ CAPACITY reports the *last* block address, not the block count. */
    return m->blocks ? (m->blocks - 1u) : 0u;
}

static uint32_t mem_block_size(void *ctx)
{
    const acb4000_mem_store *m = (const acb4000_mem_store *)ctx;
    return m->block_size;
}

static int mem_read(void *ctx, uint32_t lba, uint32_t count, uint8_t *out)
{
    const acb4000_mem_store *m = (const acb4000_mem_store *)ctx;
    if (count == 0 || lba + count > m->blocks)
        return -1;
    memcpy(out, m->data + (size_t)lba * m->block_size,
           (size_t)count * m->block_size);
    return 0;
}

static int mem_write(void *ctx, uint32_t lba, uint32_t count, const uint8_t *in)
{
    acb4000_mem_store *m = (acb4000_mem_store *)ctx;
    if (count == 0 || lba + count > m->blocks)
        return -1;
    memcpy(m->data + (size_t)lba * m->block_size, in,
           (size_t)count * m->block_size);
    return 0;
}

static int mem_format(void *ctx, uint8_t fill)
{
    acb4000_mem_store *m = (acb4000_mem_store *)ctx;
    memset(m->data, fill, (size_t)m->blocks * m->block_size);
    m->fill = fill;
    m->formatted = 1;
    return 0;
}

int acb4000_mem_store_init(acb4000_mem_store *m, uint32_t blocks,
                           uint32_t block_size, uint8_t fill)
{
    if (m == NULL || blocks == 0)
        return -1;
    if (block_size < ACB4000_BLOCK_MIN || block_size > ACB4000_BLOCK_MAX)
        return -1;

    memset(m, 0, sizeof *m);
    m->blocks = blocks;
    m->block_size = block_size;
    m->fill = fill;
    m->data = (uint8_t *)malloc((size_t)blocks * block_size);
    if (m->data == NULL)
        return -1;
    memset(m->data, fill, (size_t)blocks * block_size);
    m->formatted = 1;

    m->store.ctx = m;
    m->store.capacity = mem_capacity;
    m->store.block_size = mem_block_size;
    m->store.read = mem_read;
    m->store.write = mem_write;
    m->store.format = mem_format;
    return 0;
}

void acb4000_mem_store_free(acb4000_mem_store *m)
{
    if (m == NULL)
        return;
    free(m->data);
    m->data = NULL;
    m->blocks = 0;
}
