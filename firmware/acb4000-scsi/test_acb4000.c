/* Host tests for the ACB-4000 SCSI personality (#179).
 *
 * Build and run (no board, no SDK -- plain C):
 *
 *     firmware/acb4000-scsi/run_tests.sh          # tests only
 *     firmware/acb4000-scsi/run_tests.sh -v       # ... and print a trace
 *
 * What is being tested, and why each thing earns its place:
 *
 *   1. the manual's CDB geometry      -- the class code really does fix the CDB
 *      length, because the command phase depends on it;
 *   2. the register handshake, replayed from the *driver's own routine*
 *      (HARDBIOS.SPR file 0x285 / CNTLRCOD.OVL 0x8030) rather than from a
 *      convenient abstraction -- this is the closest the host gets to running
 *      the period software, and it is what makes the bit map a test and not a
 *      comment;
 *   3. the geometry round trip        -- MODE SELECT in, MODE SENSE out, byte
 *      for byte, because the MD-10's DPB is built from it (docs/acb4000-firmware.md);
 *   4. the commands that actually blocked PREP.COM -- VERIFY (2F) and the
 *      SEARCH DATA EQUAL family -- plus FORMAT's fill byte;
 *   5. the expanded set behind jumper I-J, refused when the jumper is not set;
 *   6. the two LUNs, and the `reference` profile.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "acb4000.h"

static int failures;

#define CHECK(cond, ...)                                               \
    do {                                                               \
        if (!(cond)) {                                                 \
            printf("  FAIL line %d: ", __LINE__);                      \
            printf(__VA_ARGS__);                                       \
            printf("\n");                                              \
            failures++;                                                \
        }                                                              \
    } while (0)

static int verbose;

/* ------------------------------------------------------------------ 1. CDBs */

static void test_cdb_lengths(void)
{
    /* class 0 -> 6 bytes, class 1 and 2 -> 10, class 3 -> 12 */
    CHECK(acb4000_cdb_length(0x00) == 6, "TEST UNIT READY should be 6 bytes");
    CHECK(acb4000_cdb_length(0x15) == 6, "MODE SELECT should be 6 bytes");
    CHECK(acb4000_cdb_length(0x25) == 10, "READ CAPACITY should be 10 bytes");
    CHECK(acb4000_cdb_length(0x2F) == 10, "VERIFY should be 10 bytes");
    CHECK(acb4000_cdb_length(0x31) == 10, "SEARCH DATA EQUAL should be 10 bytes");
    CHECK(acb4000_cdb_length(0x60) == 12, "a class 3 opcode should be 12 bytes");
    CHECK(acb4000_cdb_length(0xE0) == 6,
          "the E0 diagnostics are class 7, which falls back to 6 bytes");
}

/* -------------------------------------------------------------- 2. the geometry */

static void test_params(void)
{
    acb4000_params p;

    acb4000_params_default(&p);
    CHECK(p.cylinders == 306, "the manual's default cylinder count is 306");
    CHECK(p.heads == 2, "the manual's default head count is 2");
    CHECK(p.reduced_write_current == 128, "the default RWC is cylinder 128");
    CHECK(p.step_code == 0, "the default step code is 0 (ST-506)");
    CHECK(p.block_size == 512, "the default block size is 512");

    /* the drive table's PYXIS13 -- the vendor's own default for a new entry */
    p.cylinders = 321;
    p.heads = 4;
    p.sectors_per_track = 18;
    CHECK(acb4000_params_blocks(&p) == 23112,
          "PYXIS13 should be 321 x 4 x 18 = 23112 blocks, got %u",
          (unsigned)acb4000_params_blocks(&p));
    /* ... and that is the editor's own 11 556K (23112 x 512 B) */
    CHECK((uint32_t)acb4000_params_blocks(&p) * 512u == 11556u * 1024u,
          "PYXIS13's block count should reproduce the editor's 11556K");
}

/* ----------------------------------------------------------------- 3. the store */

static void test_store(void)
{
    acb4000_mem_store m;
    uint8_t buf[512];
    uint8_t expect[512];
    uint32_t i;

    CHECK(acb4000_mem_store_init(&m, 64, 512, ACB4000_FILL_DEFAULT) == 0,
          "a 64-block store should initialise");
    CHECK(m.store.capacity(m.store.ctx) == 63,
          "capacity() should report the last block address, not the count");
    CHECK(m.store.block_size(m.store.ctx) == 512, "block size should be 512");

    for (i = 0; i < sizeof expect; i++)
        expect[i] = ACB4000_FILL_DEFAULT;
    CHECK(m.store.read(m.store.ctx, 7, 1, buf) == 0, "block 7 should be readable");
    CHECK(memcmp(buf, expect, sizeof buf) == 0,
          "a fresh store should be the fill byte throughout");

    for (i = 0; i < sizeof buf; i++)
        buf[i] = (uint8_t)i;
    CHECK(m.store.write(m.store.ctx, 7, 1, buf) == 0, "block 7 should be writable");
    memset(buf, 0, sizeof buf);
    CHECK(m.store.read(m.store.ctx, 7, 1, buf) == 0, "block 7 should read back");
    CHECK(buf[0] == 0 && buf[255] == 255, "the written bytes should survive");

    /* ... and FORMAT re-fills it */
    CHECK(m.store.format(m.store.ctx, 0xE5) == 0, "FORMAT should fill the unit");
    CHECK(m.fill == 0xE5, "the store should remember the fill byte it was given");
    CHECK(m.store.read(m.store.ctx, 7, 1, buf) == 0, "block 7 should still be there");
    CHECK(buf[0] == 0xE5 && buf[255] == 0xE5, "FORMAT should overwrite the block");

    /* out of range is refused rather than wrapped */
    CHECK(m.store.read(m.store.ctx, 64, 1, buf) != 0, "block 64 is past the end");
    CHECK(m.store.read(m.store.ctx, 63, 2, buf) != 0, "a run past the end is refused");

    acb4000_mem_store_free(&m);
}

/* ------------------------------------------------- 4. the driver, replayed
 *
 * A model of the MD-10's own transaction routine, transcribed from the listing
 * in docs/osborne1ng-machine.md (HARDBIOS.SPR file 0x285, address 0xE285):
 *
 *   e28b  in a,(032h) / and 001h / jr nz,e28b   wait for the handshake to clear
 *   e291  ld a,(00557h) / out (030h),a          the select byte
 *   e296  ld a,010h / out (032h),a              assert the handshake
 *   e29a  in a,(032h) / and 001h / jr z,e29a    ... and wait for the card
 *   e2a0  xor a / out (032h),a                  release it: the command phase
 *   e2a8  in a,(032h) / bit 6 / bit 1 / bit 5   one CDB byte per REQ, via OUTI
 *   e2bf  in a,(032h) / bit 6 / and 002h        the data phase: 512 B per pass
 *   e2da  ini / in a,(032h) / bit 6 / bit 5     byte-at-a-time data-in
 *   e2e6  in b,(c) / in a,(032h) / and 040h     the status byte, then acknowledge
 *   e2ee  in a,(030h) / ld a,b / and 002h       0 = good, 2 = check condition
 *
 * The routine is the *specification* for the register model: if the shim's bit
 * map were wrong, these tests would hang or read the wrong byte.  That is why
 * the model is a transcription and not a convenience wrapper.
 */
typedef struct {
    const uint8_t *out;      /* the CDB, followed by whatever the command carries */
    uint32_t       out_len;
    uint32_t       out_pos;
    uint8_t       *in;       /* what the host receives */
    uint32_t       in_cap;
    uint32_t       in_pos;
} drv_buf;

#define DRV_GUARD 200000   /* a wrong bit map must fail, not hang the suite */

static uint8_t drv_in(acb4000_shim *s, int off)
{
    return acb4000_shim_read(s, off);
}

static void drv_out(acb4000_shim *s, int off, uint8_t v)
{
    acb4000_shim_write(s, off, v);
}

/* Returns the routine's own answer: 0 = good, 2 = check condition, 0xFF = no
 * controller answered the select (the presence probe's failure mode).
 *
 * Every offset and bit comes from the profile, so the same model drives the
 * `reference` profile too -- which is the point of layer 2 being data. */
static int drv_transaction(acb4000_shim *s, uint8_t select_byte, drv_buf *b)
{
    const acb4000_profile *p = s->profile;
    int guard;
    uint8_t st, status;

    /* wait for the select handshake to clear */
    for (guard = 0; (drv_in(s, p->status_reg) & p->bit_sel) != 0; guard++)
        if (guard > DRV_GUARD) return -2;

    drv_out(s, p->data_reg, select_byte);  /* the select byte */
    drv_out(s, p->sel_reg, p->sel_value);  /* assert the handshake */

    if ((drv_in(s, p->status_reg) & p->bit_sel) == 0)   /* the card never answered */
        return 0xFF;
    drv_out(s, p->sel_reg, 0x00u);         /* release it: the command phase */

    /* the command phase: a CDB byte for every REQ while PHASE is up and END is
     * clear -- the routine's `outi` loop at e2a8 */
    for (guard = 0; guard < DRV_GUARD; guard++) {
        st = drv_in(s, p->status_reg);
        if (st & p->bit_end)               /* the phase is over */
            break;
        if ((st & p->bit_req) == 0)        /* no REQ -> poll */
            continue;
        if ((st & p->bit_phase) == 0)      /* not the command phase -> done */
            break;
        drv_out(s, p->data_reg, (b->out_pos < b->out_len) ? b->out[b->out_pos] : 0x00u);
        b->out_pos++;
    }

    /* the data phase.  The routine decides by the status bits, not by the
     * opcode: END clear + REQ means data-out (OTIR, 512 bytes a pass); END set
     * with PHASE clear means data-in (a byte at a time). */
    for (guard = 0; guard < DRV_GUARD; guard++) {
        uint32_t i;

        st = drv_in(s, p->status_reg);
        if (st & p->bit_end) {             /* e2cf: the phase is over */
            if (st & p->bit_phase)         /* PHASE -> the status phase */
                break;
            /* data-in (e2da): take a byte, then look again.  The byte that
             * finds the end of the phase is the status byte -- the routine
             * takes it before it notices, which is why the status survives two
             * reads. */
            if (b->in_pos < b->in_cap)
                b->in[b->in_pos++] = drv_in(s, p->data_reg);
            else
                (void)drv_in(s, p->data_reg);
            continue;
        }
        if ((st & p->bit_req) == 0)        /* no REQ -> poll */
            continue;
        /* data-out: 512 bytes a pass (2 x OTIR with B = 0).  Past the end of the
         * phase the card ignores the bytes, exactly as the OTIR loop does. */
        for (i = 0; i < 512u; i++) {
            uint8_t v = (b->out_pos < b->out_len) ? b->out[b->out_pos] : 0x00u;
            b->out_pos++;
            drv_out(s, p->data_reg, v);
        }
    }

    /* the status byte, read twice: once into B, once to acknowledge */
    status = drv_in(s, p->data_reg);
    for (guard = 0; (drv_in(s, p->status_reg) & p->bit_end) == 0; guard++)
        if (guard > DRV_GUARD) return -2;
    (void)drv_in(s, p->data_reg);

    return status & 0x02u;
}

/* The presence probe (docs/acb4000-host-adapter.md 1): write 04h to base+2 and
 * read it back -- "exactly one controller on-line". */
static void test_probe(void)
{
    acb4000_mem_store m;
    acb4000_target t;
    acb4000_shim s;

    (void)acb4000_mem_store_init(&m, 64, 512, ACB4000_FILL_DEFAULT);
    acb4000_target_init(&t, &m.store, 0);
    acb4000_shim_init(&s, &acb4000_profile_md10, &t);

    /* the probe's own writes (CNTLRCOD.OVL 0x80D2) */
    drv_out(&s, 1, 0x8Fu);
    drv_out(&s, 1, 0x07u);
    drv_out(&s, 3, 0xCFu);
    drv_out(&s, 3, 0x6Bu);
    drv_out(&s, 3, 0x07u);
    drv_out(&s, 2, 0x04u);
    (void)drv_in(&s, 0);
    CHECK(drv_in(&s, 2) == 0x04u,
          "base+2 should read 04h -- one controller on-line, got %02X",
          drv_in(&s, 2));

    /* with no target fitted the same write must NOT read back: that is what
     * makes the probe a probe and not an echo */
    acb4000_shim_init(&s, &acb4000_profile_md10, NULL);
    drv_out(&s, 2, 0x04u);
    CHECK((drv_in(&s, 2) & 0x04u) == 0,
          "with no controller the on-line bit must stay clear");

    acb4000_mem_store_free(&m);
}


/* Run one command through the driver model.  `payload` is what follows the CDB
 * in the host's buffer, exactly as the routine's `outi`/`otir` loops would walk
 * it.  Returns the routine's answer; `*in_len` gets the number of bytes it read
 * back (which includes the status byte when the data-in loop takes one). */
static int drv_command(acb4000_shim *s, const uint8_t *cdb, int cdb_len,
                       const uint8_t *payload, uint32_t payload_len,
                       uint8_t *in, uint32_t in_cap, uint32_t *in_len)
{
    uint8_t buf[2048];
    drv_buf b;
    int r;

    if ((uint32_t)cdb_len + payload_len > sizeof buf)
        return -3;
    memcpy(buf, cdb, (size_t)cdb_len);
    if (payload_len > 0)
        memcpy(buf + cdb_len, payload, payload_len);

    memset(&b, 0, sizeof b);
    b.out = buf;
    b.out_len = (uint32_t)cdb_len + payload_len;
    b.in = in;
    b.in_cap = in_cap;

    r = drv_transaction(s, 0x01u, &b);     /* "controller 01" */
    if (in_len != NULL)
        *in_len = b.in_pos;
    return r;
}

/* ------------------------------------- 5. the geometry round trip (the payoff)
 *
 * The MD-10's DPB is *derived* from what the controller reports
 * (docs/acb4000-firmware.md), so MODE SELECT and MODE SENSE have to be exact.
 * The parameters below are PYXIS13 -- the geometry MD10.COM itself offers for a
 * new drive (docs/harddisk-decision.md section 7.2).
 */
static const uint8_t PYXIS13[22] = {
    0x00, 0x00, 0x00, 0x08,        /* the four-byte header; the list is eight long */
    0x00, 0x00, 0x00, 0x00, 0x00,  /* density 0, the whole drive */
    0x00, 0x02, 0x00,              /* block size 512 */
    0x01,                          /* layout: soft-sectored fixed drive */
    0x01, 0x41,                    /* 321 cylinders */
    0x04,                          /* 4 data heads */
    0x00, 0x84,                    /* reduced write current at 132 */
    0x00, 0x00,                    /* write precompensation (ignored on the ACB-4000A) */
    0x00,                          /* landing zone 0 */
    0x02                           /* step code 2 -- 12 us buffered */
};

static void test_mode_select_sense(void)
{
    acb4000_mem_store m;
    acb4000_target t;
    acb4000_shim s;
    uint8_t cdb[10];
    uint8_t in[64];
    uint32_t in_len;
    int r;

    (void)acb4000_mem_store_init(&m, 64, 512, ACB4000_FILL_DEFAULT);
    acb4000_target_init(&t, &m.store, 0);
    acb4000_shim_init(&s, &acb4000_profile_md10, &t);

    /* MODE SELECT -- 15 00 00 00 16 00: the count is the manual's 22 (16h) */
    cdb[0] = 0x15; cdb[1] = 0x00; cdb[2] = 0x00; cdb[3] = 0x00;
    cdb[4] = 0x16; cdb[5] = 0x00;
    r = drv_command(&s, cdb, 6, PYXIS13, sizeof PYXIS13, in, sizeof in, &in_len);
    CHECK(r == 0, "MODE SELECT should complete with good status, got %d", r);
    CHECK(t.luns[0].have_params, "MODE SELECT should have stored the geometry");
    CHECK(t.luns[0].params.cylinders == 321, "321 cylinders should have landed");
    CHECK(t.luns[0].params.heads == 4, "4 heads should have landed");
    CHECK(t.luns[0].params.reduced_write_current == 132, "RWC 132 should have landed");
    CHECK(t.luns[0].params.step_code == 2, "step code 2 should have landed");
    CHECK(t.luns[0].params.block_size == 512, "the block size should be 512");

    /* MODE SENSE -- 1A 00 00 00 24 00: the driver asks for 36 bytes and the
     * lists answer with the exact MODE SELECT format, so 22 come back. */
    cdb[0] = 0x1A; cdb[1] = 0x00; cdb[2] = 0x00; cdb[3] = 0x00;
    cdb[4] = 0x24; cdb[5] = 0x00;
    r = drv_command(&s, cdb, 6, NULL, 0, in, sizeof in, &in_len);
    CHECK(r == 0, "MODE SENSE should complete with good status, got %d", r);
    CHECK(in_len >= 22, "MODE SENSE should hand back at least 22 bytes, got %u",
          (unsigned)in_len);
    CHECK(memcmp(in, PYXIS13, 22) == 0,
          "MODE SENSE should return the geometry MODE SELECT was given");

    /* A geometry the manual's limits forbid is a bad argument, not a clamp. */
    {
        uint8_t bad[22];
        memcpy(bad, PYXIS13, sizeof bad);
        bad[13] = 0x00; bad[14] = 0x08;     /* 8 cylinders -- below the minimum of 16 */
        cdb[0] = 0x15;
        r = drv_command(&s, cdb, 6, bad, sizeof bad, in, sizeof in, &in_len);
        CHECK(r == ACB4000_ST_CHECK, "8 cylinders should be a bad argument");
        CHECK(t.luns[0].params.cylinders == 321,
              "a rejected MODE SELECT must not disturb the stored geometry");
    }

    acb4000_mem_store_free(&m);
}


/* ---------------------------------------------------- 6. READ CAPACITY (25h) */

static void test_read_capacity(void)
{
    acb4000_mem_store m;
    acb4000_target t;
    acb4000_shim s;
    uint8_t cdb[10];
    uint8_t in[32];
    uint32_t in_len;
    int r;

    (void)acb4000_mem_store_init(&m, 23112, 512, ACB4000_FILL_DEFAULT);
    acb4000_target_init(&t, &m.store, 0);
    acb4000_shim_init(&s, &acb4000_profile_md10, &t);

    /* PMI = 00: "the address of the last block on the unit" */
    memset(cdb, 0, sizeof cdb);
    cdb[0] = 0x25;
    r = drv_command(&s, cdb, 10, NULL, 0, in, sizeof in, &in_len);
    CHECK(r == 0, "READ CAPACITY should complete with good status, got %d", r);
    CHECK(in_len >= 8, "READ CAPACITY returns eight bytes, got %u", (unsigned)in_len);
    CHECK(in[0] == 0x00 && in[1] == 0x00 && in[2] == 0x5Au && in[3] == 0x47u,
          "the last block of a 23112-block unit is 0x5A47, got %02X%02X%02X%02X",
          in[0], in[1], in[2], in[3]);
    CHECK(in[4] == 0x00 && in[5] == 0x00 && in[6] == 0x02 && in[7] == 0x00,
          "the block size should read back as 512");

    /* PMI = 01 is legal too; anything else is a bad argument */
    cdb[8] = 0x01;
    r = drv_command(&s, cdb, 10, NULL, 0, in, sizeof in, &in_len);
    CHECK(r == 0, "PMI = 01 should be accepted");
    cdb[8] = 0x02;
    r = drv_command(&s, cdb, 10, NULL, 0, in, sizeof in, &in_len);
    CHECK(r == ACB4000_ST_CHECK, "PMI = 02 should be a bad argument");

    acb4000_mem_store_free(&m);
}

/* ------------------------------------------------------------ 7. FORMAT (04h)
 *
 * PREP.COM asks for a *unique* fill byte and sends D9 in its FORMAT CDB
 * (docs/osborne1ng-machine.md section 6); with no unique fill the controller's
 * own 6C is written.  Both are checked, because the fill is what makes a blank
 * volume one repeated byte (#180).
 */
static void test_format(void)
{
    acb4000_mem_store m;
    acb4000_target t;
    acb4000_shim s;
    uint8_t cdb[10];
    uint8_t in[8];
    uint8_t block[512];
    uint32_t in_len;
    uint32_t i;
    int r;

    (void)acb4000_mem_store_init(&m, 32, 512, 0x00);
    acb4000_target_init(&t, &m.store, 0);
    acb4000_shim_init(&s, &acb4000_profile_md10, &t);

    /* 04 00 00 00 00 00 -- no defect list, so the controller's own 6C fill */
    memset(cdb, 0, sizeof cdb);
    cdb[0] = 0x04;
    r = drv_command(&s, cdb, 6, NULL, 0, in, sizeof in, &in_len);
    CHECK(r == 0, "FORMAT should complete with good status, got %d", r);
    CHECK(m.fill == ACB4000_FILL_DEFAULT,
          "FORMAT with no unique fill should write 6C, got %02X", m.fill);
    CHECK(t.luns[0].fill == ACB4000_FILL_DEFAULT, "the LUN should remember the fill");
    CHECK(m.store.read(m.store.ctx, 31, 1, block) == 0, "the last block should read");
    CHECK(block[0] == 0x6C && block[511] == 0x6C, "the whole unit should be the fill");

    /* 04 02 D9 00 00 00 -- bit 1 says the fill is byte 2 */
    memset(cdb, 0, sizeof cdb);
    cdb[0] = 0x04;
    cdb[1] = 0x02;
    cdb[2] = 0xD9;
    r = drv_command(&s, cdb, 6, NULL, 0, in, sizeof in, &in_len);
    CHECK(r == 0, "FORMAT with a unique fill should complete, got %d", r);
    CHECK(m.fill == 0xD9, "the unique fill should be used, got %02X", m.fill);
    CHECK(m.store.read(m.store.ctx, 0, 1, block) == 0, "block 0 should read");
    for (i = 0; i < sizeof block; i++)
        if (block[i] != 0xD9)
            break;
    CHECK(i == sizeof block, "every byte of block 0 should be D9");

    acb4000_mem_store_free(&m);
}


/* ----------------------------------------------------- 8. READ / WRITE / VERIFY */

static void test_read_write_verify(void)
{
    acb4000_mem_store m;
    acb4000_target t;
    acb4000_shim s;
    uint8_t cdb[10];
    uint8_t in[1200];
    uint8_t out[512];
    uint32_t in_len;
    uint32_t i;
    int r;

    (void)acb4000_mem_store_init(&m, 64, 512, ACB4000_FILL_DEFAULT);
    acb4000_target_init(&t, &m.store, 0);
    acb4000_shim_init(&s, &acb4000_profile_md10, &t);

    for (i = 0; i < sizeof out; i++)
        out[i] = (uint8_t)(0xA0u + (i & 0x1Fu));

    /* WRITE -- 0A 00 00 05 01 00: one block at LBA 5 */
    memset(cdb, 0, sizeof cdb);
    cdb[0] = 0x0A; cdb[3] = 0x05; cdb[4] = 0x01;
    r = drv_command(&s, cdb, 6, out, sizeof out, in, sizeof in, &in_len);
    CHECK(r == 0, "WRITE should complete with good status, got %d", r);
    CHECK(memcmp(m.data + 5 * 512, out, 512) == 0, "the block should have landed at LBA 5");

    /* READ -- 08 00 00 05 01 00: the same block back */
    memset(cdb, 0, sizeof cdb);
    cdb[0] = 0x08; cdb[3] = 0x05; cdb[4] = 0x01;
    r = drv_command(&s, cdb, 6, NULL, 0, in, sizeof in, &in_len);
    CHECK(r == 0, "READ should complete with good status, got %d", r);
    CHECK(in_len >= 512, "READ should hand back the block, got %u bytes", (unsigned)in_len);
    CHECK(memcmp(in, out, 512) == 0, "READ should return what WRITE stored");

    /* a READ past the end is a check condition, not a wrap */
    memset(cdb, 0, sizeof cdb);
    cdb[0] = 0x08; cdb[3] = 0x40; cdb[4] = 0x01;   /* LBA 64 */
    r = drv_command(&s, cdb, 6, NULL, 0, in, sizeof in, &in_len);
    CHECK(r == ACB4000_ST_CHECK, "LBA 64 is past the end of a 64-block unit");

    /* ... and the sense bytes say so, and carry the address */
    memset(cdb, 0, sizeof cdb);
    cdb[0] = 0x03;
    r = drv_command(&s, cdb, 6, NULL, 0, in, sizeof in, &in_len);
    CHECK(r == 0, "REQUEST SENSE should always answer with good status");
    CHECK((in[0] & 0x80u) != 0, "the sense address-valid bit should be set");
    CHECK((in[0] & 0x7Fu) == ACB4000_ERR_ILLEGAL_BLOCK,
          "the error code should be illegal block address, got %02X", in[0]);
    CHECK(in[1] == 0x00 && in[2] == 0x00 && in[3] == 0x40u,
          "the sense should name LBA 64");

    /* VERIFY -- 2F 00 00 00 00 05 00 00 00 00: the pass PREP.COM waits on */
    memset(cdb, 0, sizeof cdb);
    cdb[0] = 0x2F; cdb[8] = 0x05;
    r = drv_command(&s, cdb, 10, NULL, 0, in, sizeof in, &in_len);
    CHECK(r == 0, "VERIFY should complete with good status, got %d", r);
    CHECK(acb4000_target_phase(&t) == ACB4000_PHASE_NONE, "VERIFY transfers no data");

    /* ... and a VERIFY past the end is refused, like a READ */
    memset(cdb, 0, sizeof cdb);
    cdb[0] = 0x2F; cdb[7] = 0x00; cdb[8] = 0x50;
    r = drv_command(&s, cdb, 10, NULL, 0, in, sizeof in, &in_len);
    CHECK(r == ACB4000_ST_CHECK, "a VERIFY past the end should check-condition");

    acb4000_mem_store_free(&m);
}


/* ------------------------------------------------- 9. SEARCH DATA EQUAL (31h)
 *
 * Manual 5.4.6: the argument is twenty bytes of description followed by the
 * pattern.  A satisfied search ends with the Equal status and leaves the block's
 * address in the sense bytes; an unsatisfied one ends with no sense.  This is the
 * "verify disk integrity after format by searching for the 6C fill" the manual
 * describes, and it is the command family the MAME harness had no handler for.
 */
static void test_search(void)
{
    acb4000_mem_store m;
    acb4000_target t;
    acb4000_shim s;
    uint8_t cdb[10];
    uint8_t arg[21];
    uint8_t in[32];
    uint8_t block[512];
    uint32_t in_len;
    int r;

    (void)acb4000_mem_store_init(&m, 16, 512, ACB4000_FILL_DEFAULT);
    acb4000_target_init(&t, &m.store, 0);
    acb4000_shim_init(&s, &acb4000_profile_md10, &t);

    /* a block that is *not* the fill, at LBA 3 */
    memset(block, 0x77, sizeof block);
    CHECK(m.store.write(m.store.ctx, 3, 1, block) == 0, "the odd block should write");

    /* the argument: record size 512, one record, a one-byte 6C pattern */
    memset(arg, 0, sizeof arg);
    arg[0] = 0x00; arg[1] = 0x00; arg[2] = 0x02; arg[3] = 0x00;   /* record size */
    arg[8] = 0x00; arg[9] = 0x00; arg[10] = 0x00; arg[11] = 0x01; /* one record */
    arg[12] = 0x00; arg[13] = 0x07;                               /* argument length */
    arg[18] = 0x00; arg[19] = 0x01;                               /* pattern length 1 */
    arg[20] = ACB4000_FILL_DEFAULT;

    /* 31 00 00 00 00 00 00 00 01 00 -- search one block from LBA 0 */
    memset(cdb, 0, sizeof cdb);
    cdb[0] = 0x31;
    cdb[8] = 0x01;
    r = drv_command(&s, cdb, 10, arg, sizeof arg, in, sizeof in, &in_len);
    CHECK(r == 0, "a satisfied search still reports good to the driver's `and 02h`");
    CHECK(acb4000_target_status(&t) == ACB4000_ST_EQUAL,
          "a match should end with the Equal status, got %02X",
          acb4000_target_status(&t));

    /* ... and the sense names the block that matched */
    memset(cdb, 0, sizeof cdb);
    cdb[0] = 0x03;
    r = drv_command(&s, cdb, 6, NULL, 0, in, sizeof in, &in_len);
    CHECK(r == 0, "REQUEST SENSE should answer after a search");
    CHECK((in[0] & 0x80u) != 0, "the sense address-valid bit should be set");
    CHECK(in[1] == 0x00 && in[2] == 0x00 && in[3] == 0x00,
          "the first matching block is LBA 0");

    /* a pattern that is not on the drive: no sense, no Equal */
    arg[20] = 0x99;
    memset(cdb, 0, sizeof cdb);
    cdb[0] = 0x31;
    cdb[8] = 0x01;
    r = drv_command(&s, cdb, 10, arg, sizeof arg, in, sizeof in, &in_len);
    CHECK(r == 0, "an unsatisfied search reports good");
    CHECK(acb4000_target_status(&t) == ACB4000_ST_GOOD,
          "an unsatisfied search should not set Equal, got %02X",
          acb4000_target_status(&t));

    /* the invert bit (byte 1, bit 4) makes it SEARCH DATA NOT EQUAL */
    memset(cdb, 0, sizeof cdb);
    cdb[0] = 0x31;
    cdb[1] = 0x10;
    cdb[8] = 0x01;
    r = drv_command(&s, cdb, 10, arg, sizeof arg, in, sizeof in, &in_len);
    CHECK(r == 0, "the inverted search should complete");
    CHECK(acb4000_target_status(&t) == ACB4000_ST_EQUAL,
          "search-not-equal for 99h should match the first block");

    acb4000_mem_store_free(&m);
}

/* ------------------------------------------------- 10. the expanded set (I-J)
 *
 * The four commands the Mar84 OEM manual's Table B-1 adds behind jumper I-J --
 * 05 CHECK TRACK FORMAT, 0C INITIALIZE DRIVE, 0D READ ECC BURST LENGTH and the
 * E0/E3/E4 diagnostics.  With the jumper off they must be refused rather than
 * quietly accepted: a driver that uses them has to find out.
 */
static void test_expanded_set(void)
{
    acb4000_mem_store m;
    acb4000_target t;
    acb4000_shim s;
    uint8_t cdb[12];
    uint8_t in[16];
    uint32_t in_len;
    int r;

    (void)acb4000_mem_store_init(&m, 8, 512, ACB4000_FILL_DEFAULT);

    /* jumper I-J off */
    acb4000_target_init(&t, &m.store, 0);
    acb4000_shim_init(&s, &acb4000_profile_md10, &t);
    memset(cdb, 0, sizeof cdb);
    cdb[0] = 0x0D;
    r = drv_command(&s, cdb, 6, NULL, 0, in, sizeof in, &in_len);
    CHECK(r == ACB4000_ST_CHECK, "0D should be refused with the jumper off");
    cdb[0] = 0xE0;
    r = drv_command(&s, cdb, 12, NULL, 0, in, sizeof in, &in_len);
    CHECK(r == ACB4000_ST_CHECK, "E0 should be refused with the jumper off");

    /* jumper I-J on */
    acb4000_target_init(&t, &m.store, 1);
    acb4000_shim_init(&s, &acb4000_profile_md10, &t);
    memset(cdb, 0, sizeof cdb);
    cdb[0] = 0x0D;
    r = drv_command(&s, cdb, 6, NULL, 0, in, sizeof in, &in_len);
    CHECK(r == 0, "0D should be accepted with the jumper on, got %d", r);
    CHECK(in_len >= 2 && in[0] == 0x00 && in[1] == ACB4000_ECC_BURST,
          "READ ECC BURST LENGTH should always answer 8, got %02X%02X",
          in[0], in[1]);
    cdb[0] = 0x05;
    r = drv_command(&s, cdb, 6, NULL, 0, in, sizeof in, &in_len);
    CHECK(r == 0, "05 CHECK TRACK FORMAT should be accepted with the jumper on");
    cdb[0] = 0x0C;
    r = drv_command(&s, cdb, 6, NULL, 0, in, sizeof in, &in_len);
    CHECK(r == 0, "0C INITIALIZE DRIVE should be accepted with the jumper on");
    cdb[0] = 0xE4;
    r = drv_command(&s, cdb, 12, NULL, 0, in, sizeof in, &in_len);
    CHECK(r == 0, "E4 should be accepted with the jumper on");

    /* ... and an opcode nobody implements is still refused */
    cdb[0] = 0x7F;
    r = drv_command(&s, cdb, 12, NULL, 0, in, sizeof in, &in_len);
    CHECK(r == ACB4000_ST_CHECK, "an unknown opcode should be a bad argument");

    acb4000_mem_store_free(&m);
}


/* ---------------------------------------------- 11. TRANSLATE (0Fh), and the LUNs
 *
 * TRANSLATE is how a defect list is built (manual 5.3.8), and the two LUNs are
 * what the MD-10's "units A and B" are (docs/harddisk-decision.md section 6).
 */
static void test_translate_and_luns(void)
{
    acb4000_mem_store m;
    acb4000_target t;
    acb4000_shim s;
    uint8_t cdb[10];
    uint8_t in[32];
    uint32_t in_len;
    int r;

    (void)acb4000_mem_store_init(&m, 23112, 512, ACB4000_FILL_DEFAULT);
    acb4000_target_init(&t, &m.store, 0);
    acb4000_shim_init(&s, &acb4000_profile_md10, &t);

    /* give LUN 0 the PYXIS13 geometry (72 blocks per cylinder) */
    memset(cdb, 0, sizeof cdb);
    cdb[0] = 0x15; cdb[4] = 0x16;
    r = drv_command(&s, cdb, 6, PYXIS13, sizeof PYXIS13, in, sizeof in, &in_len);
    CHECK(r == 0, "MODE SELECT to LUN 0 should complete");

    /* TRANSLATE LBA 100: cylinder 1, head 1, byte 5120 into the track */
    memset(cdb, 0, sizeof cdb);
    cdb[0] = 0x0F; cdb[3] = 100;
    r = drv_command(&s, cdb, 6, NULL, 0, in, sizeof in, &in_len);
    CHECK(r == 0, "TRANSLATE should complete with good status, got %d", r);
    CHECK(in_len >= 8, "TRANSLATE returns eight bytes, got %u", (unsigned)in_len);
    CHECK(in[0] == 0x00 && in[1] == 0x01, "LBA 100 is on cylinder 1, got %02X%02X",
          in[0], in[1]);
    CHECK(in[2] == 0x01, "LBA 100 is on head 1, got %02X", in[2]);
    CHECK(in[3] == 0x00 && in[4] == 0x14 && in[5] == 0x00,
          "LBA 100 is 5120 bytes into the track, got %02X%02X%02X",
          in[3], in[4], in[5]);

    /* LUN 1: a MODE SELECT there must not disturb LUN 0 */
    {
        uint8_t st506[22];
        memcpy(st506, PYXIS13, sizeof st506);
        st506[13] = 0x00; st506[14] = 0x99;   /* 153 cylinders */
        st506[15] = 0x04;                     /* 4 heads */
        st506[16] = 0x00; st506[17] = 0x80;   /* RWC 128 */
        st506[20] = 0x00;                     /* landing zone 0 */
        st506[21] = 0x00;                     /* step code 0 -- the ST-506 case */

        memset(cdb, 0, sizeof cdb);
        cdb[0] = 0x15; cdb[1] = 0x20;         /* LUN 1 */
        cdb[4] = 0x16;
        r = drv_command(&s, cdb, 6, st506, sizeof st506, in, sizeof in, &in_len);
        CHECK(r == 0, "MODE SELECT to LUN 1 should complete, got %d", r);
        CHECK(t.luns[1].params.cylinders == 153, "LUN 1 should have 153 cylinders");
        CHECK(t.luns[1].params.step_code == 0, "LUN 1 should be the step-code-0 case");
        CHECK(t.luns[0].params.cylinders == 321, "LUN 0 must be untouched");
        CHECK(t.luns[0].params.step_code == 2, "LUN 0's step code must be untouched");
    }

    acb4000_mem_store_free(&m);
}

/* ------------------------------------------- 12. the reference profile (Appendix A)
 *
 * The same target, a different port block.  This is the whole argument for layer
 * 2 being data: nothing above changed to serve a second adapter.
 */
static void test_reference_profile(void)
{
    acb4000_mem_store m;
    acb4000_target t;
    acb4000_shim s;
    uint8_t cdb[10];
    uint8_t in[32];
    uint32_t in_len;
    int r;

    (void)acb4000_mem_store_init(&m, 32, 512, ACB4000_FILL_DEFAULT);
    acb4000_target_init(&t, &m.store, 0);
    acb4000_shim_init(&s, &acb4000_profile_reference, &t);

    CHECK(strcmp(acb4000_profile_reference.name, "reference") == 0,
          "the profile should name itself");
    CHECK(acb4000_profile_reference.base == 0x00, "the reference model is BASE 00h");
    CHECK(acb4000_profile_reference.sel_value == 0x40, "SEL is 40h");
    CHECK(acb4000_profile_reference.bit_req == 0x80, "REQ is 80h");
    CHECK(acb4000_profile_reference.bit_end == 0x20, "MSG is 20h");

    memset(cdb, 0, sizeof cdb);
    cdb[0] = 0x00;                                  /* TEST UNIT READY */
    r = drv_command(&s, cdb, 6, NULL, 0, in, sizeof in, &in_len);
    CHECK(r == 0, "TEST UNIT READY should complete on the reference profile, got %d", r);

    memset(cdb, 0, sizeof cdb);
    cdb[0] = 0x25;                                  /* READ CAPACITY */
    r = drv_command(&s, cdb, 10, NULL, 0, in, sizeof in, &in_len);
    CHECK(r == 0, "READ CAPACITY should complete on the reference profile, got %d", r);
    CHECK(in[2] == 0x00 && in[3] == 0x1Fu, "32 blocks means the last block is 31");

    /* a select byte for a controller that is not this one is not answered */
    {
        drv_buf b;
        uint8_t buf[6];
        memset(buf, 0, sizeof buf);
        buf[0] = 0x00;
        memset(&b, 0, sizeof b);
        b.out = buf; b.out_len = 6;
        b.in = in; b.in_cap = sizeof in;
        CHECK(drv_transaction(&s, 0x02u, &b) == 0xFF,
              "controller 02 must not answer a controller-01 card");
    }

    acb4000_mem_store_free(&m);
}

/* ------------------------------------------------------------------- the suite */

int main(int argc, char **argv)
{
    verbose = (argc > 1 && strcmp(argv[1], "-v") == 0);
    (void)verbose;

    printf("acb4000-scsi: the ACB-4000 SCSI-1 personality\n");
    test_cdb_lengths();
    test_params();
    test_store();
    test_probe();
    test_mode_select_sense();
    test_read_capacity();
    test_format();
    test_read_write_verify();
    test_search();
    test_expanded_set();
    test_translate_and_luns();
    test_reference_profile();

    printf("%s (%d failure%s)\n", failures ? "FAILED" : "PASSED", failures,
           failures == 1 ? "" : "s");
    return failures ? 1 : 0;
}

