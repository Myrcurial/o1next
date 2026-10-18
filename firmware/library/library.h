/* The image library -- the firmware's one view of its three media (#283, #192).
 *
 * What it is for
 * --------------
 * Everything the interposer can be asked to mount lives in one library: floppy
 * images, Drive C blobs and hard-disk volumes, as *files* on FAT32 media.  This
 * module is the firmware's answer to "what is there, and which one goes on which
 * drive" -- and it is what the mailbox protocol's image-library class
 * (`docs/mailbox-protocol.md` section 4, opcodes 10h-1Fh) is implemented on top
 * of, for `MOUNT.COM` (#27) and the web UI (#16).
 *
 * The layout, and why the directory decides the kind
 * --------------------------------------------------
 * `docs/image-library-design.md` is the record.  At the volume root:
 *
 *     floppy/   .imd and .hfe   KIND 0, mounts A: or B:
 *     disk/     .img            KIND 1 (Drive C blob) by exact size, else KIND 2
 *                               (hard-disk volume) at 5 MiB and above
 *     printer/  .pdf            not a library kind at all -- output, listed by
 *                               the web UI (#182), never by the mailbox
 *
 * `disk/` holds two kinds on purpose, and the size tells them apart: a Drive C
 * blob's length *is* its geometry (196 608 = the 192K unit, 393 216 = the 384K
 * one -- `docs/drive-c-design.md` section 4.2), while a hard-disk volume is
 * megabytes and carries its own geometry in its header.  So the library never has
 * to guess and never has to parse anything.
 *
 * What this module deliberately does NOT do
 * -----------------------------------------
 * **It does not parse a blob.**  It identifies a file by directory and size, and
 * hands the bytes to the personality that asked (`lib_read`).  The volume's own
 * header -- the ACB-4000's `M`/`D` label at LBA 0 (#179, #180) -- is that
 * personality's business.  A parser here would be a second, drifting copy of a
 * format that already has an owner.
 *
 * The name is the CP/M identity, not the file name
 * ------------------------------------------------
 * `NAME` in the record is the **CP/M 8.3 identity, upper case**
 * (`docs/mailbox-protocol.md` section 5.3, question 1): the machine is 52 columns
 * wide and CP/M thinks in 8.3, so the long name is a web-UI nicety and the short
 * one is the identity.  `lib_identity()` is the one place that conversion lives.
 *
 * The result codes are the protocol's
 * -----------------------------------
 * LIB_OK and LIB_ERR_* below are `docs/mailbox-protocol.md` section 4.1's table,
 * verbatim and in order, so that the mailbox layer hands them straight out and
 * there is no second numbering to drift.
 */
#ifndef O1_LIBRARY_H
#define O1_LIBRARY_H

#include <stddef.h>
#include <stdint.h>

#include "media.h"

/* ---------------------------------------------------------------- the record
 *
 * 24 bytes on the wire, exactly as `docs/mailbox-protocol.md` section 5.1 fixes
 * it.  This struct is the *host-side* form; `lib_record_encode()` is the one
 * place that turns it into bytes, field by field and little-endian, so nothing
 * depends on struct layout or on the host's endianness.
 */
#define LIB_NAME_LEN   16u   /* NUL-padded; the 8.3 identity is 12 at most */
#define LIB_RECORD_LEN 24u

#define LIB_KIND_FLOPPY   0u   /* .imd / .hfe, mounts A: or B: */
#define LIB_KIND_DRIVEC   1u   /* the Drive C blob, exactly 192K or 384K */
#define LIB_KIND_HARDDISK 2u   /* a hard-disk volume, 5 MiB and up (#181) */

#define LIB_FLAG_VALID   0x01u   /* the size is valid for its kind */
#define LIB_FLAG_MOUNTED 0x02u

typedef struct {
    char     name[LIB_NAME_LEN];
    uint8_t  kind;
    uint8_t  flags;
    uint32_t size;
} lib_record;

/* ---------------------------------------------------------------- the drives
 *
 * Slots 0 and 1 are the machine's own floppy drives.  Slot 2 is the interposer's
 * storage personality -- Drive C, or the ACB-4000 hard disk.  Which of those two
 * it *is* depends on what is mounted, and naming a hard-disk volume `A:`/`B:` is
 * the MD-10 convention #181 owns; this module enforces only the kind-to-slot rule
 * below.
 */
#define LIB_DRIVE_A     0u
#define LIB_DRIVE_B     1u
#define LIB_DRIVE_C     2u
#define LIB_DRIVES      3u
#define LIB_DRIVE_NONE  0xFFFFu   /* nothing mounted */

#define LIB_DRIVE_EMPTY   0x00u   /* the drive-state byte (section 4's replies) */
#define LIB_DRIVE_MOUNTED 0x01u

/* ------------------------------------------------------------- the directory
 *
 * Data, not code: the layout is a table so that a wrong guess is one line to fix.
 * `printer/` is in the table so that the exclusion is *stated* rather than
 * omitted -- the library walks mountable directories only.
 */
#define LIB_DIR_FLOPPY  0u
#define LIB_DIR_DISK    1u
#define LIB_DIR_PRINTER 2u
#define LIB_DIRS        3u

extern const char *const lib_dir_name[LIB_DIRS];

int lib_dir_mountable(unsigned dir);

/* ------------------------------------------------------------ the size rules
 *
 * Drive C: the file length IS the geometry, so a wrong size is not a near miss.
 */
#define LIB_DRIVEC_192K   196608u   /* 384 x 512 x 1 head, 192K */
#define LIB_DRIVEC_384K   393216u   /* 384K, two heads */
/* And at or above this a `disk/` `.img` is a hard-disk volume rather than a Drive C
 * blob: the two kinds share one directory and the size band is what separates them.
 *
 * 5 MiB, from the maintainer's expectation (2026-10-18) that a hard-disk volume
 * below 5 MB is not something we will see -- the real ones are tens of MiB.  A
 * Drive C blob tops out at 393 216, so the band between that and this belongs to no
 * kind, and a file in it is listed and refused -- which is what catches a truncated
 * volume in the menu rather than at the controller.  This is policy, not a hardware
 * limit, and it is one line to move. */
#define LIB_HARDDISK_MIN  (5u * 1024u * 1024u)

/* --------------------------------------------------------------- the results
 *
 * `docs/mailbox-protocol.md` section 4.1, verbatim.  One table, used by both the
 * library and the mailbox, so a code cannot mean two things.
 */
#define LIB_OK           0x00u
#define LIB_ERR_OPCODE   0x01u   /* unknown opcode */
#define LIB_ERR_OPERANDS 0x02u   /* wrong operand count -- see the note in mailbox.h */
#define LIB_ERR_INDEX    0x03u   /* index out of range */
#define LIB_ERR_DRIVE    0x04u   /* drive out of range */
#define LIB_ERR_KIND     0x05u   /* not mountable there, or an invalid size */
#define LIB_ERR_MEDIA    0x06u   /* the blob could not be read */
#define LIB_ERR_BUSY     0x07u   /* a flux window is open; try again */
#define LIB_ERR_EMPTY    0x08u   /* nothing mounted on that drive */
#define LIB_ERR_CONTENT  0x09u   /* no such content (the ROM service, #284) */

/* ---------------------------------------------------------------- the library
 *
 * LIB_MAX_ENTRIES is a RAM bound, not a protocol one: the protocol allows 65 535
 * entries and the board has 520 KB of SRAM.  An entry is ~96 bytes, so the default
 * costs about 12 KB -- and the walk stops cleanly at the cap rather than
 * overflowing it.
 */
#define LIB_MAX_MEDIA    3u
#define LIB_MAX_ENTRIES  128u

typedef struct {
    lib_record rec;
    uint8_t    media;                  /* index into the precedence list */
    uint8_t    dir;                    /* LIB_DIR_* */
    char       file[MEDIA_NAME_MAX];   /* the stored name, to re-open it */
} lib_entry;

typedef struct {
    const media *media[LIB_MAX_MEDIA]; /* in precedence order: first match wins */
    unsigned     nmedia;
    lib_entry    entry[LIB_MAX_ENTRIES];
    unsigned     count;
    uint16_t     drive[LIB_DRIVES];    /* LIB_DRIVE_NONE, or an entry index */
} lib;

/* `media` is in precedence order and is not copied -- keep it alive. */
void lib_init(lib *l, const media *const *media, unsigned nmedia);

/* Rebuild the index by walking every mountable directory on every medium, in
 * precedence order, de-duplicating on the 8.3 identity.  A higher-precedence copy
 * that is *invalid* for its kind does not shadow a valid lower one: the search
 * falls through, so a bad file on a transient stick lands on the microSD or on the
 * flash guarantee.  A mount survives a refresh only if the entry it named is still
 * there.  Returns LIB_OK. */
int lib_refresh(lib *l);

unsigned lib_count(const lib *l);

/* LIB_OK and the record, or LIB_ERR_INDEX. */
int lib_get(const lib *l, unsigned index, lib_record *out);

/* LIB_OK, or LIB_ERR_INDEX / LIB_ERR_DRIVE / LIB_ERR_KIND.  The kind-to-slot
 * rule: a floppy goes to A: or B:, a Drive C blob or a hard-disk volume goes to
 * slot 2, and anything else is LIB_ERR_KIND. */
int lib_mount(lib *l, unsigned index, unsigned drive);
int lib_unmount(lib *l, unsigned drive);

int lib_drive_state(const lib *l, unsigned drive);   /* *_EMPTY / *_MOUNTED */
int lib_drive_entry(const lib *l, unsigned drive, unsigned *index);

/* The bytes, for the personality that mounted the entry.  LIB_OK, or
 * LIB_ERR_INDEX / LIB_ERR_MEDIA.  A read past the end is refused. */
int lib_read(const lib *l, unsigned index, uint32_t offset, void *buf, size_t len);

/* The CP/M 8.3 identity: upper case, base truncated to 8 and extension to 3,
 * NUL-padded to LIB_NAME_LEN.  `out` is cleared first, so the padding is real. */
void lib_identity(const char *file, char out[LIB_NAME_LEN]);

/* The kind a `dir`/`file` of this size is, or -1 if it is not a library file at
 * all (a `printer/` PDF, an unknown directory, a wrong extension, an empty file).
 * A *size* never makes something not-a-library-file: a `disk/` `.img` of a size
 * no kind allows is still listed, with `VALID` clear. */
int lib_kind_of(const char *dir, const char *file, uint32_t size, uint8_t *kind);

/* Is `size` valid for `kind`?  Exact for a Drive C blob; for a floppy any size at
 * all, because the geometry is the image's own business. */
int lib_size_valid(uint8_t kind, uint32_t size);

/* The 24 wire bytes, little-endian, field by field. */
void lib_record_encode(const lib_record *rec, uint8_t out[LIB_RECORD_LEN]);

#endif /* O1_LIBRARY_H */
