/* The modem's sound, built from arithmetic rather than sampled (#322, part of
 * #56).  The board's audio is an I2S class-D amplifier with its own DAC
 * (MAX98357A, U8) driving a passive transducer -- so what the panel can make is
 * a *waveform*, and this file makes waveforms.
 *
 * Why not .wav files
 * ------------------
 * Three reasons, and the third is the real one:
 *
 *   1. **Size.**  The application partition is `min_spiffs` and the build fails
 *      at 90% of it (`tools/build-o1next.sh`).  A second of 16-bit 16 kHz audio
 *      is 32 KB; the whole set here is a few hundred bytes of tables.
 *   2. **Every rate is a parameter.**  A 9600-baud sound and a 300-baud sound
 *      differ in a *number*, not in a recording.  A .wav set would need a
 *      separate recording per rate, per direction and per variant, and it would
 *      be wrong the first time someone tried 134.5 baud.
 *   3. **A sample cannot be tuned, and it cannot be checked.**  `test_o1modem.c`
 *      measures the *output* of this file: it counts zero crossings and asserts
 *      the answer tone is 2250 Hz.  You cannot do that to a .wav, and "the
 *      recording is the wrong one" is a bug no test can see.
 *
 * What the sound is, and what it is not
 * -------------------------------------
 * **This is not a modem.**  It does not interoperate, it does not transmit, and
 * nothing in this file needs to be correct to ITU timings.  It is the *noise the
 * panel makes while it is connecting*, and the specification's job here is to
 * supply the **vocabulary** -- which tones, which rates, in which order, so the
 * sound is recognisably a modem of that speed rather than a warble.
 *
 * That distinction is worth stating because it decides arguments.  A 2250 Hz
 * answer tone is a **specification** and is not negotiable: it is what a 2400-bps
 * modem sounds like.  Whether the answer tone lasts 3.3 s or 2.0 s is a **taste**
 * question, because the audience is a person in the same room and not a USR
 * Courier.  The frequencies are the specification; the durations are ours.
 *
 * The four rates, and what each one plays
 * ---------------------------------------
 * Every score is a **montage of one side of the call**, because a monologue is
 * what a speaker can do.  For each rate: the carrier (the answer tone), then the
 * first negotiation signal in each direction, then two seconds of full
 * communications.  The frequencies below are the documented ones and each is
 * cited in `docs/modem-tones.md`.
 *
 * | | 300 | 1200 | 2400 | 9600 |
 * |---|---|---|---|---|
 * | standard | Bell 103A | Bell 212A / V.22 | V.22bis | V.32 |
 * | modulation | FSK | DPSK, 600 baud | QAM-16, 600 baud | TCM, 2400 baud |
 * | answer tone | 2225 Hz (mark) | 2250 Hz | 2250 Hz | 2100 Hz + reversals |
 * | low band | 1270/1070 | 1200 | 1200 | -- (one carrier) |
 * | high band | 2225/2025 | 2400 | 2400 | 1800 Hz |
 *
 * **The 300-baud case is the odd one and it is the Osborne's own.**  The machine
 * this board is for shipped a **Bell 103A** modem
 * (`research/osborne1/Comm-Pac_Users_Manual.pdf`, "Modem-to-Modem Protocol":
 * `(1,0) = (1270, 1070) Hz` for ORIGINATE and `(2225, 2025) Hz` for ANSWER), and
 * Bell 103 has **no separate answer tone** -- the answering modem simply starts
 * sending its mark frequency.  So the "carrier" for 300 is 2225 Hz and it is the
 * same signal as the negotiation.
 *
 * What is deliberately not here
 * -----------------------------
 * No floats, no I2S, no Arduino, no `sin()` from libm.  The oscillator is an
 * integer phase accumulator over a quarter-wave table, which is why the host
 * tests can measure the output exactly -- and why the ESP32-S2 never has to
 * touch an FPU for a dial tone.
 */
#ifndef O1_MODEM_TONE_H
#define O1_MODEM_TONE_H

#include <stdint.h>

#include "rate.h"

/* The core is plain C and the sketch is C++: without this the linker looks for a
 * mangled name and the whole core reads as undefined symbols, which looks like a
 * missing file rather than a linkage mistake. */
#ifdef __cplusplus
extern "C" {
#endif

/* 16 kHz is enough for everything in the table: the highest frequency any of
 * these standards uses is V.32's 3000 Hz companion tone, and the highest
 * *meaningful* harmonic is well below 8 kHz.  It is also a standard I2S rate. */
#define O1_TONE_FS_DEFAULT 16000u

/* Peak amplitude, out of int16.  Not full scale: the transducer is small and
 * clipping is the one artefact that makes a synthesis sound like a toy. */
#define O1_TONE_AMP_DEFAULT 9000

/* ---------------------------------------------------------------- scramblers
 *
 * Both polynomials are the standards' own, and both are *multiplicative* -- the
 * output is fed back, which is what makes the scrambled stream look like noise
 * rather than like data.
 *
 *   V.22 / V.22bis / Bell 212A   G(x) = 1 + x^-14 + x^-17
 *   V.32 / V.32bis               G(x) = 1 + x^-18 + x^-23
 *
 * (The EE-terminology reference calls these "the generating polynomial for the
 * CRC", which is the same polynomial wearing a different hat: a scrambler and a
 * CRC are the same shift register with the taps read out differently.)
 *
 * **The scrambler is why a modem sounds like a modem.**  Unscrambled data at
 * 1200 bps has structure you can hear -- tones, patterns, silence.  Scrambled
 * data is flat noise with the carrier buried in it, and that hiss *is* the sound
 * everyone remembers.
 */
typedef struct {
    uint32_t sr;    /* shift register; the most recent bit is bit 0 */
} o1_scrambler;

void    o1_scr_v22_init(o1_scrambler *s);
void    o1_scr_v32_init(o1_scrambler *s);

/* One bit in, one bit out. */
uint8_t o1_scr_bit(o1_scrambler *s, uint8_t data_bit);

/* The general form, so the tests can drive both polynomials from one place and
 * so a future rate with a third polynomial costs a line rather than a function.
 * `tap_a` and `tap_b` are the exponents of the non-unity terms (14 and 17, or 18
 * and 23) -- *not* the bit positions, because an off-by-one in a polynomial
 * exponent is invisible and sounds fine.
 *
 * **A multiplicative scrambler is not its own inverse**, and saying so is worth a
 * paragraph: the *scrambler* feeds its own output back, and the *descrambler*
 * feeds the received bit in and taps the same register.  They are the same shift
 * register with the XOR on opposite sides of the tap, so a test that round-trips
 * them proves the tap positions are right -- which is the only way to catch an
 * off-by-one that would otherwise just sound like slightly different noise. */
uint8_t o1_scr_bit_of(uint32_t *sr, unsigned tap_a, unsigned tap_b, uint8_t data_bit);

/* The descrambler: the scrambled bit in, the data bit out.  Same register, same
 * taps.  Used by the tests; the board never needs it. */
uint8_t o1_desc_bit_of(uint32_t *sr, unsigned tap_a, unsigned tap_b, uint8_t scr_bit);

/* Where a phase's bits come from. */
typedef enum {
    O1_BIT_MARK = 0,       /* unscrambled binary 1 -- a steady carrier */
    O1_BIT_SCRAMBLED_MARK, /* "scrambled binary 1": the scrambler fed ones */
    O1_BIT_SCRAMBLED_DATA, /* the scrambler fed the payload text */
    O1_BIT_DOUBLE_DIBIT,   /* 0,0,1,1 repeating -- V.22bis's S1 signal */
    O1_BIT_AB,             /* 1,0 repeating -- V.32's S, the 1800 Hz phase pair */
    O1_BIT_CD              /* 0,1 repeating -- V.32's S', the 600+3000 pair */
} o1_bitpat;

/* ------------------------------------------------------------- the data source
 *
 * The payload the "full communications" phase carries.  It is scrambled, so what
 * comes out is noise -- but it is *our* noise, and a session recorded off the
 * board decodes back to this text if anyone ever wants to check.
 */
typedef struct {
    const uint8_t *bytes;
    unsigned       n;
    unsigned       idx;
    unsigned       bit;   /* 0..7, MSB first */
} o1_datasrc;

void    o1_data_init(o1_datasrc *d, const uint8_t *bytes, unsigned n);
uint8_t o1_data_bit(o1_datasrc *d);

/* One bit of a fixed pattern, with `*idx` running.  Exposed rather than private
 * because the S1 signal is a **claim in a comment** -- "unscrambled repetitive
 * double dibit pattern of 00 and 11" -- and a claim in a comment is not a test.
 * `o1_bitpat_bit(O1_BIT_DOUBLE_DIBIT, ...)` reads out 0,0,1,1,0,0,1,1 and the
 * suite asserts exactly that. */
uint8_t o1_bitpat_bit(o1_bitpat pat, unsigned *idx);

/* The text the data phase carries.  Short, printable, and it says what it is. */
extern const uint8_t o1_tone_payload[];
extern const unsigned o1_tone_payload_len;

/* ------------------------------------------------------------------ the score
 *
 * A score is a list of phases.  Each phase names a modulation and the numbers it
 * needs, and the generator walks it.  That is the whole design: **the standards
 * are data here, not code**, so adding V.21 or V.29 is a table and a test rather
 * than a new state machine.
 */
typedef enum {
    O1_SIG_SILENCE = 0,
    O1_SIG_TONE,     /* f1, or f1 + f2 when f2 is non-zero */
    O1_SIG_FSK,      /* f1 = mark, f2 = space, at `baud` */
    O1_SIG_BPSK,     /* f1 carrier, `baud`, one bit per symbol, 180 deg flips */
    O1_SIG_PSK4,     /* f1 carrier, `baud`, differentially encoded, 4 points */
    O1_SIG_QAM16,    /* f1 carrier, `baud`, 4x4 constellation */
    O1_SIG_QAM32,    /* f1 carrier, `baud`, 6x6 cross, 32 points */
    O1_SIG_DTMF      /* f1 = low group, f2 = high group */
} o1_sig;

/* Where a phase's bits come from -- `o1_bitpat`, defined above with the sources
 * it names. */

typedef struct {
    o1_sig     sig;
    o1_bitpat  bits;
    uint16_t   f1, f2;     /* channel A: carrier (or mark), and space / 2nd tone */
    uint16_t   f3, f4;     /* channel B: the same, when `two` is set */
    uint32_t   ms;
    uint16_t   baud;       /* symbol rate; 0 for a plain tone */
    uint16_t   rev_ms;     /* 180-degree reversal interval; 0 for none */
    uint8_t    two;        /* 1 = both directions at once (a full-duplex sound) */
    const char *name;
} o1_phase;

typedef struct {
    const char     *name;
    const o1_phase *phases;
    unsigned        n;
} o1_handshake;

/* The four connection sounds, plus the call-progress ones.  `docs/modem-tones.md`
 * is where each frequency comes from. */
extern const o1_handshake o1_hs_bell103;   /* 300 baud  -- the Osborne's own */
extern const o1_handshake o1_hs_v22;       /* 1200 baud -- Bell 212A / V.22 */
extern const o1_handshake o1_hs_v22bis;    /* 2400 baud -- V.22bis */
extern const o1_handshake o1_hs_v32;       /* 9600 baud -- V.32 */

extern const o1_handshake o1_hs_dialtone;  /* 350 + 440 Hz, continuous */
extern const o1_handshake o1_hs_ring;      /* 440 + 480 Hz, 2 s on / 4 s off */
extern const o1_handshake o1_hs_connect;   /* a short rising pair */
extern const o1_handshake o1_hs_disconnect;

/* The score for a rate, in milli-baud: 300000, 1200000, 2400000 or 9600000.
 * Anything else -- including 650 and 2600, which are real machine rates but not
 * modem rates -- gets the nearest of the four, and `o1_hs_for_rate` says which by
 * returning it.  A rate of 0 (the unshaped bypass) is not a modem and gets 300. */
const o1_handshake *o1_hs_for_rate(o1_rate mbaud);

/* A DTMF digit's two tones.  Returns 0 for a character that is not a digit
 * (0-9, *, #, and A-D, which are the four the keypad never had). */
int o1_dtmf_tones(char digit, uint16_t *low, uint16_t *high);

/* ------------------------------------------------------- the dial fingerprint
 *
 * **On `ATDT`, the connect string becomes audible.**  The whole string after the
 * `ATDT` is hashed, the hash becomes a short run of DTMF symbols, and those
 * symbols are dialled at the very start of the sequence -- so what the panel
 * plays is a *function of the destination* rather than a decoration.  Two hosts
 * sound different, the same host always sounds the same, and you can hear which
 * one you dialled.
 *
 * Why a hash rather than the string itself
 * ----------------------------------------
 * A hostname is not dialable: `bbs.example.net:23` has no tones.  A hash gives a
 * fixed-width, keypad-shaped answer for any string, and the length becomes a
 * *choice* rather than whatever the operator typed.
 *
 * Why 10 to 15 symbols
 * --------------------
 * Sixteen symbols would be the whole 64-bit hash, and eight is too few to be a
 * fingerprint.  The band is 10..15 and the default is **12** -- 48 bits, a
 * birthday collision at about 16 million destinations.  That is far more than a
 * wall of modems will ever see, and it keeps the dial under a second and a half.
 * The count is a parameter because it is a collision *budget*, not a
 * specification.
 *
 * Why the high nibbles
 * --------------------
 * FNV-1a's low bits are the weakly-mixed ones -- the final multiply's carries
 * travel upward -- so a truncated *low* half of a short input is measurably worse
 * than a truncated high half.  `o1_dtmf_fingerprint` takes the top nibbles.
 */
#define O1_DTMF_DIGITS_MIN 10u
#define O1_DTMF_DIGITS_MAX 15u

/* The 16-symbol DTMF alphabet, indexed by a 4-bit nibble.  **DTMF has exactly
 * sixteen symbols** -- 0-9, `*`, `#` and A-D -- so a hex nibble maps 1:1 and the
 * two spare keypad keys stand in for E and F.  That is not a dodge: `*` and `#`
 * are the two extra buttons on every keypad that ever had a modem next to it, and
 * using them keeps four bits per tone.  The alternative -- dropping E and F --
 * would be a base-14 alphabet and a longer dial for the same collision budget. */
char o1_dtmf_symbol(unsigned nibble);

/* FNV-1a, 64-bit.  The *published* reference vectors are asserted in
 * `test_o1modem.c` ("" is 0xcbf29ce484222325, "foobar" is 0x85944171f73967e8),
 * so the hash is checked against the standard rather than against itself. */
uint64_t o1_fnv1a64(const void *data, unsigned n);

/* The fingerprint for a connect string: `digits` symbols, high nibble first,
 * NUL-terminated into `out`.  `out` must hold O1_DTMF_DIGITS_MAX + 1.  `digits`
 * is clamped to [MIN, MAX].  Returns the number of symbols written.
 *
 * `connect` is hashed **exactly as given**, so a caller that trims whitespace
 * must trim it the same way every time -- a leading space is a different
 * destination, and that is the one thing the caller has to get right. */
unsigned o1_dtmf_fingerprint(const char *connect, char *out, unsigned out_n,
                             unsigned digits);

/* ----------------------------------------------------------------- the dial
 *
 * A dial is a score like any other -- one tone phase per symbol, with a gap
 * between them -- so it plays through the same generator and needs no special
 * case in the engine.  **There is no gap after the last digit**: a gap is what
 * separates two digits, and a trailing one would delay admission by 40 ms to
 * reproduce a silence nobody ever heard.
 *
 * The tone and gap lengths are ours.  DTMF specifies a *minimum* tone duration
 * (40 ms) and a minimum inter-digit interval, not a fixed pair, and 60/40 is what
 * a period keypad sounded like.
 */
#define O1_DTMF_TONE_MS 60u
#define O1_DTMF_GAP_MS  40u

typedef struct {
    o1_handshake hs;                                    /* points at `phases` */
    o1_phase     phases[O1_DTMF_DIGITS_MAX * 2u - 1u];
    char         digits[O1_DTMF_DIGITS_MAX + 1u];
    char         names[O1_DTMF_DIGITS_MAX][2u];          /* one symbol each */
    unsigned     n;                                     /* symbols */
} o1_dtmf_dial;

/* Build the dial for a connect string.  Returns the symbol count, or 0 if the
 * arguments are unusable.  The dial's *name* is the fingerprint itself, so a log
 * line and the sound say the same thing. */
unsigned o1_dtmf_dial_build(o1_dtmf_dial *d, const char *connect, unsigned digits);

/* The same, from symbols already in hand -- what the tests use, and what a caller
 * uses when it wants the digits without the hash.  Returns 0 on a symbol DTMF
 * cannot dial, which is the one way this can fail. */
unsigned o1_dtmf_dial_from_digits(o1_dtmf_dial *d, const char *digits, unsigned n);

/* ---------------------------------------------------------- the admission gate
 *
 * **A connection is not admitted until the dial has finished *and* the link is
 * up.**  Either order -- a fast host is waited for, a slow dial is waited out --
 * and the two facts arrive from different places, so they are held here rather
 * than inferred.  `admitted()` is the only question the connect path asks.
 *
 * `armed` is what keeps an ordinary connection ordinary.  A session that was never
 * dialled -- an incoming call, a phonebook entry, a plain `ATD` -- is admitted the
 * moment the link is up, because there is no dial to wait for.
 */
typedef struct {
    int armed;     /* a DTMF dial is in progress */
    int dialled;   /* ... and it has finished */
    int linked;    /* the network connection is up */
} o1_dial_gate;

void o1_dial_gate_reset(o1_dial_gate *g);     /* unarmed, nothing known */
void o1_dial_gate_arm(o1_dial_gate *g);       /* a dial starts: both facts clear */
void o1_dial_gate_dialled(o1_dial_gate *g);   /* the tones finished */
void o1_dial_gate_linked(o1_dial_gate *g);    /* the link came up */
void o1_dial_gate_abort(o1_dial_gate *g);     /* the attempt failed; start over */

/* Both facts, or no dial to wait for.  This is the whole point of the type. */
int o1_dial_gate_admitted(const o1_dial_gate *g);

/* Is a dial in progress?  A caller uses it to know whether an admission it is
 * about to grant is a *deferred* one -- which is the interesting case in a log,
 * and the one a support call is about. */
int o1_dial_gate_armed(const o1_dial_gate *g);

/* -------------------------------------------------------------- the generator
 *
 * Two modulators, because **full duplex is the sound**.  A 300-baud Bell 103
 * call is two FSK carriers at once, and a 1200-baud call is 1200 Hz one way and
 * 2400 Hz the other -- the "two tones fighting" quality that everyone recognises
 * is not decoration, it is the split band.  V.32 is the exception: echo
 * cancellation gives it **one** carrier at 1800 Hz, so `two` is 0 there and the
 * difference is audible.
 */
typedef struct {
    uint32_t     ph;        /* carrier phase, Q32: one cycle is 2^32 */
    uint32_t     inc;       /* Q32 phase increment per sample */
    uint32_t     ph2;       /* second tone's phase -- dual tones and BPSK-dual */
    uint32_t     inc2;      /* its increment; 0 when there is no second tone */
    uint32_t     dph;       /* PSK4: accumulated differential phase */
    int32_t      i, q;      /* the current symbol's I and Q, in Q15-ish units */
    uint32_t     sym_acc;   /* Q16 symbol clock: 65536 is one symbol interval */
    uint32_t     sym_inc;   /* Q16 added per sample; 0 = no symbol clock */
    uint32_t     rev_left;  /* samples to the next 180-degree reversal */
    uint32_t     rev_len;   /* samples between reversals; 0 = never */
    int          live;      /* this channel is silent for this phase */
    o1_scrambler scr;
    o1_datasrc   data;
    unsigned     pat_idx;
} o1_mod;

typedef struct {
    const o1_handshake *hs;
    unsigned    fs;
    int32_t     amp;        /* peak, out of 32767 */
    unsigned    idx;        /* which phase */
    uint64_t    pos;        /* samples emitted in this phase */
    uint64_t    len;        /* samples in this phase */
    o1_mod      a, b;
    int         done;
} o1_tone_gen;

/* Start a score.  `amp` is clamped to 32767; `fs` must be > 0.  The generator is
 * zeroed first, so a re-start is safe and a partially-played sound is dropped. */
void o1_tone_start(o1_tone_gen *g, const o1_handshake *hs, unsigned fs, int32_t amp);

/* Produce up to `n` samples.  Returns how many were written -- **less than `n`
 * when the score ends**, and 0 forever after, which is the caller's "stop". */
unsigned o1_tone_render(o1_tone_gen *g, int16_t *out, unsigned n);

int o1_tone_done(const o1_tone_gen *g);

/* Total milliseconds in a score.  The glue uses it to know how long to hold the
 * I2S channel open; the tests use it to sanity-check a table. */
uint32_t o1_hs_ms(const o1_handshake *hs);

/* The name of the phase the generator is in, or NULL when it is done.  For the
 * console: "connecting: 2250 Hz answer tone" is a much better line than a
 * progress bar. */
const char *o1_tone_phase_name(const o1_tone_gen *g);

#ifdef __cplusplus
} /* extern "C" */
#endif

#endif /* O1_MODEM_TONE_H */
