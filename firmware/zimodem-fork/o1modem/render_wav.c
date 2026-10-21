/* Render the modem sounds to .wav, so the sound can be *heard* and tuned without
 * a board (#322, part of #56).
 *
 * This is not a test and it is not shipped to the ESP32.  It is the thing a
 * person runs when the answer tone is the wrong length or the screech is too
 * loud, because "does it sound like a modem" is a question no assertion in
 * `test_o1modem.c` can answer -- and the two questions are different.  The tests
 * prove the frequencies and the durations; this is for everything else.
 *
 *   firmware/zimodem-fork/o1modem/render_wav.sh [outdir]
 *
 * Default outdir is `build/modem-tones/`, which is gitignored along with the rest
 * of `build/`.  It writes 16-bit mono PCM at the default 16 kHz, which is what
 * the MAX98357A will be fed.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "tone.h"

static void put32(FILE *f, uint32_t v)
{
    fputc((int)(v & 0xFFu), f);
    fputc((int)((v >> 8) & 0xFFu), f);
    fputc((int)((v >> 16) & 0xFFu), f);
    fputc((int)((v >> 24) & 0xFFu), f);
}

static void put16(FILE *f, uint16_t v)
{
    fputc((int)(v & 0xFFu), f);
    fputc((int)((v >> 8) & 0xFFu), f);
}

/* The canonical 44-byte PCM header.  Written first with the exact sample count,
 * because the generator's length is exact (test_o1modem.c asserts that) -- so
 * there is no need to seek back and patch the sizes. */
static void wav_header(FILE *f, unsigned fs, uint32_t samples)
{
    uint32_t data = samples * 2u;

    fwrite("RIFF", 1u, 4u, f);
    put32(f, 36u + data);
    fwrite("WAVE", 1u, 4u, f);

    fwrite("fmt ", 1u, 4u, f);
    put32(f, 16u);              /* PCM chunk size */
    put16(f, 1u);               /* PCM */
    put16(f, 1u);               /* mono */
    put32(f, fs);
    put32(f, fs * 2u);          /* byte rate: mono, 16-bit */
    put16(f, 2u);               /* block align */
    put16(f, 16u);              /* bits per sample */

    fwrite("data", 1u, 4u, f);
    put32(f, data);
}

static int render(const char *dir, const char *name, const o1_handshake *hs,
                  unsigned fs, int32_t amp)
{
    char       path[1024];
    FILE      *f;
    o1_tone_gen g;
    int16_t    buf[512];
    uint64_t   total;
    unsigned   n;

    if (snprintf(path, sizeof path, "%s/%s.wav", dir, name) >= (int)sizeof path) {
        fprintf(stderr, "path too long: %s/%s.wav\n", dir, name);
        return 0;
    }

    total = ((uint64_t)o1_hs_ms(hs) * (uint64_t)fs) / 1000u;

    f = fopen(path, "wb");
    if (f == 0) {
        perror(path);
        return 0;
    }

    wav_header(f, fs, (uint32_t)total);

    o1_tone_start(&g, hs, fs, amp);
    while ((n = o1_tone_render(&g, buf, 512u)) > 0u) {
        if (fwrite(buf, 2u, (size_t)n, f) != (size_t)n) {
            fprintf(stderr, "%s: short write\n", path);
            fclose(f);
            return 0;
        }
    }

    if (fclose(f) != 0) {
        perror(path);
        return 0;
    }

    printf("  %-12s %6u ms  %8llu samples  %s\n", name, o1_hs_ms(hs),
           (unsigned long long)total, path);
    return 1;
}

int main(int argc, char **argv)
{
    const char *dir = (argc > 1) ? argv[1] : "build/modem-tones";
    unsigned    fs  = O1_TONE_FS_DEFAULT;
    int32_t     amp = O1_TONE_AMP_DEFAULT;
    int         ok  = 1;

    printf("modem tones -> %s (%u Hz, %d amplitude)\n", dir, fs, (int)amp);

    ok &= render(dir, "300-bell103",   &o1_hs_bell103, fs, amp);
    ok &= render(dir, "1200-v22",      &o1_hs_v22,     fs, amp);
    ok &= render(dir, "2400-v22bis",   &o1_hs_v22bis,  fs, amp);
    ok &= render(dir, "9600-v32",      &o1_hs_v32,     fs, amp);
    ok &= render(dir, "dial-tone",     &o1_hs_dialtone, fs, amp);
    ok &= render(dir, "ring",          &o1_hs_ring,    fs, amp);
    ok &= render(dir, "connect",       &o1_hs_connect, fs, amp);
    ok &= render(dir, "disconnect",    &o1_hs_disconnect, fs, amp);

    return ok ? 0 : 1;
}
