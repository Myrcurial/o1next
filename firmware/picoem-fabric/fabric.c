/*
 * fabric.c -- the interposer's shift fabric, driven (#304, part of #192).
 *
 * WHAT THIS IS
 *
 *   The first firmware that touches the *board* rather than only the bus.  It programs
 *   the 74AHCT595's match value for the 74AHCT688 -- so `ADDR_HIT` means "a cycle landed
 *   in my window" -- and then, on every cycle it takes, reads the address back out of
 *   the 74AHCT165 and drives the port onto the data bus.
 *
 * WHY BOTH, AND NOT THE WINDOW ALONE
 *
 *   The 688 compares `A8-A15`, so its window is a 256-byte *page*; and on a Z80 I/O
 *   cycle `A8-A15` is the accumulator (or `B`), not the port.  So the window cannot tell
 *   one register from another, and the 165 has to.  `tools/picoem-bridge/src/fabric.rs`
 *   has the whole argument with the tests, and the bridge's `--fabric-test` is what
 *   proves it here: two ports, two answers.
 *
 * THE PACING RULE, WHICH IS THE ONE THING THAT IS THE EMULATOR'S
 *
 *   The bridge steps the emulated chip one **quantum** at a time -- 64 cycles, picoem's
 *   `DEFAULT_STEP_QUANTUM` -- and it observes the fabric once per step.  A level this
 *   firmware holds for *less* than a quantum can therefore be missed entirely: the model
 *   would see the net level and never the clock edge.  So `pace()` is not a nicety, it is
 *   the interface: every fabric level is held for at least one quantum, which is 2.3 MHz
 *   at 150 MHz and comfortably inside the 74AHCT parts' own limits.
 *
 *   It is also *measurable* rather than asserted: `--fabric-test` compares the bridge's
 *   own `SR_SCK` edge count against the floor a 24-bit snapshot must produce, so a
 *   firmware that went too fast fails the check instead of working sometimes.
 *
 * THE CHAIN WIDTH IS A CONTRACT WITH THE MODEL
 *
 *   `CHAIN_BITS` here and `FABRIC_BITS` in `tools/picoem-bridge/src/fabric.rs` are the
 *   same number in two places, exactly as the frame format is in `frame.rs` and
 *   `o1next-picoem.lua`.  They have to agree or the snapshot reads a different length
 *   than the board shifts.
 *
 * SPDX-License-Identifier: MIT
 */

#include "pico/stdlib.h"
#include "hardware/gpio.h"

/* ---------------------------------------------------------------- the pin map
 *
 * Rev B, hardware/interposer-upgrade/revb/README.md.  Everything here is bank 0, which is the
 * bank picoem models on the SIO side -- GP32-47 cannot be driven or observed in the
 * emulator at all (firmware/picoem-smoke/smoke.c has that finding).
 */
#define PIN_D0       0u   /* .. GP7 = D7 */
#define PIN_D7       7u
#define PIN_IORQ     9u
#define PIN_RD       10u
#define PIN_WR       11u
#define PIN_WAIT     22u  /* /WAIT: assert to take a cycle, release with the answer */
#define PIN_ADDR_HIT 23u  /* the 688's output: a cycle is in the window */
#define PIN_DATA_OE  24u
#define PIN_DATA_DIR 25u
#define PIN_SR_SCK   26u
#define PIN_SR_MISO  27u  /* the 165's output: the board drives it, we read it */
#define PIN_SR_LOAD  28u  /* /PL, active low */
#define PIN_SR_MOSI  29u  /* the 595's input */
#define PIN_SR_RCK   30u  /* the 595's latch */
#define PIN_OE_ADDR  31u  /* the 595's /G, active low */

#define DATA_MASK    (0xFFu << PIN_D0)

/* The contract with `fabric.rs`; see the header comment. */
#define CHAIN_BITS   24u

/* The 688 compares eight bits, so the 595 holds eight. */
#define MATCH_BITS   8u

/* The window: page zero.  Every I/O port's high byte is zero, so this window is *all*
 * of them -- which is the finding, not a choice: it is why the 165 has to exist. */
#define MATCH_VALUE  0x00u

/* ------------------------------------------------------------- the pacing rule */

/* Hold one fabric level for at least one emulated quantum.
 *
 * A volatile counter, so the compiler cannot delete the loop, and 32 iterations of it
 * is a few hundred cycles -- several quanta, deliberately generous.  `--fabric-test`
 * measures whether it was enough rather than trusting this comment.
 */
static inline void pace(void)
{
    for (volatile unsigned i = 0; i < 32u; ++i) {
    }
}

/* ------------------------------------------------------------- the shift fabric */

/* One `SR_SCK` rising edge, with `bit` presented on `SR_MOSI`.
 *
 * Both levels are held for a quantum, and the clock is returned low afterwards: the
 * bridge's model shifts on the rising edge, so a level left high is a level that never
 * produces the next edge.
 */
static void sck_edge(unsigned bit)
{
    gpio_put(PIN_SR_MOSI, bit);
    pace();
    gpio_put(PIN_SR_SCK, 1);
    pace();
    gpio_put(PIN_SR_SCK, 0);
    pace();
}

/* Program the 595: MSB first, then latch.
 *
 * The outputs stay disabled until `fabric_enable()` -- and that is deliberate rather
 * than untidy.  A firmware that latches with `/OE_ADDR` high leaves the comparator
 * watching the pull-downs, so its window is page zero whatever it shifted in; the
 * bridge's model catches exactly that (`a_disabled_595_reads_as_the_pull_downs`).
 */
static void program_match(uint32_t value)
{
    for (unsigned i = MATCH_BITS; i-- > 0;) {
        sck_edge((value >> i) & 1u);
    }

    pace();
    gpio_put(PIN_SR_RCK, 1);   /* the latch: shift register -> outputs */
    pace();
    gpio_put(PIN_SR_RCK, 0);
    pace();
}

/* Read the address chain: assert `/PL`, release it (which is the capture), then clock
 * the bits out MSB first.
 *
 * The first bit is read *before* the first clock, because that is what a 165 does: it
 * presents `QH` -- the MSB -- as soon as it is loaded, and each clock presents the next.
 */
static uint32_t read_address(void)
{
    uint32_t value = 0;

    gpio_put(PIN_SR_LOAD, 0);  /* /PL asserted: the parallel inputs are presented */
    pace();
    gpio_put(PIN_SR_LOAD, 1);  /* the release captures them */
    pace();

    for (unsigned i = 0; i < CHAIN_BITS; ++i) {
        value = (value << 1) | (gpio_get(PIN_SR_MISO) ? 1u : 0u);
        gpio_put(PIN_SR_SCK, 1);
        pace();
        gpio_put(PIN_SR_SCK, 0);
        pace();
    }

    return value;
}

/* -------------------------------------------------------------------- the bus
 *
 * The smoke firmware's three primitives, duplicated on purpose: `firmware/picoem-smoke/`
 * is the *minimal* proof that the loop closes and should stay that way, and this is the
 * first board-support firmware.  A shared header is the obvious next step when a third
 * one appears.
 */
static inline uint8_t bus_read_data(void)
{
    return (uint8_t)((gpio_get_all() & DATA_MASK) >> PIN_D0);
}

static inline void bus_drive(uint8_t value)
{
    gpio_set_dir_masked(DATA_MASK, DATA_MASK);          /* D0-D7 outputs */
    gpio_put_masked(DATA_MASK, (uint32_t)value << PIN_D0);
    gpio_put(PIN_DATA_OE, 1);                           /* the 245 is enabled */
}

static inline void bus_release(void)
{
    gpio_put(PIN_DATA_OE, 0);
    gpio_set_dir_masked(DATA_MASK, 0);                  /* D0-D7 inputs */
    gpio_put_masked(DATA_MASK, 0);
}

/* -------------------------------------------------------------------- startup */

static void fabric_pins_init(void)
{
    /* What this chip drives. */
    for (unsigned p = PIN_SR_SCK; p <= PIN_SR_RCK; ++p) {
        gpio_init(p);
        gpio_set_dir(p, GPIO_OUT);
        gpio_put(p, 0);
    }

    gpio_init(PIN_OE_ADDR);
    gpio_set_dir(PIN_OE_ADDR, GPIO_OUT);
    gpio_put(PIN_OE_ADDR, 1);          /* disabled until the window is programmed */

    gpio_init(PIN_WAIT);
    gpio_set_dir(PIN_WAIT, GPIO_OUT);
    gpio_put(PIN_WAIT, 1);             /* /WAIT released: not stretching anything */

    /* What the board drives. */
    gpio_init(PIN_SR_MISO);
    gpio_set_dir(PIN_SR_MISO, GPIO_IN);

    gpio_init(PIN_ADDR_HIT);
    gpio_set_dir(PIN_ADDR_HIT, GPIO_IN);
    gpio_pull_down(PIN_ADDR_HIT);      /* the 688's output idles low */
}

static void bus_pins_init(void)
{
    gpio_init_mask(DATA_MASK);
    gpio_set_dir_masked(DATA_MASK, 0);
    gpio_put_masked(DATA_MASK, 0);

    for (unsigned p = PIN_IORQ; p <= PIN_WR; ++p) {
        gpio_init(p);
        gpio_set_dir(p, GPIO_IN);
        gpio_pull_up(p);               /* an undriven strobe reads 0, which is asserted */
    }

    gpio_init(PIN_DATA_OE);
    gpio_set_dir(PIN_DATA_OE, GPIO_OUT);
    gpio_put(PIN_DATA_OE, 0);

    gpio_init(PIN_DATA_DIR);
    gpio_set_dir(PIN_DATA_DIR, GPIO_OUT);
    gpio_put(PIN_DATA_DIR, 0);         /* the 245 points Z80 -> us */
}


/* ----------------------------------------------------------------------- main */

int main(void)
{
    bus_pins_init();
    fabric_pins_init();

    /* Program the window once.  The 595 keeps it -- that is what a latch is for -- so
     * this is startup work, not per-cycle work.
     */
    program_match(MATCH_VALUE);
    gpio_put(PIN_OE_ADDR, 0);          /* publish it: the comparator can see it now */
    pace();

    for (;;) {
        /* Wait for an I/O cycle.  `/IORQ` is the strobe and it is active low; gating on
         * `ADDR_HIT` alone would be wrong, because the 688 follows the *address bus*,
         * which still holds the last address between cycles. */
        if (gpio_get(PIN_IORQ)) {
            tight_loop_contents();
            continue;
        }

        /* In a cycle, but not in the window.  With the window on page zero this never
         * happens for an I/O cycle -- every port's high byte is zero -- and that is the
         * finding, not a bug: the 165 below is what actually selects the register. */
        if (!gpio_get(PIN_ADDR_HIT)) {
            continue;
        }

        /* Take the cycle: stretch /WAIT while we work, exactly as the period's slow
         * peripherals did, and release it with the answer on the bus. */
        gpio_put(PIN_WAIT, 0);

        uint32_t addr = read_address();

        /* Answer a *read*.  On a write the Z80 owns the data bus and driving back would
         * be a bus conflict on hardware, so the firmware only speaks when /RD is low. */
        if (!gpio_get(PIN_RD)) {
            bus_drive((uint8_t)(addr & 0xFFu));
        }

        gpio_put(PIN_WAIT, 1);

        /* Hold the answer until the Z80 ends the cycle, then let go of the bus. */
        while (!gpio_get(PIN_IORQ)) {
            tight_loop_contents();
        }
        bus_release();
    }
}

