/* The panel and the handshake -- the logic and the register bytes (#322, part of
 * #56).  See panel.h for why any of this exists; this file is the mechanism. */
#include <string.h>

#include "panel.h"

/* --------------------------------------------------------------- the 11 lamps
 *
 * The channel is the AW9523B's pin: 0-7 are P0_0-P0_7, 8-15 are P1_0-P1_7.  The
 * order of the table is `o1_lamp`'s order, and the test asserts it against the
 * table in `hardware/wifi-comm-pac/pinmap.md`.
 */
static const struct {
    int         channel;
    const char *name;
} lamp_tab[O1_LAMP_COUNT] = {
    { 0,  "WiFi radio" },   /* P0_0 */
    { 1,  "WiFi conn"  },   /* P0_1 */
    { 2,  "HS"         },   /* P0_2 */
    { 3,  "AA"         },   /* P0_3 */
    { 4,  "CD"         },   /* P0_4 */
    { 5,  "OH"         },   /* P0_5 */
    { 6,  "RD"         },   /* P0_6 */
    { 7,  "SD"         },   /* P0_7 */
    { 8,  "TR"         },   /* P1_0 -- open drain, series resistor */
    { 9,  "MR"         },   /* P1_1 */
    { 10, "RI"         },   /* P1_2 */
};

int o1_lamp_channel(o1_lamp lamp)
{
    if ((int)lamp < 0 || (int)lamp >= (int)O1_LAMP_COUNT)
        return -1;
    return lamp_tab[lamp].channel;
}

const char *o1_lamp_name(o1_lamp lamp)
{
    if ((int)lamp < 0 || (int)lamp >= (int)O1_LAMP_COUNT)
        return "?";
    return lamp_tab[lamp].name;
}

/* ---------------------------------------------------------- the four P1 lines
 *
 * U7's P1, per pinmap.md.  These are the *interface* part's P1 pins (channels
 * 8-11); the interface part is a separate chip and its port assignment is
 * independent of the panel's.
 */
static const struct {
    int         channel;
    int         output;
    const char *name;
} if_tab[O1_IF_COUNT] = {
    { 8,  1, "CTS" },   /* P1_0 -> P1 pin 5 */
    { 9,  1, "RI"  },   /* P1_1 -> P1 pin 9 */
    { 10, 1, "MSB" },   /* P1_2 -> P1 pin 4, open drain via 74LVC1G07 */
    { 11, 0, "MCB" },   /* P1_3 <- P1 pin 8 -- the one input */
};

int o1_if_channel(o1_if_line line)
{
    if ((int)line < 0 || (int)line >= (int)O1_IF_COUNT)
        return -1;
    return if_tab[line].channel;
}

const char *o1_if_name(o1_if_line line)
{
    if ((int)line < 0 || (int)line >= (int)O1_IF_COUNT)
        return "?";
    return if_tab[line].name;
}

int o1_if_is_output(o1_if_line line)
{
    if ((int)line < 0 || (int)line >= (int)O1_IF_COUNT)
        return 0;
    return if_tab[line].output;
}

/* ------------------------------------------------------------------ the panel */

void o1_panel_init(o1_panel *p)
{
    if (p == 0)
        return;

    memset(p, 0, sizeof *p);
    p->bright    = (uint8_t)O1_PANEL_DIM_DEFAULT;
    p->pulse_ms  = O1_PANEL_PULSE_MS_DEFAULT;
    p->dirty     = 1;
    p->have_last = 0;   /* the first plan writes everything, whatever it is */
}

void o1_panel_set_brightness(o1_panel *p, uint8_t dim)
{
    if (p == 0 || p->bright == dim)
        return;
    p->bright = dim;
    p->dirty  = 1;
}

void o1_panel_set_pulse_ms(o1_panel *p, unsigned ms)
{
    if (p == 0 || p->pulse_ms == ms)
        return;
    p->pulse_ms = ms;
}

void o1_panel_invalidate(o1_panel *p)
{
    if (p == 0)
        return;

    /* `have_last = 0` and not just `dirty`, and the difference is the whole point
     * of the call: an invalidate says *nothing on the wire can be trusted*.  A
     * failed write may have landed, may not have, or may have landed on the wrong
     * register -- so the next flush rewrites the entire panel rather than only
     * what it believes changed.  (Which is also the honest answer after a bus
     * glitch: the driver has no way to know what the part actually holds.) */
    p->have_last = 0u;
    p->dirty     = 1u;
}

void o1_panel_set(o1_panel *p, o1_lamp lamp, int on)
{
    uint8_t v;

    if (p == 0 || (int)lamp < 0 || (int)lamp >= (int)O1_LAMP_COUNT)
        return;

    v = on ? 1u : 0u;
    if (p->on[lamp] == v)
        return;

    p->on[lamp] = v;
    p->dirty    = 1;

    /* Clearing a lamp by hand also cancels its monostable window: otherwise a
     * lamp told to go dark would come back on when the window expired, which is
     * the kind of bug that only shows up on a busy link. */
    if (!v)
        p->pulse_until[lamp] = 0u;
}

int o1_panel_get(const o1_panel *p, o1_lamp lamp)
{
    if (p == 0 || (int)lamp < 0 || (int)lamp >= (int)O1_LAMP_COUNT)
        return 0;
    return p->on[lamp] ? 1 : 0;
}

void o1_panel_pulse(o1_panel *p, o1_lamp lamp, uint32_t now_ms)
{
    uint32_t until;

    if (p == 0 || (int)lamp < 0 || (int)lamp >= (int)O1_LAMP_COUNT)
        return;

    until = now_ms + (uint32_t)p->pulse_ms;

    /* Never *shorten* a window that is already open.  A burst of bytes at 9600
     * baud arrives faster than one window, and a lamp whose window restarted on
     * every byte would flicker at the byte rate -- which is the thing the
     * monostable exists to prevent. */
    if (p->pulse_until[lamp] == 0u ||
        (int32_t)(until - p->pulse_until[lamp]) > 0)
        p->pulse_until[lamp] = until;

    if (!p->on[lamp]) {
        p->on[lamp] = 1u;
        p->dirty    = 1;
    }
}

unsigned o1_panel_tick(o1_panel *p, uint32_t now_ms)
{
    unsigned i, expired = 0;

    if (p == 0)
        return 0;

    for (i = 0; i < (unsigned)O1_LAMP_COUNT; i++) {
        if (p->pulse_until[i] == 0u)
            continue;
        /* Signed difference, so a wrap of the millisecond counter is a small
         * positive number rather than a 49-day stall. */
        if ((int32_t)(now_ms - p->pulse_until[i]) < 0)
            continue;

        p->pulse_until[i] = 0u;
        p->on[i]          = 0u;
        p->dirty          = 1;
        expired++;
    }
    return expired;
}

void o1_panel_apply(o1_panel *p, const o1_modem_state *s, uint32_t now_ms)
{
    if (p == 0 || s == 0)
        return;

    (void)now_ms;   /* the level lamps do not need a clock; the monostable does */

    o1_panel_set(p, O1_LAMP_WIFI_RADIO,     s->wifi_started);
    o1_panel_set(p, O1_LAMP_WIFI_CONNECTED, s->wifi_connected);

    /* HS is the *feel* rate, not the ACIA rate -- see panel.h.  A feel of 0 is
     * the unshaped bypass (#318): that is "not shaped", not "fast", so it does
     * not light HS. */
    o1_panel_set(p, O1_LAMP_HS, s->feel >= O1_PANEL_HS_MBAUD);

    o1_panel_set(p, O1_LAMP_AA, s->auto_answer);
    o1_panel_set(p, O1_LAMP_CD, s->carrier);
    o1_panel_set(p, O1_LAMP_OH, s->off_hook);
    o1_panel_set(p, O1_LAMP_TR, s->terminal_ready);
    o1_panel_set(p, O1_LAMP_MR, s->modem_ready);
    o1_panel_set(p, O1_LAMP_RI, s->ring);

    /* RD and SD are deliberately **not** touched here.  They are driven by
     * `o1_panel_pulse` from the byte paths, and a level-driven writer racing a
     * monostable would clear the lamp mid-byte -- so the lamp would be dark
     * exactly while data is moving, which is the opposite of its job. */
}

/* ----------------------------------------------------------- the register side */

uint8_t o1_panel_dim_reg(unsigned channel)
{
    /* The datasheet's table 13 order, which is *not* pin order -- see panel.h.
     * A driver that assumed `0x20 + channel` would light the wrong lamp on four
     * of sixteen channels and still look like it worked. */
    if (channel <= 7u)
        return (uint8_t)(0x24u + channel);
    if (channel <= 11u)
        return (uint8_t)(0x20u + (channel - 8u));
    if (channel <= 15u)
        return (uint8_t)(0x2Cu + (channel - 12u));
    return 0u;   /* not a channel; 0 is the input register, which is read-only */
}

void o1_panel_dims(const o1_panel *p, uint8_t out[16])
{
    unsigned i;

    if (out == 0)
        return;

    for (i = 0; i < 16u; i++)
        out[i] = 0u;

    if (p == 0)
        return;

    for (i = 0; i < (unsigned)O1_LAMP_COUNT; i++) {
        int ch = lamp_tab[i].channel;

        if (ch < 0 || ch > 15)
            continue;
        if (p->on[i])
            out[ch] = p->bright;
    }
}

uint8_t o1_iface_out(const o1_modem_state *s)
{
    uint8_t v = 0u;

    if (s == 0)
        return 0u;

    /* P1_0 = CTS, P1_1 = RI, P1_2 = MSB.  MCB (P1_3) is an input and is not
     * here -- writing it would be writing a pin the machine drives. */
    if (s->cts)
        v |= 0x01u;
    if (s->ring)
        v |= 0x02u;
    if (s->msb)
        v |= 0x04u;

    return v;
}

/* --------------------------------------------------------------- the init order
 *
 * Mode before direction before dim.  A pin in LED mode ignores the output
 * register, so a dim register written before the mode is a lamp whose state
 * depends on what the part's power-on value happened to be -- which is exactly
 * the kind of "sometimes it works" that costs a day.
 *
 * The chip id is *read* rather than written (0x10 must answer 0x23), so it is not
 * in these lists: the glue reads it once and refuses to continue on a mismatch.
 */
unsigned o1_panel_init_writes(o1_reg_write *out, unsigned out_n)
{
    unsigned i, n = 0;

    /* reset, GCR (P0 push-pull), LED mode on both ports, both ports output,
     * interrupts masked on both ports, then sixteen dims to zero. */
    static const o1_reg_write head[] = {
        { O1_AW9523_REG_RESET,    0x00u },
        { O1_AW9523_REG_GCR,      O1_AW9523_GCR_P0_PUSHPULL },
        { O1_AW9523_REG_LEDMODE0, 0x00u },   /* 0 = LED mode, both ports */
        { O1_AW9523_REG_LEDMODE0 + 1u, 0x00u },
        { O1_AW9523_REG_CONFIG0,  0x00u },   /* 0 = output, both ports */
        { O1_AW9523_REG_CONFIG0 + 1u, 0x00u },
        { O1_AW9523_REG_INTEN0,   0xFFu },   /* 1 = disabled; the panel does not
                                              * interrupt -- it is an output bank */
        { O1_AW9523_REG_INTEN0 + 1u, 0xFFu },
    };

    if (out == 0)
        return 0u;
    if (out_n < (unsigned)(sizeof head / sizeof head[0]) + 16u)
        return 0u;

    for (i = 0; i < (unsigned)(sizeof head / sizeof head[0]); i++)
        out[n++] = head[i];

    for (i = 0; i < 16u; i++) {
        out[n].reg = o1_panel_dim_reg(i);
        out[n].val = 0x00u;
        n++;
    }
    return n;
}

unsigned o1_iface_init_writes(o1_reg_write *out, unsigned out_n)
{
    static const o1_reg_write seq[] = {
        { O1_AW9523_REG_RESET,         0x00u },
        { O1_AW9523_REG_LEDMODE0 + 1u, 0xFFu },  /* 1 = GPIO mode on all of P1 */
        { O1_AW9523_REG_CONFIG0 + 1u,  0x08u },  /* P1_3 in, P1_0..P1_2 out */
        { O1_AW9523_REG_INTEN0,        0xFFu },
        /* P1_3 is MCB, the one input, and it is *enabled*: the interrupt is what
         * the INTN pin (GPIO21) is for.  1 means disabled, so the mask is the
         * complement of the one bit we want. */
        { O1_AW9523_REG_INTEN0 + 1u,   0xF7u },
        { O1_AW9523_REG_OUTPUT0 + 1u,  0x00u },
    };

    if (out == 0 || out_n < (unsigned)(sizeof seq / sizeof seq[0]))
        return 0u;

    {
        unsigned i;

        for (i = 0; i < (unsigned)(sizeof seq / sizeof seq[0]); i++)
            out[i] = seq[i];
        return (unsigned)(sizeof seq / sizeof seq[0]);
    }
}

/* ---------------------------------------------------------------- the flush */

unsigned o1_panel_flush(o1_panel *p, const o1_modem_state *s, o1_panel_plan *plan)
{
    uint8_t  dims[16];
    unsigned i;

    if (p == 0 || s == 0 || plan == 0)
        return 0u;

    plan->n_dim   = 0u;
    plan->n_iface = 0u;

    if (!p->dirty)
        return 0u;

    o1_panel_dims(p, dims);

    for (i = 0u; i < 16u; i++) {
        if (p->have_last && p->last_dim[i] == dims[i])
            continue;

        plan->dim[plan->n_dim].reg = o1_panel_dim_reg(i);
        plan->dim[plan->n_dim].val = dims[i];
        plan->n_dim++;

        /* Recorded before the write succeeds, deliberately.  A failed write is
         * reported by the caller with `o1_panel_invalidate`, and the alternative
         * -- recording on success -- needs an acknowledgement the glue would have
         * to feed back in for no gain. */
        p->last_dim[i] = dims[i];
    }

    {
        uint8_t iface = o1_iface_out(s);

        if (!p->have_last || p->last_iface != iface) {
            plan->iface[plan->n_iface].reg =
                (uint8_t)(O1_AW9523_REG_OUTPUT0 + 1u);
            plan->iface[plan->n_iface].val = iface;
            plan->n_iface++;
            p->last_iface = iface;
        }
    }

    p->have_last = 1u;
    p->dirty     = 0u;

    return plan->n_dim + plan->n_iface;
}
