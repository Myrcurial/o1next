/* Host tests for the modem's portable core -- the rate table, the frame, and the
 * double-sided buffer (#318, #319, part of #56).
 *
 * Build and run (no board, no SDK, no ESP32 core -- plain C99):
 *
 *     cc -std=c99 -Wall -Wextra -Werror -I firmware/zimodem-fork/o1modem \
 *        -o /tmp/t firmware/zimodem-fork/o1modem/rate.c \
 *        firmware/zimodem-fork/o1modem/frame.c \
 *        firmware/zimodem-fork/o1modem/buffer.c \
 *        firmware/zimodem-fork/o1modem/test_o1modem.c
 *     /tmp/t -v
 *
 * or just `firmware/zimodem-fork/o1modem/run_tests.sh -v`.
 *
 * What is being tested, and why each check earns its place
 * --------------------------------------------------------
 * Both issues are about *arithmetic that has to be right*, so the tests are
 * anchored to values the archive documents rather than to values this code chose:
 *
 *   1. **The frame is the article's own table.**  *The Portable Companion* #7
 *      (June 1983) prints a "Table of 6850 control codes", and four of its
 *      entries are quoted in docs/o1-modem-serial.md -- 55h, 56h, 49h, 51h.  If
 *      the decode is right, all four come out as the article says; if it is a
 *      plausible invention, they do not.
 *   2. **650 is not 600.**  The factory 600/2400 jumper is ~8.3% fast, and the
 *      whole point of the table is that it carries the *real* rates.  So the
 *      suite measures a J1-out machine and asserts it locks on 650/2600 and not
 *      on 600/2400 -- and that a measurement between them refuses rather than
 *      picking one.
 *   3. **300 baud is 30 characters a second.**  That is a fact about a real modem,
 *      not about this implementation, so the pacer is checked against it: one
 *      second of imaginary time releases exactly 30 characters at 300 baud and
 *      65 at 650, and chunking the elapsed time differently does not change the
 *      total -- which is the property that says the carry does not drift.
 *   4. **The overflow policy keeps the right half.**  REFUSE and DROP_OLDEST are
 *      different products, so the tests assert the *content* that survives, not
 *      just the count.
 *   5. **The bypass is the same knob as the rate.**  A transfer must not be
 *      re-clocked, so rate 0 releases everything at once however long the gap.
 */
#include <inttypes.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "buffer.h"
#include "frame.h"
#include "rate.h"

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
    printf("    ");
    vprintf(fmt, ap);
    printf("\n");
    va_end(ap);
}

/* ------------------------------------------------------------ the 6850 frame */

static void test_frame(void)
{
    /* The article's four values, as quoted in docs/o1-modem-serial.md.  This is
     * the cross-check: 55h = 8-N-1 @1200, 56h = 8-N-1 @300, 49h = 7-E-1 @1200,
     * 51h = 8-N-2 @1200. */
    static const struct {
        uint8_t     byte;
        unsigned    data;
        o1_parity   par;
        unsigned    stop;
        o1_div      div;
        const char *why;
    } doc[] = {
        { 0x55u, 8u, O1_PAR_NONE, 1u, O1_DIV_16, "8-N-1 @1200" },
        { 0x56u, 8u, O1_PAR_NONE, 1u, O1_DIV_64, "8-N-1 @300"  },
        { 0x49u, 7u, O1_PAR_EVEN, 1u, O1_DIV_16, "7-E-1 @1200" },
        { 0x51u, 8u, O1_PAR_NONE, 2u, O1_DIV_16, "8-N-2 @1200" },
    };
    unsigned i;
    int      b;

    printf("the 6850 control byte (the article's table)\n");

    for (i = 0; i < sizeof doc / sizeof doc[0]; i++) {
        o1_frame f = o1_frame_of(doc[i].byte);
        char     s[8];

        CHECK(f.data_bits == doc[i].data, "%02X %s: %u data bits, wanted %u",
              doc[i].byte, doc[i].why, f.data_bits, doc[i].data);
        CHECK(f.parity == doc[i].par, "%02X %s: parity %d, wanted %d",
              doc[i].byte, doc[i].why, (int)f.parity, (int)doc[i].par);
        CHECK(f.stop_bits == doc[i].stop, "%02X %s: %u stop bits, wanted %u",
              doc[i].byte, doc[i].why, f.stop_bits, doc[i].stop);
        CHECK(f.div == doc[i].div, "%02X %s: divide %d, wanted %d",
              doc[i].byte, doc[i].why, (int)f.div, (int)doc[i].div);

        o1_frame_str(&f, s, sizeof s);
        note("%02X -> %s", doc[i].byte, s);
    }

    /* The bit count the pacer depends on.  8-N-1 is ten bits, and 7-E-1 is also
     * ten -- which is the trap: same character time, different frame. */
    {
        o1_frame f8n1 = o1_frame_of(0x55u);
        o1_frame f7e1 = o1_frame_of(0x49u);
        o1_frame f8n2 = o1_frame_of(0x51u);
        o1_frame f7o2 = o1_frame_of(0x03u);   /* 7 bits, odd parity, 2 stop */

        CHECK(o1_frame_bits(&f8n1) == 10u, "8-N-1 is %u bits, wanted 10",
              o1_frame_bits(&f8n1));
        CHECK(o1_frame_bits(&f7e1) == 10u, "7-E-1 is %u bits, wanted 10",
              o1_frame_bits(&f7e1));
        CHECK(o1_frame_bits(&f8n2) == 11u, "8-N-2 is %u bits, wanted 11",
              o1_frame_bits(&f8n2));
        CHECK(o1_frame_bits(&f7o2) == 11u, "7-O-2 is %u bits, wanted 11",
              o1_frame_bits(&f7o2));
    }

    /* Every byte round-trips, not just the documented four: a module that
     * rewrites a BIOS byte has to preserve the bits it does not care about. */
    for (b = 0; b < 256; b++) {
        o1_frame f = o1_frame_of((uint8_t)b);
        uint8_t  again = o1_frame_byte(&f);

        CHECK(again == (uint8_t)b, "round trip: %02X -> %02X", b, (unsigned)again);
    }
    note("all 256 control bytes round-trip");

    /* The string is a fixed 3 characters plus a terminator, and a short buffer
     * must truncate rather than run off the end. */
    {
        o1_frame f = o1_frame_of(0x55u);
        char     s[8];

        memset(s, 'x', sizeof s);
        o1_frame_str(&f, s, 4u);
        CHECK(strcmp(s, "8N1") == 0, "8-N-1 renders as \"%s\", wanted \"8N1\"", s);

        memset(s, 'x', sizeof s);
        o1_frame_str(&f, s, 3u);
        CHECK(s[2] == '\0' && s[0] == '8', "out_n=3 gave \"%s\"", s);

        memset(s, 'x', sizeof s);
        o1_frame_str(&f, s, 1u);
        CHECK(s[0] == '\0', "out_n=1 gave \"%s\", wanted \"\"", s);

        memset(s, 'x', sizeof s);
        o1_frame_str(0, s, sizeof s);
        CHECK(s[0] == '\0', "a null frame gave \"%s\", wanted \"\"", s);
    }
}

/* ------------------------------------------------------------- the rate table */

static void test_rate(void)
{
    unsigned i;

    printf("the rate table\n");

    CHECK(o1_rate_count == 20u, "the table has %u rows, wanted 20", o1_rate_count);

    for (i = 1; i < o1_rate_count; i++) {
        CHECK(o1_rate_table[i].mbaud > o1_rate_table[i - 1].mbaud,
              "row %u (%u) is not above row %u (%u)", i,
              o1_rate_table[i].mbaud, i - 1, o1_rate_table[i - 1].mbaud);
        CHECK(o1_rate_table[i].note != 0, "row %u has no note", i);
    }

    /* Every rate in the table snaps to itself. */
    for (i = 0; i < o1_rate_count; i++) {
        int got = o1_rate_snap(o1_rate_table[i].mbaud, O1_RATE_TOL_PPM_DEFAULT);

        CHECK(got == (int)i, "%u snapped to %d, wanted %u",
              o1_rate_table[i].mbaud, got, i);
    }
    note("%u rates, each snapping to itself", o1_rate_count);

    /* **650 is not 600.**  A J1-out machine measures 650/2600 and must not be
     * read as the 600/2400 on the panel -- 8.3% is 0.83 of a bit over a 10-bit
     * frame, which is the difference between working and not. */
    CHECK(o1_rate_table[o1_rate_snap(650000u, O1_RATE_TOL_PPM_DEFAULT)].mbaud == 650000u,
          "650000 did not snap to 650000");
    CHECK(o1_rate_table[o1_rate_snap(2600000u, O1_RATE_TOL_PPM_DEFAULT)].mbaud == 2600000u,
          "2600000 did not snap to 2600000");
    CHECK(o1_rate_table[o1_rate_snap(600000u, O1_RATE_TOL_PPM_DEFAULT)].mbaud == 600000u,
          "600000 did not snap to 600000 -- the OSBAUD rate is real too");

    /* Between them is a refusal, not a coin toss.  625000 is 4.0% from each, so
     * a 2% tolerance must take neither. */
    CHECK(o1_rate_snap(625000u, O1_RATE_TOL_PPM_DEFAULT) < 0,
          "625000 snapped to something -- the tolerance is too loose to tell 600 from 650");

    /* Turbo 650 is 1300, and 1300 is not 1200. */
    CHECK(o1_rate_table[o1_rate_snap(1300000u, O1_RATE_TOL_PPM_DEFAULT)].mbaud == 1300000u,
          "1300000 did not snap to 1300000");
    CHECK(o1_rate_table[o1_rate_snap(5200000u, O1_RATE_TOL_PPM_DEFAULT)].mbaud == 5200000u,
          "5200000 did not snap to 5200000");

    /* Nothing near the table refuses. */
    CHECK(o1_rate_snap(250000u, O1_RATE_TOL_PPM_DEFAULT) < 0,
          "250000 snapped to something");
    CHECK(o1_rate_snap(38400000u, O1_RATE_TOL_PPM_DEFAULT) < 0,
          "turbo 19200 (38400) snapped to something -- it is not in the table");
    CHECK(o1_rate_snap(0u, O1_RATE_TOL_PPM_DEFAULT) < 0, "zero snapped to something");

    /* The tolerance is a parameter, so a caller with a worse measurement can
     * loosen it and one with a better measurement can tighten it. */
    CHECK(o1_rate_snap(1206000u, O1_RATE_TOL_PPM_DEFAULT) >= 0,
          "0.5%% off refused at 2%%");
    CHECK(o1_rate_snap(1206000u, 1000u) < 0, "0.5%% off accepted at 0.1%%");

    /* Signed error, so a log can say which side the measurement was on. */
    CHECK(o1_rate_error_ppm(650000u, 600000u) == -76923,
          "error of 600000 against 650000 is %" PRId32 ", wanted -76923",
          o1_rate_error_ppm(650000u, 600000u));
    CHECK(o1_rate_error_ppm(600000u, 650000u) == 83333,
          "error of 650000 against 600000 is %" PRId32 ", wanted 83333",
          o1_rate_error_ppm(600000u, 650000u));
    CHECK(o1_rate_error_ppm(0u, 1200000u) == 0, "zero measured is not zero error");

    /* The ladder: nearest first, and the *order* is the point -- the caller's
     * verify step walks it when the measurement is poor. */
    {
        int      rank[32];
        unsigned n = o1_rate_rank(648000u, rank, 32u);

        CHECK(n == o1_rate_count, "rank returned %u of %u", n, o1_rate_count);
        CHECK(o1_rate_table[rank[0]].mbaud == 650000u, "nearest to 648000 is %u",
              o1_rate_table[rank[0]].mbaud);
        CHECK(o1_rate_table[rank[1]].mbaud == 600000u, "second nearest to 648000 is %u",
              o1_rate_table[rank[1]].mbaud);
        CHECK(o1_rate_table[rank[2]].mbaud == 1200000u ||
              o1_rate_table[rank[2]].mbaud == 300000u,
              "third nearest to 648000 is %u, wanted 300000 or 1200000",
              o1_rate_table[rank[2]].mbaud);
        CHECK(o1_rate_rank(0u, rank, 4u) == 4u, "rank honoured out_n");
    }

    /* Stability is a proxy for verification: n < 2 is not agreement. */
    {
        o1_rate same[3]  = { 1200000u, 1201000u, 1199000u };
        o1_rate split[2] = { 1200000u, 1300000u };

        CHECK(o1_rate_stable(same, 3u, O1_RATE_TOL_PPM_DEFAULT), "three close samples are not stable");
        CHECK(!o1_rate_stable(split, 2u, O1_RATE_TOL_PPM_DEFAULT), "1200 and 1300 are stable");
        CHECK(!o1_rate_stable(same, 1u, O1_RATE_TOL_PPM_DEFAULT), "one sample is stable");
    }
}

/* ------------------------------------------------------------------ the lock */

static void test_lock(void)
{
    o1_rate_lock l;

    printf("the lock\n");

    o1_rate_lock_init(&l, 3u, O1_RATE_TOL_PPM_DEFAULT);
    CHECK(o1_rate_lock_feed(&l, 1200000u) == 0, "locked on the first sample");
    CHECK(l.state == O1_LOCK_IDLE, "state is %d after one sample", (int)l.state);
    CHECK(o1_rate_lock_feed(&l, 1201000u) == 0, "locked on the second sample");
    CHECK(o1_rate_lock_feed(&l, 1199000u) == 1, "did not lock on the third sample");
    CHECK(o1_rate_lock_value(&l) == 1200000u, "locked %u, wanted 1200000",
          o1_rate_lock_value(&l));
    CHECK(o1_rate_lock_note(&l) != 0, "a locked rate has no note");

    /* A repeat on the same rate leaves the lock alone. */
    CHECK(o1_rate_lock_feed(&l, 1200000u) == 0, "re-locked on a repeat");
    CHECK(o1_rate_lock_value(&l) == 1200000u, "the lock moved on a repeat");

    /* Re-jumpered, or dropped into turbo: the lock goes and the count restarts. */
    CHECK(o1_rate_lock_feed(&l, 1300000u) == 0, "locked immediately on a new rate");
    CHECK(l.state == O1_LOCK_IDLE, "state is %d after the rate moved", (int)l.state);
    CHECK(o1_rate_lock_value(&l) == 0u, "a value survived the rate change");
    o1_rate_lock_feed(&l, 1300000u);
    CHECK(o1_rate_lock_feed(&l, 1300000u) == 1, "did not re-lock on the new rate");
    CHECK(o1_rate_lock_value(&l) == 1300000u, "re-locked on %u",
          o1_rate_lock_value(&l));

    /* A measurement nowhere near the table neither locks nor leaves a count
     * behind: two bad samples either side of a good one must not add up. */
    o1_rate_lock_init(&l, 2u, O1_RATE_TOL_PPM_DEFAULT);
    CHECK(o1_rate_lock_feed(&l, 1200000u) == 0, "locked early");
    CHECK(o1_rate_lock_feed(&l, 250000u) == 0, "locked on a rate not in the table");
    CHECK(l.state == O1_LOCK_REFUSED, "state is %d after a bad sample", (int)l.state);
    CHECK(l.samples == 0u, "a bad sample left %u samples behind", l.samples);
    CHECK(o1_rate_lock_feed(&l, 1200000u) == 0, "locked on a count that should be reset");
    CHECK(o1_rate_lock_feed(&l, 1200000u) == 1, "did not lock after two good samples");

    /* Two candidates in alternation never lock -- which is what a machine we do
     * not understand looks like, and refusing is the right answer. */
    o1_rate_lock_init(&l, 2u, O1_RATE_TOL_PPM_DEFAULT);
    CHECK(o1_rate_lock_feed(&l, 1200000u) == 0, "locked early");
    CHECK(o1_rate_lock_feed(&l, 1300000u) == 0, "locked on an alternating pair");
    CHECK(o1_rate_lock_feed(&l, 1200000u) == 0, "locked on an alternating pair");
    CHECK(o1_rate_lock_feed(&l, 1300000u) == 0, "locked on an alternating pair");
    CHECK(l.state != O1_LOCK_LOCKED, "alternating samples locked");

    /* `need` is honoured, and need < 1 clamps to 1 rather than locking on nothing. */
    o1_rate_lock_init(&l, 0u, O1_RATE_TOL_PPM_DEFAULT);
    CHECK(l.need == 1u, "need 0 became %u", l.need);
    CHECK(o1_rate_lock_feed(&l, 1200000u) == 1, "need 1 did not lock on one sample");

    o1_rate_lock_reset(&l);
    CHECK(l.state == O1_LOCK_IDLE && l.cand < 0 && l.samples == 0u,
          "reset left state %d cand %d samples %u", (int)l.state, l.cand, l.samples);
    CHECK(o1_rate_lock_value(&l) == 0u, "reset left a value");
    CHECK(o1_rate_lock_note(&l) == 0, "reset left a note");
}

/* -------------------------------------------------------------- the ring */

static void test_ring(void)
{
    uint8_t in[16];
    uint8_t store[8];
    uint8_t out[16];
    o1_ring r;
    unsigned i, n;

    printf("the ring\n");

    for (i = 0; i < sizeof in; i++)
        in[i] = (uint8_t)i;

    o1_ring_init(&r, store, 8u);
    CHECK(o1_ring_used(&r) == 0u && o1_ring_free(&r) == 8u, "a fresh ring is not empty");

    CHECK(o1_ring_push(&r, in, 6u) == 6u, "push 6 refused");
    CHECK(o1_ring_used(&r) == 6u, "used is %u after 6", o1_ring_used(&r));
    CHECK(o1_ring_free(&r) == 2u, "free is %u after 6", o1_ring_free(&r));

    n = o1_ring_pop(&r, out, 4u);
    CHECK(n == 4u && out[0] == 0u && out[3] == 3u, "popped %u, wanted 0..3", n);

    /* The write end is now past the read end, so this push wraps. */
    CHECK(o1_ring_push(&r, in + 6, 5u) == 5u, "the wrap push refused");
    CHECK(o1_ring_used(&r) == 7u, "used is %u after the wrap", o1_ring_used(&r));

    n = o1_ring_pop(&r, out, 16u);
    CHECK(n == 7u, "after the wrap popped %u, wanted 7", n);
    for (i = 0; i < 7u; i++) {
        CHECK(out[i] == (uint8_t)(4u + i), "after the wrap byte %u is %u, wanted %u",
              i, out[i], 4u + i);
    }
    CHECK(o1_ring_used(&r) == 0u, "the ring is not empty");

    /* drop takes from the oldest end -- what DROP_OLDEST is built on. */
    o1_ring_push(&r, in, 6u);
    CHECK(o1_ring_drop(&r, 2u) == 2u, "drop refused");
    CHECK(o1_ring_used(&r) == 4u, "used is %u after dropping 2", o1_ring_used(&r));
    n = o1_ring_pop(&r, out, 4u);
    CHECK(n == 4u && out[0] == 2u && out[3] == 5u, "dropping took the wrong end: %u..%u",
          out[0], out[3]);

    CHECK(o1_ring_drop(&r, 9u) == 0u, "dropping from an empty ring returned something");

    /* A zero-capacity ring is empty, not a crash or a division by zero. */
    o1_ring_init(&r, store, 0u);
    CHECK(o1_ring_push(&r, in, 4u) == 0u, "a zero-capacity ring accepted");
    CHECK(o1_ring_pop(&r, out, 4u) == 0u, "a zero-capacity ring popped");
    CHECK(o1_ring_drop(&r, 4u) == 0u, "a zero-capacity ring dropped");
    CHECK(o1_ring_free(&r) == 0u, "a zero-capacity ring reports free space");
}

/* ------------------------------------------------------------- the pacer */

static void test_pace(void)
{
    o1_pace  p;
    uint64_t per;
    unsigned n, total, i;

    printf("the pacer\n");

    /* 300 baud, 8-N-1: ten bits a character, so 33.3 ms each and 30 a second.
     * That is a fact about a 300-baud modem, not about this code. */
    o1_pace_init(&p, 300000u, 10u);
    per = o1_pace_byte_ns(&p);
    CHECK(per == 33333333ull, "a 300-baud character is %" PRIu64 " ns, wanted 33333333", per);

    CHECK(o1_pace_allow(&p, 0u) == 0u, "zero elapsed released something");

    n = o1_pace_allow(&p, 1000000000ull);
    CHECK(n == 30u, "one second at 300 baud released %u, wanted 30", n);

    /* The carry is exact, so the next second is also 30 and not 29 or 31. */
    n = o1_pace_allow(&p, 1000000000ull);
    CHECK(n == 30u, "the second second released %u, wanted 30", n);

    /* Chunking must not change the total: that is what "the carry does not
     * drift" means.  100 calls of 10 ms is one second either way. */
    o1_pace_init(&p, 300000u, 10u);
    total = 0;
    for (i = 0; i < 100u; i++)
        total += o1_pace_allow(&p, 10000000ull);
    CHECK(total == 30u, "100 chunks of 10 ms released %u, wanted 30", total);

    /* 650 -- the J1-out rate, and the one that is not on the panel. */
    o1_pace_init(&p, 650000u, 10u);
    per = o1_pace_byte_ns(&p);
    CHECK(per == 15384615ull, "a 650-baud character is %" PRIu64 " ns, wanted 15384615", per);
    n = o1_pace_allow(&p, 1000000000ull);
    CHECK(n == 65u, "one second at 650 baud released %u, wanted 65", n);

    /* The frame changes the character time: 8-N-2 is eleven bits, not ten. */
    o1_pace_init(&p, 300000u, 11u);
    per = o1_pace_byte_ns(&p);
    CHECK(per == 36666666ull, "an 11-bit character at 300 is %" PRIu64 " ns, wanted 36666666", per);

    /* Unshaped is the bypass: everything, however long the gap. */
    o1_pace_init(&p, O1_PACE_UNSHAPED, 10u);
    CHECK(o1_pace_byte_ns(&p) == 0ull, "unshaped has a character time");
    CHECK(o1_pace_allow(&p, 0u) == 0xFFFFFFFFu, "unshaped held something back");

    /* A rate change is a discontinuity, not a debt: turning shaping back on
     * must not dump a backlog built up while it was off. */
    o1_pace_init(&p, 300000u, 10u);
    o1_pace_allow(&p, 33333333ull * 3ull + 1ull);
    o1_pace_set_rate(&p, O1_PACE_UNSHAPED);
    o1_pace_set_rate(&p, 300000u);
    CHECK(o1_pace_allow(&p, 0u) == 0u, "a rate change left a backlog behind");
}

/* ------------------------------------------------------------ the buffer */

static void test_buffer(void)
{
    uint8_t   to_o1_store[8];
    uint8_t   to_net_store[8];
    uint8_t   out[160];
    o1_buffer b;
    o1_frame  f = o1_frame_of(0x55u);   /* 8-N-1, ten bits a character */
    unsigned  n;

    printf("the double-sided buffer\n");

    /* socket -> machine, paced at 300 baud. */
    o1_buffer_init(&b, to_o1_store, 8u, to_net_store, 8u, O1_OVERFLOW_REFUSE);
    o1_buffer_set_frame(&b, &f);
    o1_buffer_set_rate(&b, 300000u);

    CHECK(o1_buffer_from_net(&b, (const uint8_t *)"hello", 5u) == 5u,
          "the socket's five bytes were not all accepted");
    CHECK(o1_ring_used(&b.to_o1) == 5u, "the machine side holds %u, wanted 5",
          o1_ring_used(&b.to_o1));

    CHECK(o1_buffer_to_o1(&b, out, 160u, 0ull) == 0u, "zero elapsed released something");

    n = o1_buffer_to_o1(&b, out, 160u, 33333333ull);
    CHECK(n == 1u && out[0] == 'h', "one character time released %u, first byte %u",
          n, n ? out[0] : 0u);

    n = o1_buffer_to_o1(&b, out, 160u, 33333333ull * 4ull);
    CHECK(n == 4u && memcmp(out, "ello", 4u) == 0, "released %u (\"%.4s\"), wanted \"ello\"",
          n, (const char *)out);
    CHECK(o1_ring_used(&b.to_o1) == 0u, "the machine side is not empty");

    /* machine -> socket: batched, and never paced -- the socket is not asked to
     * wait on the ACIA.  No elapsed time is needed for it to move. */
    CHECK(o1_buffer_from_o1(&b, (const uint8_t *)"world", 5u) == 5u,
          "the machine's bytes were refused");
    n = o1_buffer_to_net(&b, out, 160u);
    CHECK(n == 5u && memcmp(out, "world", 5u) == 0, "the socket got %u (\"%.5s\")",
          n, (const char *)out);
    CHECK(b.dropped == 0u, "the buffer dropped %u with nothing to drop", b.dropped);

    /* The J1-out machine, end to end: 650 baud is 65 characters a second, and
     * that is the number the panel does not say. */
    {
        uint8_t   store[128];
        o1_buffer r;
        unsigned  i;

        o1_buffer_init(&r, store, 128u, to_net_store, 8u, O1_OVERFLOW_REFUSE);
        o1_buffer_set_frame(&r, &f);
        o1_buffer_set_rate(&r, 650000u);

        for (i = 0; i < 65u; i++)
            o1_buffer_from_net(&r, (const uint8_t *)"x", 1u);
        CHECK(o1_ring_used(&r.to_o1) == 65u, "only %u of 65 arrived", o1_ring_used(&r.to_o1));

        n = o1_buffer_to_o1(&r, out, 160u, 1000000000ull);
        CHECK(n == 65u, "one second at 650 baud released %u, wanted 65", n);
        CHECK(o1_ring_used(&r.to_o1) == 0u, "the machine side is not empty");
    }

    /* REFUSE keeps what has arrived: the first four bytes survive, the rest are
     * refused and counted. */
    {
        uint8_t   small[4];
        o1_buffer r;

        o1_buffer_init(&r, small, 4u, to_net_store, 8u, O1_OVERFLOW_REFUSE);
        CHECK(o1_buffer_from_net(&r, (const uint8_t *)"ABCD", 4u) == 4u,
              "the ring would not fill");
        CHECK(o1_buffer_from_net(&r, (const uint8_t *)"EF", 2u) == 0u,
              "REFUSE accepted into a full ring");
        CHECK(r.dropped == 2u, "REFUSE counted %u dropped, wanted 2", r.dropped);

        n = o1_ring_pop(&r.to_o1, out, 160u);
        CHECK(n == 4u && memcmp(out, "ABCD", 4u) == 0, "REFUSE kept \"%.4s\", wanted \"ABCD\"",
              (const char *)out);
    }

    /* DROP_OLDEST keeps the newest.  What survives is the assertion that
     * matters -- a count alone would pass on the wrong half. */
    {
        uint8_t   small[4];
        o1_buffer r;

        o1_buffer_init(&r, small, 4u, to_net_store, 8u, O1_OVERFLOW_DROP_OLDEST);
        CHECK(o1_buffer_from_net(&r, (const uint8_t *)"ABCD", 4u) == 4u,
              "the ring would not fill");
        CHECK(o1_buffer_from_net(&r, (const uint8_t *)"EF", 2u) == 2u,
              "DROP_OLDEST refused");
        CHECK(r.dropped == 2u, "DROP_OLDEST counted %u dropped, wanted 2", r.dropped);

        n = o1_ring_pop(&r.to_o1, out, 160u);
        CHECK(n == 4u && memcmp(out, "CDEF", 4u) == 0,
              "DROP_OLDEST kept \"%.4s\", wanted \"CDEF\"", (const char *)out);
    }

    /* The bypass: rate 0 releases everything at once, however long the gap.
     * This is the XMODEM/Kermit path -- re-clocking a transfer fails it. */
    {
        o1_buffer r;

        o1_buffer_init(&r, to_o1_store, 8u, to_net_store, 8u, O1_OVERFLOW_REFUSE);
        o1_buffer_set_frame(&r, &f);
        o1_buffer_set_rate(&r, 300000u);
        o1_buffer_set_rate(&r, O1_PACE_UNSHAPED);

        CHECK(o1_buffer_from_net(&r, (const uint8_t *)"0123456789", 10u) == 8u,
              "eight bytes were not accepted into an eight-byte ring");
        CHECK(o1_buffer_to_o1(&r, out, 160u, 0ull) == 8u,
              "the bypass held something back");
    }
}

int main(int argc, char **argv)
{
    int i;

    for (i = 1; i < argc; i++) {
        if (strcmp(argv[i], "-v") == 0) {
            verbose = 1;
        } else {
            fprintf(stderr, "usage: %s [-v]\n", argv[0]);
            return 2;
        }
    }

    test_frame();
    test_rate();
    test_lock();
    test_ring();
    test_pace();
    test_buffer();

    if (failures == 0) {
        printf("o1modem: all checks passed\n");
        return 0;
    }

    printf("o1modem: %d check(s) failed\n", failures);
    return 1;
}
