/*
 * smoke.c -- the picoem bridge's smoke firmware (#286, part of #192).
 *
 * This is the smallest firmware that can prove the bridge end to end: a Z80 bus
 * cycle arriving on the interposer's pins, an answer leaving on the same pins,
 * and both visible from the MAME side.  It is not a personality -- #179 is --
 * and it is deliberately not PIO, because the question it answers is "does a
 * real Pico SDK binary, built from this tree, run inside picoem and answer the
 * bus?", and a polled GPIO loop answers that with the fewest moving parts.
 *
 * WHAT IT IS
 *
 *   A one-byte register, addressed by the Z80's own I/O strobes.  Write a byte
 *   and it latches it; read and it drives the latched byte back out.  That is
 *   the ACB-4000's data register in miniature (docs/acb4000-host-adapter.md),
 *   so the shape of the firmware is the shape the personality will keep.
 *
 *   GP37 toggles once per handled cycle.  That is the liveness signal: the
 *   bridge counts edges, so "the firmware saw the cycle" is a number in the
 *   reply frame and not an inference.
 *
 * THE PINS ARE THE REV B PIN MAP (hardware/interposer/revb/README.md)
 *
 *   GP0-GP7   D0-D7        data bus, via the 74AHCT245
 *   GP8       /MREQ        input, active low
 *   GP9       /IORQ        input, active low
 *   GP10      /RD          input, active low
 *   GP11      /WR          input, active low
 *   GP24      DATA_OE      output, high while this chip drives the data bus
 *   GP25      DATA_DIR     output, the 245's direction
 *   GP26      SR_SCK       the heartbeat here -- borrowed from the 595/165
 *                          shift fabric, and borrowed on purpose
 *
 *   The heartbeat is on GP26 and not on the Rev B map's spare pin (GP37)
 *   because **picoem models only GPIO bank 0 on the SIO side**: its `Sio` has
 *   `gpio_out` and `gpio_oe` and no GPIO_HI_OUT / GPIO_HI_OE, so GP32-GP47 can
 *   be neither driven nor observed through SIO, and `gpio_in_hi` reflects PIO
 *   outputs alone. A heartbeat on GP37 would toggle on hardware and be
 *   invisible in the emulator -- which is a finding about picoem (it matters
 *   for GP38/39, the ESP32 UART, and GP47, the debug LED) and not something to
 *   paper over by guessing. Everything else this firmware touches is bank 0,
 *   which is the bank the Rev B bus uses.
 *
 * WHY THE STROBES ARE PULLED UP
 *
 *   An input pin with nothing driving it reads 0 in picoem exactly as it reads
 *   0 on a board with no pull-up, and 0 is "asserted" for every one of these
 *   strobes.  The bridge drives them (see tools/picoem-bridge), so the pull-ups
 *   are for the idle case: with them, the firmware idles instead of inventing a
 *   cycle.  On Rev B the same job is done by the board's pull-ups.
 *
 * SPDX-License-Identifier: MIT
 */

#include "pico/stdlib.h"
#include "hardware/gpio.h"

/* The Rev B pin map, in one place so the bridge and this file cannot drift. */
#define PIN_D0       0u   /* .. GP7 = D7 */
#define PIN_D7       7u
#define PIN_MREQ     8u
#define PIN_IORQ     9u
#define PIN_RD       10u
#define PIN_WR       11u
#define PIN_DATA_OE  24u
#define PIN_DATA_DIR 25u
#define PIN_HB       26u   /* SR_SCK, borrowed -- see the header comment */

#define DATA_MASK    (0xFFu << PIN_D0)
#define HB_MASK      (1u << PIN_HB)

/* The byte this register holds.  Static, so it survives the idle loop. */
static uint8_t latched;

static inline uint8_t bus_read_data(void)
{
    return (uint8_t)((gpio_get_all() & DATA_MASK) >> PIN_D0);
}

static inline void bus_drive(uint8_t value)
{
    gpio_set_dir_masked(DATA_MASK, DATA_MASK);          /* D0-D7 outputs */
    gpio_put_masked(DATA_MASK, (uint32_t)value << PIN_D0);
    gpio_put(PIN_DATA_OE, 1);                           /* 245 enabled */
}

static inline void bus_release(void)
{
    gpio_put(PIN_DATA_OE, 0);
    gpio_set_dir_masked(DATA_MASK, 0);                  /* D0-D7 inputs */
    gpio_put_masked(DATA_MASK, 0);
}

int main(void)
{
    gpio_init_mask(DATA_MASK);
    gpio_set_dir_masked(DATA_MASK, 0);
    gpio_put_masked(DATA_MASK, 0);

    for (unsigned pin = PIN_MREQ; pin <= PIN_WR; ++pin) {
        gpio_init(pin);
        gpio_set_dir(pin, GPIO_IN);
        gpio_pull_up(pin);
    }

    gpio_init(PIN_DATA_OE);
    gpio_set_dir(PIN_DATA_OE, GPIO_OUT);
    gpio_put(PIN_DATA_OE, 0);

    gpio_init(PIN_DATA_DIR);
    gpio_set_dir(PIN_DATA_DIR, GPIO_OUT);
    gpio_put(PIN_DATA_DIR, 0);                          /* 245: Z80 -> us */

    gpio_init(PIN_HB);
    gpio_set_dir(PIN_HB, GPIO_OUT);
    gpio_put(PIN_HB, 0);

    for (;;) {
        if (gpio_get(PIN_IORQ)) {
            tight_loop_contents();                      /* no I/O cycle */
            continue;
        }

        if (!gpio_get(PIN_WR)) {
            latched = bus_read_data();
            bus_drive(latched);
            gpio_xor_mask(HB_MASK);
            while (!gpio_get(PIN_WR)) {
                tight_loop_contents();                  /* hold until /WR rises */
            }
            bus_release();
        } else if (!gpio_get(PIN_RD)) {
            bus_drive(latched);
            gpio_xor_mask(HB_MASK);
            while (!gpio_get(PIN_RD)) {
                tight_loop_contents();
            }
            bus_release();
        }
    }
}
