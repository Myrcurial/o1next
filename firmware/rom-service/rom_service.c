/* The ROM service -- see rom_service.h for the contract, the ids, and why the
 * payload is a port rather than an asset (#284).
 *
 * The whole module is the two hooks `mb_extension` defines, because the engine
 * already owns everything else: the transaction, the operand counting, the result
 * codes, the reply buffer and the abandon rule are `mailbox.c`'s (section 3), and
 * this class adds two opcodes to them.
 */
#include "rom_service.h"

/* ---------------------------------------------------------------- the opcodes
 *
 * `MB_UNKNOWN` for anything else, which is what makes the engine answer `01h` for
 * an opcode this class does not own -- exactly as it would for any unknown opcode,
 * so a client cannot tell "not mine" from "not there", and does not need to.
 */
static unsigned rs_operands(void *ctx, uint8_t opcode)
{
    (void)ctx;

    switch (opcode) {
    case RS_OP_PRESENT: return 1u;   /* the content id */
    case RS_OP_INFO:    return 0u;   /* no operands, so the reply is immediate */
    default:            return MB_UNKNOWN;
    }
}

/* ------------------------------------------------------------------ the reply
 *
 * A reply is never empty: `0` on the wire means "not ready", so even an error is
 * the one-byte result code (section 3, rule 3).  On an error the reply is the
 * result code *alone* -- section 4 gives each command a payload, and a payload is
 * what a successful answer carries, so none is invented for a failure.
 */
static int rs_run(void *ctx, uint8_t opcode, const uint8_t *operand, mb_reply *out)
{
    rom_service *rs = (rom_service *)ctx;

    switch (opcode) {
    case RS_OP_PRESENT:
        /* The reply says whether the content is there; the *bytes* do not cross
         * the door -- a 3599-byte payload could not, and that is the protocol's
         * "no bulk channel, ever" rule.  The window carries them, and page 1
         * already holds the payload. */
        out->len     = 1u;
        out->data[0] = (uint8_t)rs_present(rs, operand[0], NULL, NULL);
        return 1;

    case RS_OP_INFO:
        /* For the web UI and for a human, not for the ROM: the ROM asks the door
         * for nothing at the sign-on any more (#278). */
        out->len     = 3u;
        out->data[0] = LIB_OK;
        out->data[1] = RS_INFO_VERSION;
        out->data[2] = RS_INFO_FLAGS;
        return 1;

    default:
        /* Not ours.  `rs_operands` already refused it, so the engine's own
         * unknown-opcode path is what a client sees. */
        return 0;
    }
}

/* -------------------------------------------------------------------- the API */

void rs_init(rom_service *rs, const rom_payload *payload)
{
    rs->payload.bytes = NULL;
    rs->payload.len   = 0u;

    if (payload != NULL) {
        rs->payload = *payload;
    }

    rs->ext.operands = rs_operands;
    rs->ext.run      = rs_run;
    rs->ext.ctx      = rs;
}

const mb_extension *rs_extension(rom_service *rs)
{
    return &rs->ext;
}

int rs_present(const rom_service *rs, uint8_t id, const uint8_t **bytes, uint32_t *len)
{
    if (id != RS_CONTENT_PAYLOAD) {
        /* `1` and `2` (the frame's halves) and `3` (the screen's code) retired with
         * the ROM-side frame path (#278); `09h` is the protocol's "no such
         * content" (section 4.2).  Any other id is the same answer. */
        return LIB_ERR_CONTENT;
    }

    if (rs == NULL || rs->payload.bytes == NULL || rs->payload.len == 0u) {
        /* Nothing to present.  `06h` is section 4.2's "a flash read that failed",
         * and it is the honest answer: the payload is not there. */
        return LIB_ERR_MEDIA;
    }

    /* Written only on success, so a caller that keeps its own page 1 is
     * undisturbed by an id that is not there (section 4.2). */
    if (bytes != NULL) {
        *bytes = rs->payload.bytes;
    }
    if (len != NULL) {
        *len = rs->payload.len;
    }

    return LIB_OK;
}
