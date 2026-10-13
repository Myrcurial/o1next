/* The Adaptec ACB-4000 SCSI-1 target personality, and the Z80 host-adapter shim
 * it answers through (#179, #8).
 *
 * Why this exists
 * ---------------
 * `docs/harddisk-decision.md` section 5 splits the personality into three layers,
 * and the split is the whole design:
 *
 *   1. the SCSI target        -- machine independent, written to the OEM manual
 *   2. the host-adapter shim  -- a port block, i.e. *data* (a profile), not code
 *   3. the backing store      -- the volume blob behind a small read/write API
 *
 * Because layer 2 is data, one target serves any Z80 machine with an
 * ACB-4000-class driver: the Osborne 1 / MD-10 profile (`base` 30h) and the OEM
 * manual's Appendix A reference model are two entries in the same table.
 *
 * This file is pure logic -- no hardware access, no RTOS, no SDK -- so it builds
 * and is tested on the host (see test_acb4000.c and run_tests.sh), exactly as
 * `firmware/rom-ident/` does.  On the RP2350 the same three files are compiled
 * into the interposer firmware and the store is backed by the FAT32 library
 * instead of a malloc'd buffer; nothing else changes.
 *
 * What is authoritative
 * ---------------------
 * The command set and every data layout here come from the ACB-4000 OEM manual
 * (`research/adaptec/acb4000/`), not from the driver and not from the controller
 * ROMs.  The register handshake and the status bit map come from the *driver*
 * (`docs/acb4000-host-adapter.md` section 1, `docs/osborne1ng-machine.md`), because the
 * manual's host-adapter model is the reference one and the MD-10's is not.
 */
#ifndef O1_ACB4000_H
#define O1_ACB4000_H

#include <stddef.h>
#include <stdint.h>

/* ------------------------------------------------------------------ constants
 *
 * The ones the manual pins.  Anything not pinned is a parameter, not a #define.
 */
#define ACB4000_LUNS            2u      /* two ST-506 drives on one controller */
#define ACB4000_FILL_DEFAULT    0x6Cu   /* the controller's default FORMAT fill */
#define ACB4000_FILL_CPM        0xE5u   /* ... and CP/M's, for a CP/M system */
#define ACB4000_BLOCK_MIN       256u    /* the manual: block size 256, 512 or 1024 */
#define ACB4000_BLOCK_MAX       1024u
#define ACB4000_ECC_BURST       8u      /* 0D READ ECC BURST LENGTH always returns 8 */
#define ACB4000_TRACK_BYTES     8192u   /* "the normal 32 sectors" of 256 B per track */
#define ACB4000_SENSE_LEN       4u      /* the controller returns four sense bytes */
#define ACB4000_STAGING         2048u   /* the controller's own RAM buffer is 1 KiB */

/* The completion status byte (manual 5.5).  Bits 0, 4, 5, 6 and 7 are always
 * zero; the three that mean anything are these. */
#define ACB4000_ST_GOOD         0x00u
#define ACB4000_ST_CHECK        0x02u   /* check condition -- REQUEST SENSE is up */
#define ACB4000_ST_EQUAL        0x04u   /* a search was satisfied */
#define ACB4000_ST_BUSY         0x08u   /* busy, or a LUN with outstanding sense */
#define ACB4000_ST_MASK         0x0Eu

/* The error codes the sense byte carries (manual section 6.4).  Only the ones
 * this implementation can actually raise are named. */
#define ACB4000_ERR_NONE            0x00u
#define ACB4000_ERR_UNRECOVERED     0x03u
#define ACB4000_ERR_DRIVE_NOT_READY 0x04u
#define ACB4000_ERR_SEEK            0x15u
#define ACB4000_ERR_BAD_FORMAT      0x1Cu
#define ACB4000_ERR_ILLEGAL_BLOCK   0x21u
#define ACB4000_ERR_BAD_ARGUMENT    0x24u
#define ACB4000_ERR_INVALID_LUN     0x25u
#define ACB4000_ERR_WRITE_PROTECT   0x27u

/* What the shim asks the target after a CDB has been delivered. */
typedef enum {
    ACB4000_PHASE_NONE = 0,  /* no data phase: go straight to status */
    ACB4000_PHASE_DATA_IN,   /* the target has bytes for the host */
    ACB4000_PHASE_DATA_OUT   /* the host has bytes for the target */
} acb4000_phase;

/* ------------------------------------------------- layer 3: the backing store
 *
 * The controller's drive, seen through five calls.  On hardware this is the
 * FAT32 blob (docs/harddisk-decision.md section 7, #180); on the host it is a
 * malloc'd buffer, and that is the only difference -- so the target below never
 * knows which it is talking to.
 *
 * `capacity()` returns the address of the **last** block, because that is what
 * READ CAPACITY (25h) reports and it saves every caller the off-by-one.
 */
typedef struct acb4000_store acb4000_store;
struct acb4000_store {
    void *ctx;
    uint32_t (*capacity)(void *ctx);                                    /* last block address */
    uint32_t (*block_size)(void *ctx);
    int      (*read)(void *ctx, uint32_t lba, uint32_t count, uint8_t *out);
    int      (*write)(void *ctx, uint32_t lba, uint32_t count, const uint8_t *in);
    int      (*format)(void *ctx, uint8_t fill);                        /* fill the whole unit */
};

/* The in-memory implementation: what the host tests use, and the shape the
 * RP2350's store takes before the FAT32 library is wired in.  `format()` fills
 * every block with the byte -- which is what makes a blank volume one repeated
 * byte, the property #180's sparse blob encoding is built on. */
typedef struct {
    acb4000_store store;
    uint8_t      *data;
    uint32_t      blocks;
    uint32_t      block_size;
    uint8_t       fill;
    int           formatted;
} acb4000_mem_store;

int  acb4000_mem_store_init(acb4000_mem_store *m, uint32_t blocks,
                            uint32_t block_size, uint8_t fill);
void acb4000_mem_store_free(acb4000_mem_store *m);

/* --------------------------------------------------- layer 1: the SCSI target
 *
 * The MODE SELECT / MODE SENSE drive parameter list (manual figure 5-20).  The
 * nine bytes the host round-trips are cylinders, heads, reduced-write-current,
 * write-precompensation, landing-zone and step code -- the same nine the
 * `DRIVETBL.DAT` record carries, which is why the shim's `md10` profile is a
 * byte-order change and not a remapping.
 *
 * Byte order: the *manual's descriptor* is big-endian (MSB first, figure 5-20);
 * the drive table on disk is little-endian.  This struct is host order -- the
 * two byte-swaps happen in `mode_select()` / `mode_sense()` and nowhere else.
 */
typedef struct {
    uint8_t  layout_code;             /* 01 soft-sectored fixed, 02 hard-sectored/removable */
    uint16_t cylinders;               /* 16..2048; default 306 */
    uint8_t  heads;                   /* 1..16;    default 2 */
    uint16_t reduced_write_current;   /* 0..2047;  default 128 (the manual) */
    uint16_t write_precomp;           /* ignored on the ACB-4000A -- tied to RWC */
    uint8_t  landing_zone;            /* bit 7 = direction, low 7 bits = cylinders */
    uint8_t  step_code;               /* 0 = 3.0 ms ST-506, 1 = 28 us ST-412, 2 = 12 us */
    uint8_t  hard_sectored;           /* bytes 0A/0B only exist for these */
    uint8_t  removable;
    uint16_t sectors_per_track_hs;    /* hard-sectored only */
    uint32_t block_size;              /* 256, 512 or 1024 */
    /* Not in the descriptor, but needed to turn an LBA into a cylinder and a
     * head (TRANSLATE, 0Fh).  The drive table's own capacity formula assumes 18
     * (`cyl x heads x 18 x 512`, docs/harddisk-decision.md section 7.2) while the
     * manual's 8 KiB track gives 16 at a 512-byte block.  Nothing is reconciled
     * here; the default is the drive table's, so a reported geometry matches
     * what period software shows. */
    uint8_t  sectors_per_track;
} acb4000_params;

void     acb4000_params_default(acb4000_params *p);       /* the manual's ST-506 defaults */
uint32_t acb4000_params_blocks(const acb4000_params *p);  /* cylinders x heads x sectors */


/* One logical unit's state: its geometry, its fill byte and its sense. */
typedef struct {
    acb4000_params params;
    int            have_params;    /* a MODE SELECT has been seen */
    uint8_t        fill;           /* the fill the last FORMAT used */
    uint8_t        sense[ACB4000_SENSE_LEN];
    int            sense_valid;    /* a check condition is outstanding */
} acb4000_lun;

/* The target.  Feed it a CDB with `acb4000_target_command()`, then ask for the
 * phase, move bytes, and read the status -- which is exactly what the shim (and
 * on hardware the PIO side) does. */
typedef struct {
    const acb4000_store *store;
    acb4000_lun          luns[ACB4000_LUNS];
    int                  extended;      /* jumper I-J: the expanded command set */

    /* the command in flight */
    uint8_t       cdb[16];
    int           cdb_len;
    uint8_t       opcode;
    uint8_t       lun;
    uint32_t      lba;
    uint32_t      blocks;
    uint32_t      block_size;   /* the unit's block size for this command */
    acb4000_phase phase;
    uint32_t      total;        /* bytes the data phase will move */
    uint32_t      moved;        /* bytes moved so far */
    uint8_t       status;       /* the completion status byte to report */

    /* a staging buffer for the short transfers (MODE SENSE's parameter list,
     * READ CAPACITY's 8 bytes, TRANSLATE's 8, REQUEST SENSE's 4, the SEARCH
     * argument).  Block transfers stream through the store and never touch it. */
    uint8_t       staging[ACB4000_STAGING];
    uint32_t      staging_len;
    uint32_t      staging_moved;
    int           block_xfer;   /* 1 = the phase streams blocks through the store */

    /* FORMAT's defect list, MODE SELECT's parameter list and the SEARCH
     * argument all arrive as data-out before anything can be done with them, so
     * they are deferred until the phase has been drained. */
    int           defer;        /* which deferred action, ACB4000_DEFER_* below */
} acb4000_target;

enum {
    ACB4000_DEFER_NONE = 0,
    ACB4000_DEFER_MODE_SELECT,
    ACB4000_DEFER_FORMAT,
    ACB4000_DEFER_SEARCH
};

void          acb4000_target_init(acb4000_target *t, const acb4000_store *store, int extended);
void          acb4000_target_reset(acb4000_target *t);
void          acb4000_target_command(acb4000_target *t, const uint8_t *cdb, int cdb_len);
acb4000_phase acb4000_target_phase(const acb4000_target *t);
uint32_t      acb4000_target_length(const acb4000_target *t);
uint8_t       acb4000_target_status(const acb4000_target *t);
uint32_t      acb4000_target_read(acb4000_target *t, uint8_t *out, uint32_t len);
uint32_t      acb4000_target_write(acb4000_target *t, const uint8_t *in, uint32_t len);

/* CDB length from the group code in the opcode's top three bits (manual 5.2.1). */
int acb4000_cdb_length(uint8_t opcode);

/* ------------------------------------------------- layer 2: the host-adapter shim
 *
 * A port block, expressed as data.  Everything the two known adapters differ on
 * lives in the profile: the base port, which register carries the select byte
 * and which asserts the handshake, and the five status bits.
 *
 * The `md10` profile is *measured* (docs/acb4000-host-adapter.md section 1); the
 * `reference` one is the OEM manual's Appendix A model, kept so the same target
 * serves a machine that followed the reference design.
 */
typedef struct {
    const char *name;
    uint16_t    base;          /* the default port base (PORTCHNG.COM patches this) */
    int         data_reg;      /* where the select byte and the data live */
    int         status_reg;    /* the register the host reads the status from */
    int         sel_reg;       /* which register asserts the handshake */
    uint8_t     sel_value;     /* ... with which value */
    uint8_t     select_mask;   /* the one-of-eight ID mask this controller answers */
    uint8_t     bit_sel;       /* status: the selection handshake */
    uint8_t     bit_req;       /* status: REQ -- move a byte now */
    uint8_t     bit_online;    /* status: one controller on-line */
    uint8_t     bit_phase;     /* status: 1 = command/status/message, 0 = data */
    uint8_t     bit_end;       /* status: the current phase is complete */
} acb4000_profile;

extern const acb4000_profile acb4000_profile_md10;
extern const acb4000_profile acb4000_profile_reference;

typedef enum {
    ACB4000_XFER_IDLE = 0,
    ACB4000_XFER_SELECTED,
    ACB4000_XFER_COMMAND,
    ACB4000_XFER_DATA,
    ACB4000_XFER_STATUS
} acb4000_xfer;

typedef struct {
    const acb4000_profile *profile;
    acb4000_target        *target;
    acb4000_xfer           xfer;
    uint8_t                cdb[16];
    int                    cdb_index;
    int                    cdb_length;
    uint8_t                reg[4];       /* what the host last wrote to each register */
    uint8_t                select;       /* the select byte the host wrote */
    uint8_t                last_read;    /* the last byte handed over on the data port */
    int                    status_reads; /* the status byte survives two reads */
    int                    online;
} acb4000_shim;

void    acb4000_shim_init(acb4000_shim *s, const acb4000_profile *p, acb4000_target *t);
void    acb4000_shim_reset(acb4000_shim *s);
uint8_t acb4000_shim_read(acb4000_shim *s, int offset);            /* offset 0..3 */
void    acb4000_shim_write(acb4000_shim *s, int offset, uint8_t data);

#endif /* O1_ACB4000_H */

