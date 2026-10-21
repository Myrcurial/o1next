/* The rates an Osborne 1 can actually present, and the lock that finds one (#319).
 *
 * Why a table, and not a calculation
 * ---------------------------------
 * The module cannot read the machine's baud divider -- the rate is *hardware*
 * (UC3, and on a modified machine OSBAUD; docs/o1-modem-serial.md).  So it has to
 * be **measured** and then matched against the rates a real machine can be in.
 * That set is small, documented, and -- the point -- **not the set printed on the
 * machine**:
 *
 *   stock, J1 in        300 / 1200
 *   J1 out              650 / 2600    <- marked 600 / 2400, actually ~8.3% fast
 *   factory mod (4.4)   2400 / 9600
 *   OSBAUD fitted       any of 16, 50 .. 19200, including 110 and 134.5
 *   turbo (#55)         the machine's own rate, doubled
 *
 * The 8.3% is the whole reason this file exists.  Over a 10-bit frame it is 0.83
 * of a bit -- marginal to failing -- so a table built from the panel marking
 * mis-decodes a J1-out machine.  **650 and 2600 are the real rates**, and the
 * table carries them instead of 600 and 2400.
 *
 * Why the default tolerance is 2%
 * -------------------------------
 * The table's tightest spacing is **8.33%** -- 600 against 650, 1200 against 1300,
 * 2400 against 2600, 4800 against 5200 -- so anything below 4.17% separates them.
 * The measurement is far better than that: a 1 us RMT tick is 0.03% of a 300-baud
 * bit and 1.9% of a 19200-baud bit, and averaging over the pulses in one byte
 * divides the quantisation by the sample count.  So 2% is chosen for **margin,
 * not need**, and it is a parameter: a caller with a better measurement tightens
 * it, and one with a worse measurement had better not.
 *
 * What is deliberately not here
 * -----------------------------
 * No floats (rates are integer **milli-baud**, so 134.5 is exact), no ESP32
 * headers, no UART -- this is the arithmetic, and `test_o1modem.c` is the proof.
 * The RMT/PCNT front end that *produces* the measurement is #319's remaining half,
 * and it lands in the fork, not here.
 *
 * Why the ladder
 * --------------
 * `o1_rate_snap()` answers "which rate is this?" when the measurement is good.
 * When it is not, the caller wants an *order* to try, not a refusal: the machine
 * is sending real bytes, so a wrong rate produces garbage immediately and the
 * caller's verify step rejects it.  `o1_rate_rank()` is that order -- every
 * candidate, nearest to the measurement first -- and it is how a bad measurement
 * still ends in a lock.
 */
#ifndef O1_MODEM_RATE_H
#define O1_MODEM_RATE_H

#include <stdint.h>

/* The core is plain C and the sketch is C++: without this the linker looks for a
 * mangled name and the whole core reads as undefined symbols, which looks like a
 * missing file rather than a linkage mistake. */
#ifdef __cplusplus
extern "C" {
#endif

/* Milli-baud.  300 baud is 300000, 134.5 baud is 134500 -- exact, no rounding. */
typedef uint32_t o1_rate;

/* 2% -- see the note above on why the tightest table spacing is 8.33%. */
#define O1_RATE_TOL_PPM_DEFAULT 20000u

/* One entry of the table, with the reason it is in it. */
typedef struct {
    o1_rate     mbaud;
    const char *note;
} o1_rate_cand;

/* The rates, ascending.  `o1_rate_count` is the length. */
extern const o1_rate_cand o1_rate_table[];
extern const unsigned     o1_rate_count;

/* Signed relative error of `cand` against `measured`, in ppm:
 * (cand - measured) / measured * 1e6.  `measured` of 0 is 0, not a division. */
int32_t o1_rate_error_ppm(o1_rate measured, o1_rate cand);

/* The nearest table entry within `tol_ppm`, or -1 if none is.  The index is the
 * return, because the caller wants the *candidate* (its note, its neighbours),
 * not just the number. */
int o1_rate_snap(o1_rate measured, uint32_t tol_ppm);

/* Every candidate index, nearest-to-`measured` first.  Writes at most `out_n`
 * and returns how many were written -- the caller passes `o1_rate_count`.
 * This is the ladder: walk it and let the verify step decide. */
unsigned o1_rate_rank(o1_rate measured, int *out, unsigned out_n);

/* Do all `n` measurements agree within `tol_ppm`?  n < 2 is not agreement. */
int o1_rate_stable(const o1_rate *hist, unsigned n, uint32_t tol_ppm);

/* The lock: `need` consecutive measurements that snap to the *same* candidate.
 *
 * Stability is a proxy for verification, and deliberately so -- the real check is
 * decoding bytes, which needs a UART and belongs to the integration, not to this
 * arithmetic.  What this state machine guarantees is the property the integration
 * depends on: **it refuses rather than mis-locks**, and it says which it did.
 *
 * A candidate the measurement is nowhere near never locks; a measurement that
 * wanders between two candidates never locks; only `need` in a row on one
 * candidate does. */
typedef enum {
    O1_LOCK_IDLE = 0,  /* nothing yet */
    O1_LOCK_LOCKED,    /* `cand` is the answer */
    O1_LOCK_REFUSED    /* the most recent measurement snapped to no candidate */
} o1_lock_state;

typedef struct {
    o1_lock_state state;
    int           cand;     /* table index, or -1 */
    unsigned      samples;  /* consecutive agreements on `cand` */
    unsigned      need;     /* how many are required */
    uint32_t      tol_ppm;
} o1_rate_lock;

void o1_rate_lock_init(o1_rate_lock *l, unsigned need, uint32_t tol_ppm);

/* Feed one measurement.  Returns 1 on the call that reaches LOCKED, else 0.
 * Feeding after LOCKED re-checks: a measurement that no longer snaps to `cand`
 * drops the lock back to IDLE and starts counting again. */
int o1_rate_lock_feed(o1_rate_lock *l, o1_rate measured);

/* Back to IDLE with nothing remembered -- what a rate change or a re-lock does. */
void o1_rate_lock_reset(o1_rate_lock *l);

/* The locked rate in milli-baud, or 0 when not locked. */
o1_rate o1_rate_lock_value(const o1_rate_lock *l);

/* The locked candidate's note, or NULL when not locked. */
const char *o1_rate_lock_note(const o1_rate_lock *l);

#ifdef __cplusplus
} /* extern "C" */
#endif

#endif /* O1_MODEM_RATE_H */
