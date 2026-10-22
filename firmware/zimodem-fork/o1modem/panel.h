/* The panel and the handshake -- eleven lamps and four P1 lines on two AW9523B
 * expanders (#322, part of #56; the board is #324/#325).
 *
 * Why this is not `SUPPORT_LED_PINS`
 * ----------------------------------
 * Upstream has three lamps on three GPIO -- WiFi, HS and AA -- and the switch
 * that enables them is commented out.  `DEFAULT_HS_BAUD` is 38400, so upstream's
 * HS means "faster than anything this machine can do", and there is no CD, no OH,
 * no RD, no SD, no TR, no MR and no RI at all.  This is therefore **new state**,
 * not new wiring: eleven lamps that each have to be told what they mean, and four
 * P1 handshake lines that only exist on this board.
 *
 * The bank, and where each lamp gets its truth
 * --------------------------------------------
 * From #322, which is the maintainer's own list plus the two WiFi lamps.  Every
 * row is a *source*, not a decoration -- a lamp with no source is a lamp that
 * lies, and a panel that lies is worse than a dark panel:
 *
 *   WiFi radio    STA started -- `WL_CONNECTED` is not the same thing
 *   WiFi conn     `WiFi.status() == WL_CONNECTED`
 *   HS            the **feel** rate >= 9600 (#320) -- *not* the ACIA rate
 *   AA            the S0 register / listener state (`ATAn`)
 *   CD            socket state -- the DE-9 has no DCD, so there is nothing
 *                 else it could be (pinmap.md, "Open before layout" 3)
 *   OH            a channel or socket is open
 *   RD            bytes leaving the machine, pulse-stretched
 *   SD            bytes arriving for the machine, pulse-stretched
 *   TR            **MCB, P1 pin 8** -- the machine's "low suppresses output"
 *                 line is its DTR-equivalent
 *   MR            set once the modem's own init has completed
 *   RI            the RING path -- and P1 pin 9, which the machine sees
 *
 * **HS follows the feel rate, and that is the whole point of #320.**  Upstream
 * keys HS to `baudRate`, which is the ACIA's rate -- so a machine strapped for
 * 300 baud could never light it.  The feel rate is what the *operator* asked for,
 * so it is what the lamp reports.
 *
 * Why RD and SD are latched
 * -------------------------
 * A byte at 9600 baud is about a millisecond, which is a flicker nobody sees and
 * an interrupt nobody wants.  So RD and SD are **monostable in software**: a byte
 * starts a `pulse_ms` window and the lamp stays lit to the end of it.  They are
 * indicators, not a scope, and the stretch is a parameter rather than a constant
 * because "how long should a byte look like" is a taste question.
 *
 * Why the panel survives a hang
 * -----------------------------
 * The AW9523B **holds its outputs**.  Charlieplexing, or anything that needs the
 * CPU to keep refreshing, goes dark when the firmware stops -- which is exactly
 * when the panel is most useful.  Here a hung firmware leaves the last state it
 * wrote, still readable, so "it froze with CD and OH lit" is a diagnosis rather
 * than a shrug.  That property is why the driver **writes on change only**: a
 * panel that is rewritten every loop is a panel that goes blank in the failure it
 * was meant to report.
 *
 * What is deliberately not here
 * -----------------------------
 * No I2C, no Arduino, no `Wire`.  This file produces **register bytes** and the
 * fork's glue writes them -- so the lamp logic, the pulse stretch and the
 * channel-to-register mapping are all provable on a host with no board attached.
 * The register map is in `panel.c` with its sources named, because a wrong
 * address is a wrong board and a comment is cheaper than a respin.
 */
#ifndef O1_MODEM_PANEL_H
#define O1_MODEM_PANEL_H

#include <stdint.h>

#include "rate.h"

/* The core is plain C and the sketch is C++: without this the linker looks for a
 * mangled name and the whole core reads as undefined symbols, which looks like a
 * missing file rather than a linkage mistake. */
#ifdef __cplusplus
extern "C" {
#endif

/* ------------------------------------------------------------- the 11 lamps
 *
 * The channel numbers are the *expander's* pins, and they come from
 * `hardware/wifi-comm-pac/pinmap.md` -- U6, the panel part at `0x58`:
 *
 *   P0_0 .. P0_7   the eight push-pull constant-current lamps
 *   P1_0 .. P1_2   TR, MR and RI -- P1 is open-drain only on this part, which
 *                  is why those three carry series resistors
 *
 * `test_o1modem.c` asserts this map against the pinmap's table, because a lamp on
 * the wrong channel is a panel that reads wrong and nothing else would catch it.
 */
typedef enum {
    O1_LAMP_WIFI_RADIO = 0,   /* P0_0 */
    O1_LAMP_WIFI_CONNECTED,   /* P0_1 */
    O1_LAMP_HS,               /* P0_2 -- >= 9600, per the feel rate */
    O1_LAMP_AA,               /* P0_3 */
    O1_LAMP_CD,               /* P0_4 */
    O1_LAMP_OH,               /* P0_5 */
    O1_LAMP_RD,               /* P0_6 */
    O1_LAMP_SD,               /* P0_7 */
    O1_LAMP_TR,               /* P1_0 */
    O1_LAMP_MR,               /* P1_1 */
    O1_LAMP_RI,               /* P1_2 */
    O1_LAMP_COUNT
} o1_lamp;

/* The expander channel for a lamp, or -1 if it is not on the panel part. */
int o1_lamp_channel(o1_lamp lamp);

/* "WiFi radio", "HS", ... -- for logs and the web UI.  Never NULL. */
const char *o1_lamp_name(o1_lamp lamp);

/* -------------------------------------------------------- the four P1 lines
 *
 * U7, the interface part at `0x59`.  Three are outputs and **MCB is an input**,
 * which is the one that has to be read rather than written -- and the reason the
 * interface expander needs an `INTN` line at all (pinmap.md, GPIO21).
 */
typedef enum {
    O1_IF_CTS = 0,   /* P1_0 -> 74LVC4T245 -> P1 pin 5 */
    O1_IF_RI,        /* P1_1 -> 74LVC4T245 -> P1 pin 9 */
    O1_IF_MSB,       /* P1_2 -> 74LVC1G07 (open drain) -> P1 pin 4 */
    O1_IF_MCB,       /* P1_3 <- 74LVC4T245 <- P1 pin 8 -- an INPUT */
    O1_IF_COUNT
} o1_if_line;

int o1_if_channel(o1_if_line line);
const char *o1_if_name(o1_if_line line);

/* Is this line one of the module's outputs?  MCB is not. */
int o1_if_is_output(o1_if_line line);

/* ------------------------------------------------------- what the panel shows
 *
 * One struct, filled by the firmware from whatever it already knows, so the
 * mapping from modem state to lamp state lives here rather than being spread
 * across the places that *change* the state.  That is deliberate: eleven lamps
 * updated from eleven call sites is eleven chances to miss one, and the lamp that
 * gets missed is the one that matters during a fault.
 */
typedef struct {
    int      wifi_started;    /* STA started -- not the same as connected */
    int      wifi_connected;
    o1_rate  feel;            /* the "feel" rate, milli-baud (#320); 0 = unshaped */
    int      auto_answer;     /* S0 / listener state */
    int      carrier;         /* socket state -- there is no DCD on P1 */
    int      off_hook;        /* a channel is open */
    int      terminal_ready;  /* MCB, P1 pin 8 -- the machine's DTR-equivalent */
    int      modem_ready;     /* the modem's own init has completed */
    int      ring;            /* the RING path -- the machine sees this on P1 pin 9 */
    int      cts;             /* the flow-control line, P1 pin 5 */
    int      msb;             /* P1 pin 4 -- what the machine reads as carrier */
} o1_modem_state;

/* HS is "fast", and #56 decided that means **>= 9600**.  Milli-baud, so it is
 * comparable with `o1_rate` and 134.5 baud is not a rounding error. */
#define O1_PANEL_HS_MBAUD 9600000u

/* How long a byte keeps RD or SD lit.  #322 says 50-100 ms; 75 is the middle and
 * it is a parameter because it is a taste question, not a specification. */
#define O1_PANEL_PULSE_MS_DEFAULT 75u

/* Full brightness, out of the AW9523B's 256 steps.  **Not 255**, and the reason
 * is a current budget rather than a look: eleven lamps at 5 mA is 55 mA sustained
 * through P1 pin 7, which is 1.2 V of sag before the ESP32 draws anything
 * (pinmap.md).  2-3 mA modern lamps are plenty and constant-current lets us set
 * it, so the default is a quarter of the range. */
#define O1_PANEL_DIM_DEFAULT 64u

typedef struct {
    /* Logical state.  `on` is what the operator asked for; `pulse_until` is the
     * monostable window for RD and SD, and 0 means "not pulsing". */
    uint8_t  on[O1_LAMP_COUNT];
    uint32_t pulse_until[O1_LAMP_COUNT];

    /* Configuration. */
    uint8_t  bright;      /* dim value for a lamp that is on */
    unsigned pulse_ms;    /* RD/SD stretch */

    /* What the last flush actually put on the wire, so a change is detectable and
     * an unchanged panel costs no I2C traffic at all.  `dirty` is set by anything
     * that changes a lamp and cleared by a flush that succeeds. */
    uint8_t  last_dim[16];
    uint8_t  last_iface;
    uint8_t  have_last;   /* 0 until the first flush -- forces one */
    uint8_t  dirty;
} o1_panel;

void o1_panel_init(o1_panel *p);

/* Configure the two knobs.  A brightness of 0 is legal and means dark. */
void o1_panel_set_brightness(o1_panel *p, uint8_t dim);
void o1_panel_set_pulse_ms(o1_panel *p, unsigned ms);

/* Logical lamp control. */
void o1_panel_set(o1_panel *p, o1_lamp lamp, int on);
int  o1_panel_get(const o1_panel *p, o1_lamp lamp);

/* The monostable: light RD or SD for `pulse_ms` from `now_ms`.  Re-pulsing
 * extends the window rather than restarting it, so a burst of bytes is one
 * steady lamp rather than a stutter. */
void o1_panel_pulse(o1_panel *p, o1_lamp lamp, uint32_t now_ms);

/* Expire the pulses.  Returns how many lamps went dark, so a caller that wants to
 * skip the flush when nothing changed can. */
unsigned o1_panel_tick(o1_panel *p, uint32_t now_ms);

/* The whole panel, from the modem's own state.  This is the table in the header
 * comment, and nothing else writes the lamps in normal operation. */
void o1_panel_apply(o1_panel *p, const o1_modem_state *s, uint32_t now_ms);

/* ----------------------------------------------------------- the register side
 *
 * The AW9523B's dimming registers are **not** in pin order, and that is the one
 * piece of this part that a reader will not guess.  From the datasheet's table 13
 * (as implemented by Adafruit's `Adafruit_AW9523::analogWrite` and by the Linux
 * `pinctrl-aw9523` driver):
 *
 *   pin  0..7   ->  0x24 .. 0x2B
 *   pin  8..11  ->  0x20 .. 0x23
 *   pin 12..15  ->  0x2C .. 0x2F
 *
 * So channels 8-11 sit *below* 0x24 and 12-15 sit above 0x2B.  A driver that
 * assumed `0x20 + pin` would light the wrong lamp on four of sixteen channels --
 * and, worse, would light *a* lamp, so it would look like it worked.
 */
uint8_t o1_panel_dim_reg(unsigned channel);

/* The dim values for all sixteen channels of the panel part, in channel order.
 * `out` must hold 16.  A lamp that is on gets `bright`; one that is not gets 0. */
void o1_panel_dims(const o1_panel *p, uint8_t out[16]);

/* The interface part's P1 output byte: CTS, RI and MSB as bits 0, 1 and 2.
 * MCB is an input and is deliberately not in here. */
uint8_t o1_iface_out(const o1_modem_state *s);

/* The interface part's P1 input byte's MCB bit -- P1_3, so bit 3 of 0x01. */
#define O1_IF_MCB_BIT 3u

/* ------------------------------------------------------------- the init order
 *
 * Both parts come up the same way, and the order matters for one reason: **a pin
 * in LED mode ignores the output register**, so a dim register that has not been
 * written yet is an unpredictable lamp rather than a dark one.  So the sequence is
 * mode first, then direction, then dim, and it is exported rather than inlined in
 * the glue so the host tests can check the order.
 *
 * `AW9523B` facts this relies on, all three from the datasheet and confirmed
 * against Adafruit's driver and the Linux `pinctrl-aw9523` driver:
 *
 *   0x10  chip id, and it reads **0x23** -- so "is the expander there" is a read,
 *         not a guess.  A board that answers with something else is a board with
 *         the wrong part on it, and saying so at boot beats debugging a dark panel.
 *   0x11  GCR, bit 4: **0 = P0 open-drain, 1 = P0 push-pull**.  The reset default
 *         is open-drain, and the panel's eight lamps want push-pull -- this is the
 *         one bit that has to be set, and it is the "P0 push-pull CC" in pinmap.md.
 *         P1 has no push-pull option, which is why TR/MR/RI are open-drain and
 *         carry series resistors.
 *   0x12  0x12/0x13 are the per-port LED-mode registers, **0 = LED mode** and
 *         1 = GPIO.  It reads inverted from what a reader expects.
 *   0x7F  soft reset, write 0.
 */
#define O1_AW9523_ADDR_PANEL 0x58u
#define O1_AW9523_ADDR_IFACE 0x59u

#define O1_AW9523_REG_INPUT0    0x00u
#define O1_AW9523_REG_OUTPUT0   0x02u
#define O1_AW9523_REG_CONFIG0   0x04u
#define O1_AW9523_REG_INTEN0    0x06u
#define O1_AW9523_REG_CHIPID    0x10u
#define O1_AW9523_REG_GCR       0x11u
#define O1_AW9523_REG_LEDMODE0  0x12u
#define O1_AW9523_REG_RESET     0x7Fu

#define O1_AW9523_CHIPID_VALUE  0x23u
#define O1_AW9523_GCR_P0_PUSHPULL 0x10u

/* One register write, so the glue walks a list instead of knowing the part. */
typedef struct {
    uint8_t reg;
    uint8_t val;
} o1_reg_write;

/* The panel part's init: soft reset, chip id check, P0 push-pull, all sixteen
 * pins to LED mode and output, dim to 0.  Returns the number written, or 0 if
 * `out_n` is too small -- 16 writes fit comfortably. */
unsigned o1_panel_init_writes(o1_reg_write *out, unsigned out_n);

/* The interface part's init: soft reset, chip id check, P1_0..P1_2 outputs and
 * P1_3 an input, all four in GPIO mode (not LED mode), interrupts off. */
unsigned o1_iface_init_writes(o1_reg_write *out, unsigned out_n);

/* One flush's worth of writes, split by device because they are two chips on one
 * bus: the panel part's dim registers, and the interface part's output byte.  The
 * glue walks the two lists and writes each to its own address. */
#define O1_PANEL_PLAN_DIM_MAX   16u
#define O1_PANEL_PLAN_IFACE_MAX 2u

typedef struct {
    o1_reg_write dim[O1_PANEL_PLAN_DIM_MAX];
    unsigned     n_dim;
    o1_reg_write iface[O1_PANEL_PLAN_IFACE_MAX];
    unsigned     n_iface;
} o1_panel_plan;

/* What has to go on the wire to make the hardware match `p` -- and **nothing**,
 * counted as zero, when it already does.  That "nothing" is the feature: the
 * panel is written on change only, so a hung firmware leaves the last state
 * standing rather than a panel being rewritten into the void.
 *
 * A caller that sees a write fail calls `o1_panel_invalidate` and tries again. */
unsigned o1_panel_flush(o1_panel *p, const o1_modem_state *s, o1_panel_plan *plan);

/* Mark the panel dirty without changing it -- what a caller does after an I2C
 * write it knows failed, so the next flush **rewrites the whole panel** rather
 * than only what it believes changed.  See panel.c for why the two are not the
 * same thing. */
void o1_panel_invalidate(o1_panel *p);

#ifdef __cplusplus
} /* extern "C" */
#endif

#endif /* O1_MODEM_PANEL_H */
