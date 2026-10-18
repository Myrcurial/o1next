/* A `media` over FatFS -- see media_fatfs.h (#285).
 *
 * The three rules media.h states are enforced here, and two of them are the ones
 * that cost something to get wrong:
 *
 *   - a read past the end of a file is refused **before** the read, because a
 *     short read has already written past the caller's buffer (the bug
 *     media_dir.c had, and the suite caught);
 *   - a directory that does not exist is an *empty medium*, not a fault, because
 *     "no card" and "a card with no floppy/ on it" are both ordinary;
 *   - and `f_write` may write less than it was asked to, so it is looped.
 */
#include "media_fatfs.h"

#include <stdio.h>
#include <string.h>

#include "blockdev.h"

static int build_path(char *out, size_t cap, const media_fatfs *m,
                      const char *dir, const char *name)
{
    int n;

    if (name != NULL)
        n = snprintf(out, cap, "%s/%s/%s", m->prefix, dir, name);
    else
        n = snprintf(out, cap, "%s/%s", m->prefix, dir);
    if (n < 0 || (size_t)n >= cap)
        return MEDIA_ERR;
    return MEDIA_OK;
}

static void copy_name(char *out, const char *in)
{
    size_t len = strlen(in);

    memset(out, 0, MEDIA_NAME_MAX);
    if (len > MEDIA_NAME_MAX - 1u)
        len = MEDIA_NAME_MAX - 1u;
    memcpy(out, in, len);
}

static int fatfs_list(void *ctx, const char *dir, unsigned index, media_entry *out)
{
    media_fatfs *m = (media_fatfs *)ctx;
    char         path[MEDIA_FATFS_PATH_MAX];
    FILINFO      fno;
    DIR          dh;
    unsigned     seen = 0;

    if (out == NULL || build_path(path, sizeof path, m, dir, NULL) != MEDIA_OK)
        return MEDIA_ERR;

    if (f_opendir(&dh, path) != FR_OK)
        return MEDIA_END;   /* no such directory is an empty medium, not a fault */

    for (;;) {
        if (f_readdir(&dh, &fno) != FR_OK)
            break;
        if (fno.fname[0] == '\0')
            break;                      /* the end of the directory */
        if (fno.fname[0] == '.')
            continue;                   /* . , .. and anything hidden */
        if (fno.fattrib & AM_DIR)
            continue;                   /* directories are not library entries */
        if (seen++ < index)
            continue;

        memset(out, 0, sizeof *out);
        copy_name(out->name, fno.fname);
        out->size = (uint32_t)fno.fsize;
        f_closedir(&dh);
        return MEDIA_OK;
    }

    f_closedir(&dh);
    return MEDIA_END;
}

static int fatfs_stat(void *ctx, const char *dir, const char *name, uint32_t *size)
{
    media_fatfs *m = (media_fatfs *)ctx;
    char         path[MEDIA_FATFS_PATH_MAX];
    FILINFO      fno;

    if (name == NULL || build_path(path, sizeof path, m, dir, name) != MEDIA_OK)
        return MEDIA_ERR;
    if (f_stat(path, &fno) != FR_OK || (fno.fattrib & AM_DIR))
        return MEDIA_ERR;
    if (size != NULL)
        *size = (uint32_t)fno.fsize;
    return MEDIA_OK;
}

static int fatfs_read(void *ctx, const char *dir, const char *name,
                      uint32_t offset, void *buf, size_t len)
{
    media_fatfs *m = (media_fatfs *)ctx;
    char         path[MEDIA_FATFS_PATH_MAX];
    FILINFO      fno;
    FIL          f;
    UINT         got = 0;

    if (name == NULL || buf == NULL || len == 0u)
        return MEDIA_ERR;
    if (build_path(path, sizeof path, m, dir, name) != MEDIA_OK)
        return MEDIA_ERR;

    /* The size first.  A `f_read` that comes back short has already written past
     * the end of the caller's buffer, so the check cannot be on the return value
     * -- which is exactly the bug the host media had. */
    if (f_stat(path, &fno) != FR_OK || (fno.fattrib & AM_DIR))
        return MEDIA_ERR;
    if ((uint64_t)offset + (uint64_t)len > (uint64_t)fno.fsize)
        return MEDIA_ERR;

    if (f_open(&f, path, FA_READ) != FR_OK)
        return MEDIA_ERR;
    if (f_lseek(&f, (FSIZE_t)offset) != FR_OK) {
        f_close(&f);
        return MEDIA_ERR;
    }
    if (f_read(&f, buf, (UINT)len, &got) != FR_OK) {
        f_close(&f);
        return MEDIA_ERR;
    }
    f_close(&f);
    return got == (UINT)len ? MEDIA_OK : MEDIA_ERR;
}

static int fatfs_write(void *ctx, const char *dir, const char *name,
                       uint32_t offset, const void *buf, size_t len)
{
    media_fatfs *m = (media_fatfs *)ctx;
    char         path[MEDIA_FATFS_PATH_MAX];
    FIL          f;
    const BYTE  *p = (const BYTE *)buf;
    size_t       done = 0;

    if (name == NULL || buf == NULL || len == 0u)
        return MEDIA_ERR;
    if (build_path(path, sizeof path, m, dir, name) != MEDIA_OK)
        return MEDIA_ERR;

    if (f_open(&f, path, FA_READ | FA_WRITE | FA_OPEN_ALWAYS) != FR_OK)
        return MEDIA_ERR;
    if (f_lseek(&f, (FSIZE_t)offset) != FR_OK) {
        f_close(&f);
        return MEDIA_ERR;
    }

    /* f_write may write less than it was asked to; a zero-length write is the only
     * real failure. */
    while (done < len) {
        UINT wrote = 0;

        if (f_write(&f, p + done, (UINT)(len - done), &wrote) != FR_OK || wrote == 0u) {
            f_close(&f);
            return MEDIA_ERR;
        }
        done += wrote;
    }
    f_sync(&f);
    f_close(&f);
    return MEDIA_OK;
}

static const struct media_ops fatfs_ops = {
    "fatfs",
    fatfs_list,
    fatfs_stat,
    fatfs_read,
    fatfs_write
};

int media_fatfs_init(media_fatfs *m, unsigned pdrv)
{
    if (m == NULL || pdrv >= BLOCKDEV_COUNT)
        return BLOCKDEV_ERR;

    memset(m, 0, sizeof *m);
    m->pdrv   = pdrv;
    m->prefix[0] = (char)('0' + (int)pdrv);
    m->prefix[1] = ':';
    m->prefix[2] = '\0';

    /* opt = 0: register, and mount on the first access.  A card that is absent or
     * unformatted then reads as an empty medium rather than failing here. */
    if (f_mount(&m->fs, m->prefix, 0) != FR_OK)
        return BLOCKDEV_ERR;

    m->media.ops = &fatfs_ops;
    m->media.ctx = m;
    return BLOCKDEV_OK;
}
