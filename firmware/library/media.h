/* The media seam -- what the image library needs from storage (#283, #192).
 *
 * The library never touches a filesystem.  It asks a `media` for a directory
 * listing, a size and some bytes, and that is the whole interface -- so the same
 * library code runs over a directory on a developer's laptop (media_dir.c, which
 * is what the host tests use) and over FatFS on the interposer (#285).  It is the
 * same trick as `acb4000_store.c`'s five calls, and for the same reason: the seam
 * is what makes the logic testable without a board.
 *
 * Three media, one namespace.  The interposer carries three library media -- the
 * external SPI flash module, one microSD and one USB stick, all FAT32 -- and `lib`
 * merges them (library.h).  The order they are handed to lib_init() *is* the
 * precedence order, and it is a decision rather than a default: **USB stick,
 * microSD, external flash**.  The stick is the transient member -- plugging one in
 * with a demo image is how you test something, so it wins -- the microSD is the
 * semi-permanent library, and the external flash is always fitted, so it is the
 * floor and the guarantee.  And a copy that is invalid for its kind falls through
 * to the next medium, so a bad file on a stick still lands on something that works.
 *
 * The RP2354B's own in-package 2 MB flash is NOT a medium.  It holds the firmware
 * and its assets -- the boot splash animation -- and nothing here reaches it.
 *
 * Every call is indexed and allocation-free, because the board has no heap to
 * spare: `list` walks a directory one entry at a time rather than building a list.
 */
#ifndef O1_MEDIA_H
#define O1_MEDIA_H

#include <stddef.h>
#include <stdint.h>

/* The longest name a medium may hand back, extension included.  FAT long names
 * run to 255, but the library only ever keeps the CP/M 8.3 identity (LIB_NAME_LEN,
 * 16) and this is the room to *find* a file by the name it is stored under. */
#define MEDIA_NAME_MAX 64

typedef struct {
    char     name[MEDIA_NAME_MAX];  /* as stored, extension included */
    uint32_t size;
} media_entry;

typedef struct media media;

#define MEDIA_OK   0
#define MEDIA_END  1
#define MEDIA_ERR (-1)

struct media_ops {
    const char *id;             /* "flash", "sd", "usb" -- for logs and tests */

    /* The entry at `index` in `dir`, 0-based.  Stable until the medium changes. */
    int (*list)(void *ctx, const char *dir, unsigned index, media_entry *out);

    int (*stat)(void *ctx, const char *dir, const char *name, uint32_t *size);

    /* A read that would run past the end of the file is refused, not shortened. */
    int (*read)(void *ctx, const char *dir, const char *name,
                uint32_t offset, void *buf, size_t len);

    /* Not used by the library yet -- the printer (#19) and the web UI (#182) are
     * the writers.  Here so that the seam is the whole interface. */
    int (*write)(void *ctx, const char *dir, const char *name,
                 uint32_t offset, const void *buf, size_t len);
};

struct media {
    const struct media_ops *ops;
    void                   *ctx;
};

#endif /* O1_MEDIA_H */
