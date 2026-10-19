/* The 6850 control byte -- see frame.h for why, and for the test vectors (#319). */
#include "frame.h"

/* The word-select field (bits 2-4) is the 6850's own encoding, and it is the
 * reason the article's four quoted values decode: 5 is 8-N-1, 2 is 7-E-1 and
 * 4 is 8-N-2. */
static void word_select(unsigned ws, unsigned *data, o1_parity *par, unsigned *stop)
{
    ws &= 7u;

    *data = (ws >= 4u) ? 8u : 7u;
    *stop = ((ws == 0u) || (ws == 1u) || (ws == 4u)) ? 2u : 1u;

    switch (ws) {
    case 0u:
    case 2u:
        *par = O1_PAR_EVEN;
        break;
    case 1u:
    case 3u:
        *par = O1_PAR_ODD;
        break;
    case 6u:
        *par = O1_PAR_EVEN;
        break;
    case 7u:
        *par = O1_PAR_ODD;
        break;
    default:
        *par = O1_PAR_NONE;   /* 4 and 5 are the no-parity encodings */
        break;
    }
}

/* The inverse of word_select.  Returns the 3-bit field. */
static unsigned word_select_of(unsigned data_bits, o1_parity par, unsigned stop_bits)
{
    unsigned two = (stop_bits == 2u) ? 1u : 0u;

    if (data_bits == 7u) {
        /* 7 bits: 0 = E,2  1 = O,2  2 = E,1  3 = O,1 */
        if (par == O1_PAR_ODD)
            return two ? 1u : 3u;
        return two ? 0u : 2u;
    }

    /* 8 bits: 4 = N,2  5 = N,1  6 = E,1  7 = O,1 */
    if (par == O1_PAR_NONE)
        return two ? 4u : 5u;
    if (par == O1_PAR_EVEN)
        return 6u;
    return 7u;
}

o1_frame o1_frame_of(uint8_t control_byte)
{
    o1_frame f;

    f.div  = (o1_div)(control_byte & 0x03u);
    word_select((unsigned)((control_byte >> 2) & 0x07u), &f.data_bits, &f.parity,
                &f.stop_bits);
    f.tx     = (o1_txctl)((control_byte >> 5) & 0x03u);
    f.rx_int = (unsigned)((control_byte >> 7) & 0x01u);
    return f;
}

uint8_t o1_frame_byte(const o1_frame *f)
{
    unsigned b;

    if (f == 0)
        return 0u;

    b  = (unsigned)(f->div & 0x03);
    b |= (word_select_of(f->data_bits, f->parity, f->stop_bits) & 0x07u) << 2;
    b |= ((unsigned)(f->tx) & 0x03u) << 5;
    b |= (f->rx_int & 0x01u) << 7;
    return (uint8_t)b;
}

unsigned o1_frame_bits(const o1_frame *f)
{
    unsigned bits;

    if (f == 0)
        return 0;

    bits = 1u + f->data_bits + f->stop_bits;   /* start + data + stop */
    if (f->parity != O1_PAR_NONE)
        bits++;
    return bits;
}

void o1_frame_str(const o1_frame *f, char *out, unsigned out_n)
{
    char     tmp[4];
    char     par;
    unsigned i, n;

    if (out == 0 || out_n == 0u)
        return;

    if (f == 0) {          /* no frame is an empty string, not a guess */
        out[0] = '\0';
        return;
    }

    switch (f->parity) {
    case O1_PAR_EVEN:
        par = 'E';
        break;
    case O1_PAR_ODD:
        par = 'O';
        break;
    default:
        par = 'N';
        break;
    }

    tmp[0] = (char)('0' + (f->data_bits % 10u));
    tmp[1] = par;
    tmp[2] = (char)('0' + (f->stop_bits % 10u));
    tmp[3] = '\0';

    n = (out_n - 1u) < 3u ? (out_n - 1u) : 3u;
    for (i = 0; i < n; i++)
        out[i] = tmp[i];
    out[n] = '\0';
}
