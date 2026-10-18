/* The image library -- see library.h for what this is and why (#283, #192).
 *
 * Nothing in here touches a filesystem, a clock or a pin: it is a walk over
 * `media` plus the two rules the protocol fixes -- the CP/M 8.3 identity, and the
 * kind-to-slot rule.  That is what lets the whole module be tested on a laptop.
 */
#include "library.h"

#include <string.h>

const char *const lib_dir_name[LIB_DIRS] = { "floppy", "disk", "printer" };

int lib_dir_mountable(unsigned dir)
{
    /* `printer/` is output, not a library: the web UI lists it (#182) and the
     * mailbox never sees it.  It is in the table so that the exclusion is
     * deliberate and stated, rather than an omission somebody re-adds later. */
    return dir == LIB_DIR_FLOPPY || dir == LIB_DIR_DISK;
}

/* ------------------------------------------------------------------ names
 *
 * FAT names arrive in whatever case the user typed, and the library's identity is
 * upper case 8.3 -- so both of these fold case, and neither allocates.
 */

static char upper(char c)
{
    return (c >= 'a' && c <= 'z') ? (char)(c - 'a' + 'A') : c;
}

static const char *extension(const char *file)
{
    const char *dot = strrchr(file, '.');
    if (dot == NULL || dot[1] == '\0')
        return "";
    return dot + 1;
}

static int ext_is(const char *file, const char *want)
{
    const char *e = extension(file);

    for (; *e != '\0' && *want != '\0'; e++, want++)
        if (upper(*e) != upper(*want))
            return 0;
    return *e == '\0' && *want == '\0';
}

void lib_identity(const char *file, char out[LIB_NAME_LEN])
{
    const char *base;
    const char *dot;
    const char *p;
    unsigned n = 0;

    memset(out, 0, LIB_NAME_LEN);
    if (file == NULL)
        return;

    /* the stored name, not the path */
    base = file;
    for (p = file; *p != '\0'; p++)
        if (*p == '/' || *p == '\\')
            base = p + 1;

    dot = strrchr(base, '.');
    for (p = base; *p != '\0' && p != dot && n < 8u; p++)
        out[n++] = upper(*p);

    if (dot != NULL && dot[1] != '\0') {
        out[n++] = '.';
        for (p = dot + 1; *p != '\0' && n < 12u; p++)
            out[n++] = upper(*p);
    }
    /* 8 + '.' + 3 = 12 characters, and LIB_NAME_LEN - 1 = 15, so the NUL the
     * memset above left is always still there. */
}

/* ------------------------------------------------------------- the kind rules */

int lib_size_valid(uint8_t kind, uint32_t size)
{
    switch (kind) {
    case LIB_KIND_FLOPPY:
        /* The geometry is the image's own business -- the floppy personality
         * replays what the image says (#20), so any size is structurally fine
         * here and a wrong one is caught when the image is read. */
        return size > 0u;
    case LIB_KIND_DRIVEC:
        /* The length IS the geometry, so this is exact: 196 608 is the 192K unit
         * and 393 216 the 384K one (docs/drive-c-design.md 4.2). */
        return size == LIB_DRIVEC_192K || size == LIB_DRIVEC_384K;
    case LIB_KIND_HARDDISK:
        /* A hard-disk volume carries its own geometry in its header (#180), so
         * the size is only bounded from below -- the exact geometry is the
         * ACB-4000 personality's business, not the library's. */
        return size >= LIB_HARDDISK_MIN;
    default:
        return 0;
    }
}

int lib_kind_of(const char *dir, const char *file, uint32_t size, uint8_t *kind)
{
    if (dir == NULL || file == NULL || kind == NULL)
        return -1;

    if (strcmp(dir, lib_dir_name[LIB_DIR_FLOPPY]) == 0) {
        if (!ext_is(file, "imd") && !ext_is(file, "hfe"))
            return -1;
        *kind = LIB_KIND_FLOPPY;
        return 0;
    }

    if (strcmp(dir, lib_dir_name[LIB_DIR_DISK]) == 0) {
        if (!ext_is(file, "img") || size == 0u)
            return -1;
        /* One directory, two kinds, and the size band is what separates them.  A
         * size that is valid for *neither* is still a library entry: it is listed
         * as the kind its band says, with VALID clear, because a user who copied
         * the wrong file needs to see it in the menu and be told why it will not
         * mount -- `MOUNT` refuses it with 05h (section 5.2). */
        *kind = (size >= LIB_HARDDISK_MIN) ? LIB_KIND_HARDDISK : LIB_KIND_DRIVEC;
        return 0;
    }

    return -1;       /* printer/, or a directory we do not know */
}

/* ------------------------------------------------------------- the wire record */

void lib_record_encode(const lib_record *rec, uint8_t out[LIB_RECORD_LEN])
{
    memset(out, 0, LIB_RECORD_LEN);
    memcpy(out, rec->name, LIB_NAME_LEN);          /* 0..15, already NUL-padded */
    out[16] = rec->kind;
    out[17] = rec->flags;
    out[18] = (uint8_t)(rec->size & 0xFFu);
    out[19] = (uint8_t)((rec->size >> 8) & 0xFFu);
    out[20] = (uint8_t)((rec->size >> 16) & 0xFFu);
    out[21] = (uint8_t)((rec->size >> 24) & 0xFFu);
    /* 22..23: reserved, zero */
}

/* ------------------------------------------------------------------ the index */

void lib_init(lib *l, const media *const *media, unsigned nmedia)
{
    unsigned i;

    memset(l, 0, sizeof *l);
    if (nmedia > LIB_MAX_MEDIA)
        nmedia = LIB_MAX_MEDIA;
    for (i = 0; i < nmedia; i++)
        l->media[i] = media[i];
    l->nmedia = nmedia;
    for (i = 0; i < LIB_DRIVES; i++)
        l->drive[i] = LIB_DRIVE_NONE;
}

/* The merge.  The identity is the key: the first medium to offer a name owns it,
 * so a file dropped on a card overrides the factory image of the same name, and
 * the external flash -- always fitted -- is what is left when nothing else is. */
static int already_have(const lib *l, const char *identity)
{
    unsigned i;

    for (i = 0; i < l->count; i++)
        if (memcmp(l->entry[i].rec.name, identity, LIB_NAME_LEN) == 0)
            return 1;
    return 0;
}

static void detach(lib *l, unsigned index)
{
    unsigned d;

    for (d = 0; d < LIB_DRIVES; d++) {
        if (l->drive[d] == (uint16_t)index) {
            l->drive[d] = LIB_DRIVE_NONE;
            l->entry[index].rec.flags &= (uint8_t)~LIB_FLAG_MOUNTED;
        }
    }
}

int lib_refresh(lib *l)
{
    /* What was mounted before the walk, so that a mount survives a refresh whose
     * entry is still there -- the firmware's state outlives the host's
     * (docs/mailbox-protocol.md section 6). */
    char     mounted[LIB_DRIVES][LIB_NAME_LEN];
    unsigned m, dir, d;

    for (d = 0; d < LIB_DRIVES; d++) {
        memset(mounted[d], 0, LIB_NAME_LEN);
        if (l->drive[d] != LIB_DRIVE_NONE && l->drive[d] < l->count)
            memcpy(mounted[d], l->entry[l->drive[d]].rec.name, LIB_NAME_LEN);
        l->drive[d] = LIB_DRIVE_NONE;
    }
    l->count = 0;

    for (m = 0; m < l->nmedia; m++) {
        const media *md = l->media[m];

        if (md == NULL || md->ops == NULL || md->ops->list == NULL)
            continue;

        for (dir = 0; dir < LIB_DIRS; dir++) {
            unsigned index;

            if (!lib_dir_mountable(dir))
                continue;

            for (index = 0;; index++) {
                media_entry e;
                lib_entry  *slot;
                char        identity[LIB_NAME_LEN];
                uint8_t     kind;

                memset(&e, 0, sizeof e);
                if (md->ops->list(md->ctx, lib_dir_name[dir], index, &e) != MEDIA_OK)
                    break;                       /* end of the directory, or an error */
                if (lib_kind_of(lib_dir_name[dir], e.name, e.size, &kind) != 0)
                    continue;                    /* not a library file at all */
                lib_identity(e.name, identity);
                if (already_have(l, identity))
                    continue;                    /* a higher-precedence medium owns it */
                if (l->count >= LIB_MAX_ENTRIES)
                    break;                       /* the RAM cap: stop, do not overflow */

                slot = &l->entry[l->count];
                memset(slot, 0, sizeof *slot);
                memcpy(slot->rec.name, identity, LIB_NAME_LEN);
                slot->rec.kind  = kind;
                slot->rec.size  = e.size;
                slot->rec.flags = lib_size_valid(kind, e.size) ? LIB_FLAG_VALID : 0u;
                slot->media     = (uint8_t)m;
                slot->dir       = (uint8_t)dir;
                memcpy(slot->file, e.name, MEDIA_NAME_MAX - 1u);
                slot->file[MEDIA_NAME_MAX - 1u] = '\0';
                l->count++;
            }
        }
    }

    /* Re-attach what is still there. */
    for (d = 0; d < LIB_DRIVES; d++) {
        unsigned i;

        if (mounted[d][0] == '\0')
            continue;
        for (i = 0; i < l->count; i++) {
            if (memcmp(l->entry[i].rec.name, mounted[d], LIB_NAME_LEN) == 0) {
                l->drive[d] = (uint16_t)i;
                l->entry[i].rec.flags |= LIB_FLAG_MOUNTED;
                break;
            }
        }
    }

    return LIB_OK;
}

unsigned lib_count(const lib *l)
{
    return l->count;
}

int lib_get(const lib *l, unsigned index, lib_record *out)
{
    if (index >= l->count)
        return LIB_ERR_INDEX;
    *out = l->entry[index].rec;
    return LIB_OK;
}

/* ----------------------------------------------------------------- the mounts */

int lib_mount(lib *l, unsigned index, unsigned drive)
{
    uint8_t kind;

    if (drive >= LIB_DRIVES)
        return LIB_ERR_DRIVE;
    if (index >= l->count)
        return LIB_ERR_INDEX;

    /* The kind-to-slot rule.  A floppy is a floppy drive; a Drive C blob and a
     * hard-disk volume are the same slot, because slot 2 is the interposer's
     * storage personality and the two are mutually exclusive on one machine
     * (docs/mailbox-protocol.md section 6).  Which *name* a hard-disk volume
     * takes is #181's drive-mapping table, not this module's. */
    kind = l->entry[index].rec.kind;
    if (kind == LIB_KIND_FLOPPY) {
        if (drive != LIB_DRIVE_A && drive != LIB_DRIVE_B)
            return LIB_ERR_KIND;
    } else if (kind == LIB_KIND_DRIVEC || kind == LIB_KIND_HARDDISK) {
        if (drive != LIB_DRIVE_C)
            return LIB_ERR_KIND;
    } else {
        return LIB_ERR_KIND;
    }

    /* Listed with VALID clear means the size is wrong for its kind, and MOUNT
     * refuses it rather than mounting something that cannot work -- the file is
     * still *listed*, so the user can see why (section 5.2). */
    if ((l->entry[index].rec.flags & LIB_FLAG_VALID) == 0)
        return LIB_ERR_KIND;

    detach(l, index);                       /* one entry, one drive */
    if (l->drive[drive] != LIB_DRIVE_NONE && l->drive[drive] < l->count)
        l->entry[l->drive[drive]].rec.flags &= (uint8_t)~LIB_FLAG_MOUNTED;
    l->drive[drive] = (uint16_t)index;
    l->entry[index].rec.flags |= LIB_FLAG_MOUNTED;
    return LIB_OK;
}

int lib_unmount(lib *l, unsigned drive)
{
    if (drive >= LIB_DRIVES)
        return LIB_ERR_DRIVE;
    if (l->drive[drive] == LIB_DRIVE_NONE)
        return LIB_ERR_EMPTY;

    if (l->drive[drive] < l->count)
        l->entry[l->drive[drive]].rec.flags &= (uint8_t)~LIB_FLAG_MOUNTED;
    l->drive[drive] = LIB_DRIVE_NONE;
    return LIB_OK;
}

int lib_drive_state(const lib *l, unsigned drive)
{
    if (drive >= LIB_DRIVES)
        return LIB_ERR_DRIVE;
    return l->drive[drive] == LIB_DRIVE_NONE ? LIB_DRIVE_EMPTY : LIB_DRIVE_MOUNTED;
}

int lib_drive_entry(const lib *l, unsigned drive, unsigned *index)
{
    if (drive >= LIB_DRIVES)
        return LIB_ERR_DRIVE;
    if (l->drive[drive] == LIB_DRIVE_NONE)
        return LIB_ERR_EMPTY;
    if (index != NULL)
        *index = l->drive[drive];
    return LIB_OK;
}

/* ------------------------------------------------------------------- the bytes */

int lib_read(const lib *l, unsigned index, uint32_t offset, void *buf, size_t len)
{
    const lib_entry *e;
    const media     *md;

    if (index >= l->count)
        return LIB_ERR_INDEX;

    e = &l->entry[index];
    if (e->media >= l->nmedia)
        return LIB_ERR_MEDIA;
    md = l->media[e->media];
    if (md == NULL || md->ops == NULL || md->ops->read == NULL)
        return LIB_ERR_MEDIA;

    if (md->ops->read(md->ctx, lib_dir_name[e->dir], e->file, offset, buf, len) != MEDIA_OK)
        return LIB_ERR_MEDIA;
    return LIB_OK;
}
