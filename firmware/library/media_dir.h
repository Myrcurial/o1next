/* A `media` over a directory tree on the host (#283).
 *
 * This is the implementation the host tests use, and the one a developer's
 * checkout gives them for free: point it at a directory that has `floppy/`,
 * `disk/` and `printer/` under it and the library cannot tell it from the card.
 * It is host-only -- the board's implementation is FatFS (#285) -- and it exists
 * so that the library's logic is testable the moment it is written rather than
 * the moment a board exists.
 *
 * It is deliberately dumb: no FAT, no long-name handling beyond what the host
 * filesystem already does, and `list` re-opens and skips to reach index N (O(n^2)
 * over one directory, which for a library of a few hundred files on a laptop is
 * nothing, and it keeps the whole thing allocation-free).
 */
#ifndef O1_MEDIA_DIR_H
#define O1_MEDIA_DIR_H

#include "media.h"

#define MEDIA_DIR_ROOT_MAX 512

typedef struct {
    media media;                        /* .ops and .ctx -- pass &m.media */
    char  root[MEDIA_DIR_ROOT_MAX];
} media_dir;

/* `root` is the volume root.  Returns MEDIA_OK, or MEDIA_ERR if the root is too
 * long or is not a directory. */
int media_dir_init(media_dir *m, const char *root);

#endif /* O1_MEDIA_DIR_H */
