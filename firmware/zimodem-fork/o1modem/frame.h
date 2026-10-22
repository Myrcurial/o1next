/* The 6850's control byte -- the *frame*, and the other half of what a modem
 * personality has to present (#319, part of #56).
 *
 * Baud rate is only half of it.  Data bits, parity and stop bits come from the
 * ACIA's control register, and the Osborne 1 lets its owner change them: *The
 * Portable Companion* #7 (June 1983, PDF pp. 56-57) is a worked BIOS patch that
 * puts a new control byte at **BIOS offset 1FE9h** and SYSGENs it
 * (docs/o1-modem-serial.md, section "Framing").  So a modem that only ever
 * presents 8-N-1 fails on a machine whose owner patched the frame for a lab
 * instrument -- which is exactly the case that article exists for.
 *
 * The article's own table is this module's test vector
 * ---------------------------------------------------
 * It prints a "Table of 6850 control codes" covering all sixteen combinations at
 * 1200 and 300 baud, and four of those values are quoted in docs/o1-modem-serial.md:
 *
 *     8-N-1 @1200 = 55h        7-E-1 @1200 = 49h
 *     8-N-1 @300  = 56h        8-N-2 @1200 = 51h
 *
 * Decoded as the 6850's control register -- bits 0-1 the clock divide, bits 2-4
 * the word select -- all four come out exactly right, which is the cross-check
 * that this decoding is the real one rather than a plausible invention.
 * `test_o1modem.c` asserts all four, and the round trip.
 *
 * What is and is not the frame
 * ----------------------------
 * `data_bits`, `parity`, `stop_bits` and `div` are the frame.  `tx` and `rx_int`
 * are *not* -- they are the register's transmit-control and receive-interrupt
 * fields -- but they are decoded and round-tripped anyway, because a module that
 * rewrites a BIOS byte has to preserve the bits it does not care about.
 */
#ifndef O1_MODEM_FRAME_H
#define O1_MODEM_FRAME_H

#include <stdint.h>

/* The core is plain C and the sketch is C++: without this the linker looks for a
 * mangled name and the whole core reads as undefined symbols, which looks like a
 * missing file rather than a linkage mistake. */
#ifdef __cplusplus
extern "C" {
#endif

/* Bits 0-1.  The machine uses /16 and /64 -- the factory default 55h/56h sit in
 * the /16 and /64 fields respectively, and the divider's clock is 16x the marked
 * rate on the /16 setting (docs/o1-memory-io-map.md, "6850 ACIA detail").  /1 is
 * decoded because the field exists, not because this machine uses it, and the
 * fourth encoding is left as reserved rather than guessed at. */
typedef enum {
    O1_DIV_1 = 0,
    O1_DIV_16 = 1,
    O1_DIV_64 = 2,
    O1_DIV_RSVD = 3
} o1_div;

typedef enum {
    O1_PAR_NONE = 0,
    O1_PAR_EVEN,
    O1_PAR_ODD
} o1_parity;

/* Bits 5-6, the transmit-control field.  Not the frame -- round-tripped. */
typedef enum {
    O1_TX_BREAK = 0,   /* RTS low, break asserted, TX interrupt disabled */
    O1_TX_INT_OFF = 1, /* RTS low, TX interrupt disabled */
    O1_TX_INT_ON = 2,  /* RTS low, TX interrupt enabled  */
    O1_TX_RTS_HIGH = 3 /* RTS high, TX interrupt disabled */
} o1_txctl;

typedef struct {
    o1_div    div;        /* bits 0-1 */
    unsigned  data_bits;  /* 7 or 8  */
    o1_parity parity;
    unsigned  stop_bits;  /* 1 or 2  */
    o1_txctl  tx;         /* bits 5-6 -- preserved, not part of the frame */
    unsigned  rx_int;     /* bit 7   -- preserved, not part of the frame */
} o1_frame;

/* Decode a control byte.  Every one of the 256 values decodes; nothing refuses. */
o1_frame o1_frame_of(uint8_t control_byte);

/* The inverse, and exact: `o1_frame_byte(o1_frame_of(b)) == b` for all 256. */
uint8_t o1_frame_byte(const o1_frame *f);

/* Total bits on the wire for one character: 1 start + data + parity + stop.
 * 8-N-1 is 10, 7-E-1 is 10, 8-N-2 is 11.  The pacer needs this (buffer.h). */
unsigned o1_frame_bits(const o1_frame *f);

/* "8N1", "7E1", "8N2" -- for logs and the web UI.  Writes at most `out_n`
 * including the terminator; `out_n` of 0 writes nothing. */
void o1_frame_str(const o1_frame *f, char *out, unsigned out_n);

#ifdef __cplusplus
} /* extern "C" */
#endif

#endif /* O1_MODEM_FRAME_H */
