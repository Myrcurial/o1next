/* The double-sided baud buffer -- see buffer.h for why (#318, part of #56). */
#include "buffer.h"

/* ------------------------------------------------------------------ the ring */

void o1_ring_init(o1_ring *r, uint8_t *storage, unsigned cap)
{
    if (r == 0)
        return;

    r->buf  = storage;
    r->cap  = (storage == 0) ? 0u : cap;
    r->head = 0;
    r->tail = 0;
    r->used = 0;
}

unsigned o1_ring_used(const o1_ring *r)
{
    return (r == 0) ? 0u : r->used;
}

unsigned o1_ring_free(const o1_ring *r)
{
    return (r == 0 || r->cap == 0u) ? 0u : (r->cap - r->used);
}

unsigned o1_ring_push(o1_ring *r, const uint8_t *src, unsigned n)
{
    unsigned i, room;

    if (r == 0 || src == 0 || r->cap == 0u)
        return 0;

    room = o1_ring_free(r);
    if (n > room)
        n = room;

    for (i = 0; i < n; i++) {
        r->buf[r->tail] = src[i];
        r->tail = (r->tail + 1u) % r->cap;
    }
    r->used += n;
    return n;
}

unsigned o1_ring_pop(o1_ring *r, uint8_t *dst, unsigned n)
{
    unsigned i;

    if (r == 0 || dst == 0 || r->cap == 0u)
        return 0;

    if (n > r->used)
        n = r->used;

    for (i = 0; i < n; i++) {
        dst[i] = r->buf[r->head];
        r->head = (r->head + 1u) % r->cap;
    }
    r->used -= n;
    return n;
}

unsigned o1_ring_drop(o1_ring *r, unsigned n)
{
    if (r == 0 || r->cap == 0u || n == 0u)
        return 0;

    if (n > r->used)
        n = r->used;

    r->head = (r->head + n) % r->cap;
    r->used -= n;
    return n;
}

void o1_ring_clear(o1_ring *r)
{
    if (r == 0)
        return;

    r->head = 0;
    r->tail = 0;
    r->used = 0;
}

/* ----------------------------------------------------------------- the pacer */

void o1_pace_init(o1_pace *p, o1_rate rate, unsigned frame_bits)
{
    if (p == 0)
        return;

    p->acc_ns = 0;
    p->rate   = rate;
    p->bits   = frame_bits;
}

void o1_pace_set_rate(o1_pace *p, o1_rate rate)
{
    if (p == 0)
        return;

    p->rate   = rate;
    p->acc_ns = 0;   /* a rate change is a discontinuity, not a debt */
}

void o1_pace_set_frame(o1_pace *p, unsigned frame_bits)
{
    if (p == 0)
        return;

    p->bits   = frame_bits;
    p->acc_ns = 0;
}

/* rate is milli-baud, so:
 *     seconds per character = bits / (rate / 1000)
 *     nanoseconds           = bits * 1e12 / rate
 * At 300 baud and 10 bits that is 33,333,333 ns -- 33.3 ms, or 30 cps. */
uint64_t o1_pace_byte_ns(const o1_pace *p)
{
    if (p == 0 || p->rate == O1_PACE_UNSHAPED || p->bits == 0u)
        return 0;

    return ((uint64_t)p->bits * 1000000000000ULL) / (uint64_t)p->rate;
}

unsigned o1_pace_allow(o1_pace *p, uint64_t elapsed_ns)
{
    uint64_t per, n;

    if (p == 0)
        return 0;

    per = o1_pace_byte_ns(p);
    if (per == 0)
        return 0xFFFFFFFFu;   /* unshaped -- the caller caps it by what it holds */

    p->acc_ns += elapsed_ns;

    n = p->acc_ns / per;
    if (n > 0xFFFFFFFFu)
        n = 0xFFFFFFFFu;
    p->acc_ns -= n * per;
    return (unsigned)n;
}

/* ---------------------------------------------------------------- the buffer */

void o1_buffer_init(o1_buffer *b,
                    uint8_t *to_o1_store, unsigned to_o1_cap,
                    uint8_t *to_net_store, unsigned to_net_cap,
                    o1_overflow policy)
{
    if (b == 0)
        return;

    o1_ring_init(&b->to_o1, to_o1_store, to_o1_cap);
    o1_ring_init(&b->to_net, to_net_store, to_net_cap);

    /* 8-N-1 until told otherwise: it is the factory default, and the frame the
     * BIOS patch at 1FE9h is the exception to. */
    o1_pace_init(&b->pace, O1_PACE_UNSHAPED, 10u);

    b->policy  = policy;
    b->dropped = 0;
}

void o1_buffer_set_frame(o1_buffer *b, const o1_frame *f)
{
    if (b == 0)
        return;

    o1_pace_set_frame(&b->pace, o1_frame_bits(f));
}

void o1_buffer_set_rate(o1_buffer *b, o1_rate rate)
{
    if (b == 0)
        return;

    o1_pace_set_rate(&b->pace, rate);
}

/* One place for the policy, so both directions cannot drift apart. */
static unsigned ring_accept(o1_ring *r, o1_overflow policy, unsigned *dropped,
                            const uint8_t *src, unsigned n)
{
    unsigned pushed;

    if (policy == O1_OVERFLOW_DROP_OLDEST) {
        unsigned free_n = o1_ring_free(r);

        if (n > free_n)
            *dropped += o1_ring_drop(r, n - free_n);
    }

    pushed = o1_ring_push(r, src, n);
    *dropped += n - pushed;   /* nothing was held, so it was never accepted */
    return pushed;
}

unsigned o1_buffer_from_net(o1_buffer *b, const uint8_t *src, unsigned n)
{
    if (b == 0 || src == 0 || n == 0u)
        return 0;

    return ring_accept(&b->to_o1, b->policy, &b->dropped, src, n);
}

unsigned o1_buffer_from_o1(o1_buffer *b, const uint8_t *src, unsigned n)
{
    if (b == 0 || src == 0 || n == 0u)
        return 0;

    return ring_accept(&b->to_net, b->policy, &b->dropped, src, n);
}

unsigned o1_buffer_to_o1(o1_buffer *b, uint8_t *dst, unsigned n, uint64_t elapsed_ns)
{
    unsigned allow;

    if (b == 0 || dst == 0 || n == 0u)
        return 0;

    allow = o1_pace_allow(&b->pace, elapsed_ns);
    if (allow > n)
        allow = n;

    return o1_ring_pop(&b->to_o1, dst, allow);
}

unsigned o1_buffer_to_net(o1_buffer *b, uint8_t *dst, unsigned n)
{
    if (b == 0 || dst == 0 || n == 0u)
        return 0;

    return o1_ring_pop(&b->to_net, dst, n);
}
