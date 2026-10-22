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
#include <math.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "buffer.h"
#include "frame.h"
#include "panel.h"
#include "rate.h"
#include "tone.h"

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

/* ------------------------------------------------------------------ the panel
 *
 * The panel's tests are all "does this match a document", because that is what
 * the panel *is*: a table in pinmap.md, a table in the AW9523B datasheet, and a
 * table in #322.  Every one of the three is a place where a plausible-looking
 * wrong answer would light a lamp and look fine.
 */
static void test_panel(void)
{
    static const struct {
        o1_lamp     lamp;
        int         ch;
        const char *name;
    } want[] = {
        { O1_LAMP_WIFI_RADIO,     0, "WiFi radio" },
        { O1_LAMP_WIFI_CONNECTED, 1, "WiFi conn"  },
        { O1_LAMP_HS,             2, "HS"         },
        { O1_LAMP_AA,             3, "AA"         },
        { O1_LAMP_CD,             4, "CD"         },
        { O1_LAMP_OH,             5, "OH"         },
        { O1_LAMP_RD,             6, "RD"         },
        { O1_LAMP_SD,             7, "SD"         },
        { O1_LAMP_TR,             8, "TR"         },
        { O1_LAMP_MR,             9, "MR"         },
        { O1_LAMP_RI,            10, "RI"         },
    };
    static const uint8_t dim_reg[16] = {
        0x24u, 0x25u, 0x26u, 0x27u, 0x28u, 0x29u, 0x2Au, 0x2Bu,
        0x20u, 0x21u, 0x22u, 0x23u, 0x2Cu, 0x2Du, 0x2Eu, 0x2Fu,
    };
    o1_panel       p;
    o1_panel_plan  plan;
    o1_modem_state st;
    unsigned       i, n;

    printf("the panel (pinmap.md's table, and the AW9523B's)\n");

    for (i = 0u; i < sizeof want / sizeof want[0]; i++) {
        CHECK(o1_lamp_channel(want[i].lamp) == want[i].ch,
              "%s is on channel %d, pinmap.md says %d",
              want[i].name, o1_lamp_channel(want[i].lamp), want[i].ch);
        CHECK(strcmp(o1_lamp_name(want[i].lamp), want[i].name) == 0,
              "lamp %u is called \"%s\", wanted \"%s\"",
              i, o1_lamp_name(want[i].lamp), want[i].name);
    }

    /* The dimming registers are *not* in pin order -- table 13 of the datasheet,
     * and the one thing about this part a reader will not guess. */
    for (i = 0u; i < 16u; i++)
        CHECK(o1_panel_dim_reg(i) == dim_reg[i],
              "channel %u dims at %02X, the datasheet says %02X",
              i, o1_panel_dim_reg(i), dim_reg[i]);

    /* The four handshake lines: three outputs and MCB, which is not. */
    CHECK(o1_if_channel(O1_IF_CTS) == 8 && o1_if_is_output(O1_IF_CTS),
          "CTS is not P1_0/out");
    CHECK(o1_if_channel(O1_IF_RI) == 9 && o1_if_is_output(O1_IF_RI),
          "RI is not P1_1/out");
    CHECK(o1_if_channel(O1_IF_MSB) == 10 && o1_if_is_output(O1_IF_MSB),
          "MSB is not P1_2/out");
    CHECK(o1_if_channel(O1_IF_MCB) == 11 && !o1_if_is_output(O1_IF_MCB),
          "MCB must be P1_3 and must be an input");

    /* The iface byte: CTS bit 0, RI bit 1, MSB bit 2, and MCB nowhere. */
    memset(&st, 0, sizeof st);
    st.cts = 1;
    CHECK(o1_iface_out(&st) == 0x01u, "CTS is not bit 0");
    st.ring = 1;
    CHECK(o1_iface_out(&st) == 0x03u, "RI is not bit 1");
    st.msb = 1;
    CHECK(o1_iface_out(&st) == 0x07u, "MSB is not bit 2");
    CHECK((o1_iface_out(&st) & (1u << O1_IF_MCB_BIT)) == 0u,
          "the iface output byte is writing MCB, which the machine drives");

    /* HS follows the *feel* rate and not the ACIA rate (#320, #322). */
    o1_panel_init(&p);
    memset(&st, 0, sizeof st);
    st.feel = 2400000u;
    o1_panel_apply(&p, &st, 0u);
    CHECK(!o1_panel_get(&p, O1_LAMP_HS), "2400 baud lit HS");
    st.feel = 9600000u;
    o1_panel_apply(&p, &st, 0u);
    CHECK(o1_panel_get(&p, O1_LAMP_HS), "9600 baud did not light HS");
    st.feel = 0u;
    o1_panel_apply(&p, &st, 0u);
    CHECK(!o1_panel_get(&p, O1_LAMP_HS), "the unshaped bypass lit HS");

    /* RD and SD are monostable, and a burst must not flicker. */
    o1_panel_init(&p);
    o1_panel_pulse(&p, O1_LAMP_RD, 1000u);
    CHECK(o1_panel_get(&p, O1_LAMP_RD), "a pulse did not light RD");
    CHECK(o1_panel_tick(&p, 1000u + p.pulse_ms - 1u) == 0u, "the pulse expired early");
    CHECK(o1_panel_get(&p, O1_LAMP_RD), "RD went dark early");

    /* A byte arriving mid-window *extends* it.  This is the flicker case: at 9600
     * baud bytes arrive faster than the window, and a restarting window would
     * blink at the byte rate. */
    o1_panel_pulse(&p, O1_LAMP_RD, 1000u + p.pulse_ms - 10u);
    CHECK(o1_panel_tick(&p, 1000u + p.pulse_ms) == 0u,
          "a second pulse inside the window did not extend it");
    CHECK(o1_panel_tick(&p, 1000u + 2u * p.pulse_ms) == 1u, "the pulse never expired");
    CHECK(!o1_panel_get(&p, O1_LAMP_RD), "RD stayed lit after the window");

    /* `apply` must not touch RD or SD -- a level writer racing the monostable
     * would clear the lamp while data is moving. */
    memset(&st, 0, sizeof st);
    o1_panel_pulse(&p, O1_LAMP_RD, 5000u);
    o1_panel_apply(&p, &st, 5000u);
    CHECK(o1_panel_get(&p, O1_LAMP_RD), "apply() cleared a pulsing RD");

    /* The flush is on change only, and "nothing" is the feature: a hung firmware
     * leaves the last state standing because nothing rewrites it.
     *
     * Note the two-call shape -- `apply` then `flush`.  `apply` is what turns the
     * modem's state into lamp state (and is where the dirty flag comes from);
     * `flush` is what turns lamp state into register bytes.  Keeping them apart is
     * what lets the tests check "nothing changed" without an I2C bus. */
    o1_panel_init(&p);
    memset(&st, 0, sizeof st);
    st.feel = 1200000u;
    o1_panel_apply(&p, &st, 0u);
    CHECK(o1_panel_flush(&p, &st, &plan) > 0u, "the first flush wrote nothing");

    o1_panel_apply(&p, &st, 0u);
    CHECK(o1_panel_flush(&p, &st, &plan) == 0u, "an unchanged panel was rewritten");

    st.carrier = 1;
    o1_panel_apply(&p, &st, 0u);
    n = o1_panel_flush(&p, &st, &plan);
    CHECK(n == 1u, "lighting one lamp wrote %u registers", n);
    CHECK(plan.n_dim == 1u && plan.dim[0].reg == o1_panel_dim_reg(4u),
          "CD did not write channel 4's dim register");
    CHECK(plan.dim[0].val == p.bright,
          "a lit lamp did not get the configured brightness");

    st.carrier = 0;
    o1_panel_apply(&p, &st, 0u);
    CHECK(o1_panel_flush(&p, &st, &plan) == 1u, "clearing CD did not write");
    CHECK(plan.dim[0].val == 0u, "a dark lamp was not written to zero");

    /* And the frozen panel: after a failure the caller invalidates, and the next
     * flush writes the *whole* panel again rather than only what changed. */
    o1_panel_invalidate(&p);
    o1_panel_apply(&p, &st, 0u);
    n = o1_panel_flush(&p, &st, &plan);
    CHECK(n == 17u,
          "an invalidated panel wrote %u registers, expected 16 dims + the iface byte",
          n);
    CHECK(plan.n_dim == 16u, "an invalidated panel wrote %u dim registers", plan.n_dim);

    /* The init order: mode, then direction, then dim.  A pin in LED mode ignores
     * the output register, so a dim written before the mode is a lamp whose state
     * depends on the part's power-on value. */
    {
        o1_reg_write seq[32];
        unsigned     m = o1_panel_init_writes(seq, 32u);

        CHECK(m == 24u, "the panel init is %u writes, expected 24", m);
        CHECK(seq[0].reg == O1_AW9523_REG_RESET, "the panel init does not reset first");
        CHECK(seq[1].reg == O1_AW9523_REG_GCR &&
              seq[1].val == O1_AW9523_GCR_P0_PUSHPULL,
              "GCR does not set P0 push-pull -- the panel's eight lamps need it");
        CHECK(seq[2].reg == O1_AW9523_REG_LEDMODE0 && seq[2].val == 0x00u,
              "P0 is not put in LED mode (0 = LED mode on this part)");
        CHECK(seq[3].reg == O1_AW9523_REG_LEDMODE0 + 1u && seq[3].val == 0x00u,
              "P1 is not put in LED mode");
        CHECK(seq[4].reg == O1_AW9523_REG_CONFIG0 && seq[4].val == 0x00u,
              "P0 is not configured as outputs");
        CHECK(o1_panel_init_writes(seq, 8u) == 0u,
              "the panel init did not refuse a buffer that is too small");
    }

    {
        o1_reg_write seq[16];
        unsigned     m = o1_iface_init_writes(seq, 16u);

        CHECK(m == 6u, "the iface init is %u writes, expected 6", m);
        CHECK(seq[2].reg == O1_AW9523_REG_CONFIG0 + 1u && seq[2].val == 0x08u,
              "the iface direction is not P1_3 in and P1_0..P1_2 out");
        CHECK(seq[4].reg == O1_AW9523_REG_INTEN0 + 1u && seq[4].val == 0xF7u,
              "MCB's interrupt is not the only enabled one (1 = disabled)");
    }
}

/* -------------------------------------------------------------- the scramblers
 *
 * A scrambler is the one part of a modem's sound that is *arithmetic* rather than
 * taste, so it is the one part that can be proved.  Both polynomials are asserted
 * by their **period**, which is a property only the right exponents have.
 */
static void test_scrambler(void)
{
    uint32_t sr;
    unsigned i;
    int      hit;

    printf("the scramblers (the two polynomials, and their periods)\n");

    /* Round trip: the descrambler inverts the scrambler.  That proves the taps
     * are on the right side of the XOR -- not that they are the right taps. */
    {
        uint32_t a = (1u << 17) - 1u, b = a;

        for (i = 0u; i < 4000u; i++) {
            uint8_t d = (uint8_t)((i * 7u + (i >> 3)) & 1u);
            uint8_t s = o1_scr_bit_of(&a, 14u, 17u, d);
            uint8_t r = o1_desc_bit_of(&b, 14u, 17u, s);

            if (r != d) {
                CHECK(0, "the V.22 scrambler round trip broke at bit %u", i);
                break;
            }
        }
    }

    /* The period.  The polynomials are primitive, so a *zero* input -- which
     * reduces the scrambler to a plain LFSR -- walks all 2^n - 1 non-zero states
     * and returns to where it started after exactly that many steps.  No other tap
     * pair gives 131071, so this is the assertion that the exponents really are
     * 14 and 17. */
    sr  = 1u;
    hit = 0;
    for (i = 1u; i <= 131071u; i++) {
        o1_scr_bit_of(&sr, 14u, 17u, 0u);
        if (sr == 1u) {
            hit = (int)i;
            break;
        }
    }
    CHECK(hit == 131071, "the V.22 scrambler's period is %d, expected 131071", hit);

    /* And V.32's, which is 2^23 - 1.  Eight million iterations is a fraction of a
     * second, and it is the only proof that the taps are 18 and 23. */
    sr  = 1u;
    hit = 0;
    for (i = 1u; i <= 8388607u; i++) {
        o1_scr_bit_of(&sr, 18u, 23u, 0u);
        if (sr == 1u) {
            hit = (int)i;
            break;
        }
    }
    CHECK(hit == 8388607, "the V.32 scrambler's period is %d, expected 8388607", hit);

    /* A scrambler that simply returned its input would pass both of the above and
     * fail this: "scrambled binary 1" has to come out looking like noise.  It is
     * also the check that catches the degenerate preset -- from all-ones or
     * all-zeros, an input of 1 passes straight through and this reads 4000 ones. */
    {
        o1_scrambler s;
        unsigned     ones = 0u, zeros = 0u;

        o1_scr_v22_init(&s);
        for (i = 0u; i < 4000u; i++) {
            if (o1_scr_bit(&s, 1u) != 0u)
                ones++;
            else
                zeros++;
        }
        CHECK(ones > 1000u && zeros > 1000u,
              "scrambled 1s came out %u ones / %u zeros -- that is not scrambling",
              ones, zeros);
        note("scrambled 1s over 4000 bits: %u ones, %u zeros", ones, zeros);
    }
}

/* ---------------------------------------------------------------- the tone tables
 *
 * Every frequency in the scores, against the source `docs/modem-tones.md` names
 * for it.  A table is data, and data drifts.
 */
static void test_tone_tables(void)
{
    unsigned i;

    printf("the tone tables (the sources in docs/modem-tones.md)\n");

    /* Bell 103A, from the Comm-Pac manual: (1,0) = (1270,1070) originate and
     * (2225,2025) answer, 300 baud FSK. */
    CHECK(o1_hs_bell103.phases[0].f1 == 2225u, "the 300-baud answer mark is not 2225 Hz");
    CHECK(o1_hs_bell103.phases[1].f1 == 1270u, "the 300-baud originate mark is not 1270 Hz");
    CHECK(o1_hs_bell103.phases[3].sig == O1_SIG_FSK &&
          o1_hs_bell103.phases[3].baud == 300u,
          "the 300-baud data phase is not FSK at 300 baud");
    CHECK(o1_hs_bell103.phases[3].f1 == 2225u && o1_hs_bell103.phases[3].f2 == 2025u,
          "the 300-baud answer band is not 2225/2025");
    CHECK(o1_hs_bell103.phases[3].f3 == 1270u && o1_hs_bell103.phases[3].f4 == 1070u,
          "the 300-baud originate band is not 1270/1070");

    /* V.22 / Bell 212A: 2250 Hz answer tone, 600 baud, 2400/1200 split band. */
    CHECK(o1_hs_v22.phases[0].f1 == 2250u, "the V.22 answer tone is not 2250 Hz");
    CHECK(o1_hs_v22.phases[6].sig == O1_SIG_PSK4 && o1_hs_v22.phases[6].baud == 600u,
          "the 1200-baud data phase is not 600-baud DPSK");
    CHECK(o1_hs_v22.phases[6].f1 == 2400u && o1_hs_v22.phases[6].f3 == 1200u,
          "the 1200-baud split band is not 2400/1200");
    CHECK(o1_hs_v22.phases[6].two == 1u, "the 1200-baud data phase is not full duplex");

    /* V.22bis: the same band and baud, sixteen points instead of four. */
    CHECK(o1_hs_v22bis.phases[0].f1 == 2250u, "the V.22bis answer tone is not 2250 Hz");
    CHECK(o1_hs_v22bis.phases[7].sig == O1_SIG_QAM16, "2400 bit/s is not QAM-16");
    CHECK(o1_hs_v22bis.phases[7].baud == 600u, "QAM-16 is not at 600 baud");

    /* S1: 100 ms of double dibit on the low band, after the standard's 456 ms
     * wait.  The *pattern* is asserted separately, below. */
    CHECK(o1_hs_v22bis.phases[3].bits == O1_BIT_DOUBLE_DIBIT &&
          o1_hs_v22bis.phases[3].ms == 100u && o1_hs_v22bis.phases[3].f1 == 1200u,
          "the S1 phase is not 100 ms of double dibit on the low band");
    CHECK(o1_hs_v22bis.phases[2].ms == 456u,
          "the standard's 456 ms wait before S1 is not in the score");

    /* V.32: 2100 Hz ANS with 450 ms reversals, 600+3000 for AC/CA, one 1800 Hz
     * carrier at 2400 baud with 32 points. */
    CHECK(o1_hs_v32.phases[0].f1 == 2100u && o1_hs_v32.phases[0].rev_ms == 450u,
          "the V.32 ANS is not 2100 Hz with 450 ms reversals");
    CHECK(o1_hs_v32.phases[1].f1 == 1800u, "the V.32 AA signal is not 1800 Hz");
    CHECK(o1_hs_v32.phases[2].f1 == 600u && o1_hs_v32.phases[2].f2 == 3000u,
          "the AC/CA pair is not 600 + 3000 Hz");
    CHECK(o1_hs_v32.phases[8].sig == O1_SIG_QAM32 && o1_hs_v32.phases[8].baud == 2400u,
          "9600 bit/s is not 2400-baud 32-point");

    /* **V.32 is not a split band.**  It is echo-cancelled, so it has one carrier,
     * and every phase of its score has to say so -- a split-band 9600 would be a
     * V.22 with a faster clock, which is a different sound entirely. */
    for (i = 0u; i < o1_hs_v32.n; i++)
        CHECK(o1_hs_v32.phases[i].two == 0u, "V.32 phase %u claims a split band", i);

    /* The rate picker, including the machine's *real* rates: 650 and 2600 are the
     * J1-out rates (#319) and are not modem rates at all. */
    CHECK(o1_hs_for_rate(300000u) == &o1_hs_bell103, "300 baud is not the Bell 103 score");
    CHECK(o1_hs_for_rate(650000u) == &o1_hs_bell103, "650 baud should get the 300 score");
    CHECK(o1_hs_for_rate(1200000u) == &o1_hs_v22, "1200 baud is not the V.22 score");
    CHECK(o1_hs_for_rate(2600000u) == &o1_hs_v22bis, "2600 baud should get the 2400 score");
    CHECK(o1_hs_for_rate(9600000u) == &o1_hs_v32, "9600 baud is not the V.32 score");
    CHECK(o1_hs_for_rate(0u) == &o1_hs_bell103, "the unshaped bypass should get 300");

    /* Durations, as the sum of the phases. */
    CHECK(o1_hs_ms(&o1_hs_v22) == 3300u + 200u + 456u + 100u + 100u + 400u + 2000u,
          "the V.22 score is %u ms", o1_hs_ms(&o1_hs_v22));
    CHECK(o1_hs_ms(&o1_hs_v32) > 5000u && o1_hs_ms(&o1_hs_v32) < 7000u,
          "the V.32 score is %u ms, which is not a plausible handshake",
          o1_hs_ms(&o1_hs_v32));

    /* S1 as a *pattern*: 0,0,1,1 repeating.  The comment claims it; this asserts
     * it, and a claim in a comment is not a test. */
    {
        static const uint8_t want8[8] = { 0u, 0u, 1u, 1u, 0u, 0u, 1u, 1u };
        unsigned idx = 0u;

        for (i = 0u; i < 8u; i++)
            CHECK(o1_bitpat_bit(O1_BIT_DOUBLE_DIBIT, &idx) == want8[i],
                  "the S1 double-dibit pattern is wrong at bit %u", i);

        /* And ABABAB is an alternation, not a constant. */
        idx = 0u;
        CHECK(o1_bitpat_bit(O1_BIT_AB, &idx) == 1u, "S does not start at A");
        CHECK(o1_bitpat_bit(O1_BIT_AB, &idx) == 0u, "S does not alternate");
    }
}

/* -------------------------------------------------------------- the rendered output
 *
 * **This is the test that earns its place.**  It measures the samples the
 * generator actually produces, so a wrong phase increment, a mis-mirrored sine
 * table, a wrong sample rate and a reversed bit order all fail it -- and not one
 * of them is visible in the source.  A .wav set cannot be tested this way at all,
 * which is half of why there is not one (tone.h).
 */
static unsigned measure_hz(const o1_handshake *hs, unsigned ms, unsigned fs)
{
    static int16_t buf[512];
    o1_tone_gen    g;
    uint64_t       samples = 0u, want;
    unsigned       crossings = 0u;
    int            last = 0;

    o1_tone_start(&g, hs, fs, O1_TONE_AMP_DEFAULT);
    want = ((uint64_t)fs * (uint64_t)ms) / 1000u;

    while (samples < want) {
        unsigned n = o1_tone_render(&g, buf, 512u);
        unsigned i;

        if (n == 0u)
            break;

        for (i = 0u; i < n && samples < want; i++) {
            int s = (buf[i] > 0) ? 1 : ((buf[i] < 0) ? -1 : 0);

            if (s != 0) {
                if (last != 0 && s != last)
                    crossings++;
                last = s;
            }
            samples++;
        }
    }

    if (samples == 0u)
        return 0u;

    /* Two zero crossings per cycle. */
    return (unsigned)(((uint64_t)crossings * (uint64_t)fs) / (2u * samples));
}

static void test_tone_render(void)
{
    static const struct {
        const o1_handshake *hs;
        unsigned            ms;
        unsigned            want;
        const char         *what;
    } t[] = {
        { &o1_hs_bell103, 1000u, 2225u, "Bell 103 answer mark" },
        { &o1_hs_v22,     1000u, 2250u, "V.22 answer tone" },
        { &o1_hs_v22bis,  1000u, 2250u, "V.22bis answer tone" },
        { &o1_hs_v32,      400u, 2100u, "V.32 ANS, before its first reversal" },
    };
    unsigned i;

    printf("the rendered output (measured, not assumed)\n");

    for (i = 0u; i < sizeof t / sizeof t[0]; i++) {
        unsigned got = measure_hz(t[i].hs, t[i].ms, O1_TONE_FS_DEFAULT);
        unsigned err = (got > t[i].want) ? (got - t[i].want) : (t[i].want - got);

        CHECK(err * 100u <= t[i].want * 2u,
              "%s measured %u Hz, wanted %u (+/-2%%)", t[i].what, got, t[i].want);
        note("%s: %u Hz over %u ms", t[i].what, got, t[i].ms);
    }

    /* The whole score renders, and it renders **exactly** the number of samples its
     * duration implies: at 16 kHz every phase's millisecond count is a whole
     * number of samples, so the total is exact and a drifting length is a failure.
     * This is also the check that catches a phase boundary which never advances --
     * a score that hangs is worse than a score that is wrong. */
    {
        o1_tone_gen    g;
        static int16_t buf[512];
        uint64_t       total = 0u, expect;
        unsigned       n;

        o1_tone_start(&g, &o1_hs_v22, O1_TONE_FS_DEFAULT, O1_TONE_AMP_DEFAULT);
        CHECK(!o1_tone_done(&g), "a fresh generator is already done");
        CHECK(o1_tone_phase_name(&g) != 0, "a fresh generator has no phase name");

        while ((n = o1_tone_render(&g, buf, 512u)) > 0u)
            total += n;

        expect = (uint64_t)o1_hs_ms(&o1_hs_v22) * (O1_TONE_FS_DEFAULT / 1000u);
        CHECK(o1_tone_done(&g), "the score never finished");
        CHECK(total == expect,
              "the V.22 score rendered %llu samples, expected %llu",
              (unsigned long long)total, (unsigned long long)expect);
        CHECK(o1_tone_render(&g, buf, 512u) == 0u, "a finished generator kept rendering");
        CHECK(o1_tone_phase_name(&g) == 0, "a finished generator still names a phase");
        note("the V.22 score: %llu samples, %u ms", (unsigned long long)total,
             o1_hs_ms(&o1_hs_v22));
    }

    /* Every sample of a score is inside the amplitude asked for, and the signal is
     * not silent -- the two ways a synthesis can be wrong while looking right. */
    {
        o1_tone_gen    g;
        static int16_t buf[512];
        int            peak = 0;
        unsigned       nonzero = 0u, n;

        o1_tone_start(&g, &o1_hs_v32, O1_TONE_FS_DEFAULT, O1_TONE_AMP_DEFAULT);
        while ((n = o1_tone_render(&g, buf, 512u)) > 0u) {
            unsigned k;

            for (k = 0u; k < n; k++) {
                int v = buf[k];
                int a = (v < 0) ? -v : v;

                if (a > peak)
                    peak = a;
                if (v != 0)
                    nonzero++;
            }
        }
        CHECK(peak <= O1_TONE_AMP_DEFAULT,
              "the V.32 score peaked at %d, above the %d asked for",
              peak, O1_TONE_AMP_DEFAULT);
        CHECK(peak > O1_TONE_AMP_DEFAULT / 2,
              "the V.32 score only reached %d -- that is too quiet to be the sound",
              peak);
        CHECK(nonzero > 1000u, "the V.32 score is mostly silence");
        note("V.32: peak %d of %d, %u non-zero samples",
             peak, O1_TONE_AMP_DEFAULT, nonzero);
    }
}

/* ----------------------------------------------------------------------- DTMF */

static void test_dtmf(void)
{
    static const struct {
        char     digit;
        uint16_t lo, hi;
    } t[] = {
        { '1', 697u, 1209u }, { '5', 770u, 1336u }, { '9', 852u, 1477u },
        { '0', 941u, 1336u }, { '*', 941u, 1209u }, { '#', 941u, 1477u },
        { 'A', 697u, 1633u }, { 'D', 941u, 1633u },
    };
    uint16_t lo, hi;
    unsigned i;

    printf("DTMF (the eight tones, and the grid)\n");

    for (i = 0u; i < sizeof t / sizeof t[0]; i++) {
        lo = 0u;
        hi = 0u;
        CHECK(o1_dtmf_tones(t[i].digit, &lo, &hi) == 1,
              "'%c' is not recognised as a DTMF digit", t[i].digit);
        CHECK(lo == t[i].lo && hi == t[i].hi,
              "'%c' is %u + %u Hz, wanted %u + %u",
              t[i].digit, lo, hi, t[i].lo, t[i].hi);
    }

    CHECK(o1_dtmf_tones('Q', &lo, &hi) == 0, "'Q' is not a DTMF digit");
    CHECK(o1_dtmf_tones('7', 0, 0) == 1, "a null out-pointer was not tolerated");
}

/* ------------------------------------------------------------ the dial fingerprint
 *
 * **The hash is checked against the published FNV-1a vectors**, not against its own
 * output.  That is the difference between "this is FNV-1a" and "this is a hash I
 * wrote that agrees with itself", and only the first one is worth asserting --
 * because the fingerprint's whole job is that two *different* implementations
 * would dial the same number for the same host.
 */
static void test_fingerprint(void)
{
    /* The reference vectors, from the FNV specification. */
    static const struct {
        const char *s;
        uint64_t    h;
    } fnv[] = {
        { "",       0xcbf29ce484222325ull },
        { "a",      0xaf63dc4c8601ec8cull },
        { "b",      0xaf63df4c8601f1a5ull },
        { "c",      0xaf63de4c8601eff2ull },
        { "foobar", 0x85944171f73967e8ull },
    };
    char     buf[O1_DTMF_DIGITS_MAX + 1u];
    unsigned i;

    printf("the dial fingerprint (FNV-1a 64, and the DTMF alphabet)\n");

    for (i = 0u; i < sizeof fnv / sizeof fnv[0]; i++)
        CHECK(o1_fnv1a64(fnv[i].s, (unsigned)strlen(fnv[i].s)) == fnv[i].h,
              "FNV-1a 64 of \"%s\" is %016llx, the reference says %016llx",
              fnv[i].s,
              (unsigned long long)o1_fnv1a64(fnv[i].s, (unsigned)strlen(fnv[i].s)),
              (unsigned long long)fnv[i].h);

    /* The sixteen symbols, in nibble order, and every one of them dialable. */
    {
        static const char want[17] = "0123456789*#ABCD";

        for (i = 0u; i < 16u; i++) {
            uint16_t lo = 0u, hi = 0u;

            CHECK(o1_dtmf_symbol(i) == want[i],
                  "nibble %u is '%c', wanted '%c'", i, o1_dtmf_symbol(i), want[i]);
            CHECK(o1_dtmf_tones(o1_dtmf_symbol(i), &lo, &hi) == 1,
                  "nibble %u maps to '%c', which DTMF cannot dial",
                  i, o1_dtmf_symbol(i));
        }
    }

    /* **The whole chain, against one published value.**  FNV-1a 64 of "foobar" is
     * 0x85944171f73967e8, so twelve symbols taken from the top is
     * 85944171D739 -- which pins the hash, the high-nibble order and the
     * 10->'*'/11->'#'/15->'D' mapping in one assertion. */
    CHECK(o1_dtmf_fingerprint("foobar", buf, sizeof buf, 12u) == 12u,
          "the fingerprint refused a twelve-symbol request");
    CHECK(strcmp(buf, "85944171D739") == 0,
          "foobar dials as \"%s\", expected \"85944171D739\"", buf);
    note("foobar -> %s", buf);

    /* Deterministic: the same host always sounds the same. */
    {
        char again[O1_DTMF_DIGITS_MAX + 1u];

        o1_dtmf_fingerprint("foobar", again, sizeof again, 12u);
        CHECK(strcmp(again, buf) == 0, "the same string dialled differently twice");
    }

    /* The length is clamped to the band rather than refused. */
    CHECK(o1_dtmf_fingerprint("foobar", buf, sizeof buf, 3u) == O1_DTMF_DIGITS_MIN,
          "a too-short request was not clamped up to %u", O1_DTMF_DIGITS_MIN);
    CHECK(o1_dtmf_fingerprint("foobar", buf, sizeof buf, 99u) == O1_DTMF_DIGITS_MAX,
          "a too-long request was not clamped down to %u", O1_DTMF_DIGITS_MAX);
    CHECK(o1_dtmf_fingerprint("foobar", buf, 8u, 12u) == 0u,
          "a buffer too small for the digits was not refused");

    /* Different destinations sound different.  Ten real-looking strings, no two
     * the same -- which is the property the operator actually hears. */
    {
        static const char *hosts[] = {
            "bbs.example.net:23", "bbs.example.net:2323", "192.0.2.10:6400",
            "mybbs", "MYBBS", "bbs.example.net", "bbs.example.com:23",
            "10.0.0.1", "10.0.0.2", "sdf.org",
        };
        char seen[10][O1_DTMF_DIGITS_MAX + 1u];
        unsigned a, b, clashes = 0u;

        for (a = 0u; a < 10u; a++) {
            o1_dtmf_fingerprint(hosts[a], seen[a], sizeof seen[a], 12u);
            for (b = 0u; b < a; b++)
                if (strcmp(seen[a], seen[b]) == 0)
                    clashes++;
        }
        CHECK(clashes == 0u, "%u of ten distinct hosts dialled the same number", clashes);
        note("ten hosts, ten dials -- the first is %s", seen[0]);
    }
}

/* One bin of a Goertzel filter: how much energy is at `f`?  The test uses it to
 * prove the two DTMF tones are really both in the rendered samples, which is the
 * one thing a phase table cannot tell you. */
static double energy_at(const int16_t *s, unsigned n, unsigned fs, unsigned f)
{
    double   w = 2.0 * 3.14159265358979323846 * (double)f / (double)fs;
    double   c = 2.0 * cos(w);
    double   s1 = 0.0, s2 = 0.0;
    unsigned i;

    for (i = 0u; i < n; i++) {
        double s0 = (double)s[i] + c * s1 - s2;

        s2 = s1;
        s1 = s0;
    }
    return (s1 * s1 + s2 * s2 - c * s1 * s2) / ((double)n * (double)n);
}

static void test_dial(void)
{
    static o1_dtmf_dial d;
    o1_dial_gate        g;

    printf("the dial (DTMF, and the admission gate)\n");

    /* Three digits: three tones and the two gaps *between* them, and none after
     * the last -- a trailing silence is admission the operator never asked for. */
    CHECK(o1_dtmf_dial_from_digits(&d, "123", 3u) == 3u, "a three-digit dial was refused");
    CHECK(d.n == 3u, "the dial has %u symbols", d.n);
    CHECK(d.hs.n == 5u, "three digits made %u phases, expected 5", d.hs.n);
    CHECK(o1_hs_ms(&d.hs) == 3u * O1_DTMF_TONE_MS + 2u * O1_DTMF_GAP_MS,
          "the dial is %u ms, expected %u", o1_hs_ms(&d.hs),
          3u * O1_DTMF_TONE_MS + 2u * O1_DTMF_GAP_MS);
    CHECK(strcmp(d.hs.name, "123") == 0, "the dial calls itself \"%s\"", d.hs.name);

    /* The first phase is '1' -- 697 + 1209 Hz -- and the second is the gap. */
    {
        uint16_t lo = 0u, hi = 0u;

        o1_dtmf_tones('1', &lo, &hi);
        CHECK(d.hs.phases[0].sig == O1_SIG_DTMF, "the first phase is not a DTMF tone");
        CHECK(d.hs.phases[0].f1 == lo && d.hs.phases[0].f2 == hi,
              "the first digit is %u+%u Hz, wanted %u+%u",
              d.hs.phases[0].f1, d.hs.phases[0].f2, lo, hi);
        CHECK(d.hs.phases[0].ms == O1_DTMF_TONE_MS, "the first tone is %u ms",
              d.hs.phases[0].ms);
        CHECK(d.hs.phases[1].sig == O1_SIG_SILENCE,
              "there is no gap after the first digit");
        CHECK(d.hs.phases[1].ms == O1_DTMF_GAP_MS, "the gap is %u ms",
              d.hs.phases[1].ms);
        CHECK(d.hs.phases[4].sig == O1_SIG_DTMF, "the last phase is not the last digit");
    }

    /* The names are per digit and not shared: `o1_tone_phase_name` hands the
     * pointer out and a caller may hold it, so one buffer would make every digit
     * report itself as the last one. */
    CHECK(d.hs.phases[0].name != 0 && strcmp(d.hs.phases[0].name, "1") == 0,
          "digit 0 is named \"%s\"", d.hs.phases[0].name ? d.hs.phases[0].name : "(null)");
    CHECK(d.hs.phases[2].name != 0 && strcmp(d.hs.phases[2].name, "2") == 0,
          "digit 1 is named \"%s\"", d.hs.phases[2].name ? d.hs.phases[2].name : "(null)");
    CHECK(d.hs.phases[1].name != 0 && strcmp(d.hs.phases[1].name, "gap") == 0,
          "the gap is named \"%s\"", d.hs.phases[1].name ? d.hs.phases[1].name : "(null)");

    /* **The rendered output, filtered.**  The table says 697 + 1209; this says the
     * samples carry both and that the frequencies neither of them uses are down.
     * A phase table cannot be wrong in a way this misses. */
    {
        static o1_tone_gen gen;
        static int16_t     buf[4096];
        unsigned           want = (O1_DTMF_TONE_MS * O1_TONE_FS_DEFAULT) / 1000u;
        unsigned           got = 0u, n;
        double             e697, e1209, e941, e1336, e1477, e_off;

        o1_tone_start(&gen, &d.hs, O1_TONE_FS_DEFAULT, O1_TONE_AMP_DEFAULT);
        while (got < want) {
            /* Exactly the first digit, and no further: `o1_tone_render` fills what
             * it is asked for, so asking for the whole buffer would render into
             * the *next* digits and the filter would measure three tones instead
             * of one.  That is what this test did the first time it ran. */
            n = o1_tone_render(&gen, buf + got, want - got);
            if (n == 0u)
                break;
            got += n;
        }
        CHECK(got == want, "the first digit rendered %u samples, expected %u", got, want);

        e697  = energy_at(buf, got, O1_TONE_FS_DEFAULT, 697u);
        e1209 = energy_at(buf, got, O1_TONE_FS_DEFAULT, 1209u);
        e941  = energy_at(buf, got, O1_TONE_FS_DEFAULT, 941u);
        e1336 = energy_at(buf, got, O1_TONE_FS_DEFAULT, 1336u);
        e1477 = energy_at(buf, got, O1_TONE_FS_DEFAULT, 1477u);
        e_off = energy_at(buf, got, O1_TONE_FS_DEFAULT, 2000u);

        CHECK(e697 > 8.0 * e_off, "'1' carries no 697 Hz (%.0f vs %.3f off-tone)",
              e697, e_off);
        CHECK(e1209 > 8.0 * e_off, "'1' carries no 1209 Hz (%.0f vs %.3f off-tone)",
              e1209, e_off);
        CHECK(e697 > 3.0 * e941, "'1' leaked 941 Hz (%.0f vs %.0f)", e697, e941);
        CHECK(e1209 > 3.0 * e1336, "'1' leaked 1336 Hz (%.0f vs %.0f)", e1209, e1336);
        CHECK(e1209 > 3.0 * e1477, "'1' leaked 1477 Hz (%.0f vs %.0f)", e1209, e1477);
        note("'1': 697 Hz %.0f, 1209 Hz %.0f; 941 %.0f, 1336 %.0f, 1477 %.0f, off %.3f",
             e697, e1209, e941, e1336, e1477, e_off);
    }

    /* And the gaps are **exactly** silent -- zero, not merely quiet. */
    {
        static o1_tone_gen gen;
        static int16_t     buf[8192];
        unsigned           total = 0u, n, k, loud = 0u, noise = 0u;
        unsigned           expect = (3u * O1_DTMF_TONE_MS + 2u * O1_DTMF_GAP_MS)
                                    * (O1_TONE_FS_DEFAULT / 1000u);

        o1_tone_start(&gen, &d.hs, O1_TONE_FS_DEFAULT, O1_TONE_AMP_DEFAULT);
        while ((n = o1_tone_render(&gen, buf + total, 8192u - total)) > 0u)
            total += n;

        CHECK(total == expect, "the dial rendered %u samples, expected %u", total, expect);

        for (k = 0u; k < total; k++) {
            /* tone = 60 ms = 960 samples, gap = 40 ms = 640. */
            int in_gap = ((k >= 960u && k < 1600u) || (k >= 2560u && k < 3200u));

            if (in_gap) {
                if (buf[k] != 0)
                    noise++;
            } else if (buf[k] != 0) {
                loud++;
            }
        }
        CHECK(noise == 0u, "%u non-zero samples in the gaps -- a gap is a silence", noise);
        CHECK(loud > 0u, "the dial is entirely silent");
    }

    /* A twelve-symbol dial for a real-looking host: the shape the brief asks for. */
    {
        char fp[O1_DTMF_DIGITS_MAX + 1u];

        CHECK(o1_dtmf_dial_build(&d, "bbs.example.net:23", 12u) == 12u,
              "the dial for a host was refused");
        o1_dtmf_fingerprint("bbs.example.net:23", fp, sizeof fp, 12u);
        CHECK(strcmp(d.hs.name, fp) == 0,
              "the dial is named \"%s\", wanted \"%s\"", d.hs.name, fp);
        CHECK(o1_hs_ms(&d.hs) > 1000u && o1_hs_ms(&d.hs) < 1500u,
              "a twelve-digit dial is %u ms, which is not a plausible dial",
              o1_hs_ms(&d.hs));
        note("bbs.example.net:23 dials as %s, %u ms", d.hs.name, o1_hs_ms(&d.hs));
    }

    /* The gate: **both facts, either order, or no dial to wait for.** */
    o1_dial_gate_reset(&g);
    CHECK(o1_dial_gate_admitted(&g), "a gate that was never armed refused a connection");
    CHECK(!o1_dial_gate_armed(&g), "a reset gate says it is armed");

    o1_dial_gate_arm(&g);
    CHECK(o1_dial_gate_armed(&g), "an armed gate says it is not armed");
    CHECK(!o1_dial_gate_admitted(&g), "an armed gate admitted before either fact");

    o1_dial_gate_linked(&g);
    CHECK(!o1_dial_gate_admitted(&g), "the link alone admitted the connection");

    o1_dial_gate_dialled(&g);
    CHECK(o1_dial_gate_admitted(&g), "both facts did not admit the connection");

    /* The other order, and re-arming clears the last attempt's facts. */
    o1_dial_gate_arm(&g);
    CHECK(!o1_dial_gate_admitted(&g), "re-arming did not clear the facts");
    o1_dial_gate_dialled(&g);
    CHECK(!o1_dial_gate_admitted(&g), "the dial alone admitted the connection");
    o1_dial_gate_linked(&g);
    CHECK(o1_dial_gate_admitted(&g), "the other order did not admit the connection");

    /* An aborted attempt starts clean -- and is then admitted immediately, because
     * there is no dial left to wait for. */
    o1_dial_gate_abort(&g);
    CHECK(o1_dial_gate_admitted(&g), "an aborted attempt did not clear the gate");
    CHECK(!o1_dial_gate_armed(&g), "an aborted gate still says it is armed");

    /* The three ways a dial can be refused.  Last, because a refusal leaves the
     * dial partially built. */
    CHECK(o1_dtmf_dial_from_digits(&d, "12E", 3u) == 0u, "'E' was dialled");
    CHECK(o1_dtmf_dial_from_digits(&d, "123456789012345678", 18u) == O1_DTMF_DIGITS_MAX,
          "an over-long dial was not clamped to %u", O1_DTMF_DIGITS_MAX);
    CHECK(o1_dtmf_dial_from_digits(&d, "", 0u) == 0u, "an empty dial was accepted");
    CHECK(o1_dtmf_dial_build(&d, "x", 0u) == O1_DTMF_DIGITS_MIN,
          "a zero-digit request was not clamped to %u", O1_DTMF_DIGITS_MIN);
}

/* The speaker (#322): Hayes `ATM`, and the `T` in `ATDT`.
 *
 * The whole truth table is written out below, independently of the
 * implementation, and every cell of it is checked in both `T` states.  That is
 * the point of the test: this policy is the one place in the project where a
 * *taste* decision -- which sounds a call makes -- is encoded, so what is worth
 * asserting is not that the code runs, but that the code agrees with the table.
 */
static void test_speaker(void)
{
    static const struct {
        o1_speaker m;
        int        tones;
        int        dial, connect, ring, drop;
    } want[] = {
        /*  mode                   T   dial connect ring drop */
        { O1_SPK_OFF,              0,    0,     0,    0,   0 },
        { O1_SPK_OFF,              1,    0,     0,    0,   0 },
        { O1_SPK_UNTIL_CARRIER,    0,    0,     0,    1,   0 },
        { O1_SPK_UNTIL_CARRIER,    1,    1,     1,    1,   0 },
        { O1_SPK_ALWAYS,           0,    0,     0,    1,   1 },
        { O1_SPK_ALWAYS,           1,    1,     1,    1,   1 },
        { O1_SPK_DIAL_ONLY,        0,    0,     0,    0,   0 },
        { O1_SPK_DIAL_ONLY,        1,    1,     0,    0,   0 }
    };
    static const char *const names[] = { "M0", "M1", "M2", "M3" };
    o1_sound_policy p;
    o1_speaker      m;
    unsigned        i;

    note("--- the speaker: Hayes ATM, and the T in ATDT");

    /* The power-up state: M1, and a call that has not asked for anything. */
    o1_sound_policy_init(&p);
    CHECK(o1_sound_policy_mode(&p) == O1_SPK_UNTIL_CARRIER,
          "the speaker powers up as %s, not M1",
          o1_speaker_name(o1_sound_policy_mode(&p)));
    CHECK(!o1_sound_policy_tones(&p), "a fresh policy says the call asked for tones");
    CHECK(!o1_sound_wants_dial(&p), "a plain ATD dialled audibly");
    CHECK(!o1_sound_wants_connect(&p), "a plain ATD made a connect sound");
    CHECK(o1_sound_wants_ring(&p), "M1 did not ring, and a ring is not a dial");
    CHECK(!o1_sound_wants_disconnect(&p),
          "M1 made a disconnect sound -- the speaker is off once the carrier is up");

    /* Every cell of the table. */
    for (i = 0u; i < (unsigned)(sizeof want / sizeof want[0]); i++) {
        o1_sound_policy_set_mode(&p, want[i].m);
        o1_sound_policy_set_tones(&p, want[i].tones);

        CHECK(o1_sound_wants_dial(&p) == want[i].dial,
              "%s%s: the dial should be %s", names[want[i].m],
              want[i].tones ? "+T" : "", want[i].dial ? "audible" : "silent");
        CHECK(o1_sound_wants_connect(&p) == want[i].connect,
              "%s%s: the connect should be %s", names[want[i].m],
              want[i].tones ? "+T" : "", want[i].connect ? "audible" : "silent");
        CHECK(o1_sound_wants_ring(&p) == want[i].ring,
              "%s%s: the ring should be %s", names[want[i].m],
              want[i].tones ? "+T" : "", want[i].ring ? "audible" : "silent");
        CHECK(o1_sound_wants_disconnect(&p) == want[i].drop,
              "%s%s: the disconnect should be %s", names[want[i].m],
              want[i].tones ? "+T" : "", want[i].drop ? "audible" : "silent");
    }

    /* `ATM<n>`: four digits, four names, and a refusal for anything else. */
    for (i = 0u; i < 4u; i++) {
        CHECK(o1_speaker_from_digit((int)i, &m), "ATM%u was refused", i);
        CHECK((int)m == (int)i, "ATM%u became %s", i, o1_speaker_name(m));
        CHECK(strcmp(o1_speaker_name(m), names[i]) == 0,
              "mode %u is called \"%s\", not \"%s\"", i, o1_speaker_name(m), names[i]);
    }
    CHECK(!o1_speaker_from_digit(4, &m), "ATM4 was accepted");
    CHECK(!o1_speaker_from_digit(9, &m), "ATM9 was accepted");
    CHECK(!o1_speaker_from_digit(-1, &m), "ATM-1 was accepted");
    CHECK(!o1_speaker_from_digit(14, &m), "ATM14 was accepted");

    /* A NULL policy is the power-up state, not a fault: the sound path asks these
     * from a hot path, and a null dereference there is a reset rather than a
     * missing beep. */
    CHECK(o1_sound_policy_mode(0) == O1_SPK_UNTIL_CARRIER,
          "a NULL policy is not the power-up state");
    CHECK(!o1_sound_wants_dial(0), "a NULL policy dialled audibly");
    CHECK(o1_sound_wants_ring(0), "a NULL policy did not ring");
    CHECK(o1_speaker_name(O1_SPK_OFF) != 0, "the name of M0 is NULL");
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
    test_panel();
    test_scrambler();
    test_tone_tables();
    test_tone_render();
    test_dtmf();
    test_fingerprint();
    test_dial();
    test_speaker();

    if (failures == 0) {
        printf("o1modem: all checks passed\n");
        return 0;
    }

    printf("o1modem: %d check(s) failed\n", failures);
    return 1;
}
