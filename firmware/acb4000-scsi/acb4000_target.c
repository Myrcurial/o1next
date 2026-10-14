/* The ACB-4000 SCSI-1 target -- layer 1 of the personality (#179).
 *
 * An ANSI X3T9.2 SCSI-1 direct-access target that answers the Adaptec ACB-4000
 * command set, written to the OEM manual and to nothing else.  It has no idea a
 * Z80 is anywhere near it: the shim (acb4000_shim.c) is what puts it behind four
 * I/O registers, and the store (acb4000_store.c) is what it reads blocks from.
 *
 * Every CDB length, data layout and status meaning here is from
 * `research/adaptec/acb4000/400003-00A_ACB-4000A_Users_Manual_Oct85.ocr.txt`
 * unless the comment says otherwise, and the section is named.  Two things are
 * *inferred* and say so: TRANSLATE's byte widths (figure 5-6 gives the field
 * order, not the widths) and the commands whose transfer length the manual does
 * not pin (WRITE/READ BUFFER, the diagnostics) -- those accept the command and
 * return status without a data phase rather than inventing a length.
 *
 * The command set is the manual's Table 5-1 (Class 0 + Class 1), plus the
 * expanded set that appears behind jumper I-J (Table 5-1's Class 0 vendor unique
 * commands, and the four the Mar84 OEM manual's Table B-1 adds: 05, 0C, 0D and
 * the E0/E3/E4 diagnostics).
 */
#include "acb4000.h"

#include <string.h>

/* ---------------------------------------------------------------- byte helpers
 *
 * The manual's descriptors are big-endian (figure 5-20 puts the MSB first); the
 * drive table on disk is little-endian.  The swap lives here and in mode_select/
 * mode_sense, nowhere else.
 */
static uint16_t be16(const uint8_t *p)
{
    return (uint16_t)(((uint16_t)p[0] << 8) | p[1]);
}

static void put_be16(uint8_t *p, uint16_t v)
{
    p[0] = (uint8_t)(v >> 8);
    p[1] = (uint8_t)(v & 0xFFu);
}

static uint32_t be32(const uint8_t *p)
{
    return ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16) |
           ((uint32_t)p[2] << 8) | (uint32_t)p[3];
}

static void put_be32(uint8_t *p, uint32_t v)
{
    p[0] = (uint8_t)(v >> 24);
    p[1] = (uint8_t)(v >> 16);
    p[2] = (uint8_t)(v >> 8);
    p[3] = (uint8_t)v;
}

int acb4000_cdb_length(uint8_t opcode)
{
    /* Manual 5.2.1: the class code is the opcode's top three bits, and the class
     * fixes the CDB length -- 6, 10 or 12 bytes.  Class 4 is 16 and class 5 is
     * 12 in ANSI X3T9.2; the ACB-4000 uses neither, but a length has to be
     * chosen so a stray byte cannot desynchronise the command phase. */
    switch ((opcode >> 5) & 0x07) {
    case 0:  return 6;
    case 1:
    case 2:  return 10;
    case 3:  return 12;
    case 4:  return 16;
    case 5:  return 12;
    default: return 6;
    }
}

/* ------------------------------------------------------------- the geometry
 *
 * The manual's defaults, for a drive formatted with no parameter list at all
 * (manual 5.3.13): an ST-506 -- 306 cylinders, 2 data heads, reduced write
 * current at 128, landing zone 0, step code 0 (3.0 ms, unbuffered).
 */
void acb4000_params_default(acb4000_params *p)
{
    memset(p, 0, sizeof *p);
    p->layout_code = 0x01;              /* soft-sectored fixed drive */
    p->cylinders = 306;
    p->heads = 2;
    p->reduced_write_current = 128;
    p->write_precomp = 0;               /* ignored on the ACB-4000A */
    p->landing_zone = 0;                /* land on the innermost track */
    p->step_code = 0;                   /* 3.0 ms unbuffered -- ST-506 */
    p->block_size = 512;
    /* The drive table's own formula (docs/harddisk-decision.md section 7.2); the
     * manual's 8 KiB track would give 16 at a 512-byte block.  See acb4000.h. */
    p->sectors_per_track = 18;
}

uint32_t acb4000_params_blocks(const acb4000_params *p)
{
    uint32_t spt = p->sectors_per_track ? p->sectors_per_track : 18u;
    return (uint32_t)p->cylinders * (uint32_t)p->heads * spt;
}

/* ------------------------------------------------------------------ lifecycle */

void acb4000_target_init(acb4000_target *t, const acb4000_store *store, int extended)
{
    memset(t, 0, sizeof *t);
    t->store = store;
    t->extended = extended ? 1 : 0;
    acb4000_target_reset(t);
}

void acb4000_target_reset(acb4000_target *t)
{
    uint32_t i;

    for (i = 0; i < ACB4000_LUNS; i++) {
        acb4000_lun *l = &t->luns[i];
        acb4000_params_default(&l->params);
        l->have_params = 0;
        l->fill = ACB4000_FILL_DEFAULT;
        memset(l->sense, 0, sizeof l->sense);
        l->sense_valid = 0;
    }

    t->phase = ACB4000_PHASE_NONE;
    t->total = t->moved = 0;
    t->status = ACB4000_ST_GOOD;
    t->staging_len = t->staging_moved = 0;
    t->defer = ACB4000_DEFER_NONE;
    t->cdb_len = 0;
    t->opcode = t->lun = 0;
    t->lba = t->blocks = 0;
    t->block_xfer = 0;
}

acb4000_phase acb4000_target_phase(const acb4000_target *t)
{
    return t->phase;
}

uint32_t acb4000_target_length(const acb4000_target *t)
{
    return t->total;
}

uint8_t acb4000_target_status(const acb4000_target *t)
{
    return t->status;
}

/* ------------------------------------------------------------------ sense
 *
 * Four bytes, as the manual says (5.5.1: "The controller returns four bytes of
 * sense information").  Byte 0 carries the error code in its low seven bits and
 * the *address valid* bit in bit 7 (5.5.2, figure 5-36); bytes 1-3 carry the
 * logical block address the error -- or a satisfied search -- refers to.
 */
static void lun_set_sense(acb4000_lun *l, uint8_t error, uint32_t lba, int addr_valid)
{
    l->sense[0] = (uint8_t)(error & 0x7Fu);
    if (addr_valid)
        l->sense[0] |= 0x80u;
    l->sense[1] = (uint8_t)(lba >> 16);
    l->sense[2] = (uint8_t)(lba >> 8);
    l->sense[3] = (uint8_t)lba;
    l->sense_valid = 1;
}

static void lun_clear_sense(acb4000_lun *l)
{
    memset(l->sense, 0, sizeof l->sense);
    l->sense_valid = 0;
}

static void check_condition(acb4000_target *t, uint8_t error, uint32_t lba, int addr_valid)
{
    t->status = ACB4000_ST_CHECK;
    t->phase = ACB4000_PHASE_NONE;
    t->total = t->moved = 0;
    t->block_xfer = 0;
    t->defer = ACB4000_DEFER_NONE;
    lun_set_sense(&t->luns[t->lun], error, lba, addr_valid);
}

/* -------------------------------------------------------------- data phases
 *
 * Three shapes, and the shim does not need to know which it has:
 *
 *   no_data()        -- go straight to status (TEST UNIT READY, SEEK, VERIFY)
 *   staging_in()     -- a short transfer the target builds in one go (MODE
 *                       SENSE, READ CAPACITY, TRANSLATE, REQUEST SENSE)
 *   block_xfer       -- a whole number of blocks streamed through the store
 *                       (READ, WRITE, WRITE AND VERIFY)
 *
 * A short *data-out* transfer (MODE SELECT, FORMAT's defect list, the SEARCH
 * argument) accumulates in `staging` and runs a deferred action once the phase
 * has been drained -- see staging_out().
 */
static void no_data(acb4000_target *t)
{
    t->phase = ACB4000_PHASE_NONE;
    t->total = t->moved = 0;
    t->block_xfer = 0;
    t->defer = ACB4000_DEFER_NONE;
}

static void staging_in(acb4000_target *t, uint32_t len)
{
    t->phase = ACB4000_PHASE_DATA_IN;
    t->staging_len = len;
    t->staging_moved = 0;
    t->total = len;
    t->moved = 0;
    t->block_xfer = 0;
    t->defer = ACB4000_DEFER_NONE;
}

static void staging_out(acb4000_target *t, uint32_t len, int defer)
{
    t->phase = ACB4000_PHASE_DATA_OUT;
    t->staging_len = 0;
    t->staging_moved = 0;
    t->total = len;
    t->moved = 0;
    t->block_xfer = 0;
    t->defer = defer;
}

static void begin_blocks(acb4000_target *t, int data_in)
{
    if (t->block_size == 0)             /* a store with no block size at all */
        t->block_size = 512u;
    t->phase = data_in ? ACB4000_PHASE_DATA_IN : ACB4000_PHASE_DATA_OUT;
    t->staging_len = 0;
    t->staging_moved = 0;
    t->total = t->blocks * t->block_size;
    t->moved = 0;
    t->block_xfer = 1;
    t->defer = ACB4000_DEFER_NONE;
    if (t->total == 0)
        no_data(t);
}


/* ------------------------------------------------------- MODE SELECT / SENSE
 *
 * Both lists are the same shape (manual 5.3.13 and 5.3.14): a four-byte header
 * whose byte 3 is the extent descriptor list's length (always eight), an
 * eight-byte extent descriptor whose last three bytes are the block size, and
 * then the ten-byte drive parameter list (twelve for a hard-sectored or
 * removable drive -- bytes 0A and 0B only exist for those).
 *
 * Byte order is the manual's: big-endian, MSB first (figure 5-20).  The drive
 * table on disk stores the same nine values little-endian, which is the whole of
 * the shim's `md10` "remapping".
 */
static uint32_t mode_block_size(const uint8_t *p)
{
    /* figure 5-19: bytes 5-7 of the extent descriptor list, LSB last */
    return ((uint32_t)p[9] << 16) | ((uint32_t)p[10] << 8) | p[11];
}

static void parse_mode_select(acb4000_target *t)
{
    acb4000_lun *l = &t->luns[t->lun];
    const uint8_t *p = t->staging;
    const uint8_t *dp;
    uint32_t dp_len, block_size;
    acb4000_params np;

    if (t->staging_len < 12) {
        check_condition(t, ACB4000_ERR_BAD_ARGUMENT, 0, 0);
        return;
    }
    if (p[3] != 8) {                        /* only a single extent is supported */
        check_condition(t, ACB4000_ERR_BAD_ARGUMENT, 0, 0);
        return;
    }
    block_size = mode_block_size(p);
    if (block_size != 256 && block_size != 512 && block_size != 1024) {
        check_condition(t, ACB4000_ERR_BAD_ARGUMENT, 0, 0);
        return;
    }

    dp = p + 12;
    dp_len = (t->staging_len > 12) ? (t->staging_len - 12) : 0;
    if (dp_len < 10) {                      /* the drive parameter list is optional */
        l->params.block_size = block_size;
        l->have_params = 1;
        t->status = ACB4000_ST_GOOD;
        no_data(t);
        return;
    }

    acb4000_params_default(&np);
    np.block_size = block_size;
    np.layout_code = dp[0];
    np.cylinders = be16(dp + 1);
    np.heads = dp[3];
    np.reduced_write_current = be16(dp + 4);
    np.write_precomp = be16(dp + 6);
    np.landing_zone = dp[8];
    np.step_code = dp[9];
    if (np.layout_code == 0x02 && dp_len >= 12) {
        np.hard_sectored = (uint8_t)((dp[10] >> 2) & 1u);
        np.removable = (uint8_t)((dp[10] >> 3) & 1u);
        np.sectors_per_track_hs = dp[11];
    }

    /* The manual's limits (5.3.13).  A violation is a bad argument, not a
     * silently-clamped geometry -- the driver would build a DPB from it. */
    if (np.cylinders < 16 || np.cylinders > 2048 ||
        np.heads < 1 || np.heads > 16 ||
        np.reduced_write_current > 2047) {
        check_condition(t, ACB4000_ERR_BAD_ARGUMENT, 0, 0);
        return;
    }

    l->params = np;
    l->have_params = 1;
    t->status = ACB4000_ST_GOOD;
    no_data(t);
}

static void build_mode_sense(acb4000_target *t)
{
    const acb4000_lun *l = &t->luns[t->lun];
    const acb4000_params *pp = &l->params;
    uint8_t *p = t->staging;
    uint32_t want = t->cdb[4];
    uint32_t n;

    /* The driver asks for 36 bytes; the lists take the exact format of the
     * MODE SELECT ones, so the answer is 22 (24 for hard-sectored) and the
     * phase ends there.  A count below the manual's 12-byte minimum still gets
     * the four-byte header and the extent descriptor. */
    if (want >= 22)
        n = (pp->layout_code == 0x02 && want >= 24) ? 24u : 22u;
    else
        n = 12u;

    memset(p, 0, n);
    p[3] = 8;                              /* the extent descriptor list's length */
    p[9] = (uint8_t)(pp->block_size >> 16);
    p[10] = (uint8_t)(pp->block_size >> 8);
    p[11] = (uint8_t)pp->block_size;

    if (n >= 22) {
        uint8_t *dp = p + 12;
        dp[0] = pp->layout_code;
        put_be16(dp + 1, pp->cylinders);
        dp[3] = pp->heads;
        put_be16(dp + 4, pp->reduced_write_current);
        put_be16(dp + 6, pp->write_precomp);
        dp[8] = pp->landing_zone;
        dp[9] = pp->step_code;
        if (n >= 24) {
            dp[10] = (uint8_t)((pp->hard_sectored ? 0x04u : 0u) |
                               (pp->removable ? 0x08u : 0u));
            dp[11] = (uint8_t)pp->sectors_per_track_hs;
        }
    }
    staging_in(t, n);
}


/* --------------------------------------------------------------- FORMAT
 *
 * Manual 5.3.4: the fill byte is 6C hex unless byte 1's bit 1 says otherwise,
 * in which case it is byte 2.  Byte 1's bit 4 says a defect list follows; only
 * the "bytes from index" format is supported, and the list is a four-byte header
 * (bytes 2-3 = its length) plus eight bytes per defect.
 */
static void do_format(acb4000_target *t)
{
    acb4000_lun *l = &t->luns[t->lun];
    uint8_t fill = (t->cdb[1] & 0x02u) ? t->cdb[2] : ACB4000_FILL_DEFAULT;

    if (t->store == NULL || t->store->format == NULL ||
        t->store->format(t->store->ctx, fill) != 0) {
        check_condition(t, ACB4000_ERR_BAD_FORMAT, 0, 0);
        return;
    }
    l->fill = fill;
    t->status = ACB4000_ST_GOOD;
    no_data(t);
}

/* ---------------------------------------------------- SEARCH DATA EQUAL (31)
 *
 * Manual 5.4.6: the argument is 20 bytes of description followed by the pattern.
 * A satisfied search ends with the Equal status (bit 2) and leaves the matching
 * block's address in the sense bytes; an unsatisfied one ends with no sense.
 * The invert bit (byte 1, bit 4) turns it into SEARCH DATA NOT EQUAL.
 */
static void do_search(acb4000_target *t)
{
    acb4000_lun *l = &t->luns[t->lun];
    const uint8_t *arg = t->staging;
    uint32_t pattern_len, n, i;
    int invert = (t->cdb[1] & 0x10u) ? 1 : 0;
    uint32_t bs = t->block_size ? t->block_size : 512u;
    uint8_t block[ACB4000_BLOCK_MAX];

    if (t->staging_len < 20) {
        check_condition(t, ACB4000_ERR_BAD_ARGUMENT, 0, 0);
        return;
    }
    pattern_len = be16(arg + 18);
    if (pattern_len == 0 || pattern_len > bs || pattern_len > ACB4000_BLOCK_MAX ||
        t->staging_len < 20 + pattern_len) {
        check_condition(t, ACB4000_ERR_BAD_ARGUMENT, 0, 0);
        return;
    }

    for (n = 0; n < t->blocks; n++) {
        uint32_t blk = t->lba + n;
        int equal;

        if (t->store == NULL || t->store->read == NULL ||
            t->store->read(t->store->ctx, blk, 1, block) != 0) {
            check_condition(t, ACB4000_ERR_ILLEGAL_BLOCK, blk, 1);
            return;
        }
        equal = 1;
        for (i = 0; i < pattern_len; i++) {
            if (block[i] != arg[20 + i]) {
                equal = 0;
                break;
            }
        }
        if (invert)
            equal = !equal;
        if (equal) {
            t->status = ACB4000_ST_EQUAL;
            no_data(t);
            lun_set_sense(l, ACB4000_ERR_NONE, blk, 1);
            return;
        }
    }
    /* Nothing matched: "report a Completion status Byte of No Sense". */
    t->status = ACB4000_ST_GOOD;
    no_data(t);
    lun_set_sense(l, ACB4000_ERR_NONE, 0, 0);
}

/* ------------------------------------------------------- the data-in builders */

static void build_read_capacity(acb4000_target *t)
{
    uint32_t last, bs;

    if (t->cdb[8] != 0x00u && t->cdb[8] != 0x01u) {
        check_condition(t, ACB4000_ERR_BAD_ARGUMENT, 0, 0);
        return;
    }
    if (t->store == NULL || t->store->capacity == NULL) {
        check_condition(t, ACB4000_ERR_DRIVE_NOT_READY, 0, 0);
        return;
    }
    last = t->store->capacity(t->store->ctx);
    bs = (t->store->block_size != NULL) ? t->store->block_size(t->store->ctx)
                                        : t->block_size;
    put_be32(t->staging + 0, last);         /* the address of the last block */
    put_be32(t->staging + 4, bs);
    staging_in(t, 8);
}

static void build_request_sense(acb4000_target *t)
{
    acb4000_lun *l = &t->luns[t->lun];

    /* "Check status will not be sent in response to this command", and the
     * sense is cleared by the command that follows the check condition. */
    memcpy(t->staging, l->sense, ACB4000_SENSE_LEN);
    lun_clear_sense(l);
    staging_in(t, ACB4000_SENSE_LEN);
}

static void build_translate(acb4000_target *t)
{
    const acb4000_lun *l = &t->luns[t->lun];
    uint32_t spt = l->params.sectors_per_track ? l->params.sectors_per_track : 18u;
    uint32_t per_cyl = (uint32_t)l->params.heads * spt;
    uint32_t cyl, head, sector, bytes_from_index;

    if (per_cyl == 0) {
        check_condition(t, ACB4000_ERR_BAD_ARGUMENT, 0, 0);
        return;
    }
    cyl = t->lba / per_cyl;
    head = (t->lba % per_cyl) / spt;
    sector = t->lba % spt;
    bytes_from_index = sector * (l->params.block_size ? l->params.block_size : 512u);

    /* Figure 5-6's defect descriptor: cylinder, head, bytes from index.  The
     * *widths* are inferred -- the figure gives the order, not the field sizes --
     * so they are stated here rather than implied: 2 + 1 + 3 + 2 reserved. */
    t->staging[0] = (uint8_t)(cyl >> 8);
    t->staging[1] = (uint8_t)cyl;
    t->staging[2] = (uint8_t)head;
    t->staging[3] = (uint8_t)(bytes_from_index >> 16);
    t->staging[4] = (uint8_t)(bytes_from_index >> 8);
    t->staging[5] = (uint8_t)bytes_from_index;
    t->staging[6] = 0;
    t->staging[7] = 0;
    staging_in(t, 8);
}


/* ------------------------------------------------------------ the dispatcher */

static uint32_t lba6(const uint8_t *c)
{
    return ((uint32_t)(c[1] & 0x1Fu) << 16) | ((uint32_t)c[2] << 8) | c[3];
}

/* ANSI X3T9.2: a six-byte command's block count of zero means 256 blocks.  The
 * manual's CDB figures follow the standard, so this is the standard's rule. */
static uint32_t blocks6(const uint8_t *c)
{
    return c[4] ? (uint32_t)c[4] : 256u;
}

static uint32_t lba10(const uint8_t *c)
{
    return be32(c + 2);
}

static uint32_t blocks10(const uint8_t *c)
{
    return be16(c + 7);
}

static uint32_t unit_block_size(const acb4000_target *t)
{
    if (t->luns[t->lun].have_params)
        return t->luns[t->lun].params.block_size;
    if (t->store != NULL && t->store->block_size != NULL)
        return t->store->block_size(t->store->ctx);
    return 512u;
}

/* VERIFY (2F) -- manual 5.4.5.  No data phase: the controller checks the ECC of
 * blocks that are already on the drive.  This is the pass `PREP.COM`'s "format
 * and verify" waits on, and the one MAME's generic SCSI target has no handler
 * for (docs/osborne1nx-machine.md section 5). */
static void do_verify(acb4000_target *t)
{
    uint8_t block[ACB4000_BLOCK_MAX];
    uint32_t n;

    for (n = 0; n < t->blocks; n++) {
        if (t->store == NULL || t->store->read == NULL ||
            t->store->read(t->store->ctx, t->lba + n, 1, block) != 0) {
            check_condition(t, ACB4000_ERR_ILLEGAL_BLOCK, t->lba + n, 1);
            return;
        }
    }
    t->status = ACB4000_ST_GOOD;
    no_data(t);
}

/* A data-out phase has been drained: run whatever was waiting on it. */
static void finish_data_out(acb4000_target *t)
{
    switch (t->defer) {
    case ACB4000_DEFER_MODE_SELECT:
        parse_mode_select(t);
        break;
    case ACB4000_DEFER_FORMAT:
        do_format(t);
        break;
    case ACB4000_DEFER_SEARCH:
        do_search(t);
        break;
    default:
        t->phase = ACB4000_PHASE_NONE;
        if (t->opcode == 0x2Eu)          /* WRITE AND VERIFY: write, then verify */
            do_verify(t);
        break;
    }
}


void acb4000_target_command(acb4000_target *t, const uint8_t *cdb, int cdb_len)
{
    acb4000_lun *l;
    int unsupported = 0;

    if (cdb_len <= 0)
        cdb_len = acb4000_cdb_length(cdb[0]);
    if (cdb_len > (int)sizeof t->cdb)
        cdb_len = (int)sizeof t->cdb;

    memset(t->cdb, 0, sizeof t->cdb);
    memcpy(t->cdb, cdb, (size_t)cdb_len);
    t->cdb_len = cdb_len;
    t->opcode = cdb[0];
    t->lun = (uint8_t)((cdb[1] >> 5) & 0x07u);   /* manual 5.2.3: byte 1, MSB */
    if (t->lun >= ACB4000_LUNS)
        t->lun = 0;

    t->phase = ACB4000_PHASE_NONE;
    t->total = t->moved = 0;
    t->staging_len = t->staging_moved = 0;
    t->block_xfer = 0;
    t->defer = ACB4000_DEFER_NONE;
    t->status = ACB4000_ST_GOOD;
    t->lba = t->blocks = 0;
    t->block_size = 0;

    l = &t->luns[t->lun];
    /* "Sense data will be cleared on receiving a subsequent command from the
     * host that received the check condition" -- manual 5.5.1. */
    if (t->opcode != 0x03u)
        lun_clear_sense(l);

    switch (t->opcode) {
    case 0x00:                                  /* TEST UNIT READY */
    case 0x01:                                  /* REZERO UNIT */
        no_data(t);
        break;

    case 0x03:                                  /* REQUEST SENSE */
        build_request_sense(t);
        break;

    case 0x04:                                  /* FORMAT UNIT */
        if (t->cdb[1] & 0x10u) {                /* a defect list follows */
            uint32_t n = 4u + (uint32_t)be16(t->cdb + 2) * 8u;
            if (n > sizeof t->staging)          /* more than the buffer can hold */
                unsupported = 1;
            else
                staging_out(t, n, ACB4000_DEFER_FORMAT);
        } else {
            do_format(t);
        }
        break;

    case 0x05:                                  /* CHECK TRACK FORMAT (I-J) */
        if (!t->extended)
            unsupported = 1;
        else
            no_data(t);
        break;

    case 0x08:                                  /* READ */
        t->lba = lba6(t->cdb);
        t->blocks = blocks6(t->cdb);
        t->block_size = unit_block_size(t);
        begin_blocks(t, 1);
        break;

    case 0x0A:                                  /* WRITE */
        t->lba = lba6(t->cdb);
        t->blocks = blocks6(t->cdb);
        t->block_size = unit_block_size(t);
        begin_blocks(t, 0);
        break;

    case 0x0B:                                  /* SEEK */
        t->lba = lba6(t->cdb);
        no_data(t);
        break;

    case 0x0C:                                  /* INITIALIZE DRIVE (I-J) */
        if (!t->extended)
            unsupported = 1;
        else
            no_data(t);
        break;

    case 0x0D:                                  /* READ ECC BURST LENGTH (I-J) */
        if (!t->extended) {
            unsupported = 1;
        } else {
            put_be16(t->staging, ACB4000_ECC_BURST);   /* always 8 */
            staging_in(t, 2);
        }
        break;

    case 0x0E:                                  /* listed in the Mar84 Table B-1 */
        no_data(t);
        break;

    case 0x0F:                                  /* TRANSLATE */
        t->lba = lba6(t->cdb);
        build_translate(t);
        break;

    /* The manual pins neither transfer length, so these accept the command and
     * return status rather than inventing a data phase (see the file header). */
    case 0x10:                                  /* SET ERROR THRESHOLD */
    case 0x11:                                  /* READ COUNTERS */
    case 0x13:                                  /* WRITE DATA BUFFER */
    case 0x14:                                  /* READ DATA BUFFER */
    case 0x1C:                                  /* RECEIVE DIAGNOSTIC */
    case 0x1D:                                  /* SEND DIAGNOSTIC */
        no_data(t);
        break;

    case 0x15:                                  /* MODE SELECT */
        staging_out(t, t->cdb[4], ACB4000_DEFER_MODE_SELECT);
        break;

    case 0x1A:                                  /* MODE SENSE */
        build_mode_sense(t);
        break;

    case 0x1B:                                  /* START/STOP UNIT */
        no_data(t);
        break;

    case 0x25:                                  /* READ CAPACITY */
        build_read_capacity(t);
        break;

    case 0x28:                                  /* READ (extended) */
        t->lba = lba10(t->cdb);
        t->blocks = blocks10(t->cdb);
        t->block_size = unit_block_size(t);
        begin_blocks(t, 1);
        break;

    case 0x2A:                                  /* WRITE (extended) */
        t->lba = lba10(t->cdb);
        t->blocks = blocks10(t->cdb);
        t->block_size = unit_block_size(t);
        begin_blocks(t, 0);
        break;

    case 0x2E:                                  /* WRITE AND VERIFY */
        t->lba = lba10(t->cdb);
        t->blocks = blocks10(t->cdb);
        t->block_size = unit_block_size(t);
        begin_blocks(t, 0);
        break;

    case 0x2F:                                  /* VERIFY */
        t->lba = lba10(t->cdb);
        t->blocks = blocks10(t->cdb);
        t->block_size = unit_block_size(t);
        do_verify(t);
        break;

    case 0x31:                                  /* SEARCH DATA EQUAL */
        t->lba = lba10(t->cdb);
        t->blocks = blocks10(t->cdb);
        t->block_size = unit_block_size(t);
        staging_out(t, 20, ACB4000_DEFER_SEARCH);   /* the pattern extends it */
        break;

    case 0xE0:                                  /* diagnostics (I-J), always good */
    case 0xE3:
    case 0xE4:
        if (!t->extended)
            unsupported = 1;
        else
            no_data(t);
        break;

    default:
        unsupported = 1;
        break;
    }

    if (unsupported)
        check_condition(t, ACB4000_ERR_BAD_ARGUMENT, 0, 0);
}


/* ---------------------------------------------------------------- the phases
 *
 * The shim (and on hardware the PIO side) moves bytes without knowing which
 * shape of phase it has: `read` produces data-in bytes, `write` consumes
 * data-out bytes, and a phase that has run out reports NONE so the shim can move
 * to the status phase.
 */
uint32_t acb4000_target_read(acb4000_target *t, uint8_t *out, uint32_t len)
{
    uint32_t given = 0;

    if (t->phase != ACB4000_PHASE_DATA_IN)
        return 0;

    if (!t->block_xfer) {
        /* a short transfer the target built in one go */
        uint32_t avail = t->staging_len - t->staging_moved;
        uint32_t n = (len < avail) ? len : avail;
        if (n > 0) {
            memcpy(out, t->staging + t->staging_moved, n);
            t->staging_moved += n;
            given = n;
        }
        if (t->staging_moved >= t->staging_len)
            t->phase = ACB4000_PHASE_NONE;
        return given;
    }

    while (given < len) {
        if (t->staging_moved >= t->staging_len) {
            uint32_t idx = t->moved / t->block_size;
            if (idx >= t->blocks) {
                t->phase = ACB4000_PHASE_NONE;
                break;
            }
            if (t->store == NULL || t->store->read == NULL ||
                t->store->read(t->store->ctx, t->lba + idx, 1, t->staging) != 0) {
                check_condition(t, ACB4000_ERR_ILLEGAL_BLOCK, t->lba + idx, 1);
                return given;
            }
            t->staging_len = t->block_size;
            t->staging_moved = 0;
        }
        {
            uint32_t avail = t->staging_len - t->staging_moved;
            uint32_t n = (len - given < avail) ? (len - given) : avail;
            memcpy(out + given, t->staging + t->staging_moved, n);
            t->staging_moved += n;
            t->moved += n;
            given += n;
        }
    }

    if (t->moved >= t->total)
        t->phase = ACB4000_PHASE_NONE;
    return given;
}

uint32_t acb4000_target_write(acb4000_target *t, const uint8_t *in, uint32_t len)
{
    uint32_t taken = 0;

    if (t->phase != ACB4000_PHASE_DATA_OUT)
        return 0;

    if (!t->block_xfer) {
        uint32_t room = (t->total > t->staging_len) ? (t->total - t->staging_len) : 0;
        uint32_t n = (len < room) ? len : room;
        if (n > (uint32_t)sizeof t->staging - t->staging_len) {   /* belt and braces */
            check_condition(t, ACB4000_ERR_BAD_ARGUMENT, 0, 0);
            return taken;
        }
        if (n > 0) {
            memcpy(t->staging + t->staging_len, in, n);
            t->staging_len += n;
            taken = n;
        }
        /* SEARCH DATA EQUAL: the argument's own bytes 18-19 give the pattern
         * length, so the phase is not over until they have arrived. */
        if (t->defer == ACB4000_DEFER_SEARCH && t->staging_len >= 20 && t->total == 20) {
            uint32_t pl = be16(t->staging + 18);
            if (pl == 0 || pl > ACB4000_BLOCK_MAX ||
                20u + pl > (uint32_t)sizeof t->staging) {
                check_condition(t, ACB4000_ERR_BAD_ARGUMENT, 0, 0);
                return taken;
            }
            t->total = 20u + pl;
        }
        if (t->staging_len >= t->total)
            finish_data_out(t);
        return taken;
    }

    while (taken < len) {
        uint32_t room = t->block_size - t->staging_len;
        uint32_t n = (len - taken < room) ? (len - taken) : room;

        memcpy(t->staging + t->staging_len, in + taken, n);
        t->staging_len += n;
        taken += n;

        if (t->staging_len == t->block_size) {
            uint32_t idx = t->moved / t->block_size;
            if (t->store == NULL || t->store->write == NULL || idx >= t->blocks ||
                t->store->write(t->store->ctx, t->lba + idx, 1, t->staging) != 0) {
                check_condition(t, ACB4000_ERR_ILLEGAL_BLOCK, t->lba + idx, 1);
                return taken;
            }
            t->moved += t->block_size;
            t->staging_len = 0;
            t->staging_moved = 0;
        }
    }

    if (t->moved >= t->total)
        finish_data_out(t);
    return taken;
}

