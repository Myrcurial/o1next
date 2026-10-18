/* A `media` over a directory tree on the host -- see media_dir.h (#283). */
#include "media_dir.h"

#include <dirent.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>

#define MEDIA_DIR_PATH_MAX (MEDIA_DIR_ROOT_MAX + MEDIA_NAME_MAX + 8)

static int build_path(char *out, size_t cap, const media_dir *m,
                      const char *dir, const char *name)
{
    int n;

    if (name != NULL)
        n = snprintf(out, cap, "%s/%s/%s", m->root, dir, name);
    else
        n = snprintf(out, cap, "%s/%s", m->root, dir);
    if (n < 0 || (size_t)n >= cap)
        return MEDIA_ERR;
    return MEDIA_OK;
}

static int dir_list(void *ctx, const char *dir, unsigned index, media_entry *out)
{
    const media_dir *m = (const media_dir *)ctx;
    char             path[MEDIA_DIR_PATH_MAX];
    char             full[MEDIA_DIR_PATH_MAX];
    DIR             *d;
    struct dirent   *ent;
    unsigned         seen = 0;

    if (out == NULL || build_path(path, sizeof path, m, dir, NULL) != MEDIA_OK)
        return MEDIA_ERR;

    d = opendir(path);
    if (d == NULL)
        return MEDIA_END;   /* no such directory is an empty medium, not a fault */

    while ((ent = readdir(d)) != NULL) {
        struct stat st;
        size_t      len;

        /* `.`, `..` and anything hidden -- and this is also what keeps a macOS
         * volume's `._name` sidecars out of the library. */
        if (ent->d_name[0] == '.')
            continue;
        if (build_path(full, sizeof full, m, dir, ent->d_name) != MEDIA_OK)
            continue;
        if (stat(full, &st) != 0 || !S_ISREG(st.st_mode))
            continue;       /* directories are not library entries */
        if (seen++ < index)
            continue;

        memset(out, 0, sizeof *out);
        len = strlen(ent->d_name);
        if (len > MEDIA_NAME_MAX - 1u)
            len = MEDIA_NAME_MAX - 1u;
        memcpy(out->name, ent->d_name, len);
        out->size = (uint32_t)st.st_size;
        closedir(d);
        return MEDIA_OK;
    }

    closedir(d);
    return MEDIA_END;
}

static int dir_stat(void *ctx, const char *dir, const char *name, uint32_t *size)
{
    const media_dir *m = (const media_dir *)ctx;
    char             path[MEDIA_DIR_PATH_MAX];
    struct stat      st;

    if (name == NULL || build_path(path, sizeof path, m, dir, name) != MEDIA_OK)
        return MEDIA_ERR;
    if (stat(path, &st) != 0 || !S_ISREG(st.st_mode))
        return MEDIA_ERR;
    if (size != NULL)
        *size = (uint32_t)st.st_size;
    return MEDIA_OK;
}

static int dir_read(void *ctx, const char *dir, const char *name,
                    uint32_t offset, void *buf, size_t len)
{
    const media_dir *m = (const media_dir *)ctx;
    char             path[MEDIA_DIR_PATH_MAX];
    struct stat      st;
    FILE            *f;
    size_t           got;

    if (name == NULL || buf == NULL)
        return MEDIA_ERR;
    if (build_path(path, sizeof path, m, dir, name) != MEDIA_OK)
        return MEDIA_ERR;

    /* The size is checked *first*, because the contract in media.h is that a read
     * past the end of the file is refused -- and a `fread` that comes back short
     * has already written past the end of the caller's buffer.  (This test's own
     * 999999-byte read is what found it: the check used to be on the return
     * value.) */
    if (stat(path, &st) != 0 || !S_ISREG(st.st_mode))
        return MEDIA_ERR;
    if ((uint64_t)offset + (uint64_t)len > (uint64_t)st.st_size)
        return MEDIA_ERR;

    f = fopen(path, "rb");
    if (f == NULL)
        return MEDIA_ERR;
    if (fseek(f, (long)offset, SEEK_SET) != 0) {
        fclose(f);
        return MEDIA_ERR;
    }
    got = fread(buf, 1, len, f);
    fclose(f);
    return got == len ? MEDIA_OK : MEDIA_ERR;
}

static int dir_write(void *ctx, const char *dir, const char *name,
                     uint32_t offset, const void *buf, size_t len)
{
    const media_dir *m = (const media_dir *)ctx;
    char             path[MEDIA_DIR_PATH_MAX];
    FILE            *f;

    if (name == NULL || buf == NULL)
        return MEDIA_ERR;
    if (build_path(path, sizeof path, m, dir, name) != MEDIA_OK)
        return MEDIA_ERR;

    f = fopen(path, "r+b");
    if (f == NULL)
        f = fopen(path, "w+b");
    if (f == NULL)
        return MEDIA_ERR;
    if (fseek(f, (long)offset, SEEK_SET) != 0 || fwrite(buf, 1, len, f) != len) {
        fclose(f);
        return MEDIA_ERR;
    }
    fclose(f);
    return MEDIA_OK;
}

static const struct media_ops media_dir_ops = {
    "dir", dir_list, dir_stat, dir_read, dir_write
};

int media_dir_init(media_dir *m, const char *root)
{
    struct stat st;
    size_t      n;

    if (m == NULL || root == NULL)
        return MEDIA_ERR;

    memset(m, 0, sizeof *m);
    n = strlen(root);
    if (n >= MEDIA_DIR_ROOT_MAX)
        return MEDIA_ERR;
    memcpy(m->root, root, n + 1);

    if (stat(m->root, &st) != 0 || !S_ISDIR(st.st_mode))
        return MEDIA_ERR;

    m->media.ops = &media_dir_ops;
    m->media.ctx = m;
    return MEDIA_OK;
}
