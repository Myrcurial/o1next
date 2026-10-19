/* The double-sided baud buffer (#318, part of #56).
 *
 * What it replaces
 * ----------------
 * Zimodem today is rate-limited by its own serial side.  `serout.ino` gates its
 * writes on
 *
 *     ((SER_BUFSIZE - HWSerial.availableForWrite()) < dequeSize)
 *
 * with `dequeSize = 1 + baudRate / INTERNAL_FLOW_CONTROL_DIV` -- a sender-side
 * throttle **keyed to the serial baud**, so a slow or drifting terminal
 * back-pressures the TCP session.  That is the coupling #318 exists to remove.
 *
 * What replaces it
 * ----------------
 * Two bounded rings, one per direction, with pacing between them and nothing
 * else:
 *
 *   socket -> machine   `to_o1`, released at the machine's rate (the pacer)
 *   machine -> socket   `to_net`, batched, and **never paced** -- the socket is
 *                       not asked to wait on the ACIA, which is the whole point
 *
 * Drift is absorbed here and never reaches the link: the factory 600/2400 jumper
 * is really 650/2600 (~8.3% fast), and turbo doubles whatever is in use (#55).
 *
 * The bypass, and why it is the same knob as the rate
 * ---------------------------------------------------
 * **A bounded buffer needs an overflow rule, and file transfer is the case that
 * breaks it.**  XMODEM and Kermit carry their own timers and window; re-clocking
 * a binary transfer through a rate shaper fails it.  So there are two things a
 * caller can want from the machine-bound side -- a paced, period-feeling session,
 * or an unshaped pipe -- and they are the same knob: **rate 0 means unshaped**.
 * One mechanism, not two flags that can disagree.  Changing the rate resets the
 * pacer's carry, because a rate change is a discontinuity and not a debt.
 *
 * The policy is a parameter, not a default
 * ----------------------------------------
 * `O1_OVERFLOW_REFUSE` keeps what has already arrived and refuses the new; it is
 * the right answer for a transfer, where losing the middle of a block is worse
 * than stalling.  `O1_OVERFLOW_DROP_OLDEST` keeps the newest, and is the right
 * answer for a terminal screen, where the newest line is what the operator is
 * looking at.  Both count what they lost, because a buffer that silently drops is
 * a buffer nobody can debug.
 *
 * What is not here
 * ----------------
 * No sockets, no UART, no ESP32 headers, no clock -- `elapsed_ns` is handed in, so
 * the tests drive a whole session in microseconds of imaginary time and the
 * firmware drives it from whatever timer it has.  This is the mechanism; the
 * wiring is the fork's.
 */
#ifndef O1_MODEM_BUFFER_H
#define O1_MODEM_BUFFER_H

#include <stdint.h>

#include "frame.h"
#include "rate.h"

/* ------------------------------------------------------------------ the ring */

typedef struct {
    uint8_t *buf;
    unsigned cap;
    unsigned head;   /* read position  */
    unsigned tail;   /* write position */
    unsigned used;
} o1_ring;

void     o1_ring_init(o1_ring *r, uint8_t *storage, unsigned cap);
unsigned o1_ring_used(const o1_ring *r);
unsigned o1_ring_free(const o1_ring *r);
unsigned o1_ring_push(o1_ring *r, const uint8_t *src, unsigned n);
unsigned o1_ring_pop(o1_ring *r, uint8_t *dst, unsigned n);

/* Discard `n` from the *oldest* end -- what DROP_OLDEST needs.  Returns the
 * number actually discarded, which is less than `n` when there was less held. */
unsigned o1_ring_drop(o1_ring *r, unsigned n);

void     o1_ring_clear(o1_ring *r);

/* ----------------------------------------------------------------- the pacer */

/* Unshaped.  Also the transfer bypass -- see the note above. */
#define O1_PACE_UNSHAPED 0u

typedef struct {
    uint64_t acc_ns;  /* time accumulated but not yet spent */
    o1_rate  rate;    /* milli-baud, or O1_PACE_UNSHAPED */
    unsigned bits;    /* bits per character, from o1_frame_bits() */
} o1_pace;

void o1_pace_init(o1_pace *p, o1_rate rate, unsigned frame_bits);
void o1_pace_set_rate(o1_pace *p, o1_rate rate);
void o1_pace_set_frame(o1_pace *p, unsigned frame_bits);

/* Nanoseconds one character costs at the configured rate; 0 when unshaped. */
uint64_t o1_pace_byte_ns(const o1_pace *p);

/* How many whole characters may be released now, `elapsed_ns` after the last
 * call?  The remainder is carried, so pacing does not drift.  Unshaped returns
 * UINT_MAX -- the caller caps it by what it is actually holding. */
unsigned o1_pace_allow(o1_pace *p, uint64_t elapsed_ns);

/* ---------------------------------------------------------------- the buffer */

typedef enum {
    O1_OVERFLOW_REFUSE = 0,   /* keep what has arrived; refuse the new */
    O1_OVERFLOW_DROP_OLDEST   /* keep the new; discard the oldest */
} o1_overflow;

typedef struct {
    o1_ring     to_o1;    /* socket -> machine, paced */
    o1_ring     to_net;   /* machine -> socket, batched */
    o1_pace     pace;
    o1_overflow policy;
    unsigned    dropped;  /* characters lost to the policy, both rings */
} o1_buffer;

void o1_buffer_init(o1_buffer *b,
                    uint8_t *to_o1_store, unsigned to_o1_cap,
                    uint8_t *to_net_store, unsigned to_net_cap,
                    o1_overflow policy);

/* The machine's frame and rate.  A rate of O1_PACE_UNSHAPED is the bypass. */
void o1_buffer_set_frame(o1_buffer *b, const o1_frame *f);
void o1_buffer_set_rate(o1_buffer *b, o1_rate rate);

/* Characters arriving from the socket.  Returns how many were accepted; the rest
 * are counted in `dropped`. */
unsigned o1_buffer_from_net(o1_buffer *b, const uint8_t *src, unsigned n);

/* Characters released toward the machine, paced.  `elapsed_ns` is the time since
 * the previous call.  Returns the count released. */
unsigned o1_buffer_to_o1(o1_buffer *b, uint8_t *dst, unsigned n, uint64_t elapsed_ns);

/* Characters arriving from the machine -- batched, never paced. */
unsigned o1_buffer_from_o1(o1_buffer *b, const uint8_t *src, unsigned n);

/* Characters drained toward the socket -- immediately, never paced. */
unsigned o1_buffer_to_net(o1_buffer *b, uint8_t *dst, unsigned n);

#endif /* O1_MODEM_BUFFER_H */
