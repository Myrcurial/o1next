/* The rate table and the lock -- see rate.h for why (#319, part of #56). */
#include "rate.h"

/* Ascending, and every entry earns its place: the 16 OSBAUD rates, the two
 * *actual* J1-out rates (650/2600 -- not the 600/2400 on the panel), and the two
 * turbo doublings that are not already in the list (1300, 5200).  Turbo's other
 * doublings land on rates that are here anyway -- turbo 300 is 600, turbo 1200 is
 * 2400, turbo 2400 is 4800, turbo 9600 is 19200 -- so they cost nothing to cover.
 *
 * A turbo-doubled rate that is *not* here (100, 220, 269, 4000, 10400, 14400,
 * 38400) snaps to a neighbour or to nothing, and the verify step catches it.  Add
 * a row if a machine is ever found in one; do not add rows speculatively, because
 * every row is a chance to mis-lock. */
const o1_rate_cand o1_rate_table[] = {
    {    50000u, "OSBAUD 50 -- the slow end of the 16-rate list" },
    {    75000u, "OSBAUD 75" },
    {   110000u, "OSBAUD 110 -- the ASR33 rate, and below ATB's floor of 128" },
    {   134500u, "OSBAUD 134.5 -- the one non-integer rate in the set" },
    {   150000u, "OSBAUD 150" },
    {   300000u, "stock J1 in, the ACIA's /64 tap" },
    {   600000u, "OSBAUD 600; also turbo 300" },
    {   650000u, "J1 out, the /64 tap -- *marked* 600, actually ~8.3% fast" },
    {  1200000u, "stock J1 in, the /16 tap -- Zimodem's default, so the out-of-box case" },
    {  1300000u, "turbo 650 -- J1 out with the 2x business turbo (#55)" },
    {  1800000u, "OSBAUD 1800" },
    {  2000000u, "OSBAUD 2000" },
    {  2400000u, "factory mod (Fig 4.4); also OSBAUD 2400; also turbo 1200" },
    {  2600000u, "J1 out, the /16 tap -- *marked* 2400, actually ~8.3% fast" },
    {  3600000u, "OSBAUD 3600" },
    {  4800000u, "OSBAUD 4800; also turbo 2400" },
    {  5200000u, "turbo 2600 -- J1 out with the 2x business turbo (#55)" },
    {  7200000u, "OSBAUD 7200" },
    {  9600000u, "factory mod; also OSBAUD 9600; the HS threshold (#320)" },
    { 19200000u, "OSBAUD 19200 -- the fast end; also turbo 9600" },
};

const unsigned o1_rate_count = (unsigned)(sizeof o1_rate_table / sizeof o1_rate_table[0]);

int32_t o1_rate_error_ppm(o1_rate measured, o1_rate cand)
{
    long long diff;

    if (measured == 0u)
        return 0;

    diff = (long long)cand - (long long)measured;
    return (int32_t)((diff * 1000000LL) / (long long)measured);
}

int o1_rate_snap(o1_rate measured, uint32_t tol_ppm)
{
    unsigned i;
    int      best = -1;
    int32_t  best_err = 0;

    if (measured == 0u)
        return -1;

    for (i = 0; i < o1_rate_count; i++) {
        int32_t err = o1_rate_error_ppm(measured, o1_rate_table[i].mbaud);

        if (err < 0)
            err = -err;
        if ((uint32_t)err > tol_ppm)
            continue;
        if (best < 0 || err < best_err) {
            best = (int)i;
            best_err = err;
        }
    }
    return best;
}

/* Insertion sort by absolute error, nearest first.  Ties keep table order, so a
 * measurement exactly between two candidates ranks the slower one first -- and
 * the caller's verify step is what actually decides. */
unsigned o1_rate_rank(o1_rate measured, int *out, unsigned out_n)
{
    unsigned i, n = 0;

    if (out == 0)
        return 0;

    for (i = 0; i < o1_rate_count && n < out_n; i++) {
        int32_t  err = o1_rate_error_ppm(measured, o1_rate_table[i].mbaud);
        unsigned j;

        if (err < 0)
            err = -err;

        j = n;
        while (j > 0) {
            int32_t prev = o1_rate_error_ppm(measured, o1_rate_table[out[j - 1]].mbaud);

            if (prev < 0)
                prev = -prev;
            if (prev <= err)
                break;
            out[j] = out[j - 1];
            j--;
        }
        out[j] = (int)i;
        n++;
    }
    return n;
}

int o1_rate_stable(const o1_rate *hist, unsigned n, uint32_t tol_ppm)
{
    unsigned i;

    if (hist == 0 || n < 2u)
        return 0;

    for (i = 1; i < n; i++) {
        int32_t err = o1_rate_error_ppm(hist[0], hist[i]);

        if (err < 0)
            err = -err;
        if ((uint32_t)err > tol_ppm)
            return 0;
    }
    return 1;
}

void o1_rate_lock_init(o1_rate_lock *l, unsigned need, uint32_t tol_ppm)
{
    if (l == 0)
        return;

    l->state   = O1_LOCK_IDLE;
    l->cand    = -1;
    l->samples = 0;
    l->need    = (need < 1u) ? 1u : need;
    l->tol_ppm = tol_ppm;
}

void o1_rate_lock_reset(o1_rate_lock *l)
{
    if (l == 0)
        return;

    l->state   = O1_LOCK_IDLE;
    l->cand    = -1;
    l->samples = 0;
}

int o1_rate_lock_feed(o1_rate_lock *l, o1_rate measured)
{
    int cand;

    if (l == 0)
        return 0;

    if (l->state == O1_LOCK_LOCKED) {
        int32_t err;

        /* Re-check, because a machine can be re-jumpered -- or drop into turbo --
         * under a live session.  Same rate: nothing happened.  Different rate:
         * the lock is gone and the count starts again. */
        err = o1_rate_error_ppm(measured, o1_rate_table[l->cand].mbaud);
        if (err < 0)
            err = -err;
        if ((uint32_t)err <= l->tol_ppm)
            return 0;
        o1_rate_lock_reset(l);
    }

    cand = o1_rate_snap(measured, l->tol_ppm);
    if (cand < 0) {
        /* Nowhere near the table.  It must not leave a half-built count behind:
         * two bad samples either side of a good one must not add up to a lock. */
        l->cand    = -1;
        l->samples = 0;
        l->state   = O1_LOCK_REFUSED;
        return 0;
    }

    if (cand == l->cand) {
        l->samples++;
    } else {
        l->cand    = cand;
        l->samples = 1;
    }

    if (l->samples >= l->need) {
        l->state = O1_LOCK_LOCKED;
        return 1;
    }

    l->state = O1_LOCK_IDLE;
    return 0;
}

o1_rate o1_rate_lock_value(const o1_rate_lock *l)
{
    if (l == 0 || l->state != O1_LOCK_LOCKED || l->cand < 0)
        return 0;
    return o1_rate_table[l->cand].mbaud;
}

const char *o1_rate_lock_note(const o1_rate_lock *l)
{
    if (l == 0 || l->state != O1_LOCK_LOCKED || l->cand < 0)
        return 0;
    return o1_rate_table[l->cand].note;
}
