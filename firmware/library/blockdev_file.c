/* A `blockdev` over a file on the host -- see blockdev_file.h (#285). */
#include "blockdev_file.h"

#include <string.h>

static int file_status(void *ctx)
{
    (void)ctx;
    return 0;                   /* a file that is open is a medium that is ready */
}

static int file_initialize(void *ctx)
{
    blockdev_file *b = (blockdev_file *)ctx;

    if (b->f == NULL)
        return BLOCKDEV_ERR;
    clearerr(b->f);
    return BLOCKDEV_OK;
}

static int file_read(void *ctx, uint32_t sector, void *buf, unsigned count)
{
    blockdev_file *b = (blockdev_file *)ctx;

    if (fseek(b->f, (long)((uint64_t)sector * BLOCKDEV_SECTOR), SEEK_SET) != 0)
        return BLOCKDEV_ERR;
    /* A short read is a failure, not a partial success -- media.h's rule, and
     * FatFS's. */
    return fread(buf, BLOCKDEV_SECTOR, count, b->f) == count ? BLOCKDEV_OK : BLOCKDEV_ERR;
}

static int file_write(void *ctx, uint32_t sector, const void *buf, unsigned count)
{
    blockdev_file *b = (blockdev_file *)ctx;

    if (fseek(b->f, (long)((uint64_t)sector * BLOCKDEV_SECTOR), SEEK_SET) != 0)
        return BLOCKDEV_ERR;
    return fwrite(buf, BLOCKDEV_SECTOR, count, b->f) == count ? BLOCKDEV_OK : BLOCKDEV_ERR;
}

static int file_sectors(void *ctx, uint32_t *count)
{
    const blockdev_file *b = (const blockdev_file *)ctx;

    if (count == NULL)
        return BLOCKDEV_ERR;
    *count = b->sectors;
    return BLOCKDEV_OK;
}

static int file_block_size(void *ctx, uint32_t *sectors)
{
    (void)ctx;
    if (sectors == NULL)
        return BLOCKDEV_ERR;
    /* A file has no erase block.  The external NOR flash's device does, and that is
     * the number f_mkfs aligns to -- this one is honest that it has none. */
    *sectors = 1u;
    return BLOCKDEV_OK;
}

static int file_sync(void *ctx)
{
    blockdev_file *b = (blockdev_file *)ctx;

    return fflush(b->f) == 0 ? BLOCKDEV_OK : BLOCKDEV_ERR;
}

static const blockdev_ops file_ops = {
    file_initialize,
    file_status,
    file_read,
    file_write,
    file_sectors,
    file_block_size,
    file_sync
};

int blockdev_file_create(const char *path, uint32_t sectors)
{
    FILE *f;

    if (path == NULL || sectors == 0u)
        return BLOCKDEV_ERR;

    f = fopen(path, "wb");
    if (f == NULL)
        return BLOCKDEV_ERR;

    /* Sparse: seek to the last byte and write it, so the file has the right length
     * without the space. */
    if (fseek(f, (long)((uint64_t)sectors * BLOCKDEV_SECTOR) - 1L, SEEK_SET) != 0 ||
        fputc(0, f) == EOF) {
        fclose(f);
        return BLOCKDEV_ERR;
    }
    fclose(f);
    return BLOCKDEV_OK;
}

int blockdev_file_init(blockdev_file *b, const char *path, const char *name)
{
    long size;
    size_t n;

    if (b == NULL || path == NULL)
        return BLOCKDEV_ERR;

    memset(b, 0, sizeof *b);
    n = strlen(path);
    if (n >= BLOCKDEV_FILE_PATH_MAX)
        return BLOCKDEV_ERR;
    memcpy(b->path, path, n + 1);

    b->f = fopen(b->path, "r+b");
    if (b->f == NULL)
        return BLOCKDEV_ERR;

    if (fseek(b->f, 0L, SEEK_END) != 0) {
        fclose(b->f);
        b->f = NULL;
        return BLOCKDEV_ERR;
    }
    size = ftell(b->f);
    if (size <= 0 || (size % (long)BLOCKDEV_SECTOR) != 0) {
        fclose(b->f);
        b->f = NULL;
        return BLOCKDEV_ERR;
    }
    rewind(b->f);

    b->sectors      = (uint32_t)(size / (long)BLOCKDEV_SECTOR);
    b->dev.ops      = &file_ops;
    b->dev.ctx      = b;
    b->dev.name     = name;
    return BLOCKDEV_OK;
}

int blockdev_file_sync(blockdev_file *b)
{
    return file_sync(b);
}

void blockdev_file_close(blockdev_file *b)
{
    if (b != NULL && b->f != NULL) {
        fclose(b->f);
        b->f = NULL;
    }
}
