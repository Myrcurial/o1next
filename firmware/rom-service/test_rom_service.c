/* Host tests for the ROM service -- the class, both doors, and the payload (#284).
 *
 * Build and run (no board, no SDK -- plain C):
 *
 *     cc -std=c99 -Wall -Wextra -I firmware/rom-service -I firmware/library \
 *        -o /tmp/t firmware/rom-service/rom_service.c \
 *        firmware/library/mailbox.c firmware/library/library.c \
 *        firmware/rom-service/test_rom_service.c
 *     /tmp/t /tmp/payload.bin -v
 *
 * or just `firmware/rom-service/run_tests.sh -v`, which assembles the payload
 * first.  argv[1] is that payload: the 3599 bytes tools/research/rom2image.py
 * builds from the repo's own archive, which is the same artifact
 * romservice-check.sh mounts as the emulator's -softrom image.
 *
 * What is being tested, and why each check earns its place
 * -------------------------------------------------------
 * The acceptance is `romservice-check.sh`'s, moved to the host: the checks the
 * emulator's softrom_device passes today are the ones this class has to pass when
 * it replaces it (docs/emulation-testbed.md, Gate D).  So the suite mirrors that
 * harness --
 *
 *   1. the door answers: ECHO as a two-pattern presence probe, INFO, NOP, an
 *      unknown opcode, and the abandon-a-pending-reply rule (protocol section 3);
 *   2. `PRESENT(0)` is the one content id left, and `1`, `2` and `3` each answer
 *      `09h` and leave whatever the caller had alone (section 4.2);
 *   3. the payload's length and bytes are the ones rom2image.py assembled -- not a
 *      fixture that happens to fit;
 *   4. the same engine answers both doors, and a transaction on one does not
 *      disturb the other.
 *
 * and adds the two the C module can state that the stand-in could not: that no
 * payload is `06h` rather than a pretend-present, and that the request register is
 * write-only -- reading it must not consume a reply.
 */
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "rom_service.h"

static int failures;
static int verbose;

#define CHECK(cond, ...)                                               \
    do {                                                               \
        if (!(cond)) {                                                 \
            printf("  FAIL line %d: ", __LINE__);                      \
            printf(__VA_ARGS__);                                       \
            printf("\n");                                              \
            failures++;                                                \
        }                                                              \
    } while (0)

static void note(const char *fmt, ...)
{
    va_list ap;

    if (!verbose)
        return;
    va_start(ap, fmt);
    printf("  ");
    vprintf(fmt, ap);
    printf("\n");
    va_end(ap);
}

/* ------------------------------------------------------------------ the door
 *
 * A door is a register pair, and that is all it is: the engine behind it is
 * door-agnostic (mailbox.h), so the two differ in their addresses and in nothing
 * else.  Modelling them separately anyway is the point -- it is what lets the
 * suite say *which* door a transaction is on, and it is what catches a class that
 * somehow depends on the door it was reached through.
 *
 * The register semantics are the machine's, and the emulator's stand-in
 * (`softrom_device::door_read`, osborne1nx.patch) is where they were read:
 *
 *   - the request register takes writes and reads `0FFh`: it does not drive the
 *     bus, so the machine can AND it with whatever else is selected there;
 *   - the reply register reads `0` for "not ready", else the reply's length, then
 *     the bytes (protocol section 3).
 */
typedef struct {
    uint16_t write_reg;
    uint16_t read_reg;
    mailbox *mb;
} door;

static door door_of(uint16_t write_reg, uint16_t read_reg, mailbox *mb)
{
    door d;

    d.write_reg = write_reg;
    d.read_reg  = read_reg;
    d.mb        = mb;
    return d;
}

static void door_write(door *d, uint8_t b)
{
    mb_write(d->mb, b);
}

static uint8_t door_read(door *d, uint16_t addr)
{
    uint8_t b;

    if (addr != d->read_reg)
        return 0xFFu;                  /* the request register is write-only */

    return mb_read(d->mb, &b) ? b : 0x00u;
}

/* One transaction's reply, as a client sees it. */
typedef struct {
    uint8_t  code;             /* reply[0], the result code */
    uint8_t  payload[32];      /* reply[1..] */
    unsigned len;
    unsigned wire_len;         /* N, the length the reply register handed out */
} xact;

/* Poll, then read the reply: the protocol's steps 2 and 3. */
static int reply_drain(door *d, xact *x)
{
    unsigned i, n;
    uint8_t  b;

    memset(x, 0, sizeof *x);
    x->code = 0xFFu;

    b = door_read(d, d->read_reg);
    if (b == 0u)
        return -1;                     /* the register read 0: not ready, no reply */
    n = b;
    x->wire_len = n;

    for (i = 0; i < n; i++) {
        if (!mb_read(d->mb, &b))
            return -1;                 /* a reply shorter than its own length */
        if (i == 0)
            x->code = b;
        else if (x->len < sizeof x->payload)
            x->payload[x->len++] = b;
    }
    return 0;
}

/* The whole transaction: the request's bytes, then the reply. */
static int xact_run(door *d, const uint8_t *req, unsigned nreq, xact *x)
{
    unsigned i;

    for (i = 0; i < nreq; i++)
        door_write(d, req[i]);

    return reply_drain(d, x);
}

/* ------------------------------------------------------------------ the fixture
 *
 * The module under test twice over: one instance with the real payload and one with
 * nothing to present, so "no payload" is a case rather than an argument.  The
 * library is empty on purpose -- this suite is about the ROM service's class, and
 * `lib_count()` is all it needs to prove the engine's own opcodes still work.
 */
static rom_service rs;
static rom_service rs_empty;
static lib         library;
static mailbox     mbox;
static door        d_user;
static door        d_rom;

/* A transaction leaves the engine at "an opcode is next", but a *test* that
 * abandons one on purpose does not, so each group starts from a known state. */
static void reset(void)
{
    mb_init(&mbox, &library, rs_extension(&rs));
}

/* ------------------------------------------------------------ the doors, pinned
 *
 * Section 2's table, and the correction the machine made to it: the protocol's
 * first draft chose `2300h`/`2301h`, and `0x2301` turned out to be the floppy's
 * track register as well as the keyboard's row 0, so the ROM's door is
 * `2800h`/`2801h`.  These are the engine's constants (mailbox.h) that this module
 * names rather than redefines, so pinning them here is what catches a drift.
 */
static void test_the_doors_are_the_protocols_numbers(void)
{
    CHECK(RS_DOOR_USER_WRITE == 0x00E7u,
          "the userland request register is 0E7h, got %04X", RS_DOOR_USER_WRITE);
    CHECK(RS_DOOR_USER_READ == 0x00EBu,
          "the userland reply register is 0EBh, got %04X", RS_DOOR_USER_READ);
    CHECK(RS_DOOR_ROM_WRITE == 0x2800u,
          "the ROM's request register is 2800h, got %04X", RS_DOOR_ROM_WRITE);
    CHECK(RS_DOOR_ROM_READ == 0x2801u,
          "the ROM's reply register is 2801h, got %04X", RS_DOOR_ROM_READ);
    CHECK(RS_DOOR_ROM_WRITE != 0x2300u && RS_DOOR_ROM_READ != 0x2301u,
          "and not the pair the protocol's first draft proposed");
}

/* ------------------------------------------------------- the protocol's replies */

static void test_echo_probe(door *d, const char *which)
{
    xact    x;
    uint8_t req[2];

    req[0] = MB_OP_ECHO;
    req[1] = 0x5Au;
    CHECK(xact_run(d, req, 2, &x) == 0, "%s: an ECHO should answer", which);
    CHECK(x.code == LIB_OK, "%s: with OK, got %02X", which, x.code);
    CHECK(x.len == 1u && x.payload[0] == 0x5Au, "%s: and the byte echoed back", which);

    /* the probe is the echo *twice with two patterns*: an absent interposer leaves
     * the register answering the floating bus, and one pattern cannot catch that */
    req[1] = 0xA5u;
    CHECK(xact_run(d, req, 2, &x) == 0, "%s: a second ECHO should answer", which);
    CHECK(x.code == LIB_OK && x.len == 1u && x.payload[0] == 0xA5u,
          "%s: with the other pattern back -- which is what makes it a presence probe",
          which);
    note("%s: ECHO 5Ah and A5h both came back", which);
}

static void test_info(door *d, const char *which)
{
    xact    x;
    uint8_t req = RS_OP_INFO;

    CHECK(xact_run(d, &req, 1, &x) == 0, "%s: INFO should answer", which);
    CHECK(x.code == LIB_OK && x.len == 2u && x.wire_len == 3u,
          "%s: with OK and two payload bytes, got code %02X, %u bytes",
          which, x.code, x.len);
    CHECK(x.payload[0] == RS_INFO_VERSION, "%s: the format version, got %02X",
          which, x.payload[0]);
    CHECK(x.payload[1] == RS_INFO_FLAGS && x.payload[1] == 0x00u,
          "%s: and a clear flags byte -- there is no asset slot left to report (#278)",
          which);
    note("%s: INFO -> version %02X, flags %02X", which, x.payload[0], x.payload[1]);
}

static void test_nop_unknown_and_recovery(door *d, const char *which)
{
    xact    x;
    uint8_t req;

    req = MB_OP_NOP;
    CHECK(xact_run(d, &req, 1, &x) == 0, "%s: NOP should answer", which);
    CHECK(x.code == LIB_OK && x.len == 0u, "%s: with OK and nothing else", which);

    /* 50h is not the mailbox's, not the clock's (20h-2Fh) and not this class's: an
     * opcode no class owns answers 01h and resets the operand count. */
    req = 0x50u;
    CHECK(xact_run(d, &req, 1, &x) == 0, "%s: an unknown opcode still answers", which);
    CHECK(x.code == LIB_ERR_OPCODE && x.len == 0u,
          "%s: with 01h and no payload, got %02X", which, x.code);

    req = MB_OP_NOP;
    CHECK(xact_run(d, &req, 1, &x) == 0 && x.code == LIB_OK,
          "%s: and NOP is a way back to a known state", which);
}

static void test_abandon_rule(door *d, const char *which)
{
    xact    x;
    uint8_t req = RS_OP_INFO;

    /* A write while a reply is pending abandons it and starts a new transaction --
     * so a wedged client cannot wedge the firmware (section 3, rule 4).  ECHO's
     * reply is left unread on purpose. */
    door_write(d, MB_OP_ECHO);
    door_write(d, 0x5Au);

    CHECK(xact_run(d, &req, 1, &x) == 0,
          "%s: a write with a reply pending should answer", which);
    CHECK(x.code == LIB_OK && x.len == 2u,
          "%s: with the *new* transaction's reply -- the abandoned one is gone", which);
}

static void test_request_register_is_write_only(door *d, const char *which)
{
    xact x;

    /* Reading the request register must not consume anything: the machine ANDs it
     * with whatever else is selected at that address, so it answers 0FFh and does
     * not drive (softrom_device::door_read, osborne1nx.patch). */
    door_write(d, RS_OP_INFO);
    CHECK(door_read(d, d->write_reg) == 0xFFu,
          "%s: the request register reads FFh -- it is write-only", which);
    CHECK(reply_drain(d, &x) == 0 && x.code == LIB_OK && x.len == 2u,
          "%s: and reading it did not consume the reply", which);
}


/* --------------------------------------------------------- PRESENT, and the payload
 *
 * The two halves of the acceptance: what the *door* answers, and what the module
 * hands whoever fills page 1.
 */

static void test_present_returns_the_payload(const rom_payload *payload)
{
    const uint8_t *bytes = NULL;
    uint32_t       len   = 0u;
    xact           x;
    uint8_t        req[2];

    /* The window's business, not the door's: PRESENT says *which* content, and the
     * bytes go to whoever fills the page.  Section 4's table calls the payload
     * "3599 bytes". */
    CHECK(rs_present(&rs, RS_CONTENT_PAYLOAD, &bytes, &len) == LIB_OK,
          "PRESENT(0) should return the payload");
    CHECK(len == 3599u, "and it is the 3599 bytes section 4 names, got %u", len);
    CHECK(bytes != NULL && bytes == payload->bytes && payload->len == len &&
          memcmp(bytes, payload->bytes, len) == 0,
          "byte for byte the payload rom2image.py assembled from the archive");
    note("PRESENT(0): %u bytes, first four %02X %02X %02X %02X",
         len,
         bytes ? bytes[0] : 0, bytes ? bytes[1] : 0,
         bytes ? bytes[2] : 0, bytes ? bytes[3] : 0);

    /* And on the door the reply is the result code alone: a 3599-byte payload
     * cannot cross a command door (section 1's "no bulk channel, ever"), so the
     * door says *which* content and the window carries it. */
    req[0] = RS_OP_PRESENT;
    req[1] = RS_CONTENT_PAYLOAD;
    CHECK(xact_run(&d_rom, req, 2, &x) == 0, "PRESENT(0) on the door should answer");
    CHECK(x.code == LIB_OK && x.wire_len == 1u && x.len == 0u,
          "with OK and nothing else -- the window carries the bytes, not the door");
}

static void test_present_retired_ids(void)
{
    static const uint8_t ids[3] = { 1u, 2u, 3u };
    static uint8_t       page1[16];
    unsigned             i;

    for (i = 0; i < 3u; i++) {
        /* The caller's own page 1: an id that is not there must not touch it
         * (section 4.2, "leaves page 1 alone"). */
        const uint8_t *bytes = page1;
        uint32_t       len   = sizeof page1;
        xact           x;
        uint8_t        req[2];

        CHECK(rs_present(&rs, ids[i], &bytes, &len) == LIB_ERR_CONTENT,
              "PRESENT(%u) should answer 09h -- that id retired with the frame path (#278)",
              ids[i]);
        CHECK(bytes == page1 && len == sizeof page1,
              "PRESENT(%u): and nothing is written on an error, so page 1 is left alone",
              ids[i]);

        req[0] = RS_OP_PRESENT;
        req[1] = ids[i];
        CHECK(xact_run(&d_rom, req, 2, &x) == 0 && x.code == LIB_ERR_CONTENT &&
              x.wire_len == 1u && x.len == 0u,
              "PRESENT(%u) on the door is 09h and the result code alone", ids[i]);
    }
}

static void test_no_payload_is_a_media_error(void)
{
    const uint8_t *bytes = NULL;
    uint32_t       len   = 0u;
    mailbox        mb;
    door           d;
    uint8_t        req[2];
    xact           x;

    /* A module handed no payload has nothing to present, and 06h is section 4.2's
     * "a flash read that failed" -- the honest answer, and the one that leaves the
     * ROM's own fallback text on the screen rather than a screenful of nothing. */
    CHECK(rs_present(&rs_empty, RS_CONTENT_PAYLOAD, &bytes, &len) == LIB_ERR_MEDIA,
          "PRESENT(0) with no payload is 06h, not a pretend-present");
    CHECK(bytes == NULL && len == 0u, "and nothing is written");

    mb_init(&mb, &library, rs_extension(&rs_empty));
    d = door_of(RS_DOOR_ROM_WRITE, RS_DOOR_ROM_READ, &mb);

    req[0] = RS_OP_PRESENT;
    req[1] = RS_CONTENT_PAYLOAD;
    CHECK(xact_run(&d, req, 2, &x) == 0 && x.code == LIB_ERR_MEDIA,
          "and the door answers 06h, got %02X", x.code);

    /* but an id that retired is still 09h, payload or not: the *id* is what is
     * wrong, and 06h would blame the flash for it */
    CHECK(rs_present(&rs_empty, 3u, &bytes, &len) == LIB_ERR_CONTENT,
          "a retired id is still 09h with no payload -- the id is what is wrong");
}

/* ------------------------------------------------------------- the two doors
 *
 * mailbox.h's reading is "one engine, two doors"; the emulator's arrangement is two
 * independent devices, one per door.  The class is door-agnostic (it is reached
 * through `mb_extension`, which does not know a door exists), so both arrangements
 * are correct -- and both are worth proving, because the second is the one that
 * makes the ROM's boot path independent of a userland client.
 */

static void test_the_same_engine_answers_both_doors(void)
{
    uint8_t req[3];
    xact    x;

    reset();

    test_echo_probe(&d_user, "userland");
    test_echo_probe(&d_rom,  "romland");
    test_info(&d_user, "userland");
    test_info(&d_rom,  "romland");

    /* 10h is the library's COUNT, not this class's: attaching an extension must not
     * steal the engine's own opcodes. */
    req[0] = MB_OP_COUNT;
    CHECK(xact_run(&d_user, req, 1, &x) == 0,
          "COUNT still answers with the ROM service attached");
    CHECK(x.code == LIB_OK && x.len == 2u, "with the library's own reply, got %02X", x.code);
    CHECK(((unsigned)x.payload[0] | ((unsigned)x.payload[1] << 8)) == lib_count(&library),
          "which is this (empty) library's count");
}

static void test_one_door_does_not_disturb_the_other(void)
{
    mailbox mb_user, mb_rom;
    door    u, r;
    uint8_t req[2];
    xact    x;

    /* One rom_service, two engines: the emulator's arrangement, where the doors are
     * answered by different devices and neither knows the other exists. */
    mb_init(&mb_user, &library, rs_extension(&rs));
    mb_init(&mb_rom,  &library, rs_extension(&rs));
    u = door_of(RS_DOOR_USER_WRITE, RS_DOOR_USER_READ, &mb_user);
    r = door_of(RS_DOOR_ROM_WRITE,  RS_DOOR_ROM_READ,  &mb_rom);

    /* A userland request left half-written: the opcode is in, the operand is not. */
    door_write(&u, RS_OP_PRESENT);

    /* ... and the ROM's sign-on transaction runs to completion regardless.  This is
     * the property worth having: the ROM's client is on the boot path. */
    req[0] = RS_OP_INFO;
    CHECK(xact_run(&r, req, 1, &x) == 0,
          "a half-written request on one door does not stop a transaction on the other");
    CHECK(x.code == LIB_OK && x.len == 2u && x.payload[0] == RS_INFO_VERSION,
          "the ROM door answers its own reply, got %02X", x.code);

    /* and the half-written one finishes correctly afterwards, on its own engine */
    door_write(&u, RS_CONTENT_PAYLOAD);
    CHECK(reply_drain(&u, &x) == 0 && x.code == LIB_OK && x.wire_len == 1u,
          "and the userland door's own request completes afterwards");

    /* A *pending, unread* reply on one door is still there after a write on the
     * other: the abandon rule is the client's, not the firmware's. */
    door_write(&r, MB_OP_ECHO);
    door_write(&r, 0x5Au);
    req[0] = RS_OP_INFO;
    CHECK(xact_run(&u, req, 1, &x) == 0 && x.code == LIB_OK,
          "a write on the userland door leaves the ROM door's transaction alone");
    CHECK(door_read(&r, r.read_reg) == 2u,
          "so the ROM door's pending reply is still there");
    CHECK(door_read(&r, r.read_reg) == LIB_OK && door_read(&r, r.read_reg) == 0x5Au,
          "with its own bytes intact");
    CHECK(door_read(&r, r.read_reg) == 0u, "and the register reads 0 again once drained");
}


/* ---------------------------------------------------------------------- main */

static uint8_t *read_payload(const char *path, uint32_t *len)
{
    FILE    *f = fopen(path, "rb");
    uint8_t *buf;
    long     n;

    if (f == NULL) {
        printf("test_rom_service: cannot open the payload at %s\n", path);
        return NULL;
    }
    if (fseek(f, 0, SEEK_END) != 0 || (n = ftell(f)) < 0 || fseek(f, 0, SEEK_SET) != 0) {
        printf("test_rom_service: cannot size %s\n", path);
        fclose(f);
        return NULL;
    }
    buf = malloc((size_t)n ? (size_t)n : 1u);
    if (buf == NULL || fread(buf, 1, (size_t)n, f) != (size_t)n) {
        printf("test_rom_service: cannot read %s\n", path);
        free(buf);
        fclose(f);
        return NULL;
    }
    fclose(f);

    *len = (uint32_t)n;
    return buf;
}

int main(int argc, char **argv)
{
    const char *path = NULL;
    uint8_t    *bytes;
    uint32_t    len = 0u;
    rom_payload payload;
    int         i;

    for (i = 1; i < argc; i++) {
        if (strcmp(argv[i], "-v") == 0)
            verbose = 1;
        else
            path = argv[i];
    }
    if (path == NULL) {
        printf("usage: test_rom_service PAYLOAD [-v]\n"
               "  PAYLOAD is what `tools/research/rom2image.py --payload-only` writes\n");
        return 2;
    }

    bytes = read_payload(path, &len);
    if (bytes == NULL)
        return 2;

    printf("ROM service -- the class, both doors, and the payload\n");
    printf("  payload: %s, %u bytes\n", path, len);

    payload.bytes = bytes;
    payload.len   = len;

    lib_init(&library, NULL, 0u);

    rs_init(&rs, &payload);
    rs_init(&rs_empty, NULL);

    d_user = door_of(RS_DOOR_USER_WRITE, RS_DOOR_USER_READ, &mbox);
    d_rom  = door_of(RS_DOOR_ROM_WRITE,  RS_DOOR_ROM_READ,  &mbox);

    test_the_doors_are_the_protocols_numbers();

    reset();
    test_echo_probe(&d_user, "userland");
    test_echo_probe(&d_rom,  "romland");
    test_info(&d_user, "userland");
    test_info(&d_rom,  "romland");
    test_nop_unknown_and_recovery(&d_user, "userland");
    test_nop_unknown_and_recovery(&d_rom,  "romland");
    test_abandon_rule(&d_user, "userland");
    test_abandon_rule(&d_rom,  "romland");
    test_request_register_is_write_only(&d_user, "userland");
    test_request_register_is_write_only(&d_rom,  "romland");

    reset();
    test_present_returns_the_payload(&payload);
    test_present_retired_ids();
    test_no_payload_is_a_media_error();
    test_the_same_engine_answers_both_doors();
    test_one_door_does_not_disturb_the_other();

    free(bytes);

    if (failures == 0) {
        printf("all checks passed\n");
        return 0;
    }
    printf("%d check(s) FAILED\n", failures);
    return 1;
}


