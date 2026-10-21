/* The modem's sound -- arithmetic, not samples (#322, part of #56).
 *
 * See tone.h for what this is *for* and `docs/modem-tones.md` for where every
 * frequency in the scores comes from.  This file is the mechanism: one integer
 * oscillator, two modulators, and a table walker.
 */
#include <string.h>

#include "tone.h"

/* ------------------------------------------------------------------- the sine
 *
 * A **quarter wave**, mirrored for the other three quadrants.  That is 65 values
 * instead of 256, which matters on a part whose application partition the build
 * refuses to overfill -- and it is exact at every multiple of 90 degrees, which is
 * the property that keeps the constellations square.
 *
 * The values are round(sin(k * pi / 128) * 32767) for k = 0..64.  They are written
 * out rather than computed because the alternative is an FPU, a libm call or a
 * CORDIC loop on a chip that has better things to do at boot.
 */
static const int16_t sine_q[65] = {
        0,   804,  1608,  2411,  3212,  4011,  4808,  5602,  6393,  7179,
     7962,  8740,  9512, 10279, 11039, 11793, 12539, 13279, 14010, 14732,
    15447, 16151, 16846, 17531, 18205, 18868, 19520, 20160, 20788, 21403,
    22006, 22595, 23170, 23732, 24279, 24812, 25330, 25833, 26320, 26791,
    27246, 27684, 28106, 28511, 28899, 29269, 29622, 29957, 30274, 30572,
    30853, 31114, 31357, 31581, 31786, 31972, 32138, 32286, 32413, 32521,
    32610, 32679, 32729, 32758, 32767,
};

/* `ph` is Q32: one full cycle is 2^32, so the top eight bits are the table index
 * and the top two of those are the quadrant. */
static int32_t o1_sine(uint32_t ph)
{
    unsigned idx  = (unsigned)(ph >> 24) & 0xFFu;
    unsigned quad = idx >> 6;
    unsigned k    = idx & 0x3Fu;

    switch (quad) {
    case 0u:  return (int32_t)sine_q[k];
    case 1u:  return (int32_t)sine_q[64u - k];
    case 2u:  return -(int32_t)sine_q[k];
    default:  return -(int32_t)sine_q[64u - k];
    }
}

/* The Q32 increment for `freq` Hz at `fs` Hz.  64-bit in the middle because
 * 16000 << 32 overflows 32 bits by a mile -- and a truncated shift here is a
 * wrong pitch that still sounds like a tone, which is the worst kind of bug. */
static uint32_t o1_inc(unsigned freq, unsigned fs)
{
    if (fs == 0u)
        return 0u;
    return (uint32_t)(((uint64_t)freq << 32) / (uint64_t)fs);
}

/* A cosine is a sine a quarter cycle early -- used by the I/Q modulator, so that
 * one phase accumulator serves both components and the constellation stays
 * square no matter where the carrier happens to be. */
static int32_t o1_cosine(uint32_t ph)
{
    return o1_sine(ph + 0x40000000u);
}

/* ---------------------------------------------------------------- scramblers
 *
 * The two tap pairs, named, so that nothing in the file carries a bare 14 or 23.
 *
 *   V.22 / V.22bis / Bell 212A   G(x) = 1 + x^-14 + x^-17   -> taps 14 and 17
 *   V.32 / V.32bis               G(x) = 1 + x^-18 + x^-23   -> taps 18 and 23
 */
#define O1_SCR_V22_TAP_A 14u
#define O1_SCR_V22_TAP_B 17u
#define O1_SCR_V32_TAP_A 18u
#define O1_SCR_V32_TAP_B 23u

static uint32_t o1_scr_mask(unsigned width)
{
    if (width == 0u)
        return 0u;
    if (width >= 32u)
        return 0xFFFFFFFFu;
    return (uint32_t)((1u << width) - 1u);
}

uint8_t o1_scr_bit_of(uint32_t *sr, unsigned tap_a, unsigned tap_b, uint8_t data_bit)
{
    uint32_t fb, out;

    if (sr == 0 || tap_a == 0u || tap_b == 0u || tap_a >= 32u || tap_b >= 32u)
        return (uint8_t)(data_bit & 1u);

    /* The taps are on the *output* register, so they are read *before* the shift:
     * bit (tap-1) is the output from (tap) bits ago. */
    fb = ((*sr >> (tap_a - 1u)) ^ (*sr >> (tap_b - 1u))) & 1u;

    out = (uint8_t)((data_bit & 1u) ^ fb);

    *sr = ((*sr << 1) | (uint32_t)out) & o1_scr_mask(tap_b);
    return out;
}

uint8_t o1_desc_bit_of(uint32_t *sr, unsigned tap_a, unsigned tap_b, uint8_t scr_bit)
{
    uint32_t fb, data;

    if (sr == 0 || tap_a == 0u || tap_b == 0u || tap_a >= 32u || tap_b >= 32u)
        return (uint8_t)(scr_bit & 1u);

    /* Here the received bit is what gets shifted in, and the taps are read from
     * the register as it was before -- the same arithmetic with the XOR moved. */
    fb = ((*sr >> (tap_a - 1u)) ^ (*sr >> (tap_b - 1u))) & 1u;

    data = ((uint32_t)(scr_bit & 1u) ^ fb) & 1u;

    *sr = ((*sr << 1) | (uint32_t)(scr_bit & 1u)) & o1_scr_mask(tap_b);
    return (uint8_t)data;
}

/* Preset to a **single 1 in the lowest stage**, and the reason is worth a
 * paragraph because the obvious choice is wrong.
 *
 * The standards preset these scramblers, and the tempting reading is "to all
 * ones".  That reading makes `scrambled binary 1` a **fixed point**: with the
 * register full of ones, the feedback is 1 XOR 1 = 0, so an input of 1 passes
 * straight through and the output is a constant.  The same happens from an
 * all-zeros preset, which converges to all-ones within `tap_b` bits.  So a
 * scrambler preset to either extreme, fed ones, produces a **steady carrier** --
 * indistinguishable from the *unscrambled* ones it is supposed to be different
 * from, and a V.22bis modem would then have nothing to detect.
 *
 * A single 1 avoids the degenerate orbit and gives the maximal-length sequence,
 * which is the property that makes "scrambled binary 1" sound like noise.  That
 * is what the sound needs and it is what the standard means; **the exact preset
 * is a detail this project could not confirm from a primary source**, and it is
 * recorded as such in `docs/modem-tones.md` rather than presented as quoted.
 *
 * (The suite asserts the sequence's *period* -- 2^17 - 1 and 2^23 - 1 -- which is
 * a property of the polynomial and not of the preset, so it holds either way.) */
void o1_scr_v22_init(o1_scrambler *s)
{
    if (s != 0)
        s->sr = 1u;
}

void o1_scr_v32_init(o1_scrambler *s)
{
    if (s != 0)
        s->sr = 1u;
}

uint8_t o1_scr_bit(o1_scrambler *s, uint8_t data_bit)
{
    if (s == 0)
        return (uint8_t)(data_bit & 1u);
    return o1_scr_bit_of(&s->sr, O1_SCR_V22_TAP_A, O1_SCR_V22_TAP_B, data_bit);
}

/* ------------------------------------------------------------- the data source */

void o1_data_init(o1_datasrc *d, const uint8_t *bytes, unsigned n)
{
    if (d == 0)
        return;
    d->bytes = bytes;
    d->n     = (bytes == 0) ? 0u : n;
    d->idx   = 0u;
    d->bit   = 0u;
}

uint8_t o1_data_bit(o1_datasrc *d)
{
    uint8_t b;

    if (d == 0 || d->bytes == 0 || d->n == 0u)
        return 1u;

    if (d->idx >= d->n) {
        d->idx = 0u;   /* loop, so a 2 s phase at 9600 baud has something to send */
        d->bit = 0u;
    }

    b = (uint8_t)((d->bytes[d->idx] >> (7u - d->bit)) & 1u);

    if (++d->bit >= 8u) {
        d->bit = 0u;
        d->idx++;
    }
    return b;
}

/* The payload.  ASCII, printable, and it says what it is -- because the whole
 * point of scrambling it is that nobody can hear the difference, and a future
 * session that decodes a capture should find something that explains itself. */
const uint8_t o1_tone_payload[] =
    "O1NEXT WIFI COMM PAC 300/1200/2400/9600 8N1\r\n";
const unsigned o1_tone_payload_len = sizeof o1_tone_payload - 1u;

/* ------------------------------------------------------------------ the scores
 *
 * Every frequency here is documented in `docs/modem-tones.md` with its source.
 * The **durations are ours** except where a source gives one -- and where a
 * duration is a standard's, the phase name says the number so a reader can see
 * which is which.
 *
 * The shape of each score is the same on purpose: **carrier, then the first
 * negotiation signal in each direction, then two seconds of full
 * communications.**  That is the brief, and it is also how a real call sounds
 * from one side of the room.
 */

/* ------------------------------------------------- 300 baud: Bell 103A / V.21
 *
 * The Osborne's own modem, and the one rate here that is *documented by this
 * project's archive* rather than by an ITU recommendation:
 *
 *     (1,0) = (1270, 1070) Hz for ORIGINATE mode
 *     (1,0) = (2225, 2025) Hz for ANSWER mode
 *     -- research/osborne1/Comm-Pac_Users_Manual.pdf, "Modem-to-Modem Protocol"
 *
 * **Bell 103 has no answer tone.**  There is no 2100 Hz and no 2250 Hz: the
 * answering modem goes off-hook and starts sending its mark frequency, and that
 * continuous 2225 Hz is what the caller hears while the call is being set up.
 * That is why the first phase here is a plain tone at the answer mark frequency
 * rather than a "tone" with a standard's name on it.
 */
static const o1_phase bell103_ph[] = {
    { O1_SIG_TONE, O1_BIT_MARK, 2225, 0, 0, 0, 2000u, 0, 0, 0,
      "answer mark, 2225 Hz -- there is no answer tone in Bell 103" },
    { O1_SIG_TONE, O1_BIT_MARK, 1270, 0, 0, 0,  500u, 0, 0, 0,
      "calling modem answers with its mark, 1270 Hz" },
    { O1_SIG_TONE, O1_BIT_MARK, 2225, 0, 1270, 0, 500u, 0, 0, 1,
      "both carriers up, 2225 + 1270 Hz" },
    { O1_SIG_FSK, O1_BIT_SCRAMBLED_DATA, 2225, 2025, 1270, 1070, 2000u, 300, 0, 1,
      "300 baud, both directions -- 2225/2025 against 1270/1070" },
};

/* ------------------------------------------- 1200 baud: Bell 212A / V.22
 *
 * Split band, 600 baud, four-phase DPSK: 2400 Hz one way and 1200 Hz the other,
 * two bits per symbol, which is 1200 bit/s.
 *
 * The handshake is the ITU's, and the numbers in the phase names are the ones the
 * recommendation itself states (quoted verbatim in spandsp's `v22bis_tx.c`,
 * section 6.3.1.1.1):
 *
 *   b) "After 155 +-10 ms of unscrambled binary 1 has been detected, the modem
 *      shall remain silent for a further 456 +-10 ms then transmit an unscrambled
 *      repetitive double dibit pattern of 00 and 11 at 1200 bit/s for 100 +-3 ms."
 *
 * **That double-dibit pattern is the S1 signal**, and it is the one sound in this
 * file that is unmistakably a 2400-bps modem rather than a 1200-bps one -- which
 * is exactly why it is in both scores.
 */
static const o1_phase v22_ph[] = {
    { O1_SIG_TONE, O1_BIT_MARK, 2250, 0, 0, 0, 3300u, 0, 0, 0,
      "answer tone, 2250 Hz" },
    { O1_SIG_TONE, O1_BIT_MARK, 2400, 0, 0, 0,  200u, 0, 0, 0,
      "unscrambled binary 1, high band (2400 Hz)" },
    { O1_SIG_SILENCE, O1_BIT_MARK, 0, 0, 0, 0,  456u, 0, 0, 0,
      "calling modem waits 456 ms" },
    { O1_SIG_PSK4, O1_BIT_DOUBLE_DIBIT, 1200, 0, 0, 0, 100u, 600, 0, 0,
      "S1: unscrambled double dibit 00/11, low band" },
    { O1_SIG_PSK4, O1_BIT_DOUBLE_DIBIT, 2400, 0, 0, 0, 100u, 600, 0, 0,
      "S1 reply, high band" },
    { O1_SIG_PSK4, O1_BIT_SCRAMBLED_MARK, 2400, 0, 1200, 0, 400u, 600, 0, 1,
      "scrambled 1s at 1200 bit/s, both bands" },
    { O1_SIG_PSK4, O1_BIT_SCRAMBLED_DATA, 2400, 0, 1200, 0, 2000u, 600, 0, 1,
      "full communications, 1200 bit/s" },
};

/* --------------------------------------------------- 2400 baud: V.22bis
 *
 * The same split band and the same 600 baud, but sixteen points instead of four:
 * four bits per symbol, 2400 bit/s.  The handshake is V.22's **plus** the
 * switchover, and the switchover is the interesting part:
 *
 *   d) "600 +-10 ms after circuit 112 has been turned ON the modem shall begin
 *      transmitting scrambled binary 1 at 2400 bit/s, and 450 +-10 ms after
 *      circuit 112 has been turned ON the receiver may begin making 16-way
 *      decisions."
 *   e) "Following transmission of scrambled binary 1 at 2400 bit/s for
 *      200 +-10 ms, circuit 106 shall be conditioned..."
 *
 * So a V.22bis modem sounds like a **V.22** modem for the first second and a half
 * of every call, and then changes gear.  That is not a simplification on our
 * part -- it is the standard, and it is why the V.22 interworking phase is in
 * this score and not in the 1200 one.
 */
static const o1_phase v22bis_ph[] = {
    { O1_SIG_TONE, O1_BIT_MARK, 2250, 0, 0, 0, 3300u, 0, 0, 0,
      "answer tone, 2250 Hz" },
    { O1_SIG_TONE, O1_BIT_MARK, 2400, 0, 0, 0,  200u, 0, 0, 0,
      "unscrambled binary 1, high band" },
    { O1_SIG_SILENCE, O1_BIT_MARK, 0, 0, 0, 0,  456u, 0, 0, 0,
      "calling modem waits 456 ms" },
    { O1_SIG_PSK4, O1_BIT_DOUBLE_DIBIT, 1200, 0, 0, 0, 100u, 600, 0, 0,
      "S1: double dibit 00/11, low band -- the V.22bis capability signal" },
    { O1_SIG_PSK4, O1_BIT_DOUBLE_DIBIT, 2400, 0, 0, 0, 100u, 600, 0, 0,
      "S1 reply, high band" },
    { O1_SIG_PSK4, O1_BIT_SCRAMBLED_MARK, 2400, 0, 1200, 0, 600u, 600, 0, 1,
      "V.22 interworking: 1200 bit/s until the switchover" },
    { O1_SIG_QAM16, O1_BIT_SCRAMBLED_MARK, 2400, 0, 1200, 0, 800u, 600, 0, 1,
      "scrambled 1s at 2400 bit/s -- 600 + 450 + 200 ms of training" },
    { O1_SIG_QAM16, O1_BIT_SCRAMBLED_DATA, 2400, 0, 1200, 0, 2000u, 600, 0, 1,
      "full communications, 2400 bit/s" },
};

/* ------------------------------------------------------------ 9600 baud: V.32
 *
 * A completely different animal, and the score says so.  **V.32 has one carrier,
 * not two** -- echo cancellation separates the directions instead of splitting
 * the band -- so `two` is 0 for every phase here and the sound is a single 1800 Hz
 * signal being pushed around.  That is why a 9600-bps modem sounds nothing like a
 * 2400-bps one even at the same volume.
 *
 * 2400 baud with trellis-coded 32-point modulation at 9600 bit/s.
 *
 * The handshake, in order, from the General DataComm patent that describes it
 * signal by signal (WO1991015067A1) and the annotated spectra at 3am Systems and
 * wavecom:
 *
 *   ANS   2100 Hz, from the answering modem, with 180-degree phase reversals
 *         every 450 ms -- the reversals disable the network's echo cancellers,
 *         which would otherwise eat a full-duplex data signal.  (Wikipedia's
 *         "Answer tone" has the 450 ms number; the 2100 Hz is in the VBD tone
 *         tables as plain "ANS".)
 *   AA    1800 Hz from the calling modem, same reversal treatment.
 *   AC/CA 600 + 3000 Hz from the answering modem, alternating phase -- this is
 *         the round-trip-delay measurement that lets each end set its canceller.
 *   TRN   "scrambled marks sent at 4800 bps" -- the training sequence.  At
 *         2400 baud that is two bits per symbol, so it is QPSK.
 *   S     "ABABAB..." -- the 1800 Hz signal with its phase flipped every symbol
 *         interval, for 256 symbol intervals.
 *   S'    "CDCDCD..." -- the same idea on the 600 + 3000 Hz pair.
 *   B1    scrambled binary 1 at the line rate, which is where the screech starts.
 */
static const o1_phase v32_ph[] = {
    { O1_SIG_TONE, O1_BIT_MARK, 2100, 0, 0, 0, 1800u, 0, 450, 0,
      "ANS: 2100 Hz, 180 deg reversals every 450 ms" },
    { O1_SIG_TONE, O1_BIT_MARK, 1800, 0, 0, 0,  300u, 0, 450, 0,
      "AA: 1800 Hz, calling modem, with reversals" },
    { O1_SIG_TONE, O1_BIT_MARK, 600, 3000, 0, 0, 300u, 0, 100, 0,
      "AC/CA/AC: 600 + 3000 Hz, answering modem, alternating phase" },
    { O1_SIG_PSK4, O1_BIT_SCRAMBLED_MARK, 1800, 0, 0, 0, 300u, 2400, 0, 0,
      "TRN: scrambled marks at 4800 bit/s, answering modem" },
    { O1_SIG_BPSK, O1_BIT_AB, 1800, 0, 0, 0, 215u, 1200, 0, 0,
      "S: 1800 Hz, ABABAB..., 256 symbol intervals" },
    { O1_SIG_PSK4, O1_BIT_SCRAMBLED_MARK, 1800, 0, 0, 0, 300u, 2400, 0, 0,
      "TRN: scrambled marks, calling modem" },
    { O1_SIG_BPSK, O1_BIT_CD, 600, 3000, 0, 0, 215u, 1200, 0, 0,
      "S': 600 + 3000 Hz, CDCDCD..., 256 symbol intervals" },
    { O1_SIG_QAM32, O1_BIT_SCRAMBLED_MARK, 1800, 0, 0, 0, 400u, 2400, 0, 0,
      "B1: scrambled 1s at 9600 bit/s" },
    { O1_SIG_QAM32, O1_BIT_SCRAMBLED_DATA, 1800, 0, 0, 0, 2000u, 2400, 0, 0,
      "full communications, 9600 bit/s" },
};

/* ---------------------------------------------------------- call progress
 *
 * These are **not** modem handshakes, and the numbers are North American
 * call-progress values rather than a standard's:
 *
 *   350 + 440 Hz  the US dial tone (precise tone plan)
 *   440 + 480 Hz  the US audible ring, 2 s on and 4 s off
 *
 * The connect and disconnect pairs are **ours**: a real modem has no "connected"
 * chirp, and inventing one that sounds like a period machine is the whole point of
 * a panel that has a speaker.  Two tones, rising for connect and falling for
 * disconnect, so the two are never confused in a room.
 */
static const o1_phase dialtone_ph[] = {
    { O1_SIG_TONE, O1_BIT_MARK, 350, 440, 0, 0, 3000u, 0, 0, 0,
      "dial tone, 350 + 440 Hz" },
};

static const o1_phase ring_ph[] = {
    { O1_SIG_TONE, O1_BIT_MARK, 440, 480, 0, 0, 2000u, 0, 0, 0,
      "ring, 440 + 480 Hz" },
    { O1_SIG_SILENCE, O1_BIT_MARK, 0, 0, 0, 0, 4000u, 0, 0, 0,
      "ring cadence: 2 s on, 4 s off" },
};

static const o1_phase connect_ph[] = {
    { O1_SIG_TONE, O1_BIT_MARK, 1200, 0, 0, 0, 120u, 0, 0, 0, "connect: 1200 Hz" },
    { O1_SIG_TONE, O1_BIT_MARK, 1800, 0, 0, 0, 200u, 0, 0, 0, "connect: 1800 Hz" },
};

static const o1_phase disconnect_ph[] = {
    { O1_SIG_TONE, O1_BIT_MARK, 1800, 0, 0, 0, 120u, 0, 0, 0, "disconnect: 1800 Hz" },
    { O1_SIG_TONE, O1_BIT_MARK,  900, 0, 0, 0, 300u, 0, 0, 0, "disconnect: 900 Hz" },
};

#define O1_HS(name_, arr_) \
    { name_, arr_, (unsigned)(sizeof arr_ / sizeof arr_[0]) }

const o1_handshake o1_hs_bell103 = O1_HS("Bell 103A, 300 baud", bell103_ph);
const o1_handshake o1_hs_v22     = O1_HS("Bell 212A / V.22, 1200 baud", v22_ph);
const o1_handshake o1_hs_v22bis  = O1_HS("V.22bis, 2400 baud", v22bis_ph);
const o1_handshake o1_hs_v32     = O1_HS("V.32, 9600 baud", v32_ph);

const o1_handshake o1_hs_dialtone   = O1_HS("dial tone", dialtone_ph);
const o1_handshake o1_hs_ring       = O1_HS("ring", ring_ph);
const o1_handshake o1_hs_connect    = O1_HS("connect", connect_ph);
const o1_handshake o1_hs_disconnect = O1_HS("disconnect", disconnect_ph);

uint32_t o1_hs_ms(const o1_handshake *hs)
{
    uint32_t total = 0u;
    unsigned i;

    if (hs == 0)
        return 0u;
    for (i = 0; i < hs->n; i++)
        total += hs->phases[i].ms;
    return total;
}

const o1_handshake *o1_hs_for_rate(o1_rate mbaud)
{
    /* The four modem rates, and the rule is "nearest, low wins a tie".  That
     * matters for the machine's *real* rates: 650 and 2600 are the J1-out rates
     * (#319) and are not modem rates at all, so a 650-baud machine gets the 300
     * sound and a 2600-baud machine gets the 2400 sound -- which is the right
     * answer, because that is the modem the operator would have dialled. */
    if (mbaud == 0u || mbaud < 750000u)
        return &o1_hs_bell103;
    if (mbaud < 1800000u)
        return &o1_hs_v22;
    if (mbaud < 6000000u)
        return &o1_hs_v22bis;
    return &o1_hs_v32;
}

/* ------------------------------------------------------------------- DTMF
 *
 * The eight tones, four low and four high, in the standard 3x4 grid plus the
 * A-D column the keypad never had.  The digit is the *intersection*: 697 + 1209
 * is a "1", 941 + 1477 is a "#".
 */
int o1_dtmf_tones(char digit, uint16_t *low, uint16_t *high)
{
    static const uint16_t lo[4] = { 697u, 770u, 852u, 941u };
    static const uint16_t hi[4] = { 1209u, 1336u, 1477u, 1633u };
    static const char     keys[4][5] = {
        { '1', '2', '3', 'A', 0 },
        { '4', '5', '6', 'B', 0 },
        { '7', '8', '9', 'C', 0 },
        { '*', '0', '#', 'D', 0 },
    };
    unsigned r, c;

    for (r = 0u; r < 4u; r++) {
        for (c = 0u; c < 4u; c++) {
            if (keys[r][c] != digit)
                continue;
            if (low != 0)
                *low = lo[r];
            if (high != 0)
                *high = hi[c];
            return 1;
        }
    }
    return 0;
}

/* ------------------------------------------------------------- the bit source */

uint8_t o1_bitpat_bit(o1_bitpat pat, unsigned *idx)
{
    unsigned i = (idx == 0) ? 0u : *idx;
    uint8_t  b;

    switch (pat) {
    case O1_BIT_DOUBLE_DIBIT:
        /* 0,0,1,1 -- "an unscrambled repetitive double dibit pattern of 00 and 11
         * at 1200 bit/s", which is V.22bis section 6.3.1.1.1 b)'s S1 signal.  The
         * bits are read two at a time (one dibit per symbol), so the repeating
         * unit is two symbols and the result is a two-state phase alternation. */
        {
            static const uint8_t p[4] = { 0u, 0u, 1u, 1u };

            b = p[i & 3u];
        }
        break;

    case O1_BIT_AB:
        /* ABABAB: A and B are the two phase states, alternating every symbol. */
        b = (uint8_t)((i & 1u) ? 0u : 1u);
        break;

    case O1_BIT_CD:
        /* CDCDCD: the same alternation, started from the other state, so S and S'
         * are distinguishable by ear as well as by name. */
        b = (uint8_t)((i & 1u) ? 1u : 0u);
        break;

    case O1_BIT_MARK:
    default:
        b = 1u;
        break;
    }

    if (idx != 0)
        *idx = i + 1u;
    return b;
}

static uint8_t o1_bit(o1_mod *m, o1_bitpat pat)
{
    switch (pat) {
    case O1_BIT_SCRAMBLED_MARK:
        return o1_scr_bit(&m->scr, 1u);

    case O1_BIT_SCRAMBLED_DATA:
        return o1_scr_bit(&m->scr, o1_data_bit(&m->data));

    default:
        return o1_bitpat_bit(pat, &m->pat_idx);
    }
}

/* ---------------------------------------------------------- the constellations
 *
 * Both are real constellations rather than a rectangle of convenience:
 *
 *   16 points  the 4x4 grid -- I and Q each from {-3, -1, +1, +3}
 *   32 points  the 6x6 grid **minus the four corners**, which is the "cross"
 *              V.32's 9600 bit/s mode uses.  Removing the corners is where the
 *              power efficiency comes from, and it is also why 9600 sounds
 *              different from 2400 at the same signal level.
 *
 * Every constellation is scaled to the **same peak** (about 23170 before the
 * amplitude scale), so changing rate does not change the volume -- which is the
 * kind of thing that is invisible in code and obvious in a room.
 */
#define O1_IQ_FULL 16384

static int32_t o1_iq_level(int32_t level, int32_t max_level)
{
    return (level * O1_IQ_FULL) / max_level;
}

static void o1_qam16_map(unsigned code, int32_t *i, int32_t *q)
{
    static const int32_t lvl[4] = { -3, -1, 1, 3 };

    *i = o1_iq_level(lvl[code & 3u], 3);
    *q = o1_iq_level(lvl[(code >> 2) & 3u], 3);
}

static void o1_qam32_map(unsigned code, int32_t *i, int32_t *q)
{
    /* The 6x6 grid with the four corners removed, listed row by row.  Thirty-two
     * entries, which is exactly the five bits a symbol carries. */
    static const int8_t pt[32][2] = {
        { -3, -5 }, { -1, -5 }, {  1, -5 }, {  3, -5 },
        { -5, -3 }, { -3, -3 }, { -1, -3 }, {  1, -3 }, {  3, -3 }, {  5, -3 },
        { -5, -1 }, { -3, -1 }, { -1, -1 }, {  1, -1 }, {  3, -1 }, {  5, -1 },
        { -5,  1 }, { -3,  1 }, { -1,  1 }, {  1,  1 }, {  3,  1 }, {  5,  1 },
        { -5,  3 }, { -3,  3 }, { -1,  3 }, {  1,  3 }, {  3,  3 }, {  5,  3 },
        { -3,  5 }, { -1,  5 }, {  1,  5 }, {  3,  5 },
    };

    *i = o1_iq_level(pt[code & 31u][0], 5);
    *q = o1_iq_level(pt[code & 31u][1], 5);
}

/* ------------------------------------------------------------- the modulator */

/* Channel A's frequencies are f1/f2 and channel B's are f3/f4, so the two
 * directions of a full-duplex sound never share a number by accident. */
static uint16_t o1_freq_of(const o1_phase *ph, int ch, int second)
{
    if (ch == 0)
        return second ? ph->f2 : ph->f1;
    return second ? ph->f4 : ph->f3;
}

/* One symbol's worth of decision: which frequency, or which constellation point.
 * Called at each symbol boundary and once at the start of a phase. */
static void o1_mod_symbol(o1_mod *m, const o1_phase *ph, unsigned fs, int ch)
{
    uint16_t fmark  = o1_freq_of(ph, ch, 0);
    uint16_t fspace = o1_freq_of(ph, ch, 1);

    switch (ph->sig) {
    case O1_SIG_FSK:
        /* Frequency-shift keying: the *frequency* carries the bit, and the phase
         * accumulator runs on across the change.  That continuity is not a
         * detail -- an FSK tone that restarted its phase at every bit boundary
         * would click at 300 Hz, which is a sound no Bell 103 modem ever made. */
        m->inc = o1_inc(o1_bit(m, ph->bits) ? fmark : fspace, fs);
        break;

    case O1_SIG_BPSK:
        m->i = o1_bit(m, ph->bits) ? O1_IQ_FULL : -O1_IQ_FULL;
        m->q = 0;
        break;

    case O1_SIG_PSK4: {
        /* Differentially encoded: the *change* in phase carries the dibit, which
         * is what lets a receiver lock without an absolute phase reference -- and
         * it is why the S1 pattern (00, 11) comes out as a two-state alternation
         * rather than a four-state one. */
        static const uint32_t delta[4] = {
            0x00000000u, 0x40000000u, 0x80000000u, 0xC0000000u
        };
        unsigned lo = o1_bit(m, ph->bits);
        unsigned hi = o1_bit(m, ph->bits);

        m->dph += delta[lo | (hi << 1)];
        break;
    }

    case O1_SIG_QAM16: {
        unsigned c = 0u, k;

        for (k = 0u; k < 4u; k++)
            c = (c << 1) | o1_bit(m, ph->bits);
        o1_qam16_map(c, &m->i, &m->q);
        break;
    }

    case O1_SIG_QAM32: {
        unsigned c = 0u, k;

        for (k = 0u; k < 5u; k++)
            c = (c << 1) | o1_bit(m, ph->bits);
        o1_qam32_map(c, &m->i, &m->q);
        break;
    }

    default:
        break;
    }
}

/* One sample of one channel, before the amplitude scale.  Always within
 * +/-32767, whatever the modulation, because the two channels are averaged and a
 * clip in one of them is audible in both. */
static int32_t o1_mod_sample(const o1_mod *m, const o1_phase *ph)
{
    if (!m->live)
        return 0;

    switch (ph->sig) {
    case O1_SIG_TONE:
    case O1_SIG_DTMF: {
        int32_t s = o1_sine(m->ph);

        if (m->inc2 != 0u)
            s = (s + o1_sine(m->ph2)) >> 1;   /* halved, so a dual tone cannot clip */
        return s;
    }

    case O1_SIG_FSK:
        return o1_sine(m->ph);

    case O1_SIG_BPSK: {
        int32_t s = o1_sine(m->ph);

        if (m->inc2 != 0u)
            s = (s + o1_sine(m->ph2)) >> 1;
        return (m->i >= 0) ? s : -s;   /* the 180-degree flip, as a sign */
    }

    case O1_SIG_PSK4:
        return o1_sine(m->ph + m->dph);

    case O1_SIG_QAM16:
    case O1_SIG_QAM32:
        /* I and Q against the same carrier, ninety degrees apart.  >>15 undoes
         * the Q15 in the constellation table. */
        return (m->i * o1_cosine(m->ph) + m->q * o1_sine(m->ph)) >> 15;

    case O1_SIG_SILENCE:
    default:
        return 0;
    }
}

/* Set a channel up for a phase.  Everything a phase needs to be reproducible
 * starts from zero here, which is what makes the tests able to say "the answer
 * tone's first second contains exactly this many zero crossings" and get the same
 * answer twice. */
static void o1_mod_load(o1_mod *m, const o1_phase *ph, unsigned fs, int ch)
{
    uint16_t f1 = o1_freq_of(ph, ch, 0);
    uint16_t f2 = o1_freq_of(ph, ch, 1);

    memset(m, 0, sizeof *m);

    m->i    = O1_IQ_FULL;
    m->live = 1;

    o1_data_init(&m->data, o1_tone_payload, o1_tone_payload_len);

    /* Which scrambler is not a preference -- it is the standard's.  V.32 is a
     * different polynomial from V.22's, and using the wrong one produces noise
     * that is *almost* right, which is exactly the kind of bug that survives a
     * listening test and fails a conformance test. */
    if (ph->sig == O1_SIG_QAM32)
        o1_scr_v32_init(&m->scr);
    else
        o1_scr_v22_init(&m->scr);

    switch (ph->sig) {
    case O1_SIG_SILENCE:
        m->live = 0;
        return;

    case O1_SIG_TONE:
    case O1_SIG_DTMF:
    case O1_SIG_BPSK:
        m->inc  = o1_inc(f1, fs);
        m->inc2 = (f2 != 0u) ? o1_inc(f2, fs) : 0u;
        break;

    case O1_SIG_FSK:
    case O1_SIG_PSK4:
    case O1_SIG_QAM16:
    case O1_SIG_QAM32:
        m->inc = o1_inc(f1, fs);
        break;
    }

    if (ph->baud != 0u)
        m->sym_inc = ((uint32_t)ph->baud << 16) / fs;

    if (ph->rev_ms != 0u)
        m->rev_len = ((uint32_t)ph->rev_ms * fs) / 1000u;

    /* Load symbol zero now rather than after the first symbol interval, so a
     * phase never spends its first symbol carrying the previous phase's state. */
    if (m->sym_inc != 0u)
        o1_mod_symbol(m, ph, fs, ch);
}

static void o1_mod_step(o1_mod *m, const o1_phase *ph, unsigned fs, int ch)
{
    if (!m->live)
        return;

    m->ph += m->inc;
    if (m->inc2 != 0u)
        m->ph2 += m->inc2;

    /* The symbol clock is Q16 rather than a sample count, because 16000/2400 is
     * 6.67 samples and truncating that to 6 is a 2400-baud modem running at 2667
     * baud -- an 11% error in the one number the sound is supposed to convey. */
    if (m->sym_inc != 0u) {
        m->sym_acc += m->sym_inc;
        if (m->sym_acc >= 0x10000u) {
            m->sym_acc -= 0x10000u;
            o1_mod_symbol(m, ph, fs, ch);
        }
    }

    /* The 180-degree reversal, done by adding half a cycle rather than by
     * negating the output: negating is the same thing arithmetically, but
     * `sin(x + pi) = -sin(x)` keeps one accumulator and one code path, and the
     * discontinuity at the reversal is the *point* -- it is what the far end
     * detects and what the network's echo canceller cannot follow. */
    if (m->rev_len != 0u) {
        if (++m->rev_left >= m->rev_len) {
            m->rev_left = 0u;
            m->ph  += 0x80000000u;
            m->ph2 += 0x80000000u;
        }
    }
}

/* ------------------------------------------------------------- the generator */

static void o1_phase_begin(o1_tone_gen *g)
{
    const o1_phase *ph = &g->hs->phases[g->idx];

    g->pos = 0u;
    g->len = ((uint64_t)ph->ms * (uint64_t)g->fs) / 1000u;

    o1_mod_load(&g->a, ph, g->fs, 0);

    if (ph->two) {
        o1_mod_load(&g->b, ph, g->fs, 1);

        /* The two directions must not carry the *same* bits.  A real call has two
         * independent senders, and identical bit streams make both carriers move
         * in lockstep -- which sounds like one modem with an echo instead of two
         * modems talking.  A third of the way into the payload is enough to
         * decorrelate them for the length of any phase here. */
        g->b.data.idx = (g->b.data.n > 4u) ? (g->b.data.n / 3u) : 0u;
    } else {
        memset(&g->b, 0, sizeof g->b);
        g->b.live = 0;
    }
}

void o1_tone_start(o1_tone_gen *g, const o1_handshake *hs, unsigned fs, int32_t amp)
{
    if (g == 0)
        return;

    memset(g, 0, sizeof *g);

    g->hs = hs;
    g->fs = (fs == 0u) ? O1_TONE_FS_DEFAULT : fs;

    if (amp < 0)
        amp = 0;
    if (amp > 32767)
        amp = 32767;
    g->amp = amp;

    if (hs == 0 || hs->phases == 0 || hs->n == 0u) {
        g->done = 1;
        return;
    }

    o1_phase_begin(g);
}

unsigned o1_tone_render(o1_tone_gen *g, int16_t *out, unsigned n)
{
    unsigned i;

    if (g == 0 || out == 0 || n == 0u || g->done)
        return 0u;

    for (i = 0u; i < n; i++) {
        const o1_phase *ph = &g->hs->phases[g->idx];
        int32_t a = o1_mod_sample(&g->a, ph);
        int32_t b = o1_mod_sample(&g->b, ph);
        int32_t s = g->b.live ? ((a + b) >> 1) : a;

        /* Sampled first, then advanced: sample 0 of a phase is the symbol the
         * phase starts with, which is what makes a phase's output reproducible
         * from its own definition alone. */
        o1_mod_step(&g->a, ph, g->fs, 0);
        if (g->b.live)
            o1_mod_step(&g->b, ph, g->fs, 1);

        out[i] = (int16_t)((s * g->amp) / 32767);

        if (++g->pos >= g->len) {
            g->idx++;
            if (g->idx >= g->hs->n) {
                g->done = 1;
                return i + 1u;
            }
            o1_phase_begin(g);
        }
    }
    return n;
}

int o1_tone_done(const o1_tone_gen *g)
{
    return (g == 0 || g->done) ? 1 : 0;
}

const char *o1_tone_phase_name(const o1_tone_gen *g)
{
    if (g == 0 || g->done || g->hs == 0 || g->idx >= g->hs->n)
        return 0;
    return g->hs->phases[g->idx].name;
}
